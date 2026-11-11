# Expansions after Naxxramas — the owner's request and the plan

Agreed 2026-11-11. Eleven new games (packs), one after another, each built on the previous one:

| # | Set | Released | Pack id (suggested) | HearthstoneJSON prefix |
|---|---|---|---|---|
| 1 | Goblins vs Gnomes | 2014-12-08 | gvg-2014 | GVG_ |
| 2 | Blackrock Mountain | 2015-04-02 | brm-2015 | BRM_ |
| 3 | The Grand Tournament | 2015-08-24 | tgt-2015 | AT_ |
| 4 | The League of Explorers | 2015-11-12 | loe-2015 | LOE_ |
| 5 | Whispers of the Old Gods | 2016-04-26 | og-2016 | OG_ |
| 6 | One Night in Karazhan | 2016-08-11 | kara-2016 | KAR_ |
| 7 | Mean Streets of Gadgetzan | 2016-12-01 | msg-2016 | CFM_ |
| 8 | Journey to Un'Goro | 2017-04-06 | ungoro-2017 | UNG_ |
| 9 | Knights of the Frozen Throne | 2017-08-10 | icc-2017 | ICC_ |
| 10 | Kobolds & Catacombs | 2017-12-07 | loot-2017 | LOOT_ |
| 11 | The Witchwood | 2018-04-12 | gil-2018 | GIL_ |

(Verify every date on the Hearthstone Wiki; adventures released by wings: use the first wing's date for the
card state, and include all the set's collectible cards and the tokens they make.)

## The rules of every pack

- A pack holds all the cards of the packs before it (Basic, Classic, Naxxramas, … up to itself): like Wild,
  one format. Every card is **exactly as on the release day of that set**: cost, stats, text in every language,
  tribe (a tribe added later is absent; Mechs exist from GvG, Pirates/Dragons/… as the data of that time),
  rarity, behaviour. Check the balance changes and text/tribe changes between the previous set's release and this
  one (Hearthstone Wiki: each card's "Patch changes", the "Patch x.y" pages, the "Balance changes" pages). The
  wiki often shows today's version: always use the version of that day.
- Source of truth: hearthstone.wiki.gg (card pages, mechanics pages with their interaction notes, patches).
  HearthSim hsdata (CardDefs.xml at the build of that day) for data and localized names/texts of that time.
- Packs chain by reference like packs/naxx does with packs/classic (patches and scripts in order; a later patch
  wins). Fix the chain once in tools/pack.py so it scales to 12 levels.
- Engine: every new mechanic data-driven where it can be, Lua otherwise; the `g.*` API documented
  (docs/packs/api.md, tools/lua_api.py --check). Classic's and Naxxramas's behaviour and parity must not change.
- Every card has a card test (data/card_tests style; tools/check_card_tests.gd per pack: 0 problems).
- Deck templates (several strong decks of that set's meta), bots able to play (Library::of_pack / templates).
- **Every pack is self-contained:** it never needs another installed pack to work or to show its pictures
  (duplicated pictures inside packs are fine; the size limits are 1 GiB per pack, 2 GiB unpacked).
- **Art:** no generated card art this time. A distributed pack carries its base chain's pictures (Classic's sets
  by reference through `base`); its new cards get the procedural drawn art. Each pack gets generated backgrounds
  only (menu, board, results, library — Codex, with tools/codex_guard.sh). The owner's Blizzard art and sounds are downloaded locally, never committed, never in a
  distributed pack (`local` sets), into ~/ClassicHS-local/, and his local custom packs are built from them (each
  holds the `custom` pictures, sounds and voice of every level of its chain).
- **Assets small:** card pictures as WebP (also convert the existing local custom art); sounds and voice
  compressed (mono, low bitrate OGG Vorbis or MP3 — what Godot and pack.py take); legendary play music downloaded
  and played when the legendary is played (besides its voice line). Voice in English and Russian as before.
- **Distribution:** these packs are not inside the client builds (APK, desktop, web stay small); they are release
  files (ClassicHS-x.y.z-<pack>.cardpack) and bundled on the server, so players download them from a server or
  install a file.

## Client and engine features asked for with them

- Cards in hand whose effect depends on a condition that holds now glow yellow (e.g. "if your deck has no
  duplicates" — Reno Jackson, Kazakus, …; also Combo when it is active, "if you're holding a Dragon", Jade, …): a
  per-card condition the engine evaluates and the client shows.
- The burning rope (fuse) burns the other way (as in Hearthstone: from the right end to the left).
- Each card of a non-Classic pack shows its set (an icon/name on the card and in the big card view); the
  collection can filter by set.
- Legendary play music.

## Order of work

0. Foundation: the pack chain in pack.py, the asset tools (WebP, compressed
   sounds, legendary music; per set download of art/sound/voice EN+RU into ~/ClassicHS-local/), the condition
   glow, the rope direction, the set mark and the collection filter, distribution (not in client builds; release
   assets; server bundle).
1–11. One set at a time, in the order above: research, data (patches of that day), engine mechanics, scripts,
   card tests, templates, bots, generated backgrounds, local assets and the owner's local pack, a real bot-vs-bot
   play check; all suites green; commit. The next set starts only when the previous one is done.
12. One release with all of it; a local HTML report (screenshots, the mechanics added, per set notes).
13. Afterwards (no release, no fixes): a review of every client screen in Russian and English — overlaps, text
   out of its box, buttons off the screen — and a local HTML report with screenshots of each finding.
