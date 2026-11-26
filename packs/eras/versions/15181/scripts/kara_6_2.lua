-- Patches 6.1.3.14830 (2016-10-03) and 6.2.0.15181 (2016-10-20): the cards that work differently from the kara pack's
-- (packs/msg/scripts/msg.lua has them as of December 2016). Their costs and texts: patch.json.
local cards = {}

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local BASIC_TOTEMS = { "VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009" }

local function playable(class)
  return list.any(CLASSES, function(c)
    return c == class
  end)
end

-- The collectible cards whose data pass ok.
local function pool(g, ok)
  return list.filter(g.collectible(), function(c)
    return ok(g.info(c))
  end)
end

-- An `on` hook for an event of me's controller.
local function on_mine(event, f)
  return {
    on = {
      [event] = function(g, me, ev)
        if g.mine(me, ev) then
          f(g, me, ev)
        end
      end,
    },
  }
end

-- --- 6.1.3 ---------------------------------------------------------------------------------------

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
-- it stops once Yogg-Saron is destroyed, Silenced, transformed or returned to the hand, and the spells' Overload is its
-- controller's (6.2: Silenced and Overload).
local function yogg_on(g, me)
  return g.zone(me) == "PLAY" and not g.silenced(me) and g.health(me) > 0 and not g.has(me, "TO_DESTROY")
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
        g.cast_random(me, s, true)
        g.resolve()
      end
    end
  end,
}

-- --- 6.2 -----------------------------------------------------------------------------------------

-- Servant of Yogg-Saron: a random spell of Cost (5) or less, random targets and choices; its Overload is the Servant's
-- controller's (6.2).
cards.OG_087 = {
  battlecry = function(g, me)
    local s = g.pick(pool(g, function(i)
      return i.type == "SPELL" and i.cost <= 5
    end))
    if s then
      g.cast_random(me, s, true)
      g.resolve()
    end
  end,
}

-- Grimscale Oracle: your other Murlocs have +1 Attack (was: all other Murlocs).
cards.VAN_EX1_508 = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "MURLOC" then
        g.aura_add(m, 1, 0)
      end
    end
  end,
}

-- Murloc Warleader: your other Murlocs have +2/+1 (was: all other Murlocs).
cards.VAN_EX1_507 = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "MURLOC" then
        g.aura_add(m, 2, 1)
      end
    end
  end,
}

-- Coldlight Seer: your other Murlocs +2 Health (was: all other Murlocs).
cards.VAN_EX1_103 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "MURLOC" then
        g.buff(m, 0, 2)
      end
    end
  end,
}

-- Murloc Tidecaller: whenever you summon a Murloc, +1 Attack (was: any Murloc summoned).
cards.VAN_EX1_509 = on_mine("summon", function(g, me, ev)
  if ev.entity ~= me and g.race(ev.entity) == "MURLOC" then
    g.buff(me, 1, 0)
  end
end)

-- Ethereal Peddler: the non-Rogue class cards in your hand cost (2) less (was: the cards of a class other than your
-- hero's; neutral cards never).
cards.KAR_070 = {
  battlecry = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      local c = g.class(e)
      if playable(c) and c ~= "ROGUE" then
        g.enchant(e, { cost = -2 })
      end
    end
  end,
}

return cards
