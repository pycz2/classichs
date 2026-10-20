# Server profiling and sizing (0.28.1)

How much CPU, memory, disk and network `classichs-server` needs, measured with real
WebSocket clients playing whole games through the protocol. Kubernetes manifests built
from these numbers: `deploy/k8s/`. An interactive version of this page (Russian):
`docs/report/server-profile.html`.

**Short answer.** One process, one replica. At the test pace (every player acts every
0.5–2 s, about 3× faster than people play):

| Load | CPU (container) | Memory (container) |
|---|---|---|
| idle server | ~0 | 7 MiB (28 MiB after a first start) |
| 100 players, 50 games | 0.12 core avg; 0.25 core keeps p99 < 50 ms | 53 MiB |
| 400 players, 200 games | 0.35 core avg; 0.5 core keeps p99 < 10 ms | 181 MiB |
| 1 000 players, 500 games | 0.8 core avg; needs 2 cores for p99 < 100 ms | 440 MiB |
| 5 000 idle logged-in players | 0.02 core | 726 MiB |
| + each password login running at once | ~20 ms of a core | **+19 MiB** (argon2), no cap |

Recommended Kubernetes resources (details in "Sizing"): ≤100 players `requests 250m /
256Mi, limit 512Mi`; ≤1 000 players `requests 1 CPU / 512Mi, limit 1.5Gi`; no CPU limit.
What breaks first: memory (password-login bursts, then 145 KiB per connection), then the
global hub mutex at ~1 300–4 000 actions/s; SQLite is far from its limit.

## Method

