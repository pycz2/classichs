# Testing and validating

Four checks, from the fastest to the most real: the file check, a bot-vs-bot run, a game you play yourself, and the server's check when you upload.

## 1. tools/pack.py check

`build` runs it every time; run it alone on any `.cardpack` (yours, or one you were sent):

```sh
python3 tools/pack.py check tiny.cardpack
# tiny.cardpack: 0 errors, 0 warnings
```

It needs only Python 3 and reads the files, not the Lua. Errors (exit code 1, `build` writes nothing):

- **The zip:** paths and folders outside the layout, a bad extension, hidden files, links, a file twice, sizes over the limits, zip bombs.
- **The schemas:** every JSON file against `docs/packs/schema/*.schema.json` — strict JSON (no duplicate keys, no fractions), required fields, types, allowed values.
- **References:** every card's class, rarity, race, set and mechanics exist in `rules.json`; every mechanic maps to an engine id; champions point at `POWER` cards; every `script` file exists; art, sound and music folders match the manifest's sets; every language in `locales` has its file and every card a name in the default one; mission cards exist; rank emblems exist; `ui/theme.json` and the fonts and pictures it names.
- **Decks:** every ready deck is legal by your rules (size, class, copies by rarity, the mode's sets, collectible cards only).
- **Hashes:** `rules_hash` in the manifest matches the files.

Warnings (the pack still builds): a card without a picture in an art set, a picture of no card, an unknown effect name in `fx`, a sound in no set, a keyword without a name or tooltip, a text for an unknown card.

What `check` can't see: the Lua itself. A typo in a script, an unknown hook name or `default_power` missing is found by the engine when it loads the pack — the next step.

## 2. A quick bot-vs-bot run: tools/pack_try.gd

```sh
godot --headless --path . --script res://tools/pack_try.gd -- tiny.cardpack 10
```

From the source folder of {name} (it needs Godot 4.7.2 and the rules engine in `rules/bin/`: `tools/build_rules.sh` builds it). It loads your pack into the real engine — which compiles every script — and plays the given number of games (3 by default) with your ready decks, each deck against the next, bot against bot, both seats:

```
loaded tiny-duel 0.1.0, rules_hash 7705adf3…
game 1: Dawn vs Dusk, turn 14, 51 actions, won by Dawn
game 2: Dusk vs Dawn, turn 15, 51 actions, won by Dawn
…
4 games, 0 failed
```

A script that fails is shown with its file, line and traceback, and the exit code is 1:

```
ERROR: game 1 (Dawn vs Dusk): a card script failed at turn 10, 32 actions:
  scripts/sun.lua:16: attempt to call a nil value (field 'damge') (scripts/sun.lua:16: in function 'battlecry')
```

A pack the engine refuses says why: `ERROR: the engine refuses the pack: bad pack: rules.json: default_power "" is not a POWER card`. A game that stops moving is reported as stuck. Bot games reach most cards quickly; win rates over many games are a first look at balance (Neonfall's balance was tuned with 6000-game runs, `packs/neon/DESIGN.md` §9).

## 3. Play it in the game

1. *Games → Import a game file*, choose your `.cardpack`, *Play this game*.
2. *Play → Training*: your deck against the bot, any champion.
3. *Settings → Debug tools* (with your game active):
   - **Scene** — build any position with the mouse: champions, mana, health, armor, the cards in each hand, board, deck, traps and weapon; play it against the bot or for both sides (hot seat). The scene is also JSON you can edit.
   - **Card test** — how a card's name and text sit on the card, in all 8 languages at once, with layout problems listed.
   - **Effects test** — any card of your game on the board, in the hand or as a champion, with buffs, debuffs and states switched on and off, as a match draws it.
4. Change a file, build again, import again: a changed pack (any file) is added next to the old one in *Games*; delete the old one there.

## 4. The server's check

A game server checks every pack it is given (a player's upload, an admin's, or a file in its `--packs-dir`): the zip and the manifest by the format, the `rules_hash` against the files, then — unless a pack with the same rules passed before — the engine loads the rules, compiles every script and its bot plays a trial game with your first two legal ready decks, trying every legal move on a copy at each step. A script error, an engine failure, a stuck game or more than 20 seconds refuses the pack with the reason. Passing `pack_try.gd` first saves a round trip.

## Checklist before you share a pack

- `python3 tools/pack.py build …` — 0 errors; read the warnings.
- `pack_try.gd … 20` — 0 failed.
- Every card played once by hand (Debug tools → Scene is the fastest way).
- Texts in every language you list; a picture for every collectible card (or accept the drawn ones).
- `redistributable: true` if friends and servers may pass it on; a `license` that says so.
- A new `version` for people, and remember: a change to rules, cards, missions or scripts is a new game (`rules_hash`) — players need the new file to play together.

## For the engine's own developers

The engine's tests run the built-in packs in Rust: `cd rust && cargo test --release` (every Classic card against 7833 recorded games, every Neonfall card in a scenario — `rust/engine/tests/neon.rs`), and `python3 -m unittest tools/test_pack.py` tests `pack.py` itself. `python3 tools/neon_check.py` checks Neonfall's source (fields, the 8 locales, decks, art and sound files) and writes its card tables into `packs/neon/DESIGN.md`; a similar script is a good idea for a big pack of your own. `python3 tools/lua_api.py --check` fails when the engine's `g` functions and their documentation drift apart; the [Engine API](api.html) page is made by it.
