# Card scripts of the Classic pack

Empty for now. Phase B of docs/superpowers/plans/2026-10-16-game-packs.md moves
every card hook of `rust/engine/src/cards/*.rs` and the tutorial missions'
rules (`rust/engine/src/missions.rs`) here as Lua (docs/packs/lua.md), one
file per class (`druid.lua`, …, `neutral.lua`, `tutorial.lua`). A card points
at its hooks with `"script": "scripts/<file>.lua#<card id>"` in cards.json.
The pack is ready when all recorded games replay with it without a single
difference.
