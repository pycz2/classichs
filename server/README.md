# classichs-server

The optional game server for Classic HS: accounts, friends, messages, casual and
ranked ladders (2014 rules), the Arena, and authoritative games. One async Rust process
with a SQLite database. Design: `docs/superpowers/specs/2026-10-15-server-design.md`;
server games: `docs/superpowers/specs/2026-10-15-thin-client-design.md` ("Server games").

## Build

Stable Rust (1.94+, for SeaORM 2). The rules engine is the crate `classichs-engine` in
`../rust/engine` (a path dependency; it embeds `../data/cards.json`), so build from a
checkout of the whole repository:

```sh
cd server
cargo build --release        # → target/release/classichs-server
cargo test                   # unit + integration tests (whole games played by the engine's bot)
cargo run --release --example bench   # what an action and a game cost the server
```

## The rules

Every game runs inside the server, in the same rules engine the game uses (exact parity
with the old GDScript engine). The server keeps the only game state: it applies the
players' actions, refuses illegal ones, runs the turn clock, and sends each player only
what that player may see (never the opponent's hand, deck or secrets). Deck checks and
the Arena draft use the engine too. Nothing else needs to be installed or started.

Each game is one task that owns its engine state, so games never wait for each other.
Measured (`examples/bench.rs`, Apple M1 Pro, one core): about 0.5 ms of server work per
action (apply 0.01 ms, state hash 0.13 ms, the two players' `state` messages 0.38 ms),
so about 1900 actions a second per core; a `state` message is about 6 KB (18 KB the most seen in 1000 bot games);
a game holds about 55 KB of heap plus its history (about 300 KB in all when it ends).

## Run

```sh
./target/release/classichs-server --listen 127.0.0.1:7377 --db classichs.db
```

All flags are optional (defaults shown). `--trust-proxy` takes the client address
from the last `X-Forwarded-For` entry (use it only behind your own reverse proxy:
the login rate limits are per address). `RUST_LOG=debug` for more logging.

### The superuser and the admin panel

```sh
./target/release/classichs-server admin root --db classichs.db
```

asks for the password twice (no echo) and creates the superuser `root`, or makes
an existing account the superuser and resets its password. Then open
<http://localhost:7377/admin> and log in; the browser stays logged in (30 days,
renewed while used). Admins manage players; only the superuser makes or removes
admins; the superuser itself is changed from the command line only.

The panel is a single-page app (Preact + htm as plain ES modules, no build step;
`admin/*.js`, `admin/style.css`, embedded into the binary: edit, then rebuild). It
updates live over `/admin/ws`:

- **Dashboard**: online now, searching per mode, live games, today's games,
  registrations, logins, messages and errors, a 24-hour activity chart, game actions
  per hour, the queues, who is online, the latest events.
- **Event log**: everything the server does (below), filtered by kind, user, game,
  time and text, sorted, paged, with a live tail; a row opens its details.
- **Games**: live and finished games; a game's page is its timeline (every action,
  grouped by turn, live while it runs) and what ended it.
- **Accounts**: search, filters (online, in game, searching, offline, suspended,
  role), sorting; an account's page (profile, rank, friends, requests, blocks,
  sessions, recent games, messages, activity) with suspend, unsuspend, reset the
  password, make admin/player (superuser), delete (type the name); create accounts.
- **Messages**: every conversation between players (with unread counts), live.

