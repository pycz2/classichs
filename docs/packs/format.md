# The `.cardpack` game pack format (format 1)

A game pack is everything that makes a card game a particular game: its rules,
champions, cards and their logic, the names of its mechanics, texts in every
language, art (several sets), sounds, music, voice lines, ranks, timers and
modes. The engine (`rust/engine`) knows only neutral mechanics; a pack names
them and fills them with content. Decisions: `docs/superpowers/plans/2026-10-16-game-packs.md`
(D6–D9, D16–D19).

Related pages: [rules.md](rules.md) (`rules.json`), [cards.md](cards.md)
(`cards.json`, locales, layout), [fx.md](fx.md) (visual effects), [lua.md](lua.md)
(the Lua subset of card scripts), [api.md](api.md) (the engine API and hooks of card scripts);
§11 below: the interface theme (`ui/theme.json`); §12: the tutorial (`tutorial.json`) and scene effects. Machine-readable: [schema/](schema/) (JSON Schemas,
the engine vocabulary `keywords.json`, the effect catalog `fx.json`).
Tool: `tools/pack.py` (build, check, info, hash; see the end of this page).

## 1. Layout

A pack is a zip file with the extension `.cardpack`. Nothing else may be in it.

```
manifest.json            who and what: id, version, names, locales, art/sound/music sets, rules_hash
rules.json               limits, start, bot, fatigue, timers, classes, races, rarities, sets, mechanics, modes, ranked
cards.json               every card: stats, keywords, champion powers, script references, fx
scripts/*.lua            card logic (api.md); any depth below scripts/; scripts/README.md allowed
locales/<lang>.json      every player-facing text in one language (cards, mechanics, classes, ranks, missions, voice…)
layout/<lang>.json       optional: hand-tuned card text layout
art/<set>/<card id>.jpg|png|webp     one folder per art set
sounds/<set>/<name>.wav|ogg|mp3      one folder per sound set (+ .md credits)
music/<set>/<name>.wav|ogg|mp3       one folder per music set (+ .md credits)
voice/<lang>/…                       optional recorded voice lines (.wav|ogg|mp3)
ui/<name>.png|jpg|webp               optional pictures: logo, card back, rank emblems; by name the client also
                                     shows ui/menu (menu and screen backdrops), ui/board (the game board), ui/library
                                     (collection), ui/result_victory|result_defeat|result_draw (the result screen)
ui/theme.json                        optional: the look of the interface (§11)
ui/fonts/<name>.ttf|otf              optional: the theme's fonts, with their licences (.txt|.md)
decks/<name>.json        ready decks
missions/<n>.json        tutorial or story missions (data; their scripts live in scripts/)
tutorial.json            optional: the tutorial (§12): its missions in order, intro pages, unlock rule, hints
README.md, CREDITS.md, LICENSE.txt   optional, at the top
```

Rules for paths (checked by `tools/pack.py check`, and the client and server must
refuse a pack that breaks them):

- Only the folders above; only the listed extensions in each; `art/`, `sounds/`,
  `music/` hold files one level down (`art/<set>/<file>`), `locales/`, `layout/`,
  `decks/`, `missions/`, `ui/` hold files right in them; the one sub-folder is
  `ui/fonts/` (`.ttf`, `.otf`, `.txt`, `.md`), and the one JSON file in `ui/` is `theme.json`.
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
`missions` (`name`, `intro`, `lines`, `reward_line`), `hints`, `tutorial` (the texts of
`tutorial.json`, §12), `voice`
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

`decks/<name>.json`: `{name, champion, cards: [ids], code?, arena?, description?}`. `check`
validates every deck by the pack's rules (size, class, copies by rarity, the
mode's sets, collectible). File names sort the list (`01_…`). They are the game's deck
templates: a player's list starts empty, and a new deck (a class, then "From a template")
may start as a copy of one; the client shows its name (the locales' `decks.<file name>`
term, else `name`), its mana curve and `description` (a short text, at most 300
characters: one string or `{lang: text}`). The server's trial game plays the first two.

`missions/<n>.json`: a scripted game against a boss:

