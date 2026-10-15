# Game server (Rust) — design

> **Superseded in part (0.27):** the headless-Godot referee and the relay of NetSession messages are replaced by authoritative games on the Rust engine — see `2026-10-15-thin-client-design.md`; the admin panel is now a Preact SPA with a JSON API — see `server/README.md`.

Owner's request (2026-10-15): an optional game server besides peer-to-peer play.
Accounts (register, log in, secure), an admin panel (accounts: list, view, create,
suspend, delete; live games), SQLite, one async process, casual / ranked (2014
ranks, hidden MMR, a search window that grows) / Arena (12 wins or 3 losses, one
deck), friends by tag (up to 200), messages, blocking, friendly games. The game
logic must be checked on the server. The server is not hosted anywhere: code,
local test, release binaries for Windows, Linux and macOS, instructions.

## Where the game logic runs (ruling)

The rules engine stays one: the GDScript engine. A Rust port of the engine (one
source of truth for server, Godot and web) is a separate, later project — see
`2026-10-15-rust-engine-research.md`. Now:

- **Referee.** The server starts the game itself without a window as a referee
  process: `<game executable or godot> --headless [--path <project>] -- --referee <port>`.
  The server listens on `127.0.0.1:<port>` (a free port) and the referee connects to
  it; then one JSON request per line, one JSON reply per line (`net/referee.gd`).
  (Not stdin/stdout: headless Godot cannot read lines from a pipe — tested.) One
  referee serves all games (requests carry a game id).
- **Clients** keep their engine (the table animates from it) and play the existing
  peer protocol (`NetSession`: hello → start → action{n, action, hash} → bye) — but
  through the server, which relays every message and **checks every action with the
  referee** before it reaches the other player. An illegal action or a state hash
  that differs from the referee's ends the game: the sender loses.
- The server gives the seed (the host client must use it) and checks that the decks
  in the start message are the decks the players queued with.
- Known limit (documented): clients still know the whole state (the opponent's hand
  and deck order can be read by a modified client). A thin client fixes this after
  the Rust port.

### Referee protocol (TCP on localhost, JSON lines)

| Request | Reply |
|---|---|
| `{"op":"new","game":"g1","seed":123,"decks":[{"hero":"HERO_08","cards":[…],"arena":false},{…}]}` | `{"game":"g1","ok":true,"hash":"…","current":0}` or `{"ok":false,"error":"…"}` |
| `{"op":"act","game":"g1","action":{…}}` | `{"game":"g1","ok":true,"hash":"…","over":false,"winner":-1,"turn":3,"current":1}` or `{"ok":false,"error":"illegal"}` |
| `{"op":"drop","game":"g1"}` | `{"ok":true}` |
| `{"op":"validate","deck":{"hero":…,"cards":[…],"arena":false}}` | `{"ok":true}` / `{"ok":false,"error":"…"}` |
| `{"op":"draft","seed":5,"hero":-1,"picks":[0,2,…]}` | `{"ok":true,"heroes":[…],"hero":"HERO_08","cards":[…],"offer":[…],"done":false}` (stateless: the server keeps seed + picks) |
| `{"op":"ping"}` | `{"ok":true,"version":"0.26.0"}` |

Mulligan and concede actions are applied without a hash check (they are simultaneous
in the peer protocol); every other action must match the referee's hash.

## Server ↔ client protocol (WebSocket, JSON text frames)

Default address: `ws://localhost:7377` (port 7377, set in the game's Settings →
Server). Every message is an object with `"t"`. Max frame 64 KB.

Auth: `register {user, password}`, `login {user, password}`, `resume {token}` →
`auth {ok, token, me}` | `error {code, text}`. `logout {}`.
`me` = `{user, tag, casual_mmr?: never sent, rank: {rank, stars, legend, streak}, arena: {...}|null, season}`.

Profile/social:
- `set_tag {tag}` → `me`
- `friends {}` → `friends {list: [{user, tag, online, status}], requests_in: […], requests_out: […], blocked: […]}`
- `friend_add {tag}`, `friend_accept {user}`, `friend_decline {user}`, `friend_remove {user}`, `block {user}`, `unblock {user}`
- `msg {to, text}` → delivered as `msg {from, text, at}`; `history {with}` → `history {with, list}`
- `invite {to, deck}` → the friend gets `invite {from}`; `invite_accept {from, deck}`, `invite_decline {from}`
Play:
- `queue {mode: "casual"|"ranked", deck}` → `queued {mode}`; periodic `queue_status {waited, window}`; `unqueue {}`
- Arena: `arena_start {}` → `arena {state}`; `arena_hero {i}`; `arena_pick {i}`; `arena_queue {}`; `arena_retire {}`
- `match {game, host, seed, opponent, mode}` → the client starts a `NetSession` over the server
  channel; then both sides exchange `game {m: <NetSession message>}`; the server relays them.
- `game_over {game, result: "win"|"loss"|"draw", reason, rank?, arena?}`

## Server

Rust, one async process (tokio + axum), SQLite (rusqlite, WAL), argon2id password
hashes, session tokens (32 random bytes, stored as SHA-256), rate limits, an admin
panel at `/admin` (server-rendered HTML, its own login, HttpOnly SameSite=Strict
cookie, CSRF token on every form, HTML escaping). The superuser is made from the
command line: `classichs-server admin <name>` (asks for the password twice).

Ranked (2014, see `2026-10-15-ranked-research.md`): 25 ranks named as in 2014;
stars per rank 2 (25–21), 3 (20–16), 4 (15–11), 5 (10–1); a win +1 star, +1 bonus
from the 3rd win in a row at ranks 25–6; no star loss at 25–21; from 20 up a loss
−1 star (can drop a rank, never below 20); Legend after rank 1, Legend players
matched by MMR and numbered by MMR; monthly seasons: back to rank 25 with one
bonus star per rank above 25 held (at most 10 stars: Legend → rank 16 with 3 stars).
Hidden MMR (Elo, start 1500, K 32), separate for casual and ranked.

Matchmaking: every second; two players match when the gap is inside both windows;
a window grows with the time waited (casual: MMR gap 50 + 25/s; ranked: star gap
2 + 1 per 5 s, Legend by MMR; Arena: record gap (wins−losses) 0 + 1 per 10 s).
Blocking does not stop ladder matches (owner's ruling), only invites and messages.

Arena on the server: the server keeps the run (seed + picks; the referee computes
heroes and offers); one deck for the whole run; ends at 12 wins or 3 losses.

Friends: tag = 3–16 letters/digits, unique, case-insensitive; up to 200 friends;
requests; messages stored (last 200 per pair), 1–500 characters.
