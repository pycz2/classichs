# Cards: `cards.json`, card texts and layout

Schema: [schema/cards.schema.json](schema/cards.schema.json). `cards.json` is an
array of card objects, one per card (tokens, champions and powers included).

## 1. A card

```json
{"id": "VAN_CS2_029", "type": "SPELL", "class": "MAGE", "rarity": "FREE", "set": "VANILLA", "collectible": true,
 "cost": 4, "code_id": 68326, "legacy_code_id": 315, "script": "scripts/mage.lua#VAN_CS2_029",
 "fx": {"element": "fire", "cast": "bolt", "hit": "hurt"}}

{"id": "HERO_08", "type": "CHAMPION", "class": "MAGE", "set": "HERO_SKINS", "collectible": true, "health": 30,
 "power": "VAN_HERO_08bp"}

{"id": "VAN_NEW1_010", "type": "MINION", "class": "SHAMAN", "rarity": "LEGENDARY", "set": "VANILLA", "collectible": true,
 "cost": 8, "attack": 3, "health": 5, "keywords": ["CHARGE", "DIVINE_SHIELD", "TAUNT", "WINDFURY"], "unique": true}
```

| Field | Type | Meaning |
|---|---|---|
| `id` | `[A-Za-z0-9_]{1,64}` | Unique in the pack; art files and texts use it. |
| `type` | `MINION` `SPELL` `WEAPON` `CHAMPION` `POWER` | |
| `class` | class id | One of `rules.json` `classes`. |
| `rarity` | rarity id | Optional (tokens have none). |
| `set` | set id | One of `rules.json` `sets`. |
| `collectible` | bool | Can go into decks (if its set is a mode's set). Default false. |
| `cost`, `attack`, `health`, `durability` | int 0–999 | Default 0. A champion's `health` is its starting health. |
| `race` | race id | A minion's tribe. |
| `keywords` | [mechanic name] | The pack's names (`rules.json` `mechanics`); the engine gives the card the tags of `keyword`-kind ones. |
| `refs` | [mechanic name] | Mechanics the text mentions (tooltips only). |
| `spell_power` | int | Its `SPELL_POWER` amount. |
| `mana_lock` | int | Its `MANA_LOCK` amount (mana locked next turn). |
| `unique` | bool | Legendary frame (a dragon). |
| `power` | card id | `CHAMPION` only: its `POWER` card. |
| `code_id`, `legacy_code_id` | int | Numbers for deck codes (Classic: Hearthstone `dbfId` and the legacy one, so Hearthstone deck codes keep working). |
| `script` | `scripts/<file>.lua#<id>` | Its hooks ([format.md](format.md) §9). None: no hooks. |
| `fx` | object | Visual effects by name ([fx.md](fx.md)). Not in `rules_hash`. |
| `sounds` | `{play?, attack?, death?}` | Sound names in the chosen sound set, instead of the event's default. Not in `rules_hash`. |
| `voice` | card id | Whose voice lines it speaks (default: its own). Not in `rules_hash`. |

Everything except `fx`, `sounds` and `voice` is part of `rules_hash`.

## 2. Texts (`locales/<lang>.json`)

```json
{
  "cards": {"VAN_CS2_029": {"name": "Огненный шар", "text": "Наносит $6 ед. урона."}},
  "mechanics": {"TAUNT": {"name": "Провокация", "tip": "Враги обязаны атаковать существ с «Провокацией»."}},
  "classes": {"MAGE": "Маг"}, "races": {"BEAST": "Зверь"}, "rarities": {"FREE": "Базовая"},
  "ranks": {"25": "Злая курица", "1": "Трактирщик", "0": "Легенда"},
  "missions": {"1": {"intro": "…", "lines": {"start": "…", "hurt": "…", "defeat": "…"}, "reward_line": "…"}},
  "hints": {"play": "…"},
  "voice": {"HERO_08": {"greetings": "…", "attack": "…"}},
  "ui": {}
}
```

Card text markup (what the client understands today, `game/card_text.gd`):

- `<b>…</b>`, `<i>…</i>`: bold (keywords) and italic (flavour in brackets).
- `$N`: a number that spell power raises (shown bold and raised when it is).
- `#N`: a number that healing modifiers change (shown as is).
- `N |4(singular,plural)`: the word form for the number before it.
- `[x]` at the start: the text has hand-placed line breaks (`\n`).
- Anything else in `[ ]` is shown literally (no BBCode injection from a pack).

Missing text falls back to `default_locale`, then to the id.

## 3. Layout (`layout/<lang>.json`, optional)

Card id → `{name, text, lines?, valign?, dy?}`: font sizes of the name and the
text, the text already split into rich lines (`[b]bold[/b]`, `[lb]` for `[`),
`valign: "top"` (else centred) and a vertical shift in pixels. The Classic pack
ships the layouts tuned for its 8 languages (`data/card_layout`). Without a
layout the client measures and wraps the text itself.

## 4. Classic: where the data comes from

`packs/classic/recipe.json` builds `cards.json` from `data/cards.json`
(HearthstoneJSON, 534 cards):

| HearthstoneJSON | Pack |
|---|---|
| `type` `HERO`, `HERO_POWER` | `CHAMPION`, `POWER` (others unchanged) |
| `cardClass` | `class` |
| `mechanics` | `keywords` (names unchanged; mapped in `rules.json`) |
| `referencedTags` | `refs` |
| `spellDamage`, `overload` | `spell_power`, `mana_lock` |
| `elite` | `unique` |
| `dbfId`, `legacyDbfId` | `code_id`, `legacy_code_id` |
| `name`, `text` (`enUS`, `ruRU`, `deDE`, `frFR`, `esES`, `ptBR`, `itIT`, `plPL`) | `locales/<en ru de fr es pt_BR it pl>.json` |

`packs/classic/cards.patch.json` adds the champions' `power` (as
`rust/engine/src/state.rs` and `missions.rs` give them: `HERO_0n` →
`VAN_HERO_0nbp`, Jaraxxus → `VAN_EX1_tk33`, tutorial bosses → their mission's
power, the rest Fireblast) and every card's `fx` ([fx.md](fx.md) §3).
