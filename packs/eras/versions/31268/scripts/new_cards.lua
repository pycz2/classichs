-- Patch 14.4.0.31268 (2019-05-16): SN1P-SN4P, a Boomsday card given early (hearthstone.wiki.gg, SN1P-SN4P).
local cards = {}

-- SN1P-SN4P: Magnetic, Echo (data); Deathrattle: two 1/1 Microbots.
cards.BOT_700 = {
  deathrattle = function(g, me)
    local pos = g.died_pos(me)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), "BOT_312t", pos >= 0 and pos or nil)
    end
  end,
}

return cards
