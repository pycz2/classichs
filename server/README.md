# classichs-server

The optional game server for Classic HS: accounts, friends, messages, casual and
ranked ladders (2014 rules), the Arena, and authoritative games. One async Rust process
with a SQLite database. Design: `docs/superpowers/specs/2026-10-15-server-design.md`;
server games: `docs/superpowers/specs/2026-10-15-thin-client-design.md` ("Server games").

## Build

Stable Rust (1.94+, for SeaORM 2). The rules engine is the crate `classichs-engine` in
`../rust/engine` (a path dependency with `../rust/script`; it embeds `../data/cards.json`,
`../docs/packs/schema/keywords.json` and the Classic pack source `../packs/classic`), so
build from a checkout of the whole repository:

```sh
cd server
cargo build --release        # → target/release/classichs-server
cargo test                   # unit + integration tests (whole games played by the engine's bot)
cargo run --release --example bench   # what an action and a game cost the server
cargo run --release --example loadgen  # simulated players over the protocol (usage: its top comment)
```

Load tests, sizing and Kubernetes: `docs/server-profiling.md`, `deploy/k8s/`.

## The rules

Every game runs inside the server, in the same rules engine the game uses (exact parity
with the old GDScript engine), in a **game pack** (`.cardpack`, docs/packs/): the engine
loads a pack's rules, cards and Lua scripts by `rules_hash` the first time a game, a deck
check or a draft needs it (from the storage; kept for the life of the process, at most
`packs::MAX_RULESETS` = 48 different rule sets). Without a `pack` a request plays the
server's **default game**: the server pack the admin starred, else (first start) the newest
bundled pack with the manifest id `--default-pack` (`neon`: Neonfall), else the engine's
built-in Classic rules. The turn, mulligan, grace and away timers, the ranked ladder (ranks,
stars, floors, streaks, Legend, the season reset) and the Arena's end come from the pack's
`rules.json` (docs/packs/rules.md). The server keeps the only game state: it applies the
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

### Game packs: storage and bundled packs

Pack files (`.cardpack`, by content hash) live in an S3-compatible bucket when one is
configured, else in a local directory:

