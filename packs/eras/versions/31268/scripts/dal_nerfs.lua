-- Patch 14.2.2.31022 (2019-05-22): Preparation (3) -> (2) (the value is the script's; only the text shows it in the
-- data). Each later version of the era keeps it (a copy of this file).
local cards = {}

-- Preparation: the next spell you cast this turn costs (2) less.
cards.VAN_EX1_145 = {
  spell = function(g, me)
    g.add_cost_mod(g.ctrl(me), { kind = "spell", delta = -2, ["until"] = "use" })
  end,
}

return cards
