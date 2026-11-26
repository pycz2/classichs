-- Patch 6.1.3.14830 (2016-10-03): the cards that work differently from the kara pack's (packs/msg/scripts/msg.lua has
-- them as of December 2016). Their costs and texts: patch.json.
local cards = {}

local BASIC_TOTEMS = { "VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009" }

-- The collectible cards whose data pass ok.
local function pool(g, ok)
  return list.filter(g.collectible(), function(c)
    return ok(g.info(c))
  end)
end

-- Charge: give a friendly minion Charge; it can't attack heroes this turn (no +2 Attack any more).
cards.VAN_CS2_103 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.give_tag(t, "CHARGE")
    g.give_tag(t, "CANNOT_ATTACK_HEROES", true)
  end,
}

-- Tuskarr Totemic: a random basic Totem (one you have may come again).
cards.AT_046 = {
  battlecry = function(g, me)
    g.summon_right(me, g.pick(BASIC_TOTEMS))
  end,
}

-- Yogg-Saron, Hope's End: a random spell for each spell you cast this game (at most 30), random targets and choices;
-- it stops once Yogg-Saron is destroyed, transformed or returned to the hand. A Silence did not stop it yet, and the
-- spells' Overload went nowhere (both fixed in patch 6.2).
local function yogg_on(g, me)
  return g.zone(me) == "PLAY" and g.health(me) > 0 and not g.has(me, "TO_DESTROY")
end
cards.OG_134 = {
  battlecry = function(g, me)
    local spells = pool(g, function(i)
      return i.type == "SPELL"
    end)
    for _ = 1, math.min(g.count(g.ctrl(me), "SPELLS"), 30) do
      if not yogg_on(g, me) then
        break
      end
      local s = g.pick(spells)
      if s then
        g.cast_random(me, s)
        g.resolve()
      end
    end
  end,
}

return cards
