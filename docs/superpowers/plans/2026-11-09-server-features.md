# 0.50 — admin settings, invite keys, spectators, replays, tournaments (contract)

The owner's request (2026-11-09, Russian, summarised): (1) the autobot wait set in the admin panel for all games,
0–10 min (today 30 s); (2) watch friends' live games; (3) registration by invite key only (admin switch; keys are
uuid4, optional note, uses (default 1), no races; the admin sees who made a key and who joined with it); (4)
replays: every game kept on the server compactly, listed in the admin panel, played back in the client with
seeking; export/import a replay file; the last 10 games in the game menu; (5) tournaments (formats, series rules,
bans, timers, brackets, spectating, places, tabs), anyone can create one. One release for client and server: **0.50.0**.

This file is the contract between the parts built in parallel. Names below are binding; a part that needs a
change writes it in its report (the integrator reconciles).

## Shared rules (every part)

- Work in your own git worktree. Before the first test run: `godot --headless --path . --import`; if
  `rules/bin/` has no `libclassichs_godot.macos.dylib`, copy it from `/Users/pycz/ws/like_classic_hs/rules/bin/`
  (not in git).
- Tests: `./run_tests.sh` (ends "N tests, 0 failed"), `cd server && cargo test --release`, `cd rust && cargo test
  --release` when rust/ changes. New behaviour gets tests (GDScript TestCase in tests/, Rust in server/tests/).
- Never touch port 7377, `server/classichs.db`, `server/store`, the owner's user data, or the live server. Local
  servers only on your ports (below) with temp `--db`/`--store-dir`. Driver scripts set every user:// path to
  `user://uitest_*` (Settings.path, Profile, DeckStore, Progress, ServerLink.session_path, Packs) and are deleted
  with their `.uid` after. Never run an exported macOS .app.
- Ports: A 7401–7409, B 7411–7419, C 7421–7429, D-server 7431–7439, D-client 7441–7449.
- Migrations (server/src/migration.rs, sea-orm): A = **M8**, B = **M9**, D = **M10**. C adds none. Add your
  struct and put it in `Migrator::migrations()`; the integrator orders them.
- Every new UI string in all languages: `data/i18n/{ru,de,fr,es,pt_BR,it,pl}.json` and `data/i18n/keys.json`
  (see how existing keys are stored). Real translations, not English copies.
- Server protocol changes are documented in `server/README.md` ("Protocol summary"); the admin panel is
  `server/admin/*.js` + `index.html` (compiled in with include_str!; add new files to the asset list in admin.rs).
- Code style: as the code around it (tabs in GDScript, `##` doc comments, short "why" comments; Rust as in
  server/src). Keep diffs small; reuse what exists (ServerLink, FakeLink in tests, MatchView, Palette, Fonts,
  TouchInput for touch lists, game.rs `start`, events, hub).
