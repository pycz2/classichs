# Card scripts of the Classic pack

Card hooks in Lua (docs/packs/api.md, docs/packs/lua.md), one file per class
(`druid.lua`, …, `neutral.lua`, `tutorial.lua`); `lib.lua` holds shared
helpers and is visible to every other file as the global `lib`. A card points
at its hooks with `"script": "scripts/<file>.lua#<card id>"` (Classic:
`cards.patch.json`).

Phase B of docs/superpowers/plans/2026-10-16-game-packs.md moves every hook of
`rust/engine/src/cards/*.rs` here; until a card is ported the engine uses its
Rust hook. Done: `mage.lua` (all Mage cards and Fireblast), the Basic neutral
cards and The Coin in `neutral.lua`. The pack is ready when all recorded games
replay with it without a single difference.
