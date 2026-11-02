# Make your own game

A **game pack** is everything that makes a card game a particular game: its rules, champions, cards and what they do, the names of its mechanics, texts in every language, pictures, sounds, music, decks, missions and look. The engine of {name} knows only neutral mechanics ("a minion that must be attacked first", "an effect when played"); a pack names them and fills them with content.

A pack is one **`.cardpack`** file: a zip archive with a fixed layout. You write it as a folder of plain files and let `tools/pack.py` zip it, check it and stamp it with its hashes.

## A whole pack in ten files

**Tiny Duel** is the smallest pack that plays: the Sun Queen against the Moon King, eight-card decks, a vanilla minion, a minion with Taunt, a battlecry with a target, an aura, a deathrattle and a trap. Every file is below; together they are a game you can import and play.

```
tiny/
  manifest.json        who and what
  rules.json           limits, the opening, classes, rarities, mechanics, modes
  cards.json           every card: numbers, keywords, which script it uses
  scripts/sun.lua      the Sun Queen's cards
  scripts/moon.lua     the Moon King's cards
  scripts/neutral.lua  the extra card of the second player
  locales/en.json      names and texts in English
  locales/ru.json      … and in Russian
  decks/1_dawn.json    a ready deck for each champion
  decks/2_dusk.json
```

`manifest.json`:

```json
{
  "format": 1,
  "id": "tiny-duel",
  "version": "0.1.0",
  "engine": "0.28.0",
  "name": {"en": "Tiny Duel", "ru": "Маленькая дуэль"},
  "description": {"en": "Sun against Moon: two champions, a handful of cards."},
  "authors": ["Your Name"],
  "license": "CC BY 4.0",
  "redistributable": true,
  "default_locale": "en",
  "locales": ["en", "ru"],
  "art_sets": [], "sound_sets": [], "music_sets": [],
  "colors": {"classes": {"SUN": "f59f00", "MOON": "5c7cfa", "NEUTRAL": "868e96"}}
}
```

`rules.json`:

```json
{
  "format": 1,
  "limits": {"champion_health": 20, "max_mana": 10, "hand": 10, "board": 7, "deck_size": 8, "copies": 2},
  "start": {"first_player": "random", "hand": [3, 4], "coin": "spark", "mulligan": true},
  "bot": {"trap": 2},
  "fatigue": {"enabled": true, "first": 1, "step": 1},
  "timers": {"turn": 75, "fuse": 15, "mulligan": 45},
  "default_power": "sunbeam",
  "classes": [
    {"id": "SUN", "champion": "sun_queen"},
    {"id": "MOON", "champion": "moon_king"},
    {"id": "NEUTRAL", "neutral": true}
  ],
  "rarities": [{"id": "COMMON", "tier": "common"}, {"id": "RARE", "tier": "rare"}],
  "sets": ["core", "token"],
  "mechanics": {
    "WALL": {"engine": "GUARD"},
    "CRY": {"engine": "ON_PLAY"},
    "LAST_WORD": {"engine": "ON_DEATH"},
    "AMBUSH": {"engine": "TRAP"}
  },
  "modes": {"constructed": {"sets": ["core"], "class_cards": "own_and_neutral"}}
}
```

`cards.json` — champions and their powers are cards too; `spark` is what the second player gets after the mulligan (`start.coin`):

