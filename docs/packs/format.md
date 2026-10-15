# The `.cardpack` game pack format (format 1)

A game pack is everything that makes a card game a particular game: its rules,
champions, cards and their logic, the names of its mechanics, texts in every
language, art (several sets), sounds, music, voice lines, ranks, timers and
modes. The engine (`rust/engine`) knows only neutral mechanics; a pack names
them and fills them with content. Decisions: `docs/superpowers/plans/2026-10-16-game-packs.md`
(D6–D9, D16–D19).

Related pages: [rules.md](rules.md) (`rules.json`), [cards.md](cards.md)
(`cards.json`, locales, layout), [fx.md](fx.md) (visual effects), `lua.md`
(card scripts, phase A1/B). Machine-readable: [schema/](schema/) (JSON Schemas,
the engine vocabulary `keywords.json`, the effect catalog `fx.json`).
Tool: `tools/pack.py` (build, check, info, hash; see the end of this page).

## 1. Layout

A pack is a zip file with the extension `.cardpack`. Nothing else may be in it.

```
manifest.json            who and what: id, version, names, locales, art/sound/music sets, rules_hash
rules.json               limits, start, fatigue, timers, classes, races, rarities, sets, mechanics, modes, ranked
cards.json               every card: stats, keywords, champion powers, script references, fx
scripts/*.lua            card logic (phase B); any depth below scripts/; scripts/README.md allowed
locales/<lang>.json      every player-facing text in one language (cards, mechanics, classes, ranks, missions, voice…)
layout/<lang>.json       optional: hand-tuned card text layout
art/<set>/<card id>.jpg|png|webp     one folder per art set
sounds/<set>/<name>.wav|ogg|mp3      one folder per sound set (+ .md credits)
music/<set>/<name>.wav|ogg|mp3       one folder per music set (+ .md credits)
voice/<lang>/…                       optional recorded voice lines (.wav|ogg|mp3)
ui/<name>.png|jpg|webp               optional pictures: logo, card back, rank emblems
decks/<name>.json        ready decks
missions/<n>.json        tutorial or story missions (data; their scripts live in scripts/)
README.md, CREDITS.md, LICENSE.txt   optional, at the top
```

Rules for paths (checked by `tools/pack.py check`, and the client and server must
refuse a pack that breaks them):

- Only the folders above; only the listed extensions in each; `art/`, `sounds/`,
  `music/` hold files one level down (`art/<set>/<file>`), `locales/`, `layout/`,
  `decks/`, `missions/`, `ui/` hold files right in them.
- Each path segment matches `[A-Za-z0-9_][A-Za-z0-9_.-]*`: no `..`, no absolute
  paths, no `\`, no hidden files (leading dot), at most 200 characters.
- No symbolic links, no encrypted entries, no file twice.
- Godot `.import` files and `.godot/` never go into a pack.
- Art of a card is named by its id: `art/generated/VAN_CS2_029.jpg`.

### Size limits

| What | Limit |
|---|---|
| The `.cardpack` file | 128 MiB |
| All files unpacked | 256 MiB |
| Number of files | 10 000 |
| One file | 16 MiB |
| One picture | 2 MiB |
| Rules part (`rules.json`, `cards.json`, `missions/`, `scripts/`) unpacked | 8 MiB |
| Text part (`locales/`, `layout/`) unpacked | 32 MiB |
| Unpacked / packed size of one entry | ≤ 200 (zip bombs) |

The Lua limits (steps, depth, table and string size) are in `lua.md` (D5).

## 2. `manifest.json`

| Field | Type | Meaning |
|---|---|---|
| `format` | int, `1` | Format version. An engine refuses a format it does not know. |
| `id` | string `^[a-z0-9][a-z0-9._-]{0,63}$` | Stable id of the pack (`classic-2014`). |
| `version` | `"X.Y.Z"` | For people; the hashes identify the content. |
| `engine` | `"X.Y.Z"` | The lowest game/engine version that can run it. |
| `name`, `description` | `{lang: text}` | Shown in the pack list. |
| `authors` | [string] | |
| `license` | string | Free text: who owns what. |
| `redistributable` | bool | The author allows passing the pack to other players (P2P and server). Without it the pack is only compared by hash. |
| `default_locale` | lang | Fallback language; must be in `locales`. |
| `locales` | [lang] | Languages the pack has; each has `locales/<lang>.json`. Lang: `en`, `ru`, `pt_BR` (Godot style). |
| `art_sets`, `sound_sets`, `music_sets` | [{`id`, `name`?, `default`?, `local`?}] | One entry per folder of `art/`, `sounds/`, `music/`. At most one `default`. `local: true` = added by `--art-set`, never distributed. |
| `card_back`, `logo` | `"ui/<file>"` or null | Optional pictures; null = the client's own. |
| `colors` | `{classes: {id: "rrggbb"}, rarities: {id: "rrggbb"}}` | Frame and gem colours. |
| `fx` | [name] | Written by the build: every effect name and element the cards use (the client can tell what it lacks). |
| `rules_hash` | 64 hex | Written by the build; `check` recomputes it. |

The manifest is not part of `rules_hash`, so names, colours and art sets never
split players.

## 3. Hashes

Both hashes are SHA-256, lowercase hex, computed over the files, not over the zip
bytes (deflate output differs between zlib versions; the file list does not).

**`rules_hash`** — what changes how the game plays. Games, replays, servers and
online matching use it (D8). Two packs with the same `rules_hash` play the same
game even if their art, texts or sounds differ.

1. Files: `rules.json`, `cards.json`, `missions/*.json`, `scripts/**/*.lua`. Nothing else.
2. Each JSON file is parsed strictly (UTF-8, no BOM, duplicate keys and
   `NaN`/`Infinity` are errors; fractions are errors) and re-written canonically:
   object keys sorted by Unicode code point, no whitespace, separators `,` and `:`,
   strings in UTF-8 with only `"` `\` and U+0000–U+001F escaped (`\b \f \n \r \t`,
   others as `\u00xx` lowercase), integers in plain decimal, `true` `false` `null`.
   This is what Python's `json.dumps(v, ensure_ascii=False, sort_keys=True,
   separators=(",", ":"))` and Rust `serde_json::to_string` of a sorted map write.
3. In `cards.json`, before step 2, the presentation fields `fx`, `sounds`, `voice`
   of every card are removed.
4. Each `.lua` file: a leading UTF-8 BOM is dropped, `\r\n` and `\r` become `\n`.
5. `rules_hash = SHA-256("cardpack-rules/1\n" + Σ (path + ":" + hex(SHA-256(normalized bytes)) + "\n"))`
   over the files of step 1 sorted by the UTF-8 bytes of their path.

**`content_hash`** — the identity of the whole pack, for caches, downloads and
P2P transfer (`user://packs/<content_hash>.cardpack`, D9):

