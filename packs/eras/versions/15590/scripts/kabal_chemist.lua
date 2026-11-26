-- Kabal Chemist until the hotfix of 2017-01-24 (version 16214): a random Potion, never Dragonfire Potion (CFM_662).
local cards = {}

local POTIONS = { "CFM_021", "CFM_065", "CFM_620", "CFM_603", "CFM_604", "CFM_661", "CFM_094", "CFM_608", "CFM_611" }
cards.CFM_619 = {
  battlecry = function(g, me)
    g.add_to_hand(g.ctrl(me), g.pick(POTIONS))
  end,
}

return cards
