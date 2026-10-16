-- Shaman cards and their tokens (was rust/engine/src/cards/shaman.rs). Overload
-- comes from card data; Totemic Call and Healing Totem are in heroes.lua.
local cards = {}

-- n spell damage to two random enemy minions (Forked Lightning).
local function two_random_enemies(g, me, n)
  local pool = g.shuffle(g.minions(g.enemy(me)))
  for i = 1, math.min(2, #pool) do
    g.damage(me, pool[i], g.spell_dmg(me, n))
  end
end

-- Ancestral Healing: restore a minion to full Health and give it Taunt.
cards.VAN_CS2_041 = {
  target = "minion",
  spell = function(g, me, t)
    g.heal(me, t, g.dmg(t))
    g.give_tag(t, "TAUNT")
  end,
}

-- Totemic Might: your Totems get +2 Health.
cards.VAN_EX1_244 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if g.race(m) == "TOTEM" then
        g.buff(m, 0, 2)
      end
    end
  end,
}

-- Earth Shock: silence a minion, then 1 damage.
cards.VAN_EX1_245 = {
  target = "minion",
  spell = function(g, me, t)
    g.silence(t)
    g.damage(me, t, g.spell_dmg(me, 1))
  end,
}

-- Forked Lightning: 2 damage to two random enemy minions.
cards.VAN_EX1_251 = {
  can_play = function(g, me)
    return #g.minions(g.enemy(me)) >= 2
  end,
  spell = function(g, me)
    two_random_enemies(g, me, 2)
  end,
}

-- Frost Shock: 1 damage to an enemy character and freeze it.
cards.VAN_CS2_037 = {
  target = "enemy_char",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 1))
    g.freeze(t)
  end,
}

cards.VAN_EX1_238 = lib.hit("any", 3, true) -- Lightning Bolt

-- Rockbiter Weapon: a friendly character gets +3 Attack this turn.
cards.VAN_CS2_045 = {
  target = "friendly_char",
  spell = function(g, me, t)
    g.buff(t, 3, 0, true)
  end,
}

-- Ancestral Spirit: "Deathrattle: resummon this minion."
cards.VAN_CS2_038 = {
  target = "minion",
  spell = function(g, me, t)
    g.enchant(t, { hooks = "ench:ancestral_spirit" })
  end,
}

cards["ench:ancestral_spirit"] = {
  deathrattle = function(g, me)
    g.summon(g.ctrl(me), g.card(me), g.died_pos(me))
  end,
}

-- Flametongue Totem: adjacent minions have +2 Attack.
cards.VAN_EX1_565 = {
  aura = function(g, me)
    for _, m in ipairs(g.adjacent(me)) do
      g.aura_add(m, 2, 0)
    end
  end,
}

-- Windfury
cards.VAN_CS2_039 = {
  target = "minion",
  spell = function(g, me, t)
    g.give_tag(t, "WINDFURY")
  end,
}

-- Far Sight: draw a card; it costs (3) less.
cards.VAN_CS2_053 = {
  spell = function(g, me)
    for _, e in ipairs(g.draw(g.ctrl(me), 1)) do
      g.enchant(e, { cost = -3 })
    end
  end,
}

-- Feral Spirit: two 2/3 Spirit Wolves with Taunt.
cards.VAN_EX1_248 = {
  spell = function(g, me)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), "VAN_EX1_tk11")
    end
  end,
}

-- Hex: transform a minion into a 0/1 Frog with Taunt.
cards.VAN_EX1_246 = {
  target = "minion",
  spell = function(g, me, t)
    g.transform(t, "hexfrog")
  end,
}

cards.VAN_EX1_241 = lib.hit("any", 5, true) -- Lava Burst

-- Lightning Storm: 2-3 damage to all enemy minions, rolled per minion.
cards.VAN_EX1_259 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      local n = g.random(2, 3)
      g.damage(me, m, g.spell_dmg(me, n))
    end
  end,
}

-- Mana Tide Totem: at the end of your turn, draw a card.
cards.VAN_EX1_575 = {
  on = {
    turn_end = function(g, me, ev)
      if g.mine(me, ev) then
        g.draw(g.ctrl(me), 1)
      end
    end,
  },
}

-- Unbound Elemental: whenever you play a card with Overload, gain +1/+1.
cards.VAN_EX1_258 = {
  on = {
    play = function(g, me, ev)
      if g.mine(me, ev) and ev.entity ~= me and g.info(ev.card).mana_lock > 0 then
        g.buff(me, 1, 1)
      end
    end,
  },
}

-- Windspeaker: give another friendly minion Windfury.
cards.VAN_EX1_587 = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t)
      return t ~= me
    end,
  },
  battlecry = function(g, me, t)
    g.give_tag(t, "WINDFURY")
  end,
}

-- Bloodlust: your minions get +3 Attack this turn.
cards.VAN_CS2_046 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.buff(m, 3, 0, true)
    end
  end,
}

cards.VAN_CS2_042 = lib.hit("any", 3) -- Fire Elemental

return cards