`content_hash = SHA-256("cardpack-content/1\n" + Σ (path + ":" + hex(SHA-256(raw bytes)) + "\n"))`
over every file in the zip (directory entries ignored), sorted the same way.

(Deviation from D8, which said "SHA-256 of the whole zip": the per-file form gives
the same value for the same files whatever zip writer made them, and a receiver
can check it after unpacking.)

A deterministic build (`tools/pack.py build`) also writes byte-identical zips for
the same input: entries sorted by path, time 1980-01-01 00:00, mode 0644,
pictures and `.ogg`/`.mp3` stored, everything else deflated at level 9.

## 4. Mechanics: the engine vocabulary and pack names

The engine has its own neutral names ([schema/keywords.json](schema/keywords.json)).
A pack names each mechanic its cards use and maps it to an engine id in
`rules.json`:

```json
"mechanics": {"TAUNT": {"engine": "GUARD"}, "CHARGE": {"engine": "HASTE"}}
```

Players see the pack's words, from `locales/<lang>.json`:

```json
"mechanics": {"TAUNT": {"name": "Провокация", "tip": "Враги обязаны атаковать существ с «Провокацией»."}}
```

A card lists pack names in `keywords` (`["TAUNT"]`). The engine works with engine
ids and writes **pack names** into snapshots, events and the state hash (D7), so
the Classic pack, which keeps today's names, keeps today's state hashes and the
7833 recorded games stay its parity test. The zone that holds traps is named
after the pack's `TRAP` mechanic (`SECRET` in Classic). An engine id the pack
does not map is written as the engine id.

