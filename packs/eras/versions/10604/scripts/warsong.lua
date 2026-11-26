-- Patch 3.2.0.10604 (2015-10-20): Warsong Commander no longer gives Charge; your Charge minions have +1 Attack
-- (as packs/loe/scripts/loe.lua has it).
local cards = {}

cards.VAN_EX1_084 = {
  aura = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if g.has(m, "CHARGE") then
        g.aura_add(m, 1, 0)
      end
    end
  end,
}

return cards