```json
[
  {"id": "sun_queen", "type": "CHAMPION", "class": "SUN", "set": "core", "health": 20, "power": "sunbeam"},
  {"id": "sunbeam", "type": "POWER", "class": "SUN", "set": "core", "cost": 2, "script": "scripts/sun.lua#sunbeam"},
  {"id": "moon_king", "type": "CHAMPION", "class": "MOON", "set": "core", "health": 20, "power": "moonlight"},
  {"id": "moonlight", "type": "POWER", "class": "MOON", "set": "core", "cost": 2, "script": "scripts/moon.lua#moonlight"},
  {"id": "spark", "type": "SPELL", "class": "NEUTRAL", "set": "token", "cost": 0, "script": "scripts/neutral.lua#spark"},

  {"id": "squire", "type": "MINION", "class": "NEUTRAL", "rarity": "COMMON", "set": "core", "collectible": true,
   "cost": 1, "attack": 2, "health": 1},
  {"id": "shield_bearer", "type": "MINION", "class": "NEUTRAL", "rarity": "COMMON", "set": "core", "collectible": true,
   "cost": 2, "attack": 1, "health": 4, "keywords": ["WALL"]},
  {"id": "archer", "type": "MINION", "class": "SUN", "rarity": "COMMON", "set": "core", "collectible": true,
   "cost": 2, "attack": 2, "health": 2, "keywords": ["CRY"], "script": "scripts/sun.lua#archer"},
  {"id": "banner", "type": "MINION", "class": "SUN", "rarity": "RARE", "set": "core", "collectible": true,
   "cost": 3, "attack": 2, "health": 3, "script": "scripts/sun.lua#banner"},
  {"id": "moon_wolf", "type": "MINION", "class": "MOON", "rarity": "COMMON", "set": "core", "collectible": true,
   "cost": 3, "attack": 3, "health": 2, "keywords": ["LAST_WORD"], "script": "scripts/moon.lua#moon_wolf"},
  {"id": "cub", "type": "MINION", "class": "MOON", "set": "token", "cost": 1, "attack": 1, "health": 1},
  {"id": "ambush", "type": "SPELL", "class": "MOON", "rarity": "RARE", "set": "core", "collectible": true,
   "cost": 2, "keywords": ["AMBUSH"], "script": "scripts/moon.lua#ambush"}
]
```