| Field | Meaning |
|---|---|
| `id` | Mission number (1-based). |
| `champion`, `boss`, `boss_power` | The player's champion, the boss (a `CHAMPION`) and its power. |
| `powers_locked` | Both powers can't be used. |
| `boss_guarded` | The boss can't be attacked while it has minions. |
| `end_turn_block` | `{while_can_play, while_can_attack}`: the player can't end the turn while a card can be played / a minion can attack. |
| `player` | `{mana, hand, deck}`: starting mana crystals, hand, deck **top card first**. |
| `boss_deck` | Top card first. |
| `mulligan` | false: no mulligan. |
| `reward` | A card shown after a win. |
| `hints` | Hint keys, in order; texts in `locales/<lang>.json` `hints`. |
| `script` | `scripts/<file>.lua#<name>`: a named hook set the player's champion gets at the start (an enchantment), or null. Classic missions 1–2: `ench:tutorial_guard`, the champion can't drop below 1 health. |

Missions are in `rules_hash` (they define decks and rules); their texts are not. Which missions
form the tutorial, in what order, and what the player is shown around them is `tutorial.json` (§12).

## 9. Card scripts

`cards.json` points a card at its logic: `"script": "scripts/mage.lua#VAN_CS2_029"`.
A script file returns a table of cards with hooks; `scripts/lib.lua` (optional)
holds shared helpers, visible to the other files as the global `lib`. The
language subset is in [lua.md](lua.md); the engine API (`g`), the hooks and the
events in [api.md](api.md). A card without a script has no hooks (vanilla
minion, weapon, …). Keys of a script table that are not card ids name hook sets
for enchantments (`"ench:nightmare"`).

The engine (`rust/engine`) loads a pack with the API op `load_pack` (the
`.cardpack` bytes as base64, or a path on native hosts) and plays it with
`new {pack: <rules_hash>, …}`; without `pack` it plays its built-in Classic
ruleset, made at build time from `packs/classic` (rust/engine/README.md).

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
vocabulary; champions → `POWER` cards; `default_power` (a `POWER` card; the engine needs it whenever the pack has champions); scripts exist; art/sound/music folders ↔
manifest; every locale file present and every card named in the default one;
decks legal; mission cards exist; emblems exist; `rules_hash` current; `ui/theme.json`
against `schema/theme.schema.json` and the fonts and pictures it names present; `tutorial.json`
against `schema/tutorial.schema.json` and its cross references (§12).

The game has the same build and check inside (*Games → Pack tools*, `game/pack_check.gd`, `ui/pack_tools.gd`):
a source folder (or a `.zip` of it, or a `.cardpack`) is built without its `recipe.json` steps, checked as
`check` does, loaded into the engine and played by bots with its ready decks (as `tools/pack_try.gd`); what it
cannot check is listed in `site/dev/en/testing.md` §3. It reads the schemas from `res://packs/schema/`
(`tools/build_packs.sh` copies `schema/` there).

## 11. UI theme (`ui/theme.json`)

An optional file that styles the interface while the pack is active: buttons, panels,
headings, text, fields, popups, the End Turn button, mana crystals and rarity gems.
Without it the interface looks exactly like Classic (wooden planks, tavern panels,
Alegreya and Cinzel Decorative). Every key is optional; a missing one keeps Classic's
value. The client reads it when the pack becomes active and restyles every open screen
at once (no restart). Presentation only: not in `rules_hash`. Schema:
[schema/theme.schema.json](schema/theme.schema.json). Colours are `"rrggbb"` or
`"rrggbbaa"` (lowercase hex).

