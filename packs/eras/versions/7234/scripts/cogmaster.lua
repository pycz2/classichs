-- Cogmaster before patch 2.2.0.7835 (2015-02-25): once its Attack and Health had been swapped (Crazed Alchemist),
-- a Mech no longer raised its Attack. Crazed Alchemist marks the minion it swaps; Cogmaster's aura skips a marked one.
local cards = {}

-- Crazed Alchemist: swap a minion's Attack and Health.
cards.VAN_EX1_059 = {
  target = "minion",
  battlecry = function(g, me, t)
    g.set_stats(t, g.health(t), g.atk(t))
    g.set_tag(t, "GVG_STATS_SWAPPED", true)
  end,
}

-- Another Mech on me's side.
local function have_mech(g, me)
  for _, m in ipairs(g.minions(g.ctrl(me))) do
    if m ~= me and g.race(m) == "MECHANICAL" then
      return true
    end
  end
  return false
end

-- Cogmaster: +2 Attack while you have a Mech, unless its Attack and Health were swapped.
cards.GVG_013 = {
  aura = function(g, me)
    if g.tag(me, "GVG_STATS_SWAPPED") == 0 and have_mech(g, me) then
      g.aura_add(me, 2, 0)
    end
  end,
}

return cards