`scripts/sun.lua` (the scripts are explained step by step on [Card scripts in Lua](lua.html#worked-examples)):

```lua
local cards = {}

cards.sunbeam = {                       -- the power: deal 1 damage
  target = "any",
  hero_power = function(g, me, t) g.damage(me, t, g.hp_dmg(me, 1)) end,
}

cards.archer = {                        -- Cry: deal 1 damage to an enemy minion
  target = "enemy_minion",
  battlecry = function(g, me, t) g.damage(me, t, 1) end,
}

cards.banner = {                        -- your other minions have +1 Attack
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do g.aura_add(m, 1, 0) end
  end,
}

return cards
```

`scripts/moon.lua`:

```lua
local cards = {}

cards.moonlight = {                     -- the power: restore 2 Health
  target = "any",
  hero_power = function(g, me, t) g.heal(me, t, g.heal_amt(me, 2)) end,
}

cards.moon_wolf = {                     -- Last Word: summon a 1/1 Cub where it stood
  deathrattle = function(g, me) g.summon(g.ctrl(me), "cub", g.died_pos(me)) end,
}

cards.ambush = {                        -- a trap: when the opponent plays a minion, 2 damage to it
  secret = {
    event = "after_summon",
    cond = function(g, me, ev) return ev.played and not g.mine(me, ev) end,
    effect = function(g, me, ev) g.damage(me, ev.entity, g.spell_dmg(me, 2)) end,
  },
}

return cards
```

`scripts/neutral.lua`:

```lua
local cards = {}
cards.spark = { spell = function(g, me) g.add_mana(g.ctrl(me), 1) end }
return cards
```

`locales/en.json` (`ru.json` is the same in Russian):

```json
{
  "cards": {
    "sun_queen": {"name": "Sun Queen"},
    "sunbeam": {"name": "Sunbeam", "text": "Deal 1 damage."},
    "moon_king": {"name": "Moon King"},
    "moonlight": {"name": "Moonlight", "text": "Restore #2 Health."},
    "spark": {"name": "Spark", "text": "Gain 1 Mana this turn only."},
    "squire": {"name": "Squire"},
    "shield_bearer": {"name": "Shield Bearer", "text": "<b>Wall</b>"},
    "archer": {"name": "Archer", "text": "<b>Cry:</b> Deal 1 damage to an enemy minion."},
    "banner": {"name": "Banner", "text": "Your other minions have +1 Attack."},
    "moon_wolf": {"name": "Moon Wolf", "text": "<b>Last Word:</b> Summon a 1/1 Cub."},
    "cub": {"name": "Cub"},
    "ambush": {"name": "Ambush", "text": "<b>Ambush:</b> When your opponent plays a minion, deal $2 damage to it."}
  },
  "mechanics": {
    "WALL": {"name": "Wall", "tip": "Enemies must attack minions with Wall first."},
    "CRY": {"name": "Cry", "tip": "Does something when you play it from your hand."},
    "LAST_WORD": {"name": "Last Word", "tip": "Does something when it dies."},
    "AMBUSH": {"name": "Ambush", "tip": "Hidden until your opponent does what it waits for."}
  },
  "classes": {"SUN": "Sun", "MOON": "Moon", "NEUTRAL": "Neutral"},
  "rarities": {"COMMON": "Common", "RARE": "Rare"}
}
```

`decks/1_dawn.json` and `decks/2_dusk.json`:

```json
{"name": "Dawn", "champion": "sun_queen",
 "cards": ["squire", "squire", "shield_bearer", "shield_bearer", "archer", "archer", "banner", "banner"]}

{"name": "Dusk", "champion": "moon_king",
 "cards": ["squire", "squire", "shield_bearer", "shield_bearer", "moon_wolf", "moon_wolf", "ambush", "ambush"]}
```

Build it, check it, play it:

```sh
python3 tools/pack.py build tiny -o tiny.cardpack        # zips, checks, writes rules_hash
godot --headless --path . --script res://tools/pack_try.gd -- tiny.cardpack 4
# loaded tiny-duel 0.1.0, rules_hash 7705adf3…
# game 1: Dawn vs Dusk, turn 14, 51 actions, won by Dawn
# …
```

Then *Games → Import a game file* in {name}, choose `tiny.cardpack`, *Play this game*, and start a training game against the bot.

## The files of a pack

| Path | What | Needed |
|---|---|---|
| `manifest.json` | Who and what: id, version, names, languages, art/sound/music sets, hashes | yes |
| `rules.json` | Limits, the opening, the bot, fatigue, timers, classes, races, rarities, sets, mechanics, modes, ranks | yes |
| `cards.json` | Every card: champions, powers, minions, spells, weapons, tokens | yes |
| `scripts/*.lua` | Card logic, any folders below `scripts/`; `scripts/lib.lua` is shared helpers | for cards with special text |
| `locales/<lang>.json` | Every text a player sees, one file per language | one per language in the manifest |
| `layout/<lang>.json` | Hand-tuned card text layout | no |
| `art/<set>/<card id>.jpg\|png\|webp` | Card pictures, one folder per art set (512 px is plenty) | no: cards without art get a drawn picture |
| `sounds/<set>/<name>.wav\|ogg\|mp3` | Event sounds, one folder per sound set | no |
| `music/<set>/<name>.wav\|ogg\|mp3` | `menu`, `battle_1` … `battle_N` | no |
| `voice/<lang>/<card id>_<kind>.ogg` | Recorded voice lines | no |
| `ui/…` | `card_back`, `logo`, `menu`, `board`, `library`, `result_victory`/`_defeat`/`_draw` pictures; `theme.json` and `fonts/` | no |
| `decks/<name>.json` | Ready decks (file names sort the list) | recommended |
| `missions/<n>.json` | Tutorial or story missions | no |
| `README.md`, `CREDITS.md`, `LICENSE.txt` | For people | no |

Nothing else may be in the zip. A path segment is letters, digits, `_`, `.` and `-` (starting with a letter, digit or `_`), at most 200 characters for the whole path; no hidden files, no links, no file twice.

## manifest.json

| Field | Type | Meaning |
|---|---|---|
| `format` | `1` | The format version. An engine refuses a format it does not know. |
| `id` | `[a-z0-9][a-z0-9._-]{0,63}` | The stable id of your game (`neon`, `classic-2014`). Keep it across versions. |
| `version` | `"X.Y.Z"` | For people. The hashes, not the version, tell two packs apart. |
| `engine` | `"X.Y.Z"` | The lowest {name} version your pack is made for. |
| `name`, `description` | `{lang: text}` | Shown in the list of games. |
| `authors` | `[string]` | |
| `license` | string | Who owns what, free text. |
| `redistributable` | bool | You allow players to pass the pack on: a friend gets it automatically in an online game, a server may share it. Without it others need the same file themselves. |
| `default_locale` | lang | The fallback language; must be in `locales`. |
| `locales` | `[lang]` | `en`, `ru`, `de`, `fr`, `es`, `pt_BR`, `it`, `pl`…; each has `locales/<lang>.json`. |
| `art_sets`, `sound_sets`, `music_sets` | `[{id, name?, default?}]` | One entry per folder of `art/`, `sounds/`, `music/`; at most one `default`. Players choose among them in *Games*. |
| `card_back`, `logo` | `"ui/<file>"` | Optional pictures. |
| `colors` | `{classes: {id: "rrggbb"}, rarities: {id: "rrggbb"}}` | Frame and gem colours. |
| `fx`, `rules_hash` | — | Written by `pack.py build`; don't write them yourself. |

## rules.json

Whole numbers only. Every optional field takes the engine's default (Classic's value).

| Section | Fields |
|---|---|
| `limits` | `champion_health` (30), `max_mana` (10), `hand` (10: a card drawn into a full hand burns), `board` (7 minions a side), `deck_size` (30), `copies` (2), `copies_by_rarity` (`{"LEGENDARY": 1}`), `queue_steps` (5000: a safety limit) |
| `start` | `first_player` (`"random"`), `hand` (`[3, 4]`: cards of the first and the second player), `coin` (the card the second player gets, or null), `mulligan` (true), `first_player_draws` (true) |
| `bot` | `trap` (what the bot counts for its own trap in play; 0 = it never plays one, 2 = Neonfall), `depth` (2 = it also tries two actions in a row) |
| `fatigue` | `enabled`, `first`, `step`: damage when drawing from an empty deck |
| `timers` | seconds: `turn` (75), `fuse` (15), `mulligan` (45), `grace` (5), `away` (30) |
| `default_power` | The `POWER` card of a champion without one. **The engine needs it** even when every champion has its own power. |
| `classes` | `[{id, champion?, neutral?, playable?}]`: a class with a `champion` is playable; a `neutral` class's cards go into every deck. |
| `races` | The tribes a minion may have (`"DRONE"`, `"DAEMON"`). |
| `rarities` | `[{id, tier}]`, `tier` one of `common`, `rare`, `epic`, `legendary` (Arena odds, frames); `no_rarity_tier` for cards without one. |
| `sets` | Every `set` a card may name. |
| `mechanics` | Your name → `{"engine": <engine id>}` (below). |
| `modes.constructed` | `sets` (cards of these sets go into decks), `class_cards` (`"own_and_neutral"`), `starter_rarities`, `starter_core` (for generated starter decks) |
| `modes.arena` | The Arena draft: `sets`, `champions_offered`, `classes`, `picks`, `offer`, `tier_weights`, `special_picks`, `special_tier_weights`, `class_weight`, `neutral_weight`, `copies`, `wins`, `losses` |
| `ranked` | The ladder: `start`, `ranks` (stars per rank, floors, streak bonus, emblems), `streak`, `legend`, `season` |

Every field with Classic's values and the exact draft algorithm: [rules.json reference](../ref/rules.html).

> Neonfall gives the second player five opening cards (`"hand": [3, 5]`): with `[3, 4]` the first player won 56–60 % of bot games, with `[3, 5]` 47–53 %. The bot balance runs are in `packs/neon/DESIGN.md` §9.

## Mechanics: the engine's words and yours

The engine works with neutral ids; your pack names each one it uses. Players only ever see your names (from `locales/<lang>.json` `mechanics`). Neonfall's names, as an example:

| Engine id | What it does | Neonfall |
|---|---|---|
| `GUARD` | Enemies must attack it first | Firewall |
| `HASTE` | Can attack at once | Overclock |
| `BARRIER` | Prevents the first damage, then breaks | Hardlight |
| `DOUBLE_ATTACK` | Two attacks a turn | Dual-Core |
| `STEALTH` | Can't be attacked or targeted until it attacks | Cloak |
| `SPELLPROOF` | Can't be targeted by spells and powers | Encrypted |
| `SPELL_POWER` | +N spell damage (card field `spell_power`) | Bandwidth |
| `MANA_LOCK` | Locks N mana next turn (card field `mana_lock`) | Heat |
| `TRAP` | A hidden spell that fires on an event | Protocol |
| `ON_PLAY` | An effect when played from the hand | Boot |
| `ON_DEATH` | An effect when it dies | Flatline |
| `COMBO` | A bonus if a card was played before it this turn | Chain |
| `CHOICE` | Pick one of two effects | Fork |
| `WOUNDED` | A bonus while damaged | Redline |
| `FREEZE`, `SILENCE` | Markers: the card freezes / silences (its script does it) | Jam, Wipe |

`IMMUNE`, `CANT_ATTACK`, `AURA`, `TRIGGER`, `ADJACENT`, the state tags (`FROZEN`, `EXHAUSTED`, `ARMOR`, …) and the rest: [the full vocabulary](../ref/format.html#4-mechanics-the-engine-vocabulary-and-pack-names). A card's `keywords` are your names; keyword-kind ones (Guard, Haste, …) work by themselves, hook-kind ones (On play, On death, …) only label a card whose script has that hook.

## cards.json

An array of cards; champions, powers and tokens are cards too.

| Field | Meaning |
|---|---|
| `id` | `[A-Za-z0-9_]{1,64}`, unique; art files and texts use it. |
| `type` | `MINION`, `SPELL`, `WEAPON`, `CHAMPION`, `POWER`. |
| `class`, `rarity`, `set` | Ids from `rules.json` (tokens have no rarity). |
| `collectible` | Can go into decks (if its set is a mode's set). Default false. |
| `cost`, `attack`, `health`, `durability` | 0–999. A champion's `health` is its starting health. |
| `race` | A minion's tribe. |
| `keywords` | Mechanic names (yours); `refs`: mechanics the text mentions (for tooltips). |
| `spell_power`, `mana_lock` | The amounts of `SPELL_POWER` and `MANA_LOCK`. |
| `unique` | The legendary frame. |
| `power` | A `CHAMPION`'s `POWER` card. |
| `code_id` | A number for deck codes. |
| `script` | `scripts/<file>.lua#<key>`: its hooks. No script, no hooks (a vanilla minion). |
| `fx` | Visual effects by name: `{"element": "fire", "cast": "bolt", "hit": "hurt"}` ([effects](../ref/fx.html)). |
| `sounds`, `voice` | Its own sound names; whose voice lines it speaks. |

## Texts: `locales/<lang>.json`

| Key | |
|---|---|
| `cards` | `{id: {name, text}}`. Every card needs a name in the default language. |
| `mechanics` | `{NAME: {name, tip}}`: the keyword and its tooltip. |
| `classes`, `races`, `rarities`, `sets` | `{id: text}` |
| `ranks` | `{"25": …, "1": …, "0": "Legend"}` |
| `decks` | Deck names. |
| `missions`, `hints` | Mission intros and lines, tutorial hints. |
| `voice` | `{card id: {greetings, attack, play, death, …}}`: the emotes' words. |
| `ui` | Your own interface words (Neonfall: `armor` → "Plating", `fatigue` → "Data Rot"). |

Card text markup: `<b>…</b>` and `<i>…</i>`; `$N` a number spell power raises; `#N` a number healing modifiers change; `[x]` at the start for hand-placed line breaks. Missing text falls back to the default language, then to the id.

## Pictures, sounds, music, look

- **Art:** `art/<set>/<card id>.jpg` (or `.png`, `.webp`), at most 2 MiB a picture. Neonfall has two sets, `default` (painted) and `simple` (flat 2D); a missing picture falls back to the default set, then to a drawn one.
- **Sounds:** by event name — `play_card`, `attack`, `damage`, `death`, `hero_power`, `turn_start`, `heal`, `armor`, `equip`, `secret`, `freeze`, `shield`, `spell`, `trigger`, `hit_big`, `draw`, `victory`, `defeat`, `click`. A card may name its own (`"sounds": {"play": "…"}`).
- **Music:** `music/<set>/menu.ogg`, `battle_1.ogg`, `battle_2.ogg`, … (a shuffled playlist in a match).
- **Look:** `ui/theme.json` restyles the whole interface while your game is active: colours, button style (`wood`, `flat`, `neon`), panels, fonts (`ui/fonts/*.ttf` with their licence), the menu's particles (`embers`, `rain`, `none`). Neonfall's dark glass and magenta glow is its `ui/theme.json`; every key: [UI theme](../ref/format.html#11-ui-theme-uithemejson).

## Decks and missions

A deck: `{"name", "champion", "cards": [ids], "code"?, "arena"?}`. `pack.py check` validates each one by your rules: size, class, copies by rarity, sets, collectible.

A mission (`missions/<n>.json`) is a scripted game against a boss. See the next section.

## Tutorial

The Tutorial item appears in the game's menu when the active pack has a `tutorial.json`: the missions in order, the pages shown before each, when each hint shows ([format](../ref/format.html#12-tutorial-tutorialjson-and-scene-effects)). The missions themselves are `missions/<n>.json` files.

**A worked example: Neonfall's tutorial** (`packs/neon/tutorial.json`, `packs/neon/missions/`). Six missions from the flooded streets up to the corporate towers, each a boss of the setting with its own lines: Brick the bouncer (a card, combat, champions), Sharkey the pawnbroker (Mana, spells with a target, Jam), Glass Mira (Boot, Flatline, minions first), Dr. Varga (Firewall, Overclock and Heat, Cloak), ARCHON (Champion Powers, Chain, Wipe and Glitch) and Director Vale with the real Hostile Merger deck (Protocols, Hardlight, Encrypted). The bosses are `CHAMPION` cards of the pack (`boss_*`, set `token`); the first two missions use the pack's `scripts/tutorial.lua#ench:tutorial_guard`; rain falls over the list and the first and last boards; the texts are in all eight `locales/<lang>.json` (`tutorial`, `missions`, `hints`).

A mission has:

| Field | Meaning |
|---|---|
| `id` | The mission's number, from 1. |
| `champion`, `boss`, `boss_power` | The player's champion, the boss (a `CHAMPION` card) and its power. |
| `powers_locked`, `boss_guarded` | Both powers can't be used; the boss can't be attacked while it has minions. |
| `end_turn_block` | `{while_can_play, while_can_attack}`: the player can't end the turn while a card can be played / a minion can attack. |
| `player` | `{mana, hand, deck}`: starting mana, hand, deck **top card first**. |
| `boss_deck` | Top card first. |
| `mulligan` | false: no mulligan. |
| `reward` | A card shown after a win. |
| `hints` | Hint keys in order; their texts are in `locales/<lang>.json` `hints`. |
| `script` | `scripts/<file>.lua#<name>`: hooks the player's champion gets at the start, or null. Classic's first two missions use `ench:tutorial_guard`: the champion can't drop below 1 Health. |

A mission's words — its intro, the boss's lines (`start`, `hurt`, `defeat`…), the reward line — are in `locales/<lang>.json` `missions`. Missions count for `rules_hash`; their texts don't.

## Build a pack: tools/pack.py

```sh
python3 tools/pack.py build <source folder> -o <file>.cardpack [--art-set mine=path/to/pictures]
python3 tools/pack.py check <file>.cardpack     # every error and warning; exit code 1 on an error
python3 tools/pack.py info  <file>.cardpack     # sizes by folder, card counts, languages, sets, hashes
python3 tools/pack.py hash  <file>.cardpack     # rules_hash and content_hash
```

`build` reads the source folder, runs its `recipe.json` if there is one, writes `fx` and `rules_hash` into the manifest, runs every check and writes the zip only when there are no errors. The zip is deterministic: the same files give a byte-identical `.cardpack`.

**Recipes.** When a pack is made from data kept elsewhere, `recipe.json` lists build steps: `{"root": "<folder>", "steps": [{"do": …}, …]}`. `recipe.json` and `*.patch.json` never go into the pack.

| Step | What it does |
|---|---|
| `copy` | Copies files from a folder (`from`, `to`, `files` globs, `except`). Classic copies its art and audio this way. |
| `source` | A source in its own shape (Neonfall): drops source-only card fields (`drop_card_fields`), drops files (`drop_files`), moves files (`move`, e.g. pictures into `ui/`), takes each locale's `pack.name`/`pack.description` into the manifest and its `terms` into `ui`. |
| `hsjson`, `keywords`, `voice`, `translate`, `rank_names` | Classic's: cards and texts from HearthstoneJSON data, mechanic names, voice lines, translations, rank names. |

`--art-set id=folder` adds a picture set of your own that is marked `local` and never shared.

## Load it into the game

- **On your device:** *Games → Import a game file* (the system's file dialog; the browser's file picker on the web). The game checks the pack (paths, sizes, the format, `rules_hash`), keeps it as `packs/<content_hash>.cardpack` in its user folder and lists it. *Play this game* makes it active; its decks, art, sounds, music and look switch at once. *Delete* removes an imported one.
- **Online with a friend (codes):** if the friend has a pack with the same `rules_hash`, the game switches to it; if not and the pack is `redistributable`, the friend is offered to download it from you.
- **On a game server:** a player uploads it in the server's *Games* window (*Upload my game*: up to 10 packs of 100 MB each); an admin uploads in the admin panel, or puts `.cardpack` files into the server's `--packs-dir`. The server checks every new pack: the engine loads the rules, compiles every script and plays a trial game with your first two ready decks, trying every legal move; a script error, an engine failure, a stuck game or more than 20 seconds refuses it.

## Versions and hashes

| | What it identifies | Changes when |
|---|---|---|
| `version` | Nothing, for people | You change it |
| `rules_hash` | **The game as it plays.** Online matching, servers, replays use it: two packs with the same `rules_hash` play the same game. | `rules.json`, `cards.json` (except `fx`, `sounds`, `voice`), `missions/*.json` or `scripts/**/*.lua` change |
| `content_hash` | **The file.** Downloads, caches and the copy in the user folder. | Any file changes |

So you can fix a typo, redraw art, add a language or a sound set and still play with friends who have the older file: names, texts, pictures and the manifest are not in `rules_hash`. Change a number or a script and it is a different game. Both hashes are SHA-256 over the files (not over the zip bytes), JSON in a canonical form; the exact recipe: [Hashes](../ref/format.html#3-hashes).

## Limits

| What | Limit |
|---|---|
| The `.cardpack` file | 128 MiB (a player's upload to a server: 100 MB) |
| All files unpacked | 256 MiB |
| Number of files | 10 000 |
| One file / one picture | 16 MiB / 2 MiB |
| The rules part (`rules.json`, `cards.json`, `missions/`, `scripts/`) | 8 MiB unpacked |
| The text part (`locales/`, `layout/`) | 32 MiB unpacked |
| One zip entry, unpacked / packed | ≤ 200 (no zip bombs) |
| A script call | 200 000 steps, call depth 200, 10 000 entries a table, 64 KiB a string, 16 MiB allocated ([Lua limits](lua.html#limits)) |

## Where to read more

The reference pages describe each file exactly as the engine and the tools read it (English): [pack format](../ref/format.html), [rules.json](../ref/rules.html), [cards.json](../ref/cards.html), [visual effects](../ref/fx.html). Machine-readable JSON Schemas are in `docs/packs/schema/` in the source.