| Flag | Environment | Default |
|---|---|---|
| `--store-dir <dir>` | | `store` (used when no bucket is given) |
| `--s3-bucket <name>` | `S3_BUCKET` | none (= local directory) |
| `--s3-endpoint <url>` | `S3_ENDPOINT` | AWS; e.g. `http://seaweedfs:8333` |
| `--s3-region <r>` | `S3_REGION` | `us-east-1` |
| `--s3-access-key <k>` | `S3_ACCESS_KEY` | |
| `--s3-secret-key <s>` | `S3_SECRET_KEY` | |
| `--packs-dir <dir>` | | the first of `packs/` next to the binary, `./packs`, `../packs` or a `packs/` above the binary that holds a `.cardpack` (so `cargo run` or `target/release/classichs-server` in `server/` finds the project's `packs/`, built by `tools/build_packs.sh`) |

Flags win over the environment. Requests are path-style (`<endpoint>/<bucket>/<key>`),
so any S3-compatible store works; plain `http://` endpoints are allowed. The bucket must
exist (the compose file below creates it). The object key is `<content_hash>.cardpack`;
uploads over 10 MB go up as multipart uploads, downloads are streamed to the client.

At every start the server installs each `*.cardpack` in `--packs-dir` as an enabled
server pack, once (by the file's SHA-256): a pack the admin deleted stays deleted, a new
file is installed, and a new version of the default game becomes the default. This is how
Neonfall (the default game) and Classic ship. `--default-pack <manifest id>` (default
`neon`) names the game that becomes the default when none is set.

**Hashes** are docs/packs/format.md §3: `rules_hash` is computed by the engine
(`classichs_engine::pack::rules_hash`) and must equal the manifest's; `content_hash` is
SHA-256 over every file's path and SHA-256 (not the zip's bytes) and is the storage key.
Packs stored before (their `content_hash` was the file's SHA-256) are rehashed and moved to
the new key at start; one whose file is gone or no longer valid is turned off (`pack_rejected`).

### Docker

`docker-compose.yml` runs the server (built by `Dockerfile`: a Rust build stage and a
distroless Debian 13 runtime, user 65532, no shell; it bundles `packs/*.cardpack`, so build
the packs first) and [SeaweedFS](https://github.com/seaweedfs/seaweedfs) as the S3 store:

```sh
tools/build_packs.sh                  # packs/classic.cardpack, packs/neon.cardpack, packs/naxx.cardpack
cd server
docker compose up -d --build          # game: ws://localhost:7377, admin: http://localhost:7377/admin
docker compose exec server classichs-server admin root --db /data/classichs.db   # the superuser
docker compose logs -f server
docker compose down                   # keeps the data (volumes server-data, s3-data); -v deletes it
```

The build context is the repository root (the engine is `../rust/engine`);
`Dockerfile.dockerignore` sends only `data/cards.json`, `docs/packs/schema/keywords.json`,
`packs/classic` (source), `packs/*.cardpack`, `rust/engine`, `rust/script` and `server`.
The image has Neonfall (the default game) and Classic in `/packs`; more: mount files there
(see the compose file).
Set `S3_ACCESS_KEY` and `S3_SECRET_KEY` (an `.env` file next to the compose file) for
anything but a test; the S3 port is not published.

Why SeaweedFS: MinIO stopped publishing free images and binaries in 2025
(`minio/minio:latest` is no longer pullable). SeaweedFS is Apache-2.0, released every
few weeks for over ten years, one small image (`chrislusf/seaweedfs`, pinned to 4.48),
and `weed mini` runs the whole store (master, volume, filer, S3) in one process, takes
its credentials from `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` and creates the bucket
at start (`-bucket=packs`): no init container, no config file. Garage needs a layout,
a key and a bucket made with its CLI after the first start; RustFS is still young.
Checked: `docker compose up`, a 12 MB pack uploaded by a player (multipart) and a
server pack by the admin, downloaded byte for byte, `docker compose down` and `up`
again: everything still listed and downloadable; anonymous S3 requests get 403.

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
  per hour, the queues, who is online, the latest events, and the storage: the SQLite file
  and its WAL, the pack store. The server's version is in the top right corner of every page.
- **Event log**: everything the server does (below), filtered by kind, user, game,
  time and text, sorted, paged, with a live tail; a row opens its details.
- **Matches**: live and finished games; a game's page is its timeline (every action,
  grouped by turn, live while it runs) and what ended it. **Play** opens the replay player
  at the bottom of the page: the game's own replay view (a cut-down web build of the client,
  `ui/replay_app.tscn`, the export preset "Replay viewer"; the release's
  `ClassicHS-X.Y.Z-replay-viewer.zip`) served at `/admin/replay/` from `--replay-dir`
  (default: `replay-viewer/` next to the binary, else `../share/classichs/replay-viewer` above
  it, where tools/deploy_server.sh puts it). It fetches the replay and its pack from the API
  below; another page, its Back or ✕ closes it.
- **Games** (game packs): the server packs (the default game's star — click another to
  make it the default —, name, id, version, size, rules and content hashes, games played
  and live in its rules, downloads, enabled switch, delete with confirmation), upload by
  drag and drop (several files, with progress; each is checked by the engine), the
  players' packs (who uploaded what; the switch stops sharing it), the totals and the pack
  activity, live. Matches show each game's pack; an account shows its rank in every game.
- **Accounts**: search, filters (online, in game, searching, offline, suspended,
  role), sorting; an account's page (profile, rank, friends, requests, blocks,
  sessions, recent games, messages, activity) with suspend, unsuspend, reset the
  password, make admin/player (superuser), change the tag, delete (type the name); create accounts.
  **Games** on the page: a tab per game (every server pack's id, the built-in Classic rules)
  with its ranked standing this season (edit rank, stars, Legend, win streak, both hidden MMRs;
  reset to the season's start), its settings (the art and music sets: any key) and its decks
  (each with its cards by cost and English name; copy the deck code, rename, copy to another
  account, delete; add one from a code). The Arena run: set wins and losses, or end it. Each
  change is checked (the message says why not), logged (`admin`) and pushed to the player at
  once when online. Admins change players; the superuser admins too (as every account action).
  Every deck the panel shows (an account's, Statistics' top decks, a game's players' from its
  replay, a tournament's entrants') has **Copy code** (below, "Deck codes").
- **Messages**: every conversation between players (with unread counts), live.
- **Invite keys**: make a key (a note, how many players: 1 by default, at most 1000), copy
  it, revoke it; each key's uses left, who made it and when, the accounts that joined with
  it. An account's page says which key it joined with (and who made it) or "without a key".
- **Settings** (for the whole server, at once): the auto-bots' wait (0–600 s; 0 = at once)
  and invite-only registration.

Light and dark themes (the system's by default; the switch is remembered).

Vendored, unchanged: `admin/vendor/preact.module.js` and `hooks.module.js` from
preact@10.29.8, `htm.module.js` from htm@3.1.1 (unpkg.com `dist/` files).

#### The admin API

JSON under `/admin/api` (all but `login` need the session cookie; anything but GET
also needs the `X-CSRF-Token` header with the token from `login`/`me`):

| Call | What |
|---|---|
| `POST login {user, password}` | sets the cookie → `{id, user, role, csrf}` |
| `GET me` · `POST logout` | the admin, the CSRF token and the server's `version` (the release's, e.g. `0.62.0`) · end the session |
| `GET storage` | `{db: {path, file, wal, total}, packs: {bytes, files, what}}` (bytes) |
| `GET pack_files/{hash}` | the newest stored `.cardpack` with this content hash or rules hash (any owner, enabled or not) |
| `GET dashboard?day=<local midnight, ms>` | `{today: {kind: n}, totals, chart: {start, series}, recent, live}` |
| `GET live` | `{online: [{id, user, status}], queue: [{id, user, mode, waited, window}], games: [{id, mode, players, started, turn, current, actions}]}` |
| `GET accounts?q&status&role&sort&dir&page&size` | `{list, total, page, size}`; sort: id, user, created, last_seen, rank, ranked_mmr, casual_mmr |
| `POST accounts {user, password, role}` | creates → `{id}` |
| `GET accounts/{id}` | the account page's data; `per_game: [{pack, rules_hash, name, ranked, ladder: {ranks: [{rank, stars}], legend, start}, arena: {wins, losses} (its end), standing: {season, kept, rank, stars, streak, legend, ranked_mmr, casual_mmr}, settings, decks: [{id, name, hero, updated, code, class, class_name, count, valid, problem, cards: [{id, name, cost, n}]}]}]` |
| `POST accounts/{id}/{suspend\|unsuspend\|password\|role\|delete}` | `{password}`, `{role: "admin"\|"user"}`, `{confirm: <name>}` |
| `POST accounts/{id}/standing {pack, rank?, stars?, legend?, streak?, ranked_mmr?, casual_mmr?}` | the standing this season in a game (`pack`: its manifest id): the fields given; `legend: true` = Legend; a rank of the ladder, its stars, streak 0–1000, MMR 0–10000; a game without a ladder takes the MMRs only. `{pack, reset: true}`: back to the season's start. Pushes `me` |
| `POST accounts/{id}/arena {action: "set", wins, losses}` \| `{action: "end"}` | the run goes on with fewer wins and losses than its game's end, or ends; 409 while the player is in an Arena game or queue. Pushes `arena` and `me` |
| `POST accounts/{id}/game_settings {pack, settings: {key: text \| null}}` | as `game_settings_set`. Pushes `game_settings` |
| `POST accounts/{id}/tag {tag}` | a tag (3–16 letters or digits, unique: 409), `""` removes it. Pushes `me` |
| `POST accounts/{id}/decks {pack, code, name?}` | a deck from a code (or Hearthstone's copied text), a complete legal deck of the game; the name: given, else "### Name", else "Imported deck"; 100 decks a player (409) |
| `POST accounts/{id}/decks/{deck}/{rename\|delete\|copy}` | `{name}` (≤ 60), —, `{to: <account name>}` (one the admin may change; the same game). Pushes `decks {list}` to the owner (copy: to the receiver) |
| `GET events?kind=a,b&user&game&from&to&q&sort&dir&page&size` | `{list, total, page, size}`; from/to in ms; sort: time (default), kind, user |
| `GET conversations?user&page` · `GET conversations/{a}/{b}` | conversations, the latest first · one conversation |
| `GET games?user&mode&reason&page&size` · `GET games/{id}` | finished games · one game with its timeline and its replay's actions (`replay: {actions, hash, first}` or null) |
| `GET games/{id}/replay` | the game's replay as a `<id>.chsreplay` download (the replay JSON) |
| `GET packs` | `{server: [pack], players: [pack], stats: {server, enabled, players, uploaders, files, bytes, downloads, storage, games, live, default_rules, builtin: {rules_hash, default}, limits: {player, server, per_player}}}`; a pack is `{id, pack_id, version, name, rules_hash, content_hash, size, enabled, default, created, downloads, games, live, owner: {id, user} \| null}` (`games`/`live`: finished and live games in its rules) |
| `POST packs` (the `.cardpack` as the raw body, up to 128 MB) | a new server pack, enabled → `{pack}`; 409 `exists`, 413 `too_large`, 422 `invalid` (`{error, code}`) |
| `POST packs/{id}/{enable\|disable\|delete\|default}` | any pack, a player's too (the player's game gets a new `packs`); `default`: a server pack becomes the default game |
| `GET settings` · `POST settings {autobot_wait_ms?, signup_invite_only?}` | `{autobot_wait_ms, signup_invite_only}`; the wait 0..600000 ms (default 30000), invite-only default false; the fields given change at once |
| `GET signup_keys` | `{keys: [{id, key, note, uses_total, uses_left, created, created_by, created_by_name, revoked, accounts: [{id, user, created}]}], invite_only}`, newest first |
| `POST signup_keys {note?, uses?}` | a new uuid v4 key (note ≤ 200 characters, uses 1–1000, default 1) → `{id, key, text}` |
| `POST signup_keys/{id}/revoke` | the key registers nobody more (its accounts stay) |
| `GET tournaments?status` · `GET tournaments/{id}` | the list (summaries + `top` [{place, name}]) · one tournament as the players' `full`, every deck shown |
| `POST tournaments/{id}/cancel` | cancels one that is not over (409 otherwise) |
| `GET stats?pack&mode&bracket&period&bucket&bots&min&class` | the Statistics page (below): `{packs: [{pack, name, games}], pack, period, bucket, current, buckets: [{bucket, sides}], kept, modes, brackets, backfill, sides, classes: [{class, name, games, wins, mirrors}], matchups: [{class, opp, games, wins}], series: {hour: [[bucket, sides]] ×48, day: ×30}, decks: {total, top: [deck] ×20, by_class: {class: [deck] ×5}}, cards: [{card, name, cost, decks, copies, deck_wins, played, played_wins, plays, kept, replaced, kept_wins}]}`; period hour\|day\|week\|month\|year\|all (default), `bucket` one of its buckets (default: the current one, `current`; `buckets`: the period's buckets with games, newest first, by the filters, the current and chosen ones always; `kept`: false when the bucket's deck and card rows are pruned), `bots=0` leaves out games with a bot, `min` (default 20) the fewest games of a deck shown, `class` the cards of one class's decks; a deck is `{deck, class, hero, games, wins, cards: [{id, name, n, cost}]}` |

`/admin/replay/{file}` (the cookie) serves the replay player's files with a CSP of their own
(`'wasm-unsafe-eval'`, `blob:` workers, framed by the panel only); the panel's CSP allows that
frame and nothing else.

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
`kicked` (a second login closed the first connection), `pack_upload`, `pack_import` (a
bundled pack installed), `pack_default`, `pack_enable`, `pack_disable`, `pack_delete`,
`pack_download`, `pack_rejected` (a refused upload or a stored pack turned off: the reason), `match` (with the seed), `game_start` (who goes first, the opening draws), `game_action`
(every applied action, timeout moves marked `timeout`, with the turn, the state hash
and the engine's events), `game_left`, `game_back`, `game_end` (reason, results, the
final turn and hash, and for `illegal` the refused actions), `tournament` (created, joined,
left, closed, seeded, started, finished, cancelled; `data.tournament`), `admin` (every admin
action; the player changes `data.action` standing, arena, game_settings, tag, deck_add, deck_rename,
deck_delete, deck_copy with `data.target` and before/after), `setting` (a setting changed: `data.key`, `data.value`), `signup_key` (a key made
or revoked; `register` has `data.signup_key`), `error` (database failures and rules engine panics).

### The database

SQLite through SeaORM: the tables are the entities in `src/entity/`, the schema is
`src/migration.rs`, applied at every start (databases from 0.26 are taken over as
they are). Ranks and MMRs are in `standings` per (account, pack manifest id, season) — a
new version of a pack keeps them, a new season starts from the last one's (M4 moved the
ranks earned before packs to `classic-2014`); a game row and an Arena run keep their pack's
`rules_hash` (`""` = the built-in Classic rules, before packs). Players' decks kept on the
server are in `decks` (M6) per account and pack manifest id, like the standings; their
choices per game (art and music sets) in `game_settings` (M7), the same way. The admin's
settings are `server_settings` (key → text; M8), the invite keys `signup_keys` and the key an
account registered with `accounts.signup_key` (NULL: none, as every account before M8).
Every finished game's replay is in `replays` (M9: game, pack, p0, p1, ended, data = the
replay JSON deflate-compressed), kept for good. Tournaments (M10): `tournaments`, `t_entrants` (with the copied decks, seed, team, place), `t_matches`
(sides, the bracket sources, step, deadline, score, the series as JSON) and `t_games` (each
game of a match, its decks and winner).

