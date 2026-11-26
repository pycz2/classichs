-- Patch 14.4.0.31268 (2019-06-03, Rise of the Mech): Reckless Experimenter can't make a cost less than (1) (the
-- SN1P-SN4P fix). Each later version of the era keeps it (a copy of this file).
local cards = {}

local function has_kw(i, k)
  return list.any(i.keywords, function(x)
    return x == k
  end)
end

-- Reckless Experimenter: Deathrattle minions in your hand cost (3) less, not below (1) (one that costs less already
-- keeps its cost); those you play die at the end of the turn (the base pack's `ench:boom_reckless`).
cards.BOT_566 = {
  cost_aura = function(g, me, card, cost)
    if g.zone(card) == "HAND" and g.ctrl(card) == g.ctrl(me) and g.type(card) == "MINION"
        and has_kw(g.info(g.card(card)), "DEATHRATTLE") and cost > 1 then
      return math.max(1, cost - 3)
    end
    return cost
  end,
  on = {
    play = function(g, me, ev)
      if g.mine(me, ev) and ev.kind == "minion" and has_kw(g.info(g.card(ev.entity)), "DEATHRATTLE") then
        g.enchant(ev.entity, { hooks = "ench:boom_reckless", player = g.ctrl(me) })
      end
    end,
  },
}

return cards
