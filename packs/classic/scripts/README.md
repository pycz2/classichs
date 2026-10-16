# Card scripts of the Classic pack

Card hooks in Lua (docs/packs/api.md, docs/packs/lua.md), one file per class
(`druid.lua`, …, `neutral.lua`, `tutorial.lua`); `lib.lua` holds shared
helpers and is visible to every other file as the global `lib`. A card points
at its hooks with `"script": "scripts/<file>.lua#<card id>"` (Classic:
`cards.patch.json`).

These are all of Classic's card hooks: the engine has no card logic of its own
(phase B of docs/superpowers/plans/2026-10-16-game-packs.md). Every recorded
game replays with them without a single difference (docs/packs/api.md,
"Checking a pack against recorded games").
