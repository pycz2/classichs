-- The tutorial missions' hooks (missions/<n>.json `script`).
local cards = {}

-- Missions 1 and 2: the player's champion can't drop below 1 Health.
cards["ench:tutorial_guard"] = {
  now = {
    predamage = function(g, me, ev)
      if ev.target == me then
        ev.amount = math.min(ev.amount, math.max(0, g.health(me) - 1 + g.tag(me, "ARMOR")))
      end
    end,
  },
}

return cards
