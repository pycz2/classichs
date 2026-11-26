-- Big Bad Voodoo from patch 13.4.0.29349: "if its effect triggers on a minion that doesn't have any valid minions to
-- evolve into, it will now summon a random minion of equal cost" (trl_b.lua's summons nothing then).
local cards = {}

local function random_minion(g, cost)
  return g.pick(list.filter(g.collectible(), function(c)
    local i = g.info(c)
    return i.type == "MINION" and i.cost == cost
  end))
end

cards["ench:trl_voodoo"] = {
  deathrattle = function(g, me)
    local pos = g.died_pos(me)
    local cost = g.info(g.card(me)).cost
    local c = random_minion(g, cost + 1) or random_minion(g, cost)
    if c then
      g.summon(g.ctrl(me), c, pos >= 0 and pos or nil)
    end
  end,
}

return cards