| Engine id | Kind | What it does | Classic name |
|---|---|---|---|
| `GUARD` | keyword | Enemies must attack it first | `TAUNT` |
| `HASTE` | keyword | Can attack at once | `CHARGE` |
| `BARRIER` | keyword | Prevents the first damage, then breaks | `DIVINE_SHIELD` |
| `DOUBLE_ATTACK` | keyword | Two attacks a turn | `WINDFURY` |
| `STEALTH` | keyword | Can't be attacked or targeted until it attacks | `STEALTH` |
| `SPELLPROOF` | keyword | Can't be targeted by spells and powers | `ELUSIVE` |
| `CANT_ATTACK` | keyword | Can't attack | `CANT_ATTACK` |
| `IMMUNE` | keyword | Takes no damage | `IMMUNE` |
| `SPELL_POWER` | keyword | +N spell damage (card field `spell_power`) | `SPELLPOWER` |
| `MANA_LOCK` | keyword | Locks N mana next turn (card field `mana_lock`) | `OVERLOAD` |
| `TRAP` | keyword | Hidden spell that fires on an event | `SECRET` |
| `ON_PLAY` | hook | Effect when played from hand | `BATTLECRY` |
| `ON_DEATH` | hook | Effect when it dies | `DEATHRATTLE` |
| `COMBO` | hook | Bonus if a card was played before it this turn | `COMBO` |
| `CHOICE` | hook | Pick one of two effects | `CHOOSE_ONE` |
| `WOUNDED` | hook | Bonus while damaged | `ENRAGED` |
| `FREEZE`, `SILENCE`, `COUNTER` | marker | The card freezes / silences / counters (the effect is its hook) | same |
| `AURA`, `TRIGGER`, `ADJACENT` | marker | Client hints | `AURA`, `TRIGGER_VISUAL`, `ADJACENT_BUFF` |
| `SPELL_SCALED`, `NO_SPELL_POWER` | marker | Spell power changes / does not change its numbers | `AFFECTED_BY_SPELL_POWER`, `ImmuneToSpellpower` |
| `FROZEN`, `FROZEN_THIS_TURN`, `EXHAUSTED`, `ATTACKS`, `ARMOR`, `DURABILITY`, `USED`, `LOCKED`, `GUARDED`, `TO_DESTROY`, `DIED_POS`, `HEAL_IS_DAMAGE` | state | Tags the engine sets during a game | same |
| `POWER_MULTIPLIER` | state | Doubles spell and power damage and healing (aura tag) | `DOUBLE_HEAL_DAMAGE` |

