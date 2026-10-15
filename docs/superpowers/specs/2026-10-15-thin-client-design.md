# Thin client: one rules module in Rust for every platform

Date: 2026-10-15. Status: binding design for the integration of `rust/engine`.

## Goal

All game logic lives in one Rust crate, `rust/engine` (`classichs-engine`,
exact parity with the old GDScript engine, see its README). Godot only shows
the game: it sends actions and draws snapshots and events. The same crate runs
natively in the game server, through GDExtension in the desktop and Android
builds, and as WebAssembly in the browser. No rules code is duplicated.

## Bridges (decided after a spike, see "Spike" below)

| Platform | How Godot reaches the engine |
|---|---|
| macOS (universal), Windows x86_64, Linux x86_64, Android arm64 | GDExtension built with gdext 0.5.5 (`api-4-7`): crate `rust/godot` (`classichs-godot`), class `RulesEngine` (RefCounted) with `call_json(request: String) -> String` around one `classichs_engine::Engine`. Config `rules/classichs.gdextension`, libraries in `rules/bin/` (built, not committed). |
| Web | crate `rust/wasm` (`classichs-wasm`), target `wasm32-unknown-unknown`, plain C ABI (`alloc`, `dealloc`, `call(ptr, len)`, `out_ptr`, `out_len`); `web/rules.js` (≈30 lines) instantiates `rules.wasm` and exposes `window.ClassicRules.call_json(string) -> string`; the Web export preset loads it with `html/head_include`; build scripts copy `rules.js` and `rules.wasm` next to `index.html`. Godot calls it synchronously through `JavaScriptBridge.get_interface("ClassicRules")`. |
| Server | links `classichs-engine` as a normal Rust dependency (`path = "../rust/engine"`). |

GDScript sees one class, `Rules` (`game/rules.gd`): `Rules.request(req: Dictionary) -> Dictionary`
(not `call`: that is Object's), choosing the native class when `ClassDB.class_exists("RulesEngine")`, else
the web interface. The web build waits for `ClassicRules.ready` before the menu is usable; a build without
its library shows "the rules engine is missing" instead of the menu (no fallback).

### Spike (2026-10-15)

- Native gdext on macOS: works headless; 10 000 calls in 2 ms.
- Web, plain wasm + JavaScriptBridge: works in Chrome with the normal no-threads template; ready on the
  first frame; 10 000 calls in 28 ms; +8 KB gzip for a stub.
- Web, experimental gdext (`experimental-wasm-nothreads`, emsdk 4.0.20 = Godot 4.7.2's, nightly
  `-Zbuild-std`, the `dlink` template): builds in 11 min, but the side module imports `__cpp_exception`
  (wasm exception handling, now the default of nightly Rust for emscripten) and Godot 4.7.2 refuses it
  (LinkError). The switch that turned it off is gone from nightly 1.101; disabling the target feature
  breaks `compiler_builtins`. It would need an old pinned nightly plus emsdk and nightly in CI and the
  larger dlink template. Rejected.

## Client

- The GDScript engine (`engine/*.gd`, `cards/*.gd`, the rules in `game/bot.gd`, `game/arena_draft.gd`,
  `game/deck.gd` validation, rules in `game/missions.gd`/`game/tutorial.gd`) is removed. What only
  draws or explains (texts, history text, tutorial hints) stays in GDScript and reads snapshots.
- The UI reads a `GameView` built from engine snapshots (same field names the UI uses today, so the
  screens change little) and animates from engine events.
- Local games (training with the bot — bot moves from the `bot` op —, tutorial, debug table, card
  tests) run in the local engine with the full view.
- Server games: the client has no game of its own. To light up what can be played (and to check
  the orders queued while the table animates) it rebuilds a game from its own view with the engine
  (`new` with `state`: hidden cards become a filler minion); its legal actions equal the server's
  (rust/engine/tests/api.rs). The server still checks every `act`.
- Peer-to-peer (codes, WebRTC): both peers run the local engine with the full view (as before, both
  know both decks). Lockstep: an action is applied locally, sent with its hash; the peer applies it in
  its engine and compares. An illegal action or a different hash ends the game for both with the
  message: "Something does not add up: the two games differ. Nobody is banned." (no ban).

## Server games (authoritative)

The server keeps the only game state (engine crate). Clients get only their own view: the opponent's
hand, deck and secrets never reach them. Messages (inside the existing game WebSocket):

- S→C `match {game, mode, opponent: {user, tag}, you: 0|1, rejoin?: true}`.
- S→C `state {game, view, events, result}` after the start (opening draws) and after every applied
  action, to both players: `view` = `snapshot` for that player, `events` = the events of that action
  filtered for that player (`act` with `view`), `result` = `{over, winner, turn, current, phase,
  deadline}` (`deadline`: seconds left for the player to move).
- C→S `act {game, action}`. The server checks `action.player == you`, applies it, and answers
  `act_error {game, error}` to the sender if the engine refuses (nothing changes). After 3 refused
  actions in one game the game ends, reason `illegal`, with the "does not add up" message to both.
- Turn timer on the server: 75 s per turn (mulligan 45 s) + 5 s grace; on timeout the server plays
  the timeout moves (keep the mulligan hand, take the first option of a pending choice, end the turn).
- C→S `emote {game, id}`, `intent {game, i}` → relayed to the opponent (`from` added). Concede is the
  `concede` action. A dropped player has 30 s (as now); logging back in during a game gives
  `match {…, rejoin: true}` and a fresh `state`.
- `game_over {game, result, reason, rank?, arena?}` as before.
- Arena draft (`draft`) and deck checks (`validate`) use the engine natively. The headless Godot
  referee and its process management are removed.
- Known limit: entity ids are given out in deck-list order before the shuffle. In server games the
  opponent's list is unknown, so this leaks nothing useful; remap ids in views if that changes.

## Security

The server is the root of trust in server games: the client trusts only `state` from the server (over
`wss://` when public). In P2P games each client trusts its own engine and treats any disagreement as
the end of the game. No rules code runs in GDScript, so a modified client cannot make its own engine
accept illegal moves without it being detected by the other side.