Light and dark themes (the system's by default; the switch is remembered).

Vendored, unchanged: `admin/vendor/preact.module.js` and `hooks.module.js` from
preact@10.29.8, `htm.module.js` from htm@3.1.1 (unpkg.com `dist/` files).

#### The admin API

JSON under `/admin/api` (all but `login` need the session cookie; anything but GET
also needs the `X-CSRF-Token` header with the token from `login`/`me`):

| Call | What |
|---|---|
| `POST login {user, password}` | sets the cookie → `{id, user, role, csrf}` |
| `GET me` · `POST logout` | the admin and the CSRF token · end the session |
| `GET dashboard?day=<local midnight, ms>` | `{today: {kind: n}, totals, chart: {start, series}, recent, live}` |
| `GET live` | `{online: [{id, user, status}], queue: [{id, user, mode, waited, window}], games: [{id, mode, players, started, turn, current, actions}]}` |
| `GET accounts?q&status&role&sort&dir&page&size` | `{list, total, page, size}`; sort: id, user, created, last_seen, rank, ranked_mmr, casual_mmr |
| `POST accounts {user, password, role}` | creates → `{id}` |
| `GET accounts/{id}` | the account page's data |
| `POST accounts/{id}/{suspend\|unsuspend\|password\|role\|delete}` | `{password}`, `{role: "admin"\|"user"}`, `{confirm: <name>}` |
| `GET events?kind=a,b&user&game&from&to&q&sort&dir&page&size` | `{list, total, page, size}`; from/to in ms; sort: time (default), kind, user |
| `GET conversations?user&page` · `GET conversations/{a}/{b}` | conversations, the latest first · one conversation |
| `GET games?user&mode&reason&page&size` · `GET games/{id}` | finished games · one game with its timeline |

`/admin/ws` (the cookie, same origin) sends `hello {live}`, then `event {e}` for every
event, `live {live}` when the online list, queues or games change and `resync {}`
when the panel fell behind (reload). An event is `{id, at (ms), kind, account, user,
other, game, text, data}`.

#### The event log

Kept 90 days in the `events` table. Kinds: `register`, `login` (`data.via`:
password, token), `login_failed` (`data.reason`, `data.admin`), `logout`,
`disconnect`, `admin_login`, `admin_logout`, `tag`, `friend_request`,
`friend_accept`, `friend_decline`, `friend_remove`, `block`, `unblock`, `msg` (the
text), `invite`, `invite_accept`, `invite_decline`, `queue`, `unqueue`, `arena`,
`match` (with the seed), `game_start` (who goes first, the opening draws), `game_action`
(every applied action, timeout moves marked `timeout`, with the turn, the state hash
and the engine's events), `game_left`, `game_back`, `game_end` (reason, results, the
final turn and hash, and for `illegal` the refused actions), `admin` (every admin
action), `error` (database failures and rules engine panics).

### The database

SQLite through SeaORM: the tables are the entities in `src/entity/`, the schema is
`src/migration.rs`, applied at every start (databases from 0.26 are taken over as
they are).

### Connect the game

In the game: Settings → Server: `ws://localhost:7377`.

## Security notes

- **Put it behind TLS** (a reverse proxy such as Caddy or nginx giving `wss://` and
  `https://`) for anything beyond your own machine. Plain `ws://` sends passwords
  and tokens in the clear. Behind TLS the proxy must set `X-Forwarded-Proto: https`;
  the admin cookie then gets the `Secure` flag.
- Passwords: argon2id (default parameters), never logged or stored in clear.
- Sessions: 32 random bytes (base64url) given to the client; only their SHA-256 is
  stored; 30 days, renewed on use (game tokens on every `resume`, admin cookies at
  most hourly); deleted on logout, suspension, password reset and account deletion.
- Admin panel: its own login (superuser and admins, 10 tries a minute per address
  and per name), HttpOnly + SameSite=Strict cookie (`Secure` behind https), the CSRF
  token as a header on every state-changing call, JSON-only login, requests and the
  live feed from another Origin refused (behind a proxy with `--trust-proxy`,
  `X-Forwarded-Host` counts as the host; else the proxy must pass `Host`), a strict
  Content-Security-Policy (scripts from the server only, no inline code but the
  hashed import map), the session checked again every 30 s on the live feed.
- Queries go through SeaORM (parameterized). Suspended accounts cannot log in or play.
- Games are authoritative: clients get only their own view, so a modified client can
  neither make illegal moves nor read the opponent's hand. Known limit: entity ids are
  given out in deck-list order before the shuffle; the opponent's list is unknown, so
  this tells nothing useful.

## Limits

| What | Limit |
|---|---|
| WebSocket frame / message from a client | 64 KB |
| Login + register | 10 a minute per address and per account name |
| Messages from one connection | 300 per 10 s (then disconnected) |
| Malformed messages | 20 per connection (then disconnected) |
| Chat | 1–500 characters, 10 per 10 s, last 200 kept per pair, friends only |
| Names | user 3–20 `[A-Za-z0-9_]`; tag 3–16 letters/digits, unique ignoring case |
| Passwords | 8–128 characters |
| Friends | 200 |
| Back after a disconnect in a game | 30 s, then the game is lost |
| A turn (the mulligan) | 75 s (45 s) + 5 s, then the timeout moves |
| Refused actions | 3 per player in a game, then the game is lost |

## Protocol summary

JSON text frames, each an object with `"t"`; errors are `{"t":"error","code","text"}`.
Full details: the design doc.

- Auth: `register {user, password}`, `login {user, password}`, `resume {token}` →
  `auth {ok, token, me}`; `logout {}` → `logged_out`. Keep the token: `resume` is
  the normal way back in (after a restart too); it is valid 30 days and every
  `resume` renews it (the same token comes back). `me {}` → `me {me}`;
  `me = {user, tag, rank: {rank, stars, legend, streak}, arena, season}` (rank 0 =
  Legend, `legend` = its number).
- Social: `set_tag {tag}` → `me`; `friends {}` → `friends {list, requests_in,
  requests_out, blocked}` (also pushed after changes); `friend_add {tag}`,
  `friend_accept|friend_decline|friend_remove|block|unblock {user}`;
  `msg {to, text}` → `msg_sent {to, at}`, the friend gets `msg {from, text, at}`;
  `history {with}` → `history {with, list: [{from, text, at}]}` (oldest first).
  Friend `status` (in `friends` and below): `"online" | "in_game" | "searching" |
  "offline"`.
- Presence: `presence {user, online, status}` is pushed to all of a player's
  friends when the status changes: log in, log out or disconnect, a game starts or
  ends, searching starts or stops (queue, unqueue, Arena queue, a match). New
  friends get each other's presence at once.
- Chats: `chats {}` → `chats {list: [{with, tag, online, status, last: {from, text,
  at} | null, unread}]}`: every friend, the latest conversations first (friends
  without messages after them, by name); `unread` = their messages not yet marked
  read. `read {with}` → `read_ok {with}` marks that friend's messages read (kept in
  the database, so the counts survive restarts).
