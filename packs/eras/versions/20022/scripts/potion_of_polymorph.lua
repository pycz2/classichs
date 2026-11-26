-- Potion of Polymorph from patch 7.1.0.17720: the After Summon triggers after it see the Sheep (Snipe hits it); until
-- then they still looked at the minion it had transformed.
local cards = {}

cards.CFM_620 = {
  secret = {
    event = "after_summon",
    cond = function(g, me, ev)
      return ev.played and ev.player ~= g.ctrl(me) and g.zone(ev.entity) == "PLAY" and g.health(ev.entity) > 0
        and not g.has(ev.entity, "TO_DESTROY")
    end,
    effect = function(g, me, ev)
      ev.entity = g.transform(ev.entity, "VAN_CS2_tk1")
    end,
  },
}

return cards