- **Load generator**: `server/examples/loadgen.rs` (usage at its top). Every simulated
  client is a WebSocket connection with its own `X-Forwarded-For` (the server runs with
  `--trust-proxy`, so the per-address login limit does not throttle the test).
  - `setup`: registers N accounts (`lg0…`), saves their tokens; `--friends 10` makes each
    account friends with its 10 nearest ids (written straight into the database).
  - `idle`: N clients `resume` and stay; `--churn R` reconnects R random clients a second
    (each reconnect: `disconnect` + `login` events, presence to 10 friends twice).
  - `play`: each client resumes, queues **casual** in the default game (Neonfall) or, with
    probability 0.5, in **Classic** (`pack` = Classic's rules_hash), plays, requeues after
    `game_over`. On each `state` where it has a move it rebuilds a playable game from its own
    view (`view::from_snapshot_in`, what the Godot client does with the engine's
    `new {state}`), picks the engine bot's move (or a random legal one with `--random`),
    waits a think time (`--think 500-2000` ms; `0` = stress, but never faster than 40 ms
    between a client's messages: the server allows 300 per 10 s) and sends `act`. Measured
    between `--warm` and `--secs`: `act` → next `state` latency (client side, so an upper
    bound of the server's), message sizes, actions/s, games; with `--pid`, the server's RSS
    and CPU time (`ps`). `--admin user:pass` keeps an admin panel live feed (`/admin/ws`) open.
  - `burst`: N password logins, C at a time (argon2).
  - `mkadmin`: the superuser, before the server starts.
- **Runs**: release build; every scenario on a fresh copy of one prepared database (5 000
  accounts, 10 friends each, the superuser) and pack store; 3 runs, medians reported
  (single runs are marked n=1). Scenario scripts were kept outside the repository.
- **Machine**: Apple M1 Pro (8 performance + 2 efficiency cores), 16 GB, macOS 26.5; the
  load generator runs on the same machine (it uses about as much CPU as the server: every
  move is a snapshot rebuild plus a bot search).
- **Linux container** (what Kubernetes sees): the image from `server/Dockerfile` in Docker
  Desktop 29.7 (Linux 6.12 VM, 10 vCPUs, 3.8 GiB), `--cpus`/`--memory` limits, a named
  volume for `/data`, `docker stats` sampled every second (memory = cgroup usage without
  the page cache, as the kubelet's working set). Latency runs marked "in-network" ran the
  load generator as a container on the same Docker network; the others went through
  Docker Desktop's host port forwarding, which adds its own latency spikes at 1 000+
  connections (compare the 1-CPU rows below).
- **CPU profile**: macOS `sample` (10 s at 1 ms) of the native server at ~3 500 actions/s.
- Not a real cluster: no ingress, TLS, real network or node noise (see "Not measured").

## 1. Baseline

| | native (macOS) | Linux container |
|---|---|---|
| Start, empty database (installs + trials both bundled packs) | 0.81 s; 0.75 s CPU; peak RSS 101 MiB | 1.38 s (incl. container start); 28 MiB after |
| Start, existing database | 0.31 s; 0.24 s CPU; peak RSS 35 MiB | 0.69 s; **7 MiB** |
| Start with SeaweedFS S3, empty (uploads 59 MB of packs) | 1.5 s (0.8 s once the bucket has them) | — |
| Start with S3, existing database (reads Neonfall, 16 MB) | 0.44 s | — |
| Idle CPU | 0.01 s per 30 s (~0.03 % of a core) | 0.1–0.2 % |
| SeaweedFS `weed mini` idle | — | 206 MiB, ~1 % of a core |

Rulesets in memory (heap, measured by a counting allocator): built-in Classic **2.5 MiB**,
Neonfall **0.4 MiB**. Both are loaded at every start (`rules_for` touches the built-in
Classic rules first, then loads the default pack); the bundled Classic pack has the same
rules_hash as the built-in one, so a Classic game loads nothing more (container: +0.5 MiB
after the first Classic request). Loading a pack from the store reads the whole file
(Neonfall 16 MB, a non-built-in Classic-sized pack 43 MB) into memory for a moment: that
is the startup peak above. The trial game of each new pack (on the first start and every
upload) costs about 0.5 s of CPU for both bundled packs together, once per rules_hash.

## 2. Connections

Idle logged-in clients (`resume`, then nothing):

| Clients | connect time (64 at a time) | memory, container | per connection | CPU idle |
|---|---|---|---|---|
| 100 | 0.2 s | — | — | ~0 |
| 1 000 | 0.8 s | 153 MiB | **146 KiB** | 0.7 % of a core |
| 5 000 | 4.2 s | 726 MiB | **145 KiB** | 2.5 % |
| 5 000, 8 KiB read buffer (experiment) | — | **137 MiB** | 26 KiB | 1.9 % |

The 145 KiB per connection is tungstenite's default 128 KiB read buffer, allocated and
touched for every WebSocket. A one-line experiment in `ws_upgrade` (`lib.rs`:
`.read_buffer_size(8 * 1024)`; frames up to 64 KiB still work, the buffer grows when
needed) cut 5 000 idle clients from 726 to 137 MiB and 400 playing clients from 181 to
135 MiB, with the same latency. It was measured and reverted; see "Recommendations".
(On macOS `ps` RSS shows the same ~100–150 KiB per connection right after connecting, then
the kernel compresses the untouched pages: do not size from macOS RSS.)

Idle CPU is the 1-second background tick: the admin panel's live snapshot
(`Hub::live_json`, every online player, built under the hub lock even with no admin
watching) and matchmaking: ~20 ms of CPU a second at 5 000 online.

Presence: 19 reconnects a second (each = a `disconnect`, a `resume`, 20 presence messages
to friends, 3 events, `touch`) cost **0.12–0.14 of a core**, i.e. ~6.5 ms of CPU per
reconnect, about the same at 1 000 and 5 000 online.

Password logins and registrations (argon2id, default parameters: 19 MiB, ~20 ms):

| | rate | latency p50 / p99 | peak memory |
|---|---|---|---|
| 300 logins, 10 at a time (native) | 300/s | 29 / 125 ms | 233 MiB |
| 300 logins, 50 at a time (native) | 213/s (10 cores) | 158 / 695 ms | **949 MiB** |
| 50 at a time, container `--memory 1g`, 2 CPUs | 41/s | p99 3.3 s | 978 MiB |
| 50 at a time, container `--memory 512m` | — | — | **OOM-killed** (every game lost) |
| 10 at a time, container `--memory 512m`, 2 CPUs | 78/s | p99 232 ms | 204 MiB |

Registering the 5 000 test accounts (10 at a time) took 15.5 s and 107 s of CPU (21 ms
each). Nothing caps the number of hashes running at once (`spawn_blocking`, up to 512
threads); the per-address login limit (10 a minute) does not help against many
addresses or a crowd coming back after a restart with expired tokens. Players normally
come back with `resume` (no hash), so this is a burst risk, not a steady cost.

## 3. Games

Bot-vs-bot games through the protocol, half in Neonfall, half in Classic; think time
0.5–2 s; 110 s measured after 40 s of warm-up (native) or 80 s after 40 s (container).
A game here takes ~60–70 actions; one action = one `act` in, two `state` messages out,
one `game_action` event.

Native (M1 Pro, medians of 3):

| Clients (live games) | actions/s | games/min | server CPU | CPU per action | RSS (macOS) | latency p50 / p95 / p99 |
|---|---|---|---|---|---|---|
| 20 (10) | 7.7 | 5 | 0.03 core | 4.4 ms | 28 MiB | 4.5 / 10 / 15 ms |
| 100 (50) | 40 | 32 | 0.14 | 3.4 ms | 67 MiB | 3.8 / 9.5 / 14 ms |
| 400 (200) | 160 | 128 | 0.35 | 2.2 ms | 184 MiB | 2.0 / 6.0 / 9.3 ms |
| 1 000 (500) | 401 | 317 | 0.61 | 1.5 ms | 424 MiB | 1.3 / 2.4 / 4.1 ms |
| 400 + admin feed open | 160 | 126 | 0.35 | 2.2 ms | 184 MiB | 1.9 / 5.7 / 8.8 ms |

Stress (no think time, 40 ms between a client's messages), native:

| Clients (games) | actions/s | server CPU | CPU per action | latency p50 / p95 / p99 / max |
|---|---|---|---|---|
| 20 (10) | 231 | 0.45 | 1.9 ms | 1.9 / 7.0 / 11 / 26 ms |
| 100 (50) | 1 280 | 1.40 | 1.1 ms | 1.4 / 3.9 / 6.0 / 33 ms |
| 400 (200) | **3 959** | 3.96 | 1.0 ms | 3.9 / 24 / 42 / 142 ms |

CPU per action falls with load: the fixed costs (the 1 s tick, `queue_status` to every
waiting player each second, waking idle threads) spread over more actions. The engine's
own part is ~0.5 ms (`examples/bench.rs`); the rest is the two `state` messages, the event
log and the WebSocket I/O.

Linux container, think 0.5–2 s:

| Clients (games) | `--cpus` | CPU avg / p95 | memory | latency p50 / p95 / p99 | path |
|---|---|---|---|---|---|
| 100 (50) | 0.25 | 12 % / 15 % | 53 MiB | 2.7 / 7.0 / **14 ms** | in-network, n=1 |
| 100 (50) | 0.25 | 14 % / 17 % | 53 MiB | 5.0 / 15 / 48 ms | host port, n=1 |
| 100 (50) | 0.5 | 13 % / 16 % | 70 MiB | 4.7 / 13 / 20 ms | host port, n=1 |
| 400 (200) | 0.5 | 31 % / 36 % | 180 MiB | 1.9 / 4.2 / **8.5 ms** | in-network, n=1 |
| 400 (200) | 1 | 35 % / 49 % | 181 MiB | 2.1 / 5.6 / 16 ms | in-network, n=2 |
| 400 (200) | 1 | 37 % / 53 % | 184 MiB | 3.1 / 13 / 29 ms | host port, n=3 |
| 1 000 (500) | 1 | 85–90 % / 102 % | 440 MiB | 7–9 / 150–260 / **150–725 ms** | 7 runs, both paths |
| 1 000 (500) | 2 | 80 % / 115 % | 440 MiB | 1.8 / 5.5 / **36 ms** | in-network, n=2 |
| 1 000 (500) | 0.5 | 51 % (capped) | 495 MiB | 165 / 509 / 922 ms; only 269 actions/s | host port, n=1 |
| 2 000 (1 000) | 1 / 2 | 101 % / 184 % | 1.07 / 1.0 GiB | p99 1.3 / 1.8 s; 529 actions/s | host port, n=1 each |

Saturation in the container (stress, 400 clients, in-network, n=1): **1 CPU 761
actions/s** (p99 112 ms), **2 CPUs 1 282** (p99 84 ms), **4 CPUs 1 587** (p99 133 ms). The
container needs ~1.3 ms of CPU per action at saturation and ~2 ms at the test pace
(Docker Desktop's VM is slower than the bare M1); the native server reached ~4 000
actions/s on ~4 cores. Scaling from 2 to 4 cores is poor: see the hub mutex below.

With a CPU limit the tail grows long before the average reaches the limit: at 1 000
clients with 1 CPU the average was 85 % but p99 was 150–725 ms (CFS throttling in 100 ms
periods + the bursty 1 s tick); with 2 CPUs and the same 0.8 core average, p99 was 36 ms.

**Memory per game**: in the container, 400 players in 200 games took 181 MiB, 1 000 in 500
took 440 MiB: ~0.43 MiB per playing client, of which 145 KiB is the connection; the rest
is the game (state, history up to ~300 KB at the end, the event JSON in flight) and the
outgoing buffers. With the 8 KiB read buffer: 135 MiB for 400 players.

**Messages**: `state` 7.1–7.6 KB on average, p99 15–17 KB, the largest seen 29.5 KB (a
late Classic board); `act` ~110 bytes. Every action sends two `state`s: **~14 KB down per
action**. The test pace (1 000 players, 400 actions/s) is ~5.7 MB/s ≈ **46 Mbit/s out**,
~46 kbit/s per player; people acting every 3–6 s need about a third of that. An open
admin panel receives every event and the live snapshot: ~1.2 KB per action
(28 MB in 150 s at 160 actions/s), with no measurable server CPU (0.35 vs 0.35 core).

**The database** (event log): 42–53 KB per finished game (`game_action` events ~500 bytes
each, ~55–60 per game, plus `match`, `game_start`, `game_end`, `queue`; the `events`
table is ~77 % of the file, its 5 indexes ~16 %). The writer batches up to 500
rows per insert; at the stress peak (3 959 actions/s) the file grew 2.3 MB/s and the
write path (sqlx + SQLite + fsync) was ~3 % of the CPU samples. The WAL stays a few MB
(SQLite's automatic checkpoint at 1 000 pages). Logins add ~0.25 KB (`login`,
`disconnect`), a queue ~0.2 KB.

## 4. Admin panel

With the live feed open during 400 players' games (3 runs): same CPU (0.35 core), same
latency, no `resync` (the feed's 4 096-message buffer was never overrun), ~185 KB/s to
the panel. The feed is a `broadcast` channel: each panel costs one more copy of each
message, so a few panels are free; a panel left open over a slow link at 4 000 actions/s
would fall behind and get `resync`. The panel's searches over a 90-day event table were
not measured (they share the one database connection with the game).

## 5. Bottlenecks (in the order they are hit)

CPU profile of the native server at ~3 500 actions/s (macOS `sample`, 400 clients, no
think time). Share of all samples of the tokio workers' polls (inclusive):

| What | share | note |
|---|---|---|
| `game::Ctx::step` (one action, all of it) | 96 % | |
| … `Ctx::states` → `Ctx::send` → `Hub::send` | 67 % / 34 % | `Hub::send` does `v.to_string()` **while holding the hub mutex** |
| … `state_msg` (both views + events) | 30 % | `snapshot` 21 %, `Entity::snapshot` 9 % |
| … `Game::state_hash` (for the event log) | 12 % | SHA-256 over the canonical JSON |
| … `Game::apply` (the rules) | 3 % | |
| waiting on a pthread mutex (`__psynch_mutexwait`) | **~60 % of worker time** | of these waits: ~68 % in `Ctx::send`/`step` (hub), ~28 % in `ws::dispatch` (hub) |
| SQLite (sqlx `step`, `VdbeExec`, `fsync`) | ~3 % | on sqlx's own thread |
| the event writer, presence, `live_json`, matchmaking | < 1 % each | |

1. **Memory spikes from password hashing** (argon2: 19 MiB each, no cap on concurrency).
   The only thing that OOM-killed the server in these tests (50 concurrent logins with a
   512 MiB limit). Hit first in a cluster with tight limits.
2. **Memory per connection** (145 KiB): with many players in the menu this dominates
   (5 000 online = 726 MiB).
3. **The global hub mutex** (`std::sync::Mutex<Hub>`). Every `state` message is serialized
   to text under it, and every incoming message takes it at least twice. At ~1 000+
   actions/s threads spend more time waiting for it than working; it is why 2 → 4 cores
   gave only +24 % in the container and why the native server topped out near 4 000
   actions/s with idle cores left. At the test pace that is ~5 000 players in games; at
   human pace far more than one process will see.
4. **The engine on the async workers** (`ponytail:` note in `game.rs`): ~0.5 ms per action
   (`snapshot`, `state_hash`, `apply`), well within budget; no stall was seen (the slowest
   act → state was 142 ms at 4 000 actions/s, at saturation). `spawn_blocking` is not
   needed at this scale; it would matter only for a slow card script.
5. **SQLite's single connection**: ~3 % of CPU at the stress peak, batched inserts, no
   queueing seen. Not a limit for games. It could become one for admin searches over a
   large event table or a burst of DB-heavy requests (logins, friends, chats share it).
6. Not hit: matchmaking's O(n²) pairing (queues stayed small), the 1 s `live_json`
   (2 % of a core at 5 000 online), presence fan-out (friends ≤ 200).

## 6. Sizing

The numbers below are for the test pace (a move every 0.5–2 s, ~0.8 actions/s per game).
People play slower (turns of 20–75 s with a few actions each, plus animations: roughly
0.2–0.3 actions/s per game), so the same CPU carries ~3× the players; memory does not
shrink (connections and games are held whatever the pace).

**Memory** ≈ 30 MiB + 145 KiB × connections + 0.3 MiB × players in a game
+ 19 MiB × password logins at once (+ ~60 MiB while a pack is uploaded or first loaded).
With an 8 KiB read buffer: 26 KiB per connection instead of 145.

**CPU** ≈ 2 ms × actions/s in a Linux container (1–1.5 ms on fast cores), + ~6.5 ms per
reconnect, + ~20 ms per password login; keep the average under about half of the CPU
you give it for p99 < 100 ms.

| | Small: ≤ 100 players online | Medium: ≤ 1 000 | Large: ≤ 5 000 |
|---|---|---|---|
| live games (test pace) | ≤ 50 | ≤ 500 | ≤ 1 000–2 000 |
| measured | 0.12 core, 53 MiB | 0.8 core, 440 MiB | 726 MiB idle; 1 000 games: ~1.1 GiB |
| CPU minimal / recommended | 0.25 / 0.5 core | 1 / 2 cores | 2 / 4 cores |
| memory minimal / recommended | 256 MiB / 512 MiB | 768 MiB / 1.5 GiB | 2 / 3 GiB (1.5 with the 8 KiB buffer) |
| k8s requests | `cpu: 250m, memory: 256Mi` | `cpu: "1", memory: 512Mi` | `cpu: "2", memory: 1536Mi` |
| k8s limits | `memory: 512Mi` | `memory: 1536Mi` | `memory: 3Gi` |

No CPU limit (throttling shows up as latency at a fraction of the limit); if one is
required, set it at ≥ 2× the request. The memory limit is mostly room for login bursts:
"minimal" survives ~10 password logins at once, "recommended" ~50 (or ~25 on Large).
Beyond Large, the hub mutex, not the core count, limits one process (see 5.3).

**Disk** (`/data`, block storage):

- Event log: **~45 KB per game** kept **90 days** (pruned hourly; SQLite reuses the freed
  pages, the file stops growing after 90 days): **size ≈ games per day × 4 MB**.
  1 000 games a day → ~4 GB; 10 000 a day → ~40 GB. Logins, queues, chats add ~1 KB per
  player per day. Other tables (accounts, friends, messages ≤ 200 per pair, games,
  standings) stay small (5 000 accounts with friends: 4.7 MB).
- Pack store (S3 or `/data/store`): the bundled Classic 43 MB + Neonfall 16 MB, plus
  uploads (≤ 100 MB per player pack, ≤ 10 per player; admin packs ≤ 128 MB).
- WAL a few MB; leave free space for SQLite to rebuild indexes if ever vacuumed (~2× the file).
- Write rate: ~0.2 KB per action (~100 KB/s at 500 games at test pace; 2.3 MB/s at the
  4 000 actions/s peak), batched; any SSD-backed volume is enough.

**Network**: ~14 KB out per action (two `state`s), ~110 B in; ~46 kbit/s per player at the
test pace, ~15 kbit/s at human pace; 1 000 players ≈ 15–46 Mbit/s out. Pack downloads
(player packs, ≤ 100 MB each, streamed from the store) come on top. Each open admin panel
≈ 1.2 KB per action.

## Recommendations (not applied: measured, then left for the owner)

1. Cap concurrent password hashes: a global `tokio::sync::Semaphore` (e.g. the number of
   cores) around the two `spawn_blocking(argon2…)` in `ws.rs` and the one in `admin.rs`.
   Bounds the burst memory to ~19 MiB × cores and makes a 512 MiB limit safe.
2. `.read_buffer_size(8 * 1024)` in `ws_upgrade` (`lib.rs`; the admin feed's upgrade too):
   −120 KiB per connection, measured above.
3. Serialize outside the hub lock: `Hub::send` takes `&Value` and calls `to_string()`
   with the mutex held; let callers pass the text (or clone the connection's sender and
   drop the guard first). The single biggest CPU-contention fix; the rest of the hub can
   stay one mutex.
4. Optional, for Large: skip `live_json` when no admin panel is connected
   (`log.feed.receiver_count() == 0`).

## Not measured

Arena drafts, ranked, friendly invites, chat traffic; pack uploads and downloads; the
admin panel's searches over a large event table; TLS, an ingress and real network
latency; a real Kubernetes node (Docker Desktop's VM instead); human think times (the bot
moves 3× faster); multi-hour soak (allocator fragmentation, the hourly prune on a full
90-day table); Linux `perf` profiles (the profile is macOS `sample` of the native build).
