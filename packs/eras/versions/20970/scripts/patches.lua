-- Version 9.1.0.20970 (2017-09-18) on the Knights of the Frozen Throne pack: the cards that work differently since
-- the release (packs/loot/scripts/loot.lua has them as Kobolds & Catacombs found them). Spreading Plague, Fiery War
-- Axe and Hex only cost more (patch.json).
local cards = {}

-- Innervate (patch 9.1.0.20970): "Gain 1 Mana Crystal this turn only."
cards.VAN_EX1_169 = {
  spell = function(g, me)
    g.add_mana(g.ctrl(me), 1)
  end,
}

-- Murloc Warleader (patch 9.1.0.20970): "Your other Murlocs have +2 Attack."
cards.VAN_EX1_507 = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "MURLOC" then
        g.aura_add(m, 2, 0)
      end
    end
  end,
}

return cards
