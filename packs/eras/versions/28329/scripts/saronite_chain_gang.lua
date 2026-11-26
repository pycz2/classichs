-- Saronite Chain Gang from patch 13.0.3.28329: "Battlecry: Summon another Saronite Chain Gang" (a fresh one; icc.lua's
-- copies this minion with its buffs, and Shudderwock got a copy of itself).
local cards = {}

cards.ICC_466 = {
  battlecry = function(g, me)
    g.summon_right(me, "ICC_466")
  end,
}

return cards
