-- Leeching Poison from patch 13.0.3.28329: "Give your weapon Lifesteal this turn" (icc.lua's gives it for good).
local cards = {}

cards.ICC_221 = {
  can_play = function(g, me)
    return g.weapon(g.ctrl(me)) ~= nil
  end,
  spell = function(g, me)
    g.give_tag(g.weapon(g.ctrl(me)), "LIFESTEAL", true)
  end,
}

return cards
