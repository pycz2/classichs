# classichs-server

The optional game server for Classic HS: accounts, friends, messages, casual and
ranked ladders (2014 rules), the Arena, and refereed games. One async Rust process
with a SQLite database. Design: `docs/superpowers/specs/2026-10-15-server-design.md`.

## Build

Stable Rust (1.85+):

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
<http://localhost:7377/admin> and log in. The panel lists and searches accounts
(user, tag, created, last seen, rank, status), shows an account (suspend,
unsuspend, reset the password, delete with confirmation), creates accounts and
shows live games and queues. Admins manage players; only the superuser makes or
removes admins; the superuser itself is changed from the command line only.

### Connect the game

In the game: Settings → Server: `ws://localhost:7377`.

## Security notes

- **Put it behind TLS** (a reverse proxy such as Caddy or nginx giving `wss://` and
  `https://`) for anything beyond your own machine. Plain `ws://` sends passwords
  and tokens in the clear. Behind TLS the proxy must set `X-Forwarded-Proto: https`;
  the admin cookie then gets the `Secure` flag.
- Passwords: argon2id (default parameters), never logged or stored in clear.
- Sessions: 32 random bytes (base64url) given to the client; only their SHA-256 is
  stored; 30 days (admin sessions 12 hours); deleted on logout, suspension,
  password reset and account deletion.
- Admin panel: its own login (superuser and admins), HttpOnly + SameSite=Strict
  cookie, a CSRF token on every POST form (the login form too), every value
  HTML-escaped, works without JavaScript.
- SQL is parameterized only. Suspended accounts cannot log in or play.
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
  `auth {ok, token, me}`; `logout {}` → `logged_out`. `me {}` → `me {me}`;
  `me = {user, tag, rank: {rank, stars, legend, streak}, arena, season}` (rank 0 =
  Legend, `legend` = its number).
- Social: `set_tag {tag}` → `me`; `friends {}` → `friends {list, requests_in,
  requests_out, blocked}` (also pushed after changes); `friend_add {tag}`,
  `friend_accept|friend_decline|friend_remove|block|unblock {user}`;
  `msg {to, text}` → `msg_sent`, the friend gets `msg {from, text, at}`;
  `history {with}` → `history {with, list}`.
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
