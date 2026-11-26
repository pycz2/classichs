-- Undertaker (patch 2.1.0.7628, 2015-01-29): whenever you summon a minion with Deathrattle, +1 Attack (was +1/+1).
local cards = {}

cards.FP1_028 = {
  on = {
    summon = function(g, me, ev)
      if not g.mine(me, ev) or ev.entity == me then
        return
      end
      for _, k in ipairs(g.info(ev.card).keywords) do
        if k == "DEATHRATTLE" then
          g.buff(me, 1, 0)
          return
        end
      end
    end,
  },
}

return cards