#### Statistics

The admin's Statistics page (`src/stats.rs`, M11) reads only aggregated rows; each finished
game with a winner adds to them as it ends (`game.rs` → `stats::record`: the replay played
again in the engine). Every row has the pack (`rules_hash`), the period (`hour`, `day`, `week`,
`month`, `year`, `all`) and its UTC bucket (`2026-11-10T14`, `2026-11-10`, the week's Monday,
`2026-11`, `2026`, `all`), the mode, the player's bracket at the game's start (ranked: `Legend`,
`1-5`, `6-10`, …; Arena by the run's wins: `0-2`, `3-5`, `6+`; other modes `all`) and `bots` (1: an
`AutoBot_`/`Bot_` account played). Tables, one row per player of a game:
`stats_class` (class: games, wins, mirrors — a mirror counts no win or loss for the class),
`stats_deck` (class, deck = the hash of the class and the sorted 30 cards: games, wins),
`stats_card` (class, card: decks with it, copies, deck_wins, played = games it was played in,
played_wins, plays = times, kept / replaced = its copies in the opening hand at the mulligan,
kept_wins), `stats_matchup` (M12; class against opp: games, wins — the diagonal is the mirrors, with no
wins; both players of a mirror are in its row), `stats_decks` (a deck's hero and cards) and `stats_names` (English names of the
pack, its classes and cards: the pack's `locales/en.json`, else data/cards.json). Deck and card
rows of hours older than 48 hours and days older than 400 days are deleted; weeks, months, years
and all time stay, and the class and matchup rows of every period (the charts and past views).
The tables are `WITHOUT ROWID` (M12: their key is most of a row; 1500 games over 30 days take
18 MB instead of 34). At start, replays kept before the statistics are counted once in the
background (`stats::backfill`, 20 at a time; its place is `server_settings.stats_backfill`, so a
restart resumes); their ranked and Arena brackets are `unknown`. The same once for the matchup
rows alone (`stats_matchup_backfill`) when a database has statistics but no matchups (from 0.62).

### Connect the game

In the game: Settings → Server: `ws://localhost:7377`.

## Bots

The server can run its own players of Classic (`src/bots`), managed on the admin panel's **Bots** page:
add any number (accounts `Bot_<Level>_<n>`, with a password nobody knows), set each one's strength
(easy, medium, hard), games (ranked + casual in turn, ranked, casual, or Arena runs), daily window
(UTC) and the pause before a game, start and stop them live, see each one's state, its game as it sees
it, its last decision and its log; their errors also go to the event log (kind `bot`).

- **Fair:** a bot is a client like any player. It speaks the same protocol through an adapter —
  in this process (`transport::Transport::local`: channels into the same session code a WebSocket
  client gets, `ws::serve`) or over the network (`Transport::net`, `ws://` or `wss://`) — and sees
  only its own player's view. Hidden cards are guessed many times over (its own deck list minus the
  cards seen; the opponent's class pool), each guess with its own random seed (`brain`).
- **Thinking** (`rust/brain`, crate `classichs-brain`, shared with the game's own offline bot):
  a minion only to the rightmost slot unless a card whose effect depends on its neighbours is in play
  or in hand; a one-step look orders the actions (easy and medium keep the best 8 and 10); sequential
  halving over the guesses (easy 1, medium 2-3, hard 4-10); a hard time limit of twice the budget
  plus 0.2 s (medium 300 ms, hard 1 s), checked inside each guess too.
- **Levels** (48 games against the engine's greedy bot, which sees every card): easy 18-21 won,
  medium 39-41, hard 38; hard against medium 26-22 (`cargo test --release --test bot_levels --
  --ignored --nocapture`, `LEVEL_GAMES=48`).
- **Late moves:** a bot decides on the newest state only and drops a decision when a new state came
  meanwhile; the server refuses a move made when it is not the player's move (it crossed the clock)
  without a strike.
- **Auto-bots** (`bots::auto`): a player alone in a queue (ranked, casual, Arena) of any game the
  server has — Classic and every bundled or uploaded pack — for 30 s (the admin's Settings page: 0–600 s)
  gets a bot for one game, which plays with that game's cards: its deck is one of the pack's templates
  (`decks/*.json`) that is legal by the pack's rules, else a starter deck of a class; a pack with neither
  gets no auto-bot (Arena games always do). The bot: the level by the player's hidden MMR (under 1350 easy, up to 1650 medium,
  else hard; a ranked Legend: superhard, 3 s a decision on the server; Arena: the run's wins, 0-2 easy, 3-5 medium, 6+ hard), from a pool of accounts
  `AutoBot_<Level>_1..3` and `AutoBot_Arena_1..3` (made when first needed), paired with that player
  whatever the window, no human-pace pauses, a fresh Arena draft each game. All busy: the player
  waits on. The event log shows them (kind `auto_bot`).
- **The Arena draft** (all bots): a random hero of the three; easy takes any card, medium the best
  one 7 times in 10, hard always the best by draft score and mana curve.
- **Data built in:** 35 validated decks, 3-5 a class (`rust/brain/src/decks.json`, `DECKS.md`), the
  Arena draft scores (`arena_tiers.json`, `ARENA_TIERS.md`), the card names (`data/cards.json`,
  the crate's `names` feature).
- **CPU:** at most max(4, CPUs) bots think at once, the one whose turn ends first goes first
  (`bots::think`). Background: `docs/bots-performance.md`.

## Deploy to a Docker host behind Caddy

`deploy/docker-host/setup.sh` sets a host up once (its own domain in the host's Caddy, HTTPS on 443,
no new ports); then `DEPLOY_HOST=… DEPLOY_URL=https://… tools/deploy_server.sh X.Y.Z` deploys a
release: an image of about 70 MB (the stripped binary and the admin panel's replay player on
scratch, about 24 MB to upload), the packs only
when they change, a database copy, a check through Caddy and a rollback when the new version does
not answer, 2 images kept. The headers of these scripts tell the details.

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
| Decks kept on the server | 100 per account (all packs); a name 0–60 characters; 60 `deck_save` per 10 s |
| Settings per game | 16 keys, a text of 64 characters each; shares the decks' 60 changes per 10 s |
| Back after a disconnect in a game | the pack's `timers.away` (30 s), then the game is lost |
| A turn (the mulligan) | the pack's `timers` (Classic and Neonfall: 75 s (45 s) + 5 s), then the timeout moves |
| Refused actions | 3 per player in a game, then the game is lost |
| Connections per account | 1: a new login closes the old connection (`kicked`) |
| Tournaments | 3 not over per creator, 10 created a day; 2–128 players; start from now+11 min to now+14 days; 60 s for each accept, ban and pick |
| A player's pack | 128 MiB (as the client takes); 10 packs per player |
| A server pack (admin upload) | 128 MB |
| Inside a pack | docs/packs/format.md §1 (10 000 files, 256 MB unpacked, 16 MB a file, the rules part 8 MB, no zip bombs) |
| The check of a new pack's rules | a trial game of at most 600 actions and 20 s; one check at a time |
| Different rule sets in the engine | 48 per process (then new ones are refused until a restart) |

## Protocol summary

JSON text frames, each an object with `"t"`; errors are `{"t":"error","code","text"}`.
Full details: the design doc.

- Registration by invite (0.50): `signup_info {}` (before login too) →
  `signup_info {invite_only}`; older servers answer `error bad_request` (the client shows no
  key field). When the admin made registration invite-only, `register {user, password, key}`
  needs a key: none (or blank) → `error invite_required`, an unknown, used-up or revoked one →
  `error invite_invalid`. The key's use is taken in the same transaction as the account's
  insert (`UPDATE signup_keys SET uses_left = uses_left - 1 WHERE key = ? AND uses_left > 0 AND
  revoked = 0`, one row or nothing), so no race spends it twice and a failed insert (`taken`)
  gives the use back. With open registration `key` is optional; a valid one is still spent
  and recorded (`accounts.signup_key`). Keys are uuid v4, compared ignoring case and spaces
  around them.
- Auth: `register {user, password, key?}`, `login {user, password}`, `resume {token}` →
  `auth {ok, token, me}`; `logout {}` → `logged_out`. One connection per account: when
  an account logs in or resumes while it already has a connection, the old one gets
  `kicked {reason: "another_login"}` and is then closed with close code 4001 and reason
  `another_login` (the close frame says it again; the client should not reconnect by
  itself after it); the new one takes over (friends keep seeing it online; in a game it
  gets `match {…, rejoin: true}` and a fresh `state`). Keep the token: `resume` is
  the normal way back in (after a restart too); it is valid 30 days and every
  `resume` renews it (the same token comes back). `me {pack?}` → `me {me}`;
  `me = {user, tag, rank: {rank, stars, legend, streak}, arena, season, pack}`: the rank in
  that game (`pack`: a rules_hash; none: the default game; `auth` gives the default's), rank
  0 = Legend, `legend` = its number.
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
- Games in packs: `queue`, `arena_start`, `invite`, `invite_accept` and `me` take an
  optional `pack` (a rules_hash); without it the server's default game. Queues and games
  are a server pack's (enabled) or the default; a friendly game may also be in the
  inviter's own enabled pack (D12). Unknown or not allowed: `error pack`. Decks are checked
  with the pack's rules (`error deck`).
- Friendly games: `invite {to, deck, pack?}` (friend gets `invite {from, pack}`, `pack` =
  the game as in `packs`: `{id, name, version, rules_hash, content_hash, size, url}` — the
  client asks the player and downloads it before accepting; `{id, name, version,
  rules_hash}` for the built-in rules), `invite_accept {from, deck, pack?}` (`pack`, if
  given, must be the invite's: else `error pack`), `invite_decline {from}` (inviter gets
  `invite_declined {by}`).
- Ladder: `queue {mode: "casual"|"ranked", deck, pack?}` → `queued {mode, pack}`, then
  `queue_status {mode, waited, window}` every second; `unqueue {}`. Queues are per (mode,
  pack); `ranked` needs a pack with a ladder (`error queue`).
- Arena (one run at a time, in one pack): `arena_start {pack?}`, `arena_hero {i}`,
  `arena_pick {i}`, `arena_queue`, `arena_retire` → `arena {state}` (`state` = heroes,
  hero, cards, offer, done, wins, losses, pack (rules_hash), or null). A run whose pack left
  the server answers `error pack` (retire it).
- Games (the server holds the game; seats are 0 and 1, who goes first is random):
  - S→C `match {game, mode, opponent: {user, tag}, you: 0|1, pack, rejoin?: true}` (`pack`: the game's rules_hash).
  - S→C `state {game, view, events, result}` to both players after the start (the
    opening draws) and after every applied action: `view` = the engine's `snapshot`
    for that player, `events` = that action's engine events for that player,
    `result = {over, winner, turn, current, phase, deadline}` (`deadline`: whole
    seconds left to move; 0 when over). A turn that starts with a `turn_seconds` minion
    in play (Nozdormu; the snapshot's `turn_seconds`) lasts that long; when it leaves
    play the turn gets the usual time back.
  - C→S `act {game?, action}` (an engine action; `action.player` must be your seat).
    Refused → `act_error {game, error}` to the sender and nothing changes; a player's
    third refused action ends the game (reason `illegal`, that player loses).
  - C→S `emote {game?, id}` (≤ 32 bytes), `intent {game?, i}` (≤ 1 KB) → the opponent
    gets the same with `from` (the sender's seat). Concede is the `concede` action.
  - Turn clock (the pack's `timers`; Classic: 75 s a turn, 45 s for the mulligan, then 5 s
    `grace`); then the server plays the timeout moves (keeps the mulligan hand, takes the
    first option of a pending choice, ends the turn).
  - Dropped out: the pack's `away` (30 s) to come back, else the game is lost (`disconnect`). Logging in
    again during a game gives `match {…, rejoin: true}` and a fresh `state` (no events).
  - The end: `game_over {game, result: "win"|"loss"|"draw", reason, message?, rank?,
    arena?}`, reasons `over` (the game ended, a concede included), `illegal` (with
    `message` "Something does not add up: …"), `disconnect`, `aborted` (a rules
    engine failure). Older games in the database may show `left`, `desync`, `cheat`,
    `protocol`.
- Spectators (module `spectate`): a friend's entry in `friends` carries `in_game: {game,
  mode}` (null when not in a game). `spectate {user}` (friends only: `error not_friends`;
  `error not_in_game`; `error spectate` when the game has 20 spectators or the asker plays
  one) → `spectating {game, mode, pack, players: [n0, n1], seat, full}` and at once a
  `spectate_state {game, view, events: [], result}` with the current view, then one after every
  change (the shape of `state`). `full: false`: the view of the friend's seat (the friend's
  hand open, the opponent's hidden, as the friend sees it); `full: true` (tournaments,
  `spectate::add`): both hands and Secrets open (never deck lists or the RNG). One game at a
  time (watching another leaves the first). `unspectate {}` → `unspectated`; the end:
  `spectate_end {game, winner (seat, -1 = nobody), reason}`. A disconnect or a game of one's
  own stops it. The players are never told who watches; spectators get no emotes or intents.

### Decks

A player's decks kept on the server (a game played through the server: its Collection
works on them; "Copy local decks" copies the device's there), per pack (its manifest `id`, as ranks, so a new version keeps them). A deck is
`{id, pack, name, hero, cards, created, updated}` (`id`: the server's, a whole number;
times: unix seconds).

- `decks {pack?}` → `decks {list: [deck]}`: all of mine, or one game's (`pack`: a rules_hash,
  as `queue`), oldest first.
- `deck_save {deck: {name, hero, cards}, id?, pack?, ref?}` → `deck_saved {deck, ref}`:
  without `id` a new deck in the game of `pack` (a rules_hash; none: the default game; the
  player's own packs count too), with `id` an update of mine (`error not_found`; of another
  game: `error pack`). `ref` (≤ 64 characters) comes back as given (the client finds which of
  its decks it was). The cards are checked with the game's rules (`error deck`): every card
  one the deck may take; an unfinished deck (fewer cards than a full one) is kept too, an
  Arena deck is not. A name over 60 characters: `error bad_name`; the 101st deck:
  `error decks_full`; too fast: `error rate_limited`.
- `deck_delete {id}` → `deck_deleted {id}` (or `error not_found`: no such deck of mine).

### Tournaments

Any player creates one; players join with copied decks; the server (`src/tournament/`, a
scheduler every 2 s and after each tournament game, all state in the database: a restart
carries on) runs it. Times are unix **milliseconds**. Refusals: `error tournament` with a
human `text` (`server` for a database error).

- Life (server clock): `open` → at T−10 min `locked` (rules, decks and the start frozen; fewer
  than `min_players` → `closed`, `reason` "not enough players") → at T−1 min `seeded` (random
  seeds, Scheveningen teams, the bracket; joining and leaving end; again `closed` if too few
  are left) → at T `running` → `finished` (places) | `cancelled` (the creator, any time before
  the end; running games play on but no longer count).
- `t_create {name (3–40), pack (a server pack's rules_hash), format, options, series, best_of,
  bans, start_at (now+11 min … now+14 days), max_players (2–128), min_players (2…max, default
  2), deck_reveal, spectators}` → `tournament`. `format`: `round_robin` (`options.rounds` 1|2),
  `swiss` (`rounds` 1–10, null = ceil(log2 n) filled in at seeding; `drop_after` 0 = never,
  1–5 match losses), `elimination` (`losses` 1 single | 2 double: a losers' bracket, then a
  grand final, no reset), `scheveningen` (two random balanced teams, everyone plays everyone of
  the other team). `series`: `conquest` | `lhs`; `best_of` 1|3|5|7 (wins needed = (bo+1)/2);
  `bans` 0|1. Decks per entrant = wins needed + bans, each another class, each valid in the pack.
  Limits: 3 not over (open … running) per creator, 10 created a day per account.
- Only the creator: `t_edit {id, …}` (name, format, options, bans (not once someone joined),
  max/min players (not below the entrants), deck_reveal, spectators, start_at (later only);
  `pack`, `series`, `best_of` are fixed) until T−10; `t_reschedule {id, start_at}` (later only,
  ≤ now+14 days) until T−10; `t_cancel {id}`.
- Players: `t_join {id, decks: [{name, hero, cards}]}` (copied: deleting them later changes
  nothing) and `t_leave {id}` until T−1; `t_decks {id, decks}` until T−10.
  Each of these (and `t_create`) answers with `tournament` and makes the player a watcher.
- `t_list {tab: "upcoming"|"finished"|"closed"}` → `t_list {tab, list: [summary]}` (100 at
  most; upcoming = open … running by start, closed = closed and cancelled).
  summary = `{id, name, creator, pack, pack_name, format, series, best_of, start_at, status,
  entrants (count), max_players, joined}`.
- `t_get {id}` → `tournament {tournament: full}` and watches it: every change pushes
  `tournament {tournament: full}` (as the watcher sees it) until `t_unwatch {id}`; a player
  with a match step waiting also gets its `t_match`. full = summary + `{options, bans,
  min_players, deck_reveal, spectators, reason, created, ended, decks_per_entrant,
  wins_needed, round, entrants: [{name, seed, team, eliminated, place, points, wins, losses,
  buchholz, decks?}] (by place, then seed), matches: [{id, round, bracket ("w"|"l"|"gf" in
  elimination, else ""), slot, p: [name|null, name|null], status, score: [a, b], winner,
  games: [game ids], deadline}], can: {edit, cancel, reschedule, join, leave, decks,
  spectate}}`. Decks: one's own always; others' only with `deck_reveal` from T−10 on.
  The format's options are also at the top level (`rounds`, `drop_after`, `losses`).
  Match `status`: `pending` (sides not known yet or not free), `accept`, `ban`, `pick`,
  `playing`, `done` (forfeits too, `winner` set), `bye` (one side null: a match won by the
  other; both null: nobody). `winner`: the entrant's name or null.
- Matches: ready when both sides are free (no other match of theirs in this tournament is
  under way). Each game: `accept` (60 s; who does not accept loses that game; both: one of
  them at random), once a match `ban` (60 s, when bans: each bans one of the opponent's decks;
  timeout = a random one), `pick` (60 s; timeout = the first usable deck), then the game: the
  usual `match` (`mode: "tournament"`, plus `tournament`, `match`, `tournament_name`) and
  game messages; no rating change; a side offline or in another game at the start loses that
  game; a game without a winner (or lost in a server restart) is played again. Conquest: a deck
  that won can't be used again in the match. LHS: the losing deck is out, the winner keeps its
  deck for the next game (no pick), the loser picks from what is left. A match ends at the
  wins needed.
- The steps: `t_accept {match}`, `t_ban {match, deck: index into the opponent's decks}`,
  `t_pick {match, deck: own index}`. Pushed to both sides on every change of their match:
  `t_match {tournament, name, match, phase: "accept"|"ban"|"pick"|"wait"|"done", status,
  deadline, opponent, score: [mine, theirs], mine: [{hero, name, state}], theirs: [{hero,
  state}], pick (my deck for the coming game, or null), game (while playing), series,
  best_of, bans, winner}`; deck `state`: `ok` | `banned` | `won` (Conquest: spent) | `lost`
  (LHS: out).
- Rounds: round robin (circle method, an odd count sits one out per round) and Scheveningen are
  made at seeding; Swiss pairs a round when the previous one is over (same points first, no
  rematch when avoidable, a bye = a match won for the lowest without one); elimination: a
  bracket to the next power of two, the byes to the top seeds.
- Places: round robin, Swiss, Scheveningen by match points, then game wins − losses, then
  (Swiss) Buchholz; elimination by the stage one went out at (the semi-final losers share 3rd).
  Equal ones share a place.
- `t_spectate {match}`: the creator or an eliminated entrant, when `spectators` is on, watches
  the match's game with both hands open (the spectator messages). Tournament games' replays:
  everyone when `deck_reveal` is on or the tournament is over, else its two players and the
  creator.

### Deck codes

The client's (Collection → Export Code / Import Code, `game/deck_code.gd`) and the admin panel's
(`src/deck_code.rs`): a Hearthstone deckstring for every game. Base64 (standard, padded) of varints
`0, 1, format, 1, hero, n1, single cards…, n2, double cards…, n3, (card, count)…`; the server and the
client write format 3 (Classic) and read 1–3 (Wild, Standard). A card's number is its `code_id`
(Classic and Naxxramas: Hearthstone's dbfId, so codes from Hearthstone and deck sites import;
`legacy_code_id` where no card has that number), else — a pack without code numbers, such as
Neonfall — the Godot `String.hash()` of its id (djb2 over the code points, 32 bits), as the client's
CardDb gives it. A code names no game: it is read in the game it is imported into (an unknown number:
"The deck has a card this game does not have"). A hero that is no class champion (a Hearthstone skin)
becomes the champion of the cards' class. Hearthstone's copied text works too ("### Name" gives the
name, `#` lines are skipped). `server/tests/admin_players.rs` and the client's `test_deck_model.gd`
check the same Neonfall code.

### Game settings

A player's choices for each game (the client keeps the art and music sets there: `art`,
`music`), per pack (its manifest `id`, as decks), in the table `game_settings`
(account, pack, value: a JSON object).

- `game_settings {}` → `game_settings {games: {<pack id>: {key: text}}}`: every game's.
- `game_settings_set {settings: {key: text | null}, pack?}` (`pack`: a rules_hash, as
  `queue`; none: the default game; the player's own packs count too) merges the changes into
  that game's (null removes a key) → `game_settings {games}`. A key is 1–32 of `a-z 0-9 _`,
  a text at most 64 characters, 16 keys a game at most (else `error bad_request`); an unknown
  game `error pack`; it shares the decks' 60 changes per 10 s (`error rate_limited`).

### Replays

Every finished game (any mode, any ending) is kept as a replay: the JSON the rules engine plays
again, `{format: "classichs-replay", v: 1, game, mode, pack (rules_hash), pack_id, pack_name,
started, ended (unix s), players: [{name, hero, cards: [30 ids]}] (by seat), seed, first (the
engine's `new` first: -1 = drawn from the seed), actions: [every applied action in order:
mulligans, choices, timeout moves, concede], result: {winner (-1 none), reason, turns}, hash
(the final state hash)}`. `Game::new_in(pack, hero0, cards0, hero1, cards1, seed, first, true)`
and `apply` of every action give that hash. The client's `.chsreplay` file is this JSON.

- `replays {}` → `replays {list: [{game, mode, pack, pack_name, opponent, won, started, ended,
  turns, you (the player's seat), winner (seat, -1 none), heroes, players (names, by seat)}]}`: the player's last 50
  games, newest first.
- `replay {game}` → `replay {game, data}` for one who may watch it (`replays::can_view`: its
  players), else `error not_found`.

### Game packs

A pack is `{id, name: {lang: text}, version, rules_hash, content_hash, size, default, url}`
(`id` = the manifest's id; `default`: the server's default game; `url` is relative to the server's HTTP address, e.g.
`http://host:7377` for `ws://host:7377`).

- `packs {}` → `packs {server: [pack], mine: [pack + enabled]}`: the enabled server packs
  and the player's own (sent again by the server after the player's upload or an admin's
  change to their packs).
- `pack_delete {content_hash}` → `packs {…}` (or `error not_found`).
- `GET /packs/<content_hash>.cardpack` with the game's session token as
  `Authorization: Bearer <token>` or `?token=<token>` → the zip, streamed, with
  `ETag: "<content_hash>"`, `Cache-Control: private, max-age=31536000, immutable`
  (`If-None-Match` → 304). Who may: everyone for an enabled server pack; a player's pack
  for its owner and (while enabled) the owner's friends. Otherwise 404; no or a bad token 401.
- `POST /packs` with the token, the `.cardpack` as the raw body → `201 {pack}`; refusals
  are `{error, code}`: 401 `auth_required`/`bad_token`, 409 `exists` (already yours) or
  `too_many` (10), 413 `too_large` (128 MiB), 422 `invalid` (the reason), 400 `empty`.
- Both answer CORS (`Access-Control-Allow-Origin: *`, preflight included) for the web build.

The check (`packs::inspect` and `packs::trial`, on every upload and bundled pack): the zip
by docs/packs/format.md §1 (paths, sizes, entries; read by the engine), a `manifest.json`
with `format` 1, `id` (1–64 of `a-z 0-9 . _ -`), `version` (1–32 visible characters),
`name` (`{lang: 1–100 characters}`) and the `rules_hash` of its files; then (D11), unless a
pack with the same rules passed before, the engine loads the rules and compiles every
script, and its bot plays a trial game with the pack's first two legal ready decks (else
starter decks), trying every legal move on a copy at each step: a script error, an engine
failure, a stuck game or more than 20 s refuses the pack (`422 invalid` with the reason,
event `pack_rejected`).
