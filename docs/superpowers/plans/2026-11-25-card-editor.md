# 0.75.0: the card editor — the owner's request (2026-11-25)

(After 0.74.0. Not started: the owner says when.)

## What the owner wants

An editor where a person makes their own game: their own cards, sets, classes and subclasses, interactively —
upload pictures, write the texts comfortably — and at the end exports it as a pack (.cardpack) that the game
imports. It should use the mechanics we already have. Maybe a separate application; Godot or the web, whichever is
simpler and faster.

## The proposal (to confirm)

- **Godot, as a separate application from the same project** ("ClassicHS Studio": its own main scene and export
  presets, desktop and web). Why: it reuses what draws and plays cards today — CardView/MinionView and Art (the card
  looks exactly as in the game), the rules engine through the GDExtension (a card is tried in a real match at once:
  the debug table's CardLab), the pack reader and its checks (game/pack.gd problems(), the hashes), the locales.
  A web editor would need a second copy of the card drawing and of the pack checks.
- **The game (pack)**: id, names and description in the 8 languages, version, rules (mana, hand, board, deck size,
  fatigue …: rules.json), the tile picture, backgrounds, music and sound sets.
- **Classes and subclasses**: name, colour, hero (portrait, health), Hero Power (as a card), class cards; subclasses
  (e.g. multi-class groups, tribes) as the pack format allows.
- **Sets and rarities**: which cards are in which set, collectible or token, Standard/Wild if wanted.
- **Cards**: type (minion, spell, weapon, hero, Secret, Quest …), cost, attack, health/durability, tribe, rarity,
  class, keywords from our mechanics (a list with explanations), the text in each language with keyword highlighting
  and a live preview; the picture (upload, then frame it with the framing tool's move/zoom — the same
  classichs-art-framing/1 values); sounds and lines per slot (play, attack, death …).
- **Effects without code where possible**: building blocks over the engine's existing mechanics (Battlecry,
  Deathrattle, triggers "when/after/at the start of …", auras, targets "a minion / an enemy / all …", actions "deal N,
  heal N, draw N, summon X, give +A/+H, destroy, freeze, transform, discover …") that write the card's Lua script from
  templates; for the rest the raw Lua with the API reference (docs/packs/api.md) and a check.
- **Decks**: ready decks for the pack (the deck builder's code).
- **Try it**: any card in a debug match (CardLab and the scenario library of 0.73.0) before export.
- **Export / import**: build the .cardpack (zip with manifest, rules, cards, scripts, art, sounds, locales, the
  hashes — the same format tools/pack.py makes), check it like the server does (load, compile every script, a trial
  bot game), install it into the game; open an existing pack to edit it (a copy with a new id).

## Open questions for the owner

1. Godot application (recommended) or a web page?
2. How far the no-code effects should go before the raw Lua is needed.
3. Can a made pack be shared from the editor to a server directly (the upload API exists), or only as a file?