- Touch: every new list is a ScrollContainer (TouchInput scrolls it by finger); no hover-only information.
- Commit on your branch; message ends with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01EiXgp8TjHJ4tufzuCLnDgH`. Do not push, do not merge.
- Report (Russian, short): branch, commits, files, protocol/DB you added, what you did not do, test result lines.

## A — admin settings and invite keys (server + admin panel + client register form)

DB (M8):
- `server_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)`; keys `autobot_wait_ms` (0..600000, default
  30000) and `signup_invite_only` ("0"/"1", default "0"). A small `settings` module: get/set with a cache.
- `signup_keys(id INTEGER PK, key TEXT UNIQUE NOT NULL (uuid v4), note TEXT NULL, uses_total INT, uses_left INT,
  created INT, created_by INT NULL (account id), created_by_name TEXT, revoked INT 0/1)`.
- `accounts.signup_key INTEGER NULL` (the key an account registered with; NULL = none).

Behaviour:
- The autobot wait (bots/auto.rs `WAIT_MS`) comes from `autobot_wait_ms` at start and on every change; 0 = an
  autobot comes at once. Applies to every queue that has autobots today.
- Registration (`register`): when invite-only is on, a valid key is needed: `register {user, password, key}`.
  The key's use is taken in the same DB transaction as the account insert with
  `UPDATE signup_keys SET uses_left = uses_left - 1 WHERE key = ? AND uses_left > 0 AND revoked = 0`
  (rows_affected must be 1) — no race can overspend a key; a failed insert (name taken) rolls the use back.
  Errors: `{"t":"error","code":"invite_required"}`, `"invite_invalid"` (unknown, used up or revoked).
  With invite-only off a key is optional; a valid given key is still recorded and spent.
- `signup_info {}` → `{"t":"signup_info","invite_only":bool}` (works before login). Older servers answer
  bad_request: the client then shows no key field.
- Admin panel: a Settings page (autobot wait in seconds 0–600, invite-only switch), an Invite keys page (create:
  note, uses default 1, max 1000; list: key (copy button), note, uses left/total, created by, created at, revoke;
  the accounts that joined with it), and on the account page "Joined with key … (made by …)" or "without a key".
  Admin API under `/admin/api/settings` and `/admin/api/signup_keys`. Events logged (`setting`, `signup_key`).
- Client: the register form asks `signup_info` and shows an "Invite key" field when needed (paste button as the
  other fields); the server's error codes in the player's language.

## B — replays (server + admin + client)

Replay data (JSON, `v: 1`), enough to rebuild the game with the engine:
`{format: "classichs-replay", v: 1, game, mode, pack (rules_hash), pack_id, pack_name, started, ended,
  players: [{name, hero, cards: [30 ids]}, …] (seat order), seed, first, actions: [action, …] (every applied
  action in order, mulligans and choices too), result: {winner, reason, turns}, hash (final state hash)}`.
The engine must rebuild it exactly: check the final `hash` in tests (server: rebuild with
`classichs-engine`; client: rebuild with the rules GDExtension).

Server:
- M9: `replays(game TEXT PRIMARY KEY, pack TEXT, p0 INT NULL, p1 INT NULL, ended INT, data BLOB)`; data =
  the JSON deflate-compressed (an existing dependency if one fits, else `flate2`). Written when a game ends (every
  mode, also tournament games). Kept: all (no retention for now).
- `replays {}` → `{"t":"replays","list":[{game, mode, pack, pack_name, opponent, won, started, ended, turns}]}`:
  the player's last 50 games.
- `replay {game}` → `{"t":"replay","game", "data": {…}}` for the game's players; other access goes through a
  function `replays::can_view(app, account, game) -> bool` that D extends (tournament games). Else
  `error not_found`.
- Admin: the game page gets "Download replay" (`/admin/api/games/{id}/replay`, a .chsreplay file) and shows the
  action list (there is an event list already: reuse).

Client:
- `game/replay.gd` (class Replay): from data / to file; `build(k)` → a GameView of the game after k actions
  (engine: new game with the decks, seed, first; apply actions 0..k-1); turn starts index.
- `ui/replay_view.gd`: the table (MatchView in a read-only replay mode, both hands face up) with controls:
  to start, step back, play/pause, step forward, to end, a slider over all actions, "turn N" jumps, the players'
  names and heroes, the result. No time: actions only.
- Local store: the last 10 games (`user://replays/`, oldest dropped): local games (training vs bot, code play)
  from the Match history, server games fetched with `replay {game}` after `game_over`.
- Game menu (the pack's menu, Direct and Server): "Replays" → list (local last 10; on a server also "on this
  server": `replays {}`), Watch, Export (a `.chsreplay` file; web: download, Android: share/save as the pack
  export does), Import (pick a file; the game's pack must be installed with that rules hash, else say which).

## C — spectators (server + client)

Server (a module `spectate`):
- `spectate {user}`: watch a friend's live game (friends only; one game at a time per spectator; max 20
  spectators per game). Answer `{"t":"spectating","game","mode","pack","players":[n0,n1],"seat":friend's seat,
  "full":false}` and at once a `{"t":"spectate_state","game","view","events":[],"result":{…}}` with the current
  view, then one `spectate_state` per change (as `state`, same shape). `full:false` = the friend's view (the
  friend's hand open, the opponent's hidden); `full:true` = both hands open.
- A public function `spectate::add(app, game, account, full: bool) -> Result<(), &str>` that D uses for
  tournament matches (D checks who may).
- `unspectate {}`; at the end `{"t":"spectate_end","game","winner","reason"}`.
- The friends list carries `in_game: {game, mode}` (or a flag) so the client shows "Watch".
- The players are not told who watches (no info leak); spectators get no `intent`/`emote` of the players.

Client:
- social.gd friends list: "Watch" for a friend in a game.
- A spectator table: MatchView in a watch mode (no actions, no timer controls, "Leave"), fed by the spectator
  states; with `full:true` both hands face up. Main opens it from anywhere like a match.

## D — tournaments (server = D-server, client = D-client)

Terms: a tournament has entrants; it is played in matches (two entrants, a series of games); a series follows
its rules (Conquest or Last Hero Standing) and its length (best of 1, 3, 5, 7: wins needed = (bo+1)/2).

Options (create; `*` = fixed after creation, the rest editable until 10 min before the start):
- `name` (3–40), `pack`* (rules_hash of a server pack), `start_at` (unix ms, from now+11 min to now+14 days),
  `max_players` (2–128), `min_players` (2..max, default 2),
- `format`: `round_robin` {rounds: 1|2}, `swiss` {rounds: 1..10 (default ceil(log2 n)), drop_after: 0 (never) or
  1..5 losses}, `elimination` {losses: 1 (single) or 2 (double: a losers bracket, then a grand final)},
  `scheveningen` (two teams, random and balanced at seeding; everyone plays everyone of the other team),
- `series`*: `conquest` | `lhs`; `best_of`*: 1|3|5|7; `bans`: 0|1; decks per entrant = wins needed + bans, each a
  different class (hero), each a valid deck of the pack,
