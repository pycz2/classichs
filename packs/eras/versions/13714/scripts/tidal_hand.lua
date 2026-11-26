-- The Tidal Hand, Vilefin Inquisitor's Hero Power (patch 5.2.0.13619, 2016-07-12): it needs a free board slot.
local cards = {}

cards.OG_006b = {
  can_play = lib.room,
  hero_power = function(g, me)
    g.summon(g.ctrl(me), "OG_006a")
  end,
}

return cards