- Friendly games: `invite {to, deck}` (friend gets `invite {from}`),
  `invite_accept {from, deck}`, `invite_decline {from}` (inviter gets `invite_declined {by}`).
- Ladder: `queue {mode: "casual"|"ranked", deck}` → `queued {mode}`, then
  `queue_status {mode, waited, window}` every second; `unqueue {}`.
- Arena: `arena_start`, `arena_hero {i}`, `arena_pick {i}`, `arena_queue`,
  `arena_retire` → `arena {state}` (`state` = heroes, hero, cards, offer, done,
  wins, losses, or null).
- Games (the server holds the game; seats are 0 and 1, who goes first is random):
  - S→C `match {game, mode, opponent: {user, tag}, you: 0|1, rejoin?: true}`.
  - S→C `state {game, view, events, result}` to both players after the start (the
    opening draws) and after every applied action: `view` = the engine's `snapshot`
    for that player, `events` = that action's engine events for that player,
    `result = {over, winner, turn, current, phase, deadline}` (`deadline`: whole
    seconds left to move; 0 when over).
  - C→S `act {game?, action}` (an engine action; `action.player` must be your seat).
    Refused → `act_error {game, error}` to the sender and nothing changes; a player's
    third refused action ends the game (reason `illegal`, that player loses).
  - C→S `emote {game?, id}` (≤ 32 bytes), `intent {game?, i}` (≤ 1 KB) → the opponent
    gets the same with `from` (the sender's seat). Concede is the `concede` action.
  - Turn clock: 75 s a turn, 45 s for the mulligan, then 5 s more; then the server
    plays the timeout moves (keeps the mulligan hand, takes the first option of a
    pending choice, ends the turn).
  - Dropped out: 30 s to come back, else the game is lost (`disconnect`). Logging in
    again during a game gives `match {…, rejoin: true}` and a fresh `state` (no events).
  - The end: `game_over {game, result: "win"|"loss"|"draw", reason, message?, rank?,
    arena?}`, reasons `over` (the game ended, a concede included), `illegal` (with
    `message` "Something does not add up: …"), `disconnect`, `aborted` (a rules
    engine failure). Older games in the database may show `left`, `desync`, `cheat`,
    `protocol`.
