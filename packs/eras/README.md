# Hearthstone 2014–2019: every version (`hs-eras`)

One pack with many versions of the game (docs/packs/format.md §13, design:
docs/superpowers/specs/2026-11-26-megapack-design.md). `tools/pack.py build packs/eras -o build/packs/eras.cardpack`
builds it (`tools/build_packs.sh` does it with the other packs). This README is not copied into the pack.

## What is here

- `manifest.json`: the pack's id, names and descriptions. The builder fills in the rest from the default version's
  base pack (languages, colours, art sets…) and adds `versions`, `default_version`, `fx` and `rules_hash`.
- `recipe.json`: the versions, oldest first, and `default_version` (the one a client without a version picker plays).
- `versions/<id>/patch.json`: how version `<id>` differs from its base pack.
- `versions/<id>/scripts/*.lua` (optional): the version's own card scripts.
- `versions/<id>/decks/*.json` (optional): the version's own ready decks (below).
- `formats.json`: the Standard/Wild and Arena periods of the game (below).
- `ranked.json`: the Ranked and Arena-run periods and the rank names (below).
- `ui/`: the pack's own menu picture and library tile (they win over the base packs' pictures).

## Adding a version

1. Pick its id: the build number as a string (`"7628"`). Take the facts from
   `~/ClassicHS-local/prep/patches/versions.json` (its `changes`, `rules_changes`, `format`).
2. Add it to `recipe.json` `versions`, in date order:

   ```json
   {"id": "7628", "patch": "2.1.0.7628", "date": "2015-01-29", "era": "gvg", "formats": ["standard"],
    "name": {"en": "…", "ru": "…", "de": "…", "fr": "…", "es": "…", "pt_BR": "…", "it": "…", "pl": "…"}}
   ```

   Only these fields. `era` is the era's pack folder (`classic`, `naxx`, `gvg`, … `dal`); `name` says in a few words
   what changed, in the 8 languages; `formats` is `["standard"]` before 5.0.0.12574, `["standard", "wild"]` from it on.
   Change `default_version` when the new version should be the default (the newest one, in the end).
3. Write `versions/<id>/patch.json`:

   ```json
   {"base": "gvg", "build": 7628, "about": "2.1.0.7628 (2015-01-29): …",
    "cards": {"VAN_EX1_116": {"cost": 5, "text": {"enUS": "…", "ruRU": "…", "deDE": "…", "frFR": "…",
                                                "esES": "…", "ptBR": "…", "itIT": "…", "plPL": "…"}}},
    "add": [], "remove": [], "behaviour": {},
    "sources": ["versions.json 2.1.0.7628", "…"]}
   ```

   - `base` (required): the pack folder whose rules files, texts, layout and decks the version starts from: the
     newest pack of its era whose build is not after the version's, or the next one for a version before its era's
     pack (4944 from `classic`). The base pack is built as it is, then the patch changes it.
   - `build`: the build number (goes into the manifest). `about`, `sources`: for people.
   - `cards`: card id (the pack's id: Classic's cards are `VAN_<id>`) → the fields that change. Field names are
     HearthstoneJSON's (`cost`, `attack`, `health`, `durability`, `mechanics`, `race`, `rarity`, `set`,
     `collectible`, `cardClass`, `spellDamage`, `overload`, `elite`, …) or the pack's own (`keywords`, `script`, `fx`,
     `power`, … docs/packs/cards.md). `null`, `false` or `[]` takes a field away. `name` and `text` are
     `{HearthstoneJSON locale: text}` and must have all 8 languages (`enUS ruRU deDE frFR esES ptBR itIT plPL`):
     take them from that build with
     `python3 tools/extract_cards.py --version-texts <build> <card id> …` (it prints them as JSON). A card whose
     text changes loses its hand-tuned layout (`layout/`).
   - `add`: whole new cards as HearthstoneJSON objects (`id`, `type`, `cardClass`, …, `name`, `text` in the 8
     languages); give them pack fields (a `script`, `fx`) through `cards`.
   - `remove`: card ids the version does not have.
   - `behaviour`: `rules.json` `behaviour` flags to set (`null` clears one; docs/packs/rules.md).
   - `sets`: sets the base's `rules.json` doesn't know yet, added to its `sets` and to constructed decks (not the
     Arena): a card given before its set came out (22115: Marin the Fox, `LOOTAPALOOZA`).
   - `deck_recipes`: card id → its decks, as `rules.json` `deck_recipes` has them (docs/packs/rules.md: a card that
     stands for a whole deck); `null` takes a card's decks away.
