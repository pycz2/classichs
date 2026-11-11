# One expansion pack: the checklist (steps 1–11 of docs/superpowers/plans/2026-11-11-expansions.md)

A set `<s>` (gvg, brm, tgt, loe, og, kara, msg, ungoro, icc, loot, gil: `tools/extract_cards.py` SETS) becomes the
pack `packs/<s>/`, built on the previous one. Do the items in order; the next set starts when every box is ticked.

## 1. Research

- [ ] The release day: hearthstone.wiki.gg, the set's page (e.g. "Goblins vs Gnomes"); an adventure: its first wing.
- [ ] The patch of that day: the wiki's "Patch x.y.z.BUILD" page; HearthSim hsdata at that build
      (`github.com/HearthSim/hsdata`, tag = the build). Likely builds, confirm each on the wiki: GvG 7234, BRM 8036,
      TGT 9786, LoE 10833, OG 12574, Kara 13921, MSG 15590, Un'Goro 18336, ICC 20457, LOOT 22115, GIL 23576.
- [ ] Every card of the set (and of the packs before it) as on that day: each card page's "Patch changes", the
      "Balance changes" pages and the patches between the previous set and this one (cost, stats, text in every
      language, tribe, rarity). The wiki shows today's card: always take that day's.
- [ ] Each new mechanic's wiki page and its "Notes"/interactions (Spare Part, Discover, Inspire, Joust, …).

## 2. Data

- [ ] `python3 tools/extract_cards.py --set <s>` → `data/<s>_cards.json` (collectible cards and their tokens).
- [ ] `packs/<s>/cards.patch.json`: the release stats, tribes, `script` of each card, `fx`; `null` takes a later field away.
- [ ] `packs/<s>/cards.texts.json` (card id → `{name?, text?: {enUS, ruRU, deDE, frFR, esES, ptBR, itIT, plPL}}`): the
      texts of that day where today's differ (hsdata's CardDefs.xml at the build has them all).
- [ ] `packs/<s>/recipe.json`: `"base": "../<previous>"`, `"root": "../.."`, `"skip": ["layout"]` (as Naxxramas; the
      base's pictures stay: a pack stands alone),
      `"bundle_in_client": false`, one step `{"do": "hsjson", "from": ["data/<s>_cards.json"], "patch": ["cards.patch.json"], "texts": ["packs/<s>/cards.texts.json"]}`.
- [ ] `manifest.json` (id `<s>-<year>`, names and description in 8 languages, the base's `art_sets`, `set_marks` for every set
      with an icon in `ui/set_<x>.png`), `rules.json` (the previous one plus the new set in `sets` and in the modes'
      sets, new races and mechanics), `locales/<lang>.json` (8 languages: `sets` names, new `mechanics` names and tips).
- [ ] `python3 tools/pack.py build packs/<s> -o /tmp/<s>.cardpack`: 0 errors, 0 warnings.

## 3. Mechanics

- [ ] Data first (keywords of docs/packs/schema/keywords.json), Lua otherwise (`packs/<s>/scripts/<s>.lua`); a new engine
      feature only when Lua cannot do it, neutral (no card names), documented in docs/packs/api.md
      (`python3 tools/lua_api.py --check`).
- [ ] A card whose condition lights it in the hand ("if you're holding a Dragon", no duplicates, Jade, …): its `glow`
      hook (`glow = function(g, me) … end`, read-only). Combo cards glow by themselves.
- [ ] Classic's and Naxxramas's rules hashes and `cd rust && cargo test --release --test parity` do not change.

## 4. Tests

- [ ] A card test for every card (data/card_tests style); `tools/check_card_tests.gd` for the pack: 0 problems.
- [ ] Rust tests for every new engine feature (`rust/engine/tests/<s>.rs`, as naxx.rs).
- [ ] All suites green: `./run_tests.sh`, `cd rust && cargo test --release`, `cd server && cargo test --release`,
      `python3 -m unittest tools/test_pack.py`.

## 5. Decks

- [ ] `packs/<s>/decks/NN_<name>.json`: several strong decks of that set's meta (each legal: `pack.py check`), with
      descriptions; the bots play them (Library::of_pack / templates).

## 6. Assets (local only, never committed)

- [ ] Backgrounds: `python3 tools/pack_backgrounds.py packs/<s> --theme "<the set's places, colours, mood>"` → `ui/menu`,
      `board`, `library`, `result_*` (tools/codex_guard.sh guards the Codex limit); `ui/theme.json` in the set's colours.
- [ ] The owner's art, sounds, voice EN+RU, hero lines and legendary music:
      `python3 tools/fetch_set_assets.py --set <s>` → `~/ClassicHS-local/<s>/{art,set,voice}`; check SOURCES.md.

## 7. The local pack

- [ ] `python3 tools/fetch_set_assets.py --set <s> --build` → `~/ClassicHS-local/<s>-custom-art.cardpack` (the `custom`
      pictures, sounds and voice of every level, Classic's to this set's: the pack needs no other pack).

## 8. The play check

- [ ] A real bot-vs-bot game with the pack (`tools/pack_try.gd`, and a server game on a free port with a temp DB), the
      new mechanics seen on the table; the client with the local pack: pictures (every level's), sounds,
      legendary music, voice in Russian and English, set marks, the collection's set filter.
- [ ] `tools/build_packs.sh` puts the pack into `build/packs/` (not into the game's builds); commit on the branch.
