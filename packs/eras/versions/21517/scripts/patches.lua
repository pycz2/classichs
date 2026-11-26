-- Version 9.2.0.21517 (2017-10-17) on the Knights of the Frozen Throne pack: the cards that work differently since
-- the release (packs/loot/scripts/loot.lua has them as Kobolds & Catacombs found them): 9.1.0.20970's Innervate and
-- Murloc Warleader, 9.2's Unlicensed Apothecary and the four cards whose own discount comes after every other cost
-- change. Spreading Plague, Fiery War Axe and Hex only cost more, Counterspell and Wild Pyromancer are rules.json
-- behaviour flags (patch.json).
local cards = {}

-- Innervate (patch 9.1.0.20970): "Gain 1 Mana Crystal this turn only."
cards.VAN_EX1_169 = {
  spell = function(g, me)
    g.add_mana(g.ctrl(me), 1)
  end,
}

-- Murloc Warleader (patch 9.1.0.20970): "Your other Murlocs have +2 Attack."
cards.VAN_EX1_507 = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "MURLOC" then
        g.aura_add(m, 2, 0)
      end
    end
  end,
}

-- Unlicensed Apothecary (patch 9.2.0.21517): "After you summon a minion, deal 5 damage to your hero" (after its
-- Battlecry).
cards.CFM_900 = {
  on = {
    after_summon = function(g, me, ev)
      if g.mine(me, ev) and ev.entity ~= me then
        g.damage(me, g.hero(g.ctrl(me)), 5)
      end
    end,
  },
}

-- Their own cost change after every other one (cost_last; patch 9.2.0.21517: Dragon's Breath, Solemn Vigil, Everyfin
-- is Awesome, Obsidian Shard): Naga Sea Witch's (5), then theirs.
local function died_this_turn(g)
  local n = 0
  for p = 0, 1 do
    for _, e in ipairs(g.graveyard(p)) do
      if g.died_pos(e) >= 0 and g.tag(e, "DIED_TURN") == g.turn() then
        n = n + 1
      end
    end
  end
  return n
end
local function vigil_cost(g, me)
  return -died_this_turn(g)
end
cards.BRM_003 = { -- Dragon's Breath
  target = "any",
  cost_last = true,
  cost_mod = vigil_cost,
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
  end,
}
cards.BRM_001 = { -- Solemn Vigil
  cost_last = true,
  cost_mod = vigil_cost,
  spell = function(g, me)
    g.draw(g.ctrl(me), 2)
  end,
}
cards.LOE_113 = { -- Everyfin is Awesome
  cost_last = true,
  cost_mod = function(g, me)
    return -list.count(g.minions(g.ctrl(me)), function(m)
      return g.race(m) == "MURLOC"
    end)
  end,
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.buff(m, 2, 2)
    end
  end,
}
cards.UNG_061 = { -- Obsidian Shard
  cost_last = true,
  cost_mod = function(g, me)
    return -g.count(g.ctrl(me), "OTHER_CLASS")
  end,
}

return cards