4. A behaviour change that the data can't express (a card that works differently): put its script into
   `versions/<id>/scripts/<name>.lua`, a file that returns a table of hook sets like any card script
   (docs/packs/api.md). It goes into the version as `scripts/version/<name>.lua`, loads after the base's scripts,
   and a key it defines (a card id or an `ench:` hook set) replaces the base's hooks for it.
5. Build and check: `python3 tools/pack.py build packs/eras -o build/packs/eras.cardpack` checks every version
   (rules, scripts, texts, decks, hashes) and prints each version's rules hash. Add a test per changed card
   (tools/test_pack.py `Eras`, rust/engine/tests/eras.rs).

A version with no changes from its base pack has a patch with only `base`, `build`, `about` and `sources`
(6024 is the Naxxramas pack's cards and texts; its `rules.json` adds the formats and the Arena of its time).

## Formats and the Arena (`formats.json`)

`formats.json` holds the periods of the game by date, each with its Standard sets (and `exclude`: Hall of Fame cards,
the Promo and Reward cards once Wild came), its Wild sets (`null` before 2016-04-26) and its Arena (`sets`, `banned`,
`extra`: Arena-only cards), in the packs' set names and card ids. The builder gives each version those of the period in
force for most of its life (from its date to the day before the next game version's: `versions` lists the 58 with their
dates; the last to `until`) and writes them into its `rules.json` (`formats`, `modes.arena`); the recipe's `formats` of
the version must agree (`["standard", "wild"]` when that period has Wild). An Arena card the version doesn't have is left
out (the builder says so). Made from `~/ClassicHS-local/prep/patches/work/format_timeline.json` and `ranked_arena.md`.

## Ranked and the Arena runs (`ranked.json`)

`ranked.json` holds the Ranked periods by date (10, R1 … R10: each a `ranked` section as docs/packs/rules.md has it:
stars per rank, the ranks without star loss, the floors, the streak, Legend, the season reset), the Arena run periods
(wins and losses: 12 and 3 all along) and the rank names (`names`: English and Russian, the game's texts; a name that
changed is `[[from build, name]…]`). The builder gives each version the periods in force for most of its life (as for
`formats.json`) and writes `ranked` (each rank keeps its base pack's emblem: our own pictures, no Blizzard medals) and
`modes.arena` `wins`/`losses` into its `rules.json`, and the names of its ranks into its `locales/en.json` and
`locales/ru.json` (the other languages keep their base pack's names of ranks 25…1, the namesake cards' names; the New
Player Ranks 50…26 of October 2018 on show in English there). Made from `~/ClassicHS-local/prep/patches/ranked_arena.json`
(the wiki's Ranked and Arena pages of 2014–2019, the patch notes, the game's string files).

## Decks

`versions/<id>/decks/*.json` are the version's own ready decks; the builder puts them into the version next to its base
pack's decks (a deck with the same champion and cards only once; a deck the version's rules don't allow is left out and
printed). `tools/import_version_decks.py` copies the HearthPwn decks prepared for every version
(`~/ClassicHS-local/prep/decks/<build>/<standard|wild>/`) here as `standard_<file>.json` and `wild_<file>.json` (a deck
in both lists once, as Standard); the description keeps the deck's name, author and link. A folder `versions/<id>/` that
the recipe doesn't name yet is not read.
