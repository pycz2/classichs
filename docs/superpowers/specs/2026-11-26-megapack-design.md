# The megapack: design (0.73.0)

Plan: docs/superpowers/plans/2026-11-17-boomsday-to-ros-and-the-megapack.md ("Version 0.73.0: the megapack").
Research (local, Blizzard data stays local): ~/ClassicHS-local/prep/patches (README.md, versions.json: 58 versions,
modes.md, media_changes.md, cache/hsjson/<build>.json, cache/diffs). Every agent reads this file first; the names
and formats below are the contract between the parts.

## 1. One pack, many versions

A pack may carry **versions**. Its manifest gets:

```json
"versions": [
  {"id": "5314", "build": 5314, "patch": "1.0.0.5314", "date": "2014-05-08", "era": "classic",
   "name": {"en": "Classic, May 2014", "ru": "Классика, май 2014", ...8 languages},
   "dir": "versions/5314", "formats": ["standard"], "rules_hash": "<this version's rules hash>"},
  ...
],
"default_version": "31761"
```

- `formats`: `["standard"]` before 2016-04-26 (one format, called Standard in the UI as the game did: no Wild yet),
  `["standard", "wild"]` from 5.0.0.12574 on. Each version's `rules.json` carries `"formats": {"standard": {"sets":
  [...]}, "wild": {"sets": [...]}}` (the set lists of that date: modes.md / versions.json `format`) and the Arena
  pool and bans of that version (`"arena": {...}`).
- `versions/<id>/` holds that version's **rules files** exactly as a one-version pack has them at its root:
  `rules.json`, `cards.json`, `scripts/`, `missions/` (if any), `locales/` (the card names and texts of that build),
  `layout/` (if any: Classic's hand-tuned text layout belongs to its texts), `decks/`, `tutorial.json` (if any).
  Everything outside `versions/` is **shared**: art, sounds, voice, music, backgrounds, ui, fonts, the tile picture.
  (As built in the foundation: `is_version_file` in tools/pack.py, rust/engine/src/pack.rs and game/pack.gd.)
- **The version view**: the files of version V = the shared files + the files of `versions/V/` moved to the root.
  The engine, the client and the server all work on a view as if it were a one-version pack. The rules hash of a
  version is the usual rules hash (docs/packs/format.md §3) over its view; `manifest.rules_hash` = the default
  version's. The content hash stays the hash of the whole zip's files.
- A pack without `versions` is one implicit version (everything as today). Old clients/servers that do not know
  `versions` open the megapack as its default version (its root has the default version's rules files too: the
  builder copies them there), so nothing breaks.

## 2. Interfaces

- Python (tools/pack.py): `version_view(files: dict, version_id) -> dict` (its manifest's `rules_hash` is the
  version's), `version_ids(files)`; the builder writes the megapack from a recipe (§4); checks every version (rules
  load, scripts compile, the hashes) and the size limits (the rules and text limits are per version; the whole pack's
  1 GiB / 2 GiB / 50 000 files stay: the 58-version pack is far below them; docs/packs/format.md).
- Rust (rust/engine/src/pack.rs): `pub fn versions(files: &Files) -> Vec<VersionInfo>` (VersionInfo: id, build,
  patch, date, era, name, dir, formats, rules_hash) and `pub fn version_view(files: &Files, id: &str) ->
  Result<Files, String>`; rules_hash over a view as today; `read_zip` reads the rules files and decks of every version.
- GDScript: `Pack.versions() -> Array` (the manifest list, [] for a one-version pack), `Pack.default_version()`,
  `Pack.version_view(id) -> Pack` (a Pack whose rules files come from the version; media from the shared root;
  `.version_id` = id (`version()` is already the pack's version string); `whole()` = its pack; `rules_hash()` the
  version's; `content_hash()` the pack's). `Packs.active()` returns the view of the chosen version (Settings:
  `pack_versions` = {pack id: version id}), so the rest of the client keeps using one Pack. `Packs.version(p)`,
  `Packs.set_version(p, id)`, `Packs.is_active(p)`, `Packs.find_rules(h)` (a version's view by its rules hash);
  `Packs.set_active(view)` activates its pack at that version.
- Formats: a game is created with `"format": "standard" | "wild"` (the engine's `new` request / scenario; default
  "wild" = every set of that version, i.e. today's behaviour). The engine keeps the format's set list and uses it for
  deck checks and for every random card pool ("a random minion", Discover, generated cards), as the game did; Arena
  uses the version's Arena pool.
- Server: a pack row gets its versions (a table `pack_version`: pack id, version id, rules_hash, formats, name);
  `rules_for(rules_hash)` finds the pack by any version's rules hash and loads that view. Ranked and Casual queues
  and ladders are keyed by (rules_hash, format): one ladder per version and mode. The client's server game screen
  picks the game, then the version, then the mode.

## 3. Ids and names

- Pack id `hs-eras`; names "Hearthstone 2014–2019: every version" / "Hearthstone 2014–2019: все версии" (and the
  other 6 languages); version ids are the build numbers as strings; the UI groups versions by era (the 16 eras of
  versions.json) with the date and a short name of what changed ("Leeroy Jenkins and Starving Buzzard nerfed").
- The separate packs (classic … dal) stay and are still released in 0.73.0 (the servers have ladders in them).

## 4. Building: packs/eras

`packs/eras/recipe.json` lists the 58 versions; each version is made from an existing pack's rules files (the newest
pack of its era whose build ≤ the version's build, or the next one for a version before its era's pack: e.g. 4944
from classic) plus a **version patch** `packs/eras/versions/<id>/patch.json`:

```json
{"base": "naxx", "build": 6485, "about": "1.2.0.6485: Starving Buzzard and Leeroy Jenkins nerfs",
 "cards": {"<card id>": {"cost": 5, "attack": 6, "health": 2, "text": {"enUS": "...", "ruRU": "..."},
                         "mechanics": ["CHARGE"], "race": "BEAST", "rarity": "...", "collectible": true,
                         "name": {...}, "set": "..."}},
 "add": [<whole card objects>], "remove": ["<id>"],
 "behaviour": {"<rules.json behaviour flag>": <value>},
 "sources": ["versions.json change rows / wiki pages used"]}
```

plus optional `packs/eras/versions/<id>/scripts/*.lua`: loaded after the base's scripts; a card defined there
replaces its earlier hooks (a behaviour change: Warsong Commander 3.2.0.10604, Charge 6.1.3, Murloc auras 6.2 …).
As built (packs/eras/README.md has the details): the card ids are the pack's (`VAN_EX1_116`); `cards` takes
HearthstoneJSON's field names or the pack's (`keywords`, `script`, `fx`), null/false/[] takes a field away; `add`
holds HearthstoneJSON card objects; the recipe's versions are `{id, patch, date, era (the era's pack folder), name,
formats}` and `default_version`; a version's scripts go into it as `scripts/version/<name>.lua`, which the engine
loads last (a key defined there replaces a card's hooks or an `ench:` set).
Texts: every changed text in all 8 languages of that build (as tools/extract_cards.py does for the release builds).
Shared media: the union of all packs' media (art sets, sounds, voice, music, backgrounds), as the separate packs
have them (self-contained; the "-custom-art" local packs likewise get an "eras-custom-art" local build).

## 5. Tests

- Every version: the rules load, every script compiles, every card plays without a script error (as
  every_card_plays_without_a_script_error does per expansion), the deck templates play bot games.
- Each version patch: a test per changed card (the stat/text of that version; a behaviour change played out).
- Formats: a Standard game offers no Wild card in a random pool; deck checks per format.
- The client: version picker, the version view's rules hash, Settings remember the version.