| Key | Meaning |
|---|---|
| `about` | Free text for people. |
| `colors.text`, `colors.muted` | Interface text, secondary text. |
| `colors.accent` | Classic's gold: headings, titles, highlights, focused fields, slider fill. |
| `colors.table` | Behind the screens' pictures. |
| `colors.panel`, `colors.panel_border` | Fill (alpha for translucent glass) and rim of panels, popups, fields and menus. |
| `colors.backdrop` | Tint of the screen backdrops (`ui/menu`, `ui/library`). |
| `colors.button`, `button_hover`, `button_pressed`, `button_disabled` | Button fills (styles `flat`, `neon`). |
| `colors.button_border` | Button rim (lighter under the mouse). |
| `colors.button_text`, `button_text_hover`, `button_text_pressed`, `button_text_disabled` | Button labels. |
| `colors.outline`, `outline_size` | The dark edge around interface text (0–8 px). |
| `colors.danger`, `colors.ok` | Errors and confirmations. |
| `button.style` | `wood` (Classic's planks), `flat` (flat boxes), `neon` (flat boxes that glow). |
| `button.radius`, `button.border` | Corner radius and rim width in px. |
| `button.glow`, `glow_size`, `glow_hover`, `glow_hover_size` | `neon`: the soft light around a button, and under the mouse. |
| `button.texture`, `button.texture_margin` | A 9-slice picture in `ui/` for every button (tinted for hover, pressed, disabled); wins over `style`. |
| `panel.radius`, `panel.border`, `panel.glow`, `panel.glow_size` | Panels: corners, rim width, the glow around them. |
| `panel.texture`, `panel.texture_margin` | A 9-slice picture in `ui/` for popups, tooltips and plain panels (the frames screens draw stay flat). |
| `fonts.title`, `fonts.body` | `ui/fonts/<file>.ttf|otf`: headings and pack titles; all other interface text. A variable font with a `wght` axis gets the weights the interface asks for. It must cover every language of the pack (Latin with diacritics, Cyrillic…). Card texts keep the client's own font (the card layout is measured with it). |
| `end_turn.button`, `border`, `text`, `ready`, `ready_border` | End Turn while moves are left and when none are (default: the button colours and `ok`). |
| `mana` | The mana crystals of the game screen. |
| `rarities` | `{rarity id: colour}`: the rarity gems; wins over `manifest.json` `colors.rarities`. |
| `menu.shade`, `menu.particles` | The main menu: a tint over its picture, and a scene effect by name (§12): `embers` (Classic), `rain` (streaks in the accent colours), `snow` or `none`. |

Fonts must allow redistribution (SIL OFL, Apache…); put their licence next to them
(`ui/fonts/<Name>-OFL.txt`). Neonfall (`packs/neon/ui/`) is the example: dark glass
panels with thin cyan rims, glowing magenta-rimmed buttons, Tektur for titles and
Exo 2 for text (both OFL, subset to Latin, Latin Extended-A and Cyrillic).

In the client: `ui/palette.gd` loads the theme (`Palette.UI`, `TEXT`, `ATTACK`, `MUTED`,
`DANGER`, `OK`, `Palette.ui()` maps Classic's interface colours to the theme's roles, so
screens that pass Classic's colours restyle by themselves), `ui/fonts.gd` builds the one
Godot `Theme` from it and refills it in place on a pack switch.

## 12. Tutorial (`tutorial.json`) and scene effects

An optional file at the top of the pack. With it the game shows a Tutorial (only for this pack);
without it (Neonfall) there is none, even if the pack has `missions/`. Presentation only: not in
`rules_hash` (the missions it names are). Schema: [schema/tutorial.schema.json](schema/tutorial.schema.json).
Classic's (`packs/classic/tutorial.json`) is the full example: six missions, fourteen hints.

| Key | Meaning |
|---|---|
| `about` | Free text for people. |
| `unlock` | `in_order` (default): the first mission is open, each next one after the previous is won. `all`: every mission is open. |
| `effect` | A scene effect behind the mission list (below). |
| `missions` | `[{id, intro?, effect?}]` in the order the tutorial plays them. `id` names `missions/<id>.json` (its boss, decks, rules, `reward`, `hints`). `intro`: the pages shown before the mission (none: it starts at once). `effect`: a scene effect over the mission's board. |
| `hints` | `{hint key: [condition, …]}`: when a hint a mission lists may show (any condition holds). Each hint shows once, on the player's turn, after the mission's intro line, in the order of the mission's `hints`. |

**Texts.** Every text in the file is a key into `locales/<lang>.json` `tutorial` (keys
`[a-z0-9_.]`, e.g. `"minion_card.title"`). A mission's words are in `missions."<id>"`: `intro` (the
first line on the board), `lines.start` / `lines.hurt` (the boss at half health) / `lines.defeat`, and
`reward_line` (under the reward card after a win). Hint words are in `hints."<key>"`. The client
looks a text up in the player's language, then the pack's default language. `check`: a text missing
in the default language is an error (`lines`, `reward_line`: a warning); missing in another
language, a warning.

**A page** `{title, text, effect?, items}`: a title on top, the text at the bottom, the items on a
1280×720 stage. Items (points are `[x, y]` in stage pixels):

| Item | Draws |
|---|---|
| `{"card": id, "at": [x, y], "scale": 2}` | A card (`CardView`, 120×170 at scale 1). |
| `{"hero": id, "at": [x, y], "health": 30}` | A `CHAMPION`'s portrait in an oval centred on `at`, with its health. |
| `{"mana": n, "at": [x, y]}` | A mana bar with n crystals. |
| `{"picture": "ui/<file>", "at": [x, y], "size": [w, h]}` | A picture of the pack (any image file in it). |
| `{"note": key, "box": [x, y, w, h], "to": …}` | A note in a box; with `to`, an arrow from the box's side to a point `[x, y]` or to a part of a card of the page, `{"card": i, "part": p}`: the i-th `card` item before the note (from 0), part `cost`, `attack`, `health` (the arrow stops at the gem's edge), `text`, `text_l`, `text_r` (the text box's middle, left and right edges) or `top`. |
| `{"attack": [[x1, y1], [x2, y2]], "blocked": false}` | A red attack arrow; `blocked` crosses it out. |
| `{"big": "-2", "at": [x, y], "color": "ff6b6b"}` | A big outlined word or number (not translated: numbers, `Zzz`). |

**Hint conditions** `{"if": …}`: `always`; `can_play`, `can_attack`, `can_use_power` (the player has
such a legal move); `only_end_turn` (on the player's turn, nothing but End Turn is left); `mana`
with `at_least` (the player's mana crystals); `in_hand` with `cards` and/or `keyword` (a card in the
player's hand that is one of `cards` and has the mechanic `keyword`, a pack name); `on_board` (the
same for a minion on either side; `keyword` is a tag it has); `enemy_minions`; `enemy_weapon`.

**Scene effects.** The client has a few effects it plays over a whole screen by name; the pack
says which and where: `effect` of `tutorial.json` (the mission list), of a page (an intro page), of
a mission (its board), and `ui/theme.json` `menu.particles` (the menu, a name only). A value is a
name or an object:

| Effect | Looks |
|---|---|
| `embers` | Sparks drifting up from the bottom (Classic's menu). |
| `rain` | Thin fast streaks falling at a slant, in the theme's accent colours (Neonfall's menu). |
| `snow` | Soft flakes drifting down and sideways. |
| `none` (or null) | Nothing. |

`{"effect": name, "intensity": 0.1–3 (1 = normal: how many particles), "colors": ["rrggbb", …] (1–4,
replace the effect's own colours)}`. `check` refuses an unknown name. Effects run only while
animations are on.

```json
{
  "unlock": "in_order",
  "effect": "embers",
  "missions": [
    {"id": 1, "effect": {"effect": "rain", "intensity": 0.6, "colors": ["9ec5ff"]}, "intro": [
      {"title": "minion_card.title", "text": "minion_card.text", "items": [
        {"card": "VAN_CS2_172", "at": [520, 150], "scale": 2},
        {"note": "minion_card.cost", "box": [130, 136, 320, 100], "to": {"card": 0, "part": "cost"}},
        {"hero": "HERO_08", "at": [1050, 300], "health": 30}
      ]}
    ]}
  ],
  "hints": {"play": [{"if": "can_play"}], "taunt": [{"if": "in_hand", "keyword": "TAUNT"}, {"if": "on_board", "keyword": "TAUNT"}]}
}
```

with `locales/en.json`:

```json
{
  "tutorial": {"minion_card.title": "A minion card", "minion_card.text": "Every card costs Mana to play.",
    "minion_card.cost": "Mana cost: what it takes to play the card"},
  "missions": {"1": {"intro": "Play minions and attack Hogger!",
    "lines": {"start": "Grrr!", "hurt": "Rrraaagh!", "defeat": "Nooo..."}, "reward_line": "Oh yeah!"}},
  "hints": {"play": "Click a card in your hand to play it.", "taunt": "Minions with Taunt must be attacked first."}
}
```

`check` also verifies: every mission of the list has its `missions/<id>.json` and comes once; the
cards and champions of the pages exist (`hero` is a `CHAMPION`); pictures are in the pack; a note's
`{"card": i}` names a card before it; every hint a mission lists has a rule here and a text; the
cards of the conditions exist (an unknown `keyword`: a warning). A pack with `missions/` but no
`tutorial.json` gets a warning (no tutorial shows).

In the client: `Pack.has_tutorial()`, `Pack.tutorial()`, `Pack.text(path)` (game/pack.gd);
`Missions` (game/missions.gd: the active pack's mission ids, order, texts), `Progress` (won missions per
pack in `user://tutorial.json`), `Tutorial` (game/tutorial.gd: hints and boss lines in a game),
`TutorialView` / `TutorialIntro` (ui/: the list and the intro pages), `SceneFx` (ui/scene_fx.gd: the effects).

