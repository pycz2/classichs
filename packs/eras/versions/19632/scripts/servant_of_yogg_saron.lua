-- Servant of Yogg-Saron from patch 6.2.0.15181: the Overload of the spell it casts is its controller's (the later packs
-- keep og.lua's Servant, whose spells never Overload; versions/15181/scripts/kara_6_2.lua has it for 15181).
local cards = {}

cards.OG_087 = {
  battlecry = function(g, me)
    local s = g.pick(list.filter(g.collectible(), function(c)
      local i = g.info(c)
      return i.type == "SPELL" and i.cost <= 5
    end))
    if s then
      g.cast_random(me, s, true)
      g.resolve()
    end
  end,
}

return cards
