# classichs-engine

The rules engine of Classic HS in Rust: the general mechanics of a card game
(turns, mana, combat, keywords, triggers, auras, deaths), the bot, the Arena
draft and deck rules. It knows no game of its own: a game pack gives the rules,
cards, mechanic names and the Lua hooks of every card (below); the built-in
ruleset is the Classic pack (Hearthstone Classic, June 2014). It is the only rules
code of the game: the server links it, the game reaches it through GDExtension
(`rust/godot`, class `RulesEngine`) on desktop and Android and as WebAssembly
(`rust/wasm` + `web/rules.js`) in the browser; GDScript only draws snapshots
(`game/rules.gd`, `game/game_view.gd`; docs/superpowers/specs/2026-10-15-thin-client-design.md).
It was ported from the GDScript engine (`engine/`, `cards/`, `game/bot.gd`, …,
removed in 0.27) and behaves exactly like it: the same actions from the same seed
give the same events and the same `state_hash()` (see Parity below).

No I/O (except `load_pack` by path on native hosts), no threads; dependencies:
serde, serde_json, sha2, miniz_oxide (zip inflate), classichs-script (the Lua
subset, `rust/script`). Builds for the host, `wasm32-unknown-unknown` and
`aarch64-linux-android`.

**Game packs** (docs/packs/, D1–D19 of docs/superpowers/plans/2026-10-16-game-packs.md):
everything a game needs is a *ruleset* (`ruleset.rs`) made from a pack's
`rules.json`, `cards.json`, missions and Lua card scripts. The engine keeps the
pack's mechanic names (D7): tags in snapshots, events and the state hash are the
pack's words, and the engine finds them through `Ruleset::names` (engine ids of
docs/packs/schema/keywords.json → pack names). The built-in ruleset is the
Classic pack, embedded at build time (`build.rs`: `packs/classic` rules,
missions and scripts, and its `cards.json` made from `data/cards.json` +
`cards.patch.json` as `tools/pack.py` does, without the texts). Every API call
without `pack` plays it, so older hosts work unchanged.

