# classichs-engine

The rules engine of Classic HS (Hearthstone Classic, June 2014) in Rust: every
rule, every card, the bot, the Arena draft and deck rules. It is a port of the
GDScript engine (`engine/`, `cards/`, `game/bot.gd`, `game/arena_draft.gd`,
`game/deck.gd`, the rules part of `game/missions.gd` and `game/tutorial.gd`)
and behaves exactly like it: the same actions from the same seed give the same
events and the same `state_hash()` (see Parity below).

No I/O, no threads; dependencies: serde, serde_json, sha2. Builds for the host,
`wasm32-unknown-unknown` and `aarch64-linux-android`. Card data
(`data/cards.json`) is embedded at build time.

## Layout

| Rust | GDScript |
|---|---|
| `rng.rs` | Godot `RandomNumberGenerator` (PCG32): seed, `randi`, `randi_range`, `randf`, `state` |
| `json.rs` | Godot `JSON.stringify` (sorted keys, number format, escaping) for the hash |
| `card_db.rs` | `engine/card_db.gd` |
| `entity.rs`, `player.rs` | `engine/entity.gd`, `engine/player.gd` |
| `state.rs` | `engine/game_state.gd`: entities, events, triggers, death phase, auras, primitives |
| `game.rs` | `engine/game.gd`: setup, mulligan, turns, actions, legality |
| `cards/*.rs` | `cards/*.gd`, one file per class; `cards/mod.rs` = `registry.gd` + `t.gd` |
| `scenario.rs` | `engine/scenario.gd` |
| `bot.rs` | `game/bot.gd` |
| `arena_draft.rs`, `deck.rs`, `missions.rs` | `game/arena_draft.gd`, `game/deck.gd` + `decks.gd`, `game/missions.gd` + `tutorial.gd` |
| `api.rs` | `net/referee.gd` and more: the JSON API |

A card hook is a plain function `fn(&mut Game, me, target)`; entities are ids
(`-1` = none); events are JSON objects in `Game::event_log`, and triggers get
the index of their event, so a hook that changes an event (Counterspell,
Misdirection, Spellbender) changes the logged one, as in GDScript.

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
| `data_hash` | | `hash`: SHA-256 of cards.json (`CardDb.data_hash()`) |
| `hooks` | | `hooks`: card id → what hooks it has (`on`: event types, `aura`, `deathrattle`, `combo`, `choose_one`: [a, b], `secret`, ...) for glows and effects |
| `new` | `game`, `decks: [deck, deck]`, `seed`, `first?` (0/1, default: random), `check?` (default true: decks must be legal; false for tests) | state reply + `events` (the opening draws) |
| `new` | `game`, `scenario` (the Debug Table format, `engine/scenario.gd`) | state reply + `events` (`[]`) |
| `new` | `game`, `mission` (1-6: a tutorial mission with its rules) | state reply + `events` |
| `act` | `game`, `action`, `view?` | state reply + `events`; `ok: false` + `error` if illegal (nothing changes). After the game is over: `ok: true`, no change (as the referee) |
| `legal` | `game`, `player?` | `actions`: the legal actions, in the engine's order |
| `bot` | `game`, `player` | `action`: what `Bot.choose` takes (`null`: nothing to do) |
| `snapshot` | `game`, `view?` | `state`, see below |
| `hash` | `game` | `hash`: `state_hash()` |
| `history` | `game`, `from?`, `view?` | `history`: `[{turn, player, action, events}]` (entry 0 is the start), `start_decks` |
| `dump` | `game` | `scenario`: the position as a scenario (`Scenario.dump`) |
| `end_turn_block` | `game`, `player` | `block`: why a tutorial mission does not let the player end the turn yet (`""`: it does), `mission` |
| `drop` | `game` | |
| `validate` | `deck` | `ok`, `error` (English, as `Deck.validate()`) |
| `draft` | `seed`, `hero?` (0-2), `picks?` | `heroes`, `hero`, `cards`, `offer`, `done` (stateless, as the referee) |

The state reply (as the referee's): `ok`, `game`, `hash`, `over`, `winner`
(-1: none or a draw), `turn`, `current`, `phase` (`MULLIGAN`, `PLAY`, `OVER`).

A deck: `{"hero": "HERO_08", "cards": [30 card ids], "arena": false}`.

Actions (exactly the objects `legal` lists):
`{"type": "mulligan", "player", "replace": [ids]}`, `{"type": "end_turn", "player"}`,
`{"type": "play", "player", "entity", "target", "pos", "choice"}`,
`{"type": "attack", "player", "attacker", "defender"}`, `{"type": "hero_power", "player", "target"}`,
`{"type": "choose", "player", "option"}` (Tracking), `{"type": "concede", "player"}`.
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

`tests/parity.rs` replays games recorded from the GDScript engine by
`tools/engine_record.gd` and checks, at every step, the legal actions (hash of
the list), the bot's choice where the bot chose, ok/error, the events (hash or
full list) and the state hash; at the end of each game the `Scenario.dump`.
`misc.jsonl` checks the RNG, the mulligan seed, the referee's `draft` and
`validate`.

```sh
# committed set (tests/fixtures)
godot --headless --path . --script res://tools/engine_record.gd -- \
    --out rust/engine/tests/fixtures --games 120 --reps 1 --extra 4 --seed 1
# big set (tests/fixtures/big, gitignored; a few minutes)
godot --headless --path . --script res://tools/engine_record.gd -- \
    --out rust/engine/tests/fixtures/big --games 3000 --reps 4 --extra 25 --seed 2
cd rust && cargo test -p classichs-engine -- --nocapture   # prints games, steps, cards covered
```

Games: random and bot play from random seeds with Basic class decks, random
30-card decks from the whole pool and random class decks; every card test scene
of `data/card_tests` with its steps; random positions (Scenario) that start by
playing each playable card (tokens and tutorial cards included) with random
boards, weapons, secrets and hero powers; the six tutorial missions; illegal
and malformed actions.

When a step differs, record that game with full events:
`--only N --full` (games.jsonl) and diff.

The mulligan shuffle seed is `Game.mulligan_seed` (splitmix64 of the game seed
and the player) in both engines; it replaced Godot's internal `hash()`, which
Rust cannot reproduce (online protocol 2).