Kinds: *keyword* — a tag a card carries from its data and the engine reads;
*hook* — the card has a hook of that kind (shown to players, no tag); *marker* —
for the client only; *state* — set by the engine, not by card data. Silence
removes the keywords marked `silenced` in `keywords.json` (and the card's
hooks). Card types: `MINION`, `SPELL`, `WEAPON`, `CHAMPION` (a hero), `POWER`
(a champion's power). Zones: `DECK`, `HAND`, `PLAY`, `TRAP`, `GRAVEYARD`, `SETASIDE`.

`check` refuses a mechanic whose `engine` is not in the vocabulary and a card
keyword the pack does not map. It warns when a keyword or hook a card uses has no
name or tip in the default language.

## 5. Classes, races, rarities, sets, champions

All in `rules.json` ([rules.md](rules.md)); their player names in
`locales/<lang>.json` (`classes`, `races`, `rarities`, `sets`).

- `classes`: `{id, champion?, neutral?, playable?}`. A class with a `champion`
  can be played; its champion is a `CHAMPION` card of that class. One or more
  classes are `neutral` (their cards go into every deck). `playable: false` marks
  classes of special cards only (Classic: `DREAM`, `DEMONHUNTER`).
- A **champion** is a card of type `CHAMPION` with `health` and a `power`: the id
  of a `POWER` card (its cost and hook are the power's). `default_power` in
  `rules.json` serves champions without one.
- `races`: the tribe ids a minion may have (`race` in a card).
- `rarities`: `{id, tier}`; `tier` is one of `common`, `rare`, `epic`,
  `legendary` (arena offers, frames). Cards without rarity count as
  `no_rarity_tier`.
- `sets`: every `set` a card may name. Which sets are playable is per mode.

## 6. Locales and layout

`locales/<lang>.json` holds every text a player sees ([cards.md](cards.md) §2):
`cards` (`name`, `text`), `mechanics` (`name`, `tip`), `classes`, `races`,
`rarities`, `sets`, `ranks` (`"25"` … `"1"`, `"0"` = Legend), `decks`,
`missions` (`name`, `intro`, `lines`, `reward_line`), `hints`, `voice`
(card id → `{greetings, attack, play, death, …}`), `ui` (the pack's own UI
strings). Lookup: the player's language → `default_locale` → the id.
Every card must have a name in the default locale.

`layout/<lang>.json` (optional) is the hand-tuned text layout the Classic client
already has: card id → `{name: font size, text: font size, lines: [rich lines],
valign: "top", dy}`. Without it the client lays text out itself.

## 7. Art, sounds, music, voice

- `art/<set>/<card id>.<jpg|png|webp>`, 512 px recommended, ≤ 2 MiB. A card
  without a picture in the chosen set falls back to the default set, then to the
  client's procedural art.
- `sounds/<set>/<name>`: event sounds by name (Classic: `play_card`, `attack`,
  `damage`, `death`, `hero_power`, `turn_start`, `heal`, `armor`, `equip`,
  `secret`, `freeze`, `shield`, `spell`, `trigger`, `hit_big`, `victory`,
  `defeat`, `click`). A card may name its own (`sounds: {play, attack, death}`).
- `music/<set>/<name>`: `menu`, `battle_1` … `battle_N` (a shuffled playlist).
- `voice/<lang>/<card id>_<kind>.<ogg|wav|mp3>`: optional recordings of the voice
  lines whose words are in `locales/<lang>.json` `voice`.
- A local art set (`tools/pack.py build … --art-set mine=path`) is marked
  `local: true` and must never be uploaded or sent; the original Blizzard art
  (`art/original`) is refused by the tool.

## 8. Decks and missions

`decks/<name>.json`: `{name, champion, cards: [ids], code?, arena?}`. `check`
validates every deck by the pack's rules (size, class, copies by rarity, the
mode's sets, collectible). File names sort the list (`01_…`).

`missions/<n>.json`: a scripted game against a boss:

| Field | Meaning |
|---|---|
| `id` | Mission number (1-based). |
| `champion`, `boss`, `boss_power` | The player's champion, the boss (a `CHAMPION`) and its power. |
| `powers_locked` | Both powers can't be used. |
| `unlosable` | The player's champion can't drop below 1 health. |
| `boss_guarded` | The boss can't be attacked while it has minions. |
| `end_turn_block` | `{while_can_play, while_can_attack}`: the player can't end the turn while a card can be played / a minion can attack. |
| `player` | `{mana, hand, deck}`: starting mana crystals, hand, deck **top card first**. |
| `boss_deck` | Top card first. |
| `mulligan` | false: no mulligan. |
| `reward` | A card shown after a win. |
| `hints` | Hint keys, in order; texts in `locales/<lang>.json` `hints`. |
| `script` | `scripts/<file>.lua#<id>`: mission hooks (phase B), or null. |

Missions are in `rules_hash` (they define decks and rules); their texts are not.

## 9. Card scripts

`cards.json` points a card at its logic: `"script": "scripts/mage.lua#VAN_CS2_029"`.
A script file returns a table of cards with hooks. The language subset, the API
(`g`) and the hooks are in `lua.md` (phase A1); Classic's scripts come in phase B.
A card without a script has no hooks (vanilla minion, weapon, …).

## 10. Build recipes and `tools/pack.py`

A pack source is a folder with the pack's own files (`manifest.json`,
`rules.json`, `decks/`, `missions/`, `scripts/`, …). Optional extras:

- `locales/<lang>.json` in the source: hand-written texts; they win over
  generated ones (a deep merge where the source fills first).
- `recipe.json`: `{root, steps}` — data gathered from elsewhere at build time.
  `root` is relative to the source folder. Steps:

| `do` | Fields | What it adds |
|---|---|---|
| `copy` | `from`, `to`, `files` (globs), `except` | Files of one folder (not recursive; `.import` skipped). |
| `hsjson` | `from`, `patch`, `locales` (lang → HS locale), `rename` (type map) | `cards.json` from HearthstoneJSON data and card names/texts; `patch` (`<name>.patch.json`, card id → fields) adds or overrides fields such as `power` and `fx`. |
| `keywords` | `from` | Mechanic names and tips (`{NAME: {name: {lang}, text: {lang}}}`). |
| `voice` | `from` | Voice line texts (`{card: {kind: {lang: text}}}`). |
| `translate` | `from` (folder of `<lang>.json`: English → text), `sections` | Fills those sections of other languages from the default language's strings. |
| `rank_names` | | A rank whose emblem is a card is named after that card. |

`recipe.json` and `*.patch.json` are not copied into the pack.

```sh
tools/pack.py build packs/classic -o build/packs/classic.cardpack [--art-set mine=art/custom]
tools/pack.py check build/packs/classic.cardpack     # exit 1 on any error
tools/pack.py info  build/packs/classic.cardpack     # sizes, counts, hashes
tools/pack.py hash  build/packs/classic.cardpack     # rules_hash, content_hash
python3 -m unittest tools/test_pack.py
```

`build` writes `fx` and `rules_hash` into the manifest, runs every check and
writes the zip only when there are no errors. `check` validates the files against
the schemas in `schema/` (a small subset of JSON Schema: `type`, `enum`, `const`,
`pattern`, `minimum`/`maximum`, `minLength`/`maxLength`, `minItems`/`maxItems`,
`uniqueItems`, `properties`, `required`, `additionalProperties`,
`propertyNames`, `items`, `anyOf`, local `$ref`) and the cross references:
classes, rarities, races, sets and mechanics of every card; mechanics → engine
vocabulary; champions → `POWER` cards; scripts exist; art/sound/music folders ↔
manifest; every locale file present and every card named in the default one;
decks legal; mission cards exist; emblems exist; `rules_hash` current.