Card hooks are Lua only (`packs/classic/scripts/*.lua` for Classic,
docs/packs/api.md); a card without a `script` has none. Nothing in `src/` names
a card, a class, a race, a rarity or a mechanic of a particular game: the opening
(`start`: hands, the coin, `first_player_draws`), how the bot plays
(`bot.trap`, `bot.depth`; Classic's bot counts no trap and looks one action
ahead), champions and their powers (`classes`, a champion's `power`,
`default_power`), the Arena's classes and odds, starter decks
(`modes.constructed.starter_rarities` + `starter_core`) and copy limits come
from `rules.json`; mechanics are the neutral ids of
docs/packs/schema/keywords.json inside (`Names`, hook fields such as `on_play`,
`on_death`, `trap`, `power`, `choice`) and the pack's names only where the engine
reads or writes tags. Card types are the pack's (`CHAMPION`, `POWER`, …);
snapshots show a CHAMPION as `HERO` and a POWER as `HERO_POWER`, and the
`hooks` op keeps its keys (`battlecry`, `deathrattle`, `secret`, `hero_power`,
`choose_one`), as clients know them. Event types and snapshot field names
(`secret_revealed`, `divine_shield_lost`, `secrets`, `ol_owed`, …) are the
engine's protocol and stay as recorded (parity). Texts are the clients' (a
tutorial's end-of-turn block is a reason key).

## Layout

| Rust | GDScript |
|---|---|
| `rng.rs` | Godot `RandomNumberGenerator` (PCG32): seed, `randi`, `randi_range`, `randf`, `state` |
| `json.rs` | Godot `JSON.stringify` (sorted keys, number format, escaping) for the hash |
| `card_db.rs` | `engine/card_db.gd` |
| `entity.rs`, `player.rs` | `engine/entity.gd`, `engine/player.gd` |
| `state.rs` | `engine/game_state.gd`: entities, events, triggers, death phase, auras, primitives |
| `game.rs` | `engine/game.gd`: setup, mulligan, turns, actions, legality |
| `hooks.rs` | `t.gd` + the hook set of a card (what the engine calls; the card logic of `cards/*.gd` is the pack's Lua) |
| `ruleset.rs` | a pack's rules, cards, names, missions and hooks; the built-in Classic ruleset; the cache by rules_hash |
| `pack.rs` | reading a `.cardpack` (zip) or a folder, strict and canonical JSON, `rules_hash` (docs/packs/format.md §3) |
| `lua.rs` | loading card scripts, the `g` library (docs/packs/api.md), calling hooks, script errors |
| `scenario.rs` | `engine/scenario.gd` |
| `bot.rs` | `game/bot.gd` (+ the pack's `bot` settings, docs/packs/rules.md) |
| `arena_draft.rs`, `deck.rs`, `missions.rs` | `game/arena_draft.gd`, `game/deck.gd` + `decks.gd`, `game/missions.gd` + `tutorial.gd` |
| `api.rs` | `net/referee.gd` and more: the JSON API |

A card hook is a Lua function (`hooks::HookFn`, an index into the ruleset's
script functions); entities are ids (`-1` = none); events are JSON objects in
`Game::event_log`, and triggers get the index of their event, so a hook that
changes an event (a counter, a redirect) changes the logged one, as in GDScript
(the hook gets the event as a table; changed fields are copied back).

Lua runs on two interpreters per ruleset (`lua.rs`): the main one (a game
checks it out for a call and shares it with its look-ahead copies, so the bot
does not copy the Lua heap per action; scripts keep no state of their own) and
a read-only one for the hooks the engine calls while it only reads the game
(target filters, `can_play`, `cost_mod`, `cost_aura`). A script error ends the
game as a draw (`game_over` event with `reason: "script_error"`, `script_error`
in state replies), never a panic.

## JSON API

```rust
let mut engine = classichs_engine::Engine::new();
let reply: String = engine.call(r#"{"op": "ping"}"#);
```

One request (a JSON object with `op`) in, one reply out. Every reply has `ok`;
a refused request has `error`. Games are kept by `game` id (any string), so one
`Engine` serves many games. Ints may come as JSON floats (`3.0`), as Godot
sends them. Native hosts may also use `Engine::handle(&Value)`,
`Engine::game(id)` and the Rust types directly.

`view` (in `new`, `act`, `history`, `snapshot`): `-1` or absent = everything;
`0`/`1` = what that player may see: the card of an entity in a deck, in the
opponent's hand or among the opponent's secrets is `""` (an event's `card`
included), decks are given as `deck_count` only, and the RNG state is left out.

| op | request | reply |
|---|---|---|
| `ping` | | `version`, `engine`, `data` (card data hash) |
| `load_pack` | `data` (a `.cardpack` as base64) or `path` (native: a `.cardpack` or an unpacked pack folder) | `pack` (its rules_hash), `id`, `version`; `ok: false` + `error` for a bad pack (format, limits, rules, cards, scripts that do not load) |
| `packs` | | `packs`: `[{pack, id, version, builtin}]`, the built-in Classic one first |
| `data_hash` | `pack?` | `hash`: SHA-256 of data/cards.json for the built-in ruleset (`CardDb.data_hash()`), a pack's rules_hash |
| `hooks` | `pack?` | `hooks`: card id → what hooks it has (`on`: event types, `aura`, `deathrattle`, `combo`, `choose_one`: [a, b], `secret`, ...) for glows and effects |
| `new` | `game`, `decks: [deck, deck]`, `seed`, `first?` (0/1, default: random), `check?` (default true: decks must be legal; false for tests) | state reply + `events` (the opening draws) |
| `new` | `game`, `scenario` (the Debug Table format, `engine/scenario.gd`) | state reply + `events` (`[]`) |
| `new` | `game`, `mission` (1-6: a tutorial mission with its rules) | state reply + `events` |
| `new` | `game`, `copy` (another game's id) | state reply: the same position (RNG included; no history) |
| `new` | `game`, `state` (a `snapshot`, also a player's view) | state reply: a playable game from it (`view.rs`); hidden cards become a filler minion, decks of a view are made of hidden ids. A client of a server finds its legal actions with it (they equal the server's, `tests/api.rs`). Not for parity: no RNG, history or start decks |
| `act` | `game`, `action`, `view?` | state reply + `events`; `ok: false` + `error` if illegal (nothing changes). After the game is over: `ok: true`, no change (as the referee) |
| `legal` | `game`, `player?` | `actions`: the legal actions, in the engine's order |
| `bot` | `game`, `player` | `action`: what `Bot.choose` takes (`null`: nothing to do) |
| `snapshot` | `game`, `view?` | `state`, see below |
| `hash` | `game` | `hash`: `state_hash()` |
| `history` | `game`, `from?`, `view?` | `history`: `[{turn, player, action, events}]` (entry 0 is the start), `start_decks` |
| `dump` | `game` | `scenario`: the position as a scenario (`Scenario.dump`) |
| `end_turn_block` | `game`, `player` | `reason`: why a tutorial mission does not let the player end the turn yet (`while_can_play`, `while_can_attack`; `""`: it may), a key the client turns into words, `mission` |
| `drop` | `game` | |
| `validate` | `deck`, `pack?` | `ok`, `error` (English, as `Deck.validate()`) |
| `draft` | `seed`, `hero?` (0-2), `picks?`, `pack?` | `heroes`, `hero`, `cards`, `offer`, `done` (stateless, as the referee) |

Every `new` takes `pack` (a rules_hash from `load_pack`; absent: built-in
Classic); `copy` keeps the copied game's pack.

The state reply (as the referee's): `ok`, `game`, `hash`, `over`, `winner`
(-1: none or a draw), `turn`, `current`, `phase` (`MULLIGAN`, `PLAY`, `OVER`),
and `script_error` (the message) once a card script failed and ended the game.

A deck: `{"hero": "HERO_08", "cards": [30 card ids], "arena": false}`.

Actions (exactly the objects `legal` lists):
`{"type": "mulligan", "player", "replace": [ids]}`, `{"type": "end_turn", "player"}`,
`{"type": "play", "player", "entity", "target", "pos", "choice"}`,
`{"type": "attack", "player", "attacker", "defender"}`, `{"type": "hero_power", "player", "target"}`,
`{"type": "choose", "player", "option"}` (a `g.request_choice`), `{"type": "concede", "player"}`.
`target`/`pos`/`choice` are `-1` when not used.

### Snapshot

The full snapshot (`view` -1) is GDScript `GameState.to_dict()` (the object
whose JSON is hashed) plus what a client needs to draw:

- `turn`, `current`, `phase`, `rng` (state), `next_id`, `next_order`,
  `pending` (`{}` or `{player, source, options, zones}`), `game_over`, `winner`,
  `start_decks`, `view`, `history_len`.
- `players[i]`: `hero`, `power`, `weapon` (ids, -1), `hand`, `deck` (top card
  last), `board` (left to right), `secrets`, `mana`, `max_mana`, `ol_owed`,
  `ol_locked` (overload), `fatigue`, `played`, `minions_played`, `cost_mods`,
  `mulliganed`, `mulligan_replace`, plus `deck_count`, `spell_damage`.
- `entities["<id>"]`: `card`, `ctrl`, `zone` (`DECK`, `HAND`, `PLAY`, `SECRET`,
  `GRAVEYARD`, `SETASIDE`), `order`, `dmg`, `tags` (keywords, `ARMOR`,
  `DURABILITY`, `ATTACKS`, `EXHAUSTED`, `FROZEN`, ...), `ench` (enchantments),
  `eot` (tags that end this turn), `sil` (silenced), plus `type`, `atk` (a
  hero's includes the weapon on its own turn), `health`, `max_health`, `cost`
  (now, with every modifier), `aura` (`atk`, `hp`, `tags`, `src`: which card
  gives what). A keyword is active if it is in `tags` or `aura.tags`.

A player view leaves out deck entities (except the options of the viewer's own
pending choice), shows hidden entities as `{card: "", ctrl, zone, order}`,
empties `deck` and drops `rng`.

Known leak, kept for parity: entity ids are given out in deck-list order before
the shuffle, so an opponent who knows your list can tell which card a hidden id
is. A server that hides hands should map ids in its views.

## Parity

`tests/parity.rs` replays games recorded from the GDScript engine and checks, at every step, the legal actions (hash of
the list), the bot's choice where the bot chose, ok/error, the events (hash or
full list) and the state hash; at the end of each game the `Scenario.dump`.
`misc.jsonl` checks the RNG, the mulligan seed, the referee's `draft` and
`validate`.

The fixtures are frozen: the GDScript engine and its recorder
(`tools/engine_record.gd`) were removed in 0.27, when the game switched to this
engine (they are in git history before that; the last big run: 7833 games, 0
mismatches). A rules change now changes the fixtures on purpose: update the
recorded expectations with the change and say so in the changelog.

```sh
cd rust && cargo test -p classichs-engine -- --nocapture   # prints games, steps, cards covered, time
PARITY_BIG=0 PARITY_FILTER=MAGE cargo test -p classichs-engine --test parity -- --nocapture  # quick: some games
```

`PARITY_FILTER` (card ids, class names, `lua`) replays only the games that
mention those cards; `PARITY_BIG=0` skips `fixtures/big` (docs/packs/api.md,
"Porting"). `tests/packs.rs` checks the built-in ruleset's rules_hash against
`tools/pack.py`, loading a pack, the pack's names in snapshots, Lua hooks and
script errors.

Games: random and bot play from random seeds with Basic class decks, random
30-card decks from the whole pool and random class decks; every card test scene
of `data/card_tests` with its steps; random positions (Scenario) that start by
playing each playable card (tokens and tutorial cards included) with random
boards, weapons, secrets and hero powers; the six tutorial missions; illegal
and malformed actions.

The mulligan shuffle seed is `Game.mulligan_seed` (splitmix64 of the game seed
and the player) in both engines; it replaced Godot's internal `hash()`, which
Rust cannot reproduce (online protocol 2).