- `deck_reveal` (bool: from 10 min before the start to the end everyone sees every entrant's decks),
- `spectators` (bool: the creator and eliminated entrants may watch running matches, full view).

Lifecycle (server clock): `open` → (T−10 min) `locked`: rules, decks, reschedule frozen; fewer than min_players →
`closed` (reason "not enough players") → (T−1 min) `seeded`: the bracket is made (random seeds), joining stops
→ (T) `running` → `finished` (places) | `cancelled` (the creator, any time). Join/leave until T−1 min; decks change
until T−10 min (the decks are copied when given: deleting them from the collection changes nothing).
Reschedule (later only) until T−10 min. Limits: a creator has at most 3 tournaments not finished/cancelled/closed;
at most 10 created per day per account; 128 entrants max; name and option checks; only the creator edits.

Matches: a match becomes ready when both entrants are free (not in another game of this tournament). Steps,
each with a deadline: `accept` (60 s; no answer = that game lost by forfeit), `ban` (60 s, if bans: each bans one
of the opponent's decks; timeout = a random one), `pick` (60 s; timeout = the first usable deck), then the game
(mode `tournament`; usual turn timers; concede any time). Conquest: a deck that won a game can't be used again in
the match. LHS: the losing deck is out; the winner keeps the winning deck for the next game (no pick), the loser
picks from what is left. The series ends at the wins needed. Byes count as a match won.
Rounds: round robin (circle method) and Scheveningen are fixed at seeding; swiss pairs each round when the
previous one ends (same points, no rematch, a bye for odd); elimination: a bracket to the next power of two with
byes, double = a losers bracket and a grand final (no reset).
Places: round robin / swiss / Scheveningen by match points, then game wins − losses, then (swiss) Buchholz;
elimination by the round where one went out. Top 3 highlighted in the client and the admin panel.

Protocol (client → server; answers in brackets):
- `t_list {tab: "upcoming"|"finished"|"closed"}` → `{"t":"t_list","tab","list":[summary]}`
  summary = {id, name, creator, pack, pack_name, format, series, best_of, start_at, status, entrants, max_players,
  joined (bool)}
- `t_get {id}` → `{"t":"tournament","t":{…full…}}` and subscribes to its changes (`t_unwatch {id}` stops);
  full = summary + options + entrants [{name, seed, team, eliminated, place, points, wins, losses, decks?}] (decks:
  own always; others only when revealed: [{name, hero, cards}]) + rounds/matches [{id, round, bracket ("w"|"l"|"gf"
  for elimination, "" else), slot, p: [name|null, name|null], status, score: [a, b], winner, games: [game ids]}] +
  `can` flags for the asking player {edit, cancel, reschedule, join, leave, decks, spectate}.
- `t_create {name, pack, format, options, series, best_of, bans, start_at, max_players, min_players,
  deck_reveal, spectators}` → `tournament`; `t_edit {id, …editable}`; `t_reschedule {id, start_at}`;
  `t_cancel {id}`
- `t_join {id, decks: [{name, hero, cards}]}`; `t_decks {id, decks}`; `t_leave {id}`
- `t_accept {match}`; `t_ban {match, deck: index into the opponent's decks}`; `t_pick {match, deck: own index}`
- `t_spectate {match}` → C's `spectating` / `spectate_state` with `full:true` when allowed.
- Server pushes: `tournament {t}` to watchers on any change; `t_match {tournament, name, match, phase:
  "accept"|"ban"|"pick"|"wait"|"done", deadline (unix ms), opponent, score, mine: [{hero, name, state: "ok"|
  "banned"|"won"|"lost"}], theirs: [{hero, state}]}` to the two entrants (anywhere in the client); the game then
  starts with the usual `match` message (`mode: "tournament"`, extra `tournament`, `match`).
- Errors: `{"t":"error","code":"tournament", "text": …}` with a human text.

D-server: module `tournament` (+ `tournament/format.rs` for pairings and places as pure functions with unit
tests: round robin, swiss, single/double elimination, Scheveningen, places, byes); a scheduler tick (every few
seconds) for the lifecycle and the deadlines; tables in M10 (tournaments, entrants with copied decks, matches,
match games); GameMode `tournament` (no rating change); admin page (list, a tournament's bracket and entrants,
cancel). Spectating via C's `spectate::add` and replays via B's `replays::can_view` — until those land, write
against these names (stubs allowed; the integrator connects them).

D-client: the server's game menu gets "Tournaments": tabs Upcoming / Finished / Closed, Create (a form with all
options and their limits), a tournament page (rules, start time in local time with a countdown, entrants, join
with deck picks of distinct classes from the player's decks of that pack, leave, change decks, the creator's
edit/reschedule/cancel), the bracket drawn well (elimination: a tree with the losers bracket; round robin: a
cross table; swiss: rounds with pairings and standings; Scheveningen: two team columns and a grid), the player's
match panel (accept / ban / pick with countdowns, works from any screen as a popup like a friendly invite), Watch
buttons for allowed spectators, Replays per match (B's `replay {game}` + ReplayView), places with the top 3
highlighted. Against a FakeLink in tests (no real server needed); a real local server check once D-server exists.
