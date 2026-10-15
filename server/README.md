# classichs-server

The optional game server for Classic HS: accounts, friends, messages, casual and
ranked ladders (2014 rules), the Arena, and refereed games. One async Rust process
with a SQLite database. Design: `docs/superpowers/specs/2026-10-15-server-design.md`.

## Build

Stable Rust (1.94+, for SeaORM 2):

```sh
cd server
cargo build --release        # → target/release/classichs-server
cargo test                   # unit + integration tests (a fake referee)
```

The real-referee test runs only when told where Godot and the project are:

```sh
CLASSICHS_GODOT=godot CLASSICHS_PROJECT=/path/to/like_classic_hs cargo test real_referee
```

## The referee

Every move is checked by the game itself, started without a window. The server
listens on a free port on `127.0.0.1`, starts the referee command with that port
appended as the last argument, and talks JSON lines over that socket
(`net/referee.gd`). The command is, in order of preference:

1. `--referee "<command line>"`,
2. the `CLASSICHS_REFEREE` environment variable,
3. `godot --headless --path <project> -- --referee`, with the project folder found
   in `.` or `..` (so `cargo run` works both in the project folder and in `server/`).

With a downloaded game instead of the project (put a path with spaces in quotes):

- Linux: `--referee "/path/to/ClassicHS-x.y.z-linux-x86_64.AppImage --headless -- --referee"`
- Windows: `--referee "C:\Games\ClassicHS-x.y.z-windows-x86_64.exe --headless -- --referee"`
- macOS: `--referee "'/Applications/Classic HS.app/Contents/MacOS/Classic HS' --headless -- --referee"`

The game and the server must be the same version. The referee is restarted on the next request if it dies;
games it was checking end as a draw ("aborted").

## Run

```sh
./target/release/classichs-server \
  --listen 127.0.0.1:7377 --db classichs.db \
  --referee "godot --headless --path /path/to/like_classic_hs -- --referee"
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
`match`, `game_start`, `game_action` (every accepted action with the referee's turn
and hash), `game_left`, `game_back`, `game_end` (reason, results, and the message
that broke the rules), `admin` (every admin action), `error` (database and referee
failures).

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
- Known limit: clients still hold the whole game state (lockstep), so a modified
  client can read the opponent's hand. The referee stops illegal moves, not peeking.

## Limits

| What | Limit |
|---|---|
| WebSocket frame / message | 64 KB |
| Login + register | 10 a minute per address and per account name |
| Messages from one connection | 300 per 10 s (then disconnected) |
| Malformed messages | 20 per connection (then disconnected) |
| Chat | 1–500 characters, 10 per 10 s, last 200 kept per pair, friends only |
| Names | user 3–20 `[A-Za-z0-9_]`; tag 3–16 letters/digits, unique ignoring case |
| Passwords | 8–128 characters |
| Friends | 200 |
| Back after a disconnect in a game | 30 s, then the game is lost |

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
- Games: `match {game, host, seed, opponent, mode}`; then `game {game, m}` both ways
  carrying the NetSession messages (hello, start, action, emote, intent, bye); the
  host must start with the server's seed and the queued decks. The end:
  `game_over {game, result, reason, rank?, arena?}`, reasons `over`, `illegal`,
  `desync`, `cheat`, `protocol`, `left`, `disconnect`, `aborted`. A player who logs
  in again during a game gets `match {…, rejoin: true, log}` (the messages so far).
