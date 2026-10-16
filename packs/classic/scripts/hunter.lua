-- Hunter cards and their tokens (was rust/engine/src/cards/hunter.rs).
local cards = {}

local function is_beast(g, me, t)
  return g.race(t) == "BEAST"
end

local function has_enemy_minions(g, me)
  return #g.minions(g.enemy(me)) > 0
end

-- Hunter's Mark: change a minion's Health to 1.
cards.VAN_CS2_084 = {
  target = "minion",
  spell = function(g, me, t)
    g.set_stats(t, nil, 1)
  end,
}

cards.VAN_DS1_185 = lib.hit("any", 2, true) -- Arcane Shot

-- Bestial Wrath: a Beast gets +2 Attack and Immune this turn (2014: any Beast).
cards.VAN_EX1_549 = {
  target = { base = "minion", filter = is_beast },
  spell = function(g, me, t)
    g.buff(t, 2, 0, true)
    g.give_tag(t, "IMMUNE", true)
  end,
}

-- Flare: all minions lose Stealth, destroy the enemy Secrets, draw a card.
cards.VAN_EX1_544 = {
  spell = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      g.erase_tag(m, "STEALTH")
    end
    for _, s in ipairs(g.traps(g.enemy(me))) do
      g.remove(s, "GRAVEYARD")
      g.log({ type = "destroy", target = s })
    end
    g.draw(g.ctrl(me), 1)
  end,
}

-- Timber Wolf: your other Beasts have +1 Attack.
cards.VAN_DS1_175 = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "BEAST" then
        g.aura_add(m, 1, 0)
      end
    end
  end,
}

-- Tracking: look at the top three cards of your deck, draw one, discard the others.
cards.VAN_DS1_184 = {
  spell = function(g, me)
    local deck = g.deck(g.ctrl(me))
    local opts = {}
    for i = math.max(1, #deck - 2), #deck do
      table.insert(opts, deck[i])
    end
    g.request_choice(me, opts)
  end,
  on_choose = function(g, me, opt, still)
    local p = g.ctrl(me)
    g.draw_entity(p, opt)
    for _, e in ipairs(still) do
      if e ~= opt then
        g.remove(e, "GRAVEYARD")
        g.log({ type = "discard", player = p, entity = e, card = g.card(e) })
      end
    end
  end,
}

-- Explosive Trap: when your hero is attacked, 2 damage to all enemies.
cards.VAN_EX1_610 = {
  secret = {
    event = "attack",
    cond = lib.attacks_my_hero,
    effect = function(g, me)
      for _, c in ipairs(g.chars(g.enemy(me))) do
        g.damage(me, c, g.spell_dmg(me, 2))
      end
    end,
  },
}

-- Freezing Trap: when an enemy minion attacks, return it to the hand; it costs (2) more.
cards.VAN_EX1_611 = {
  secret = {
    event = "attack",
    cond = function(g, me, ev)
      return g.is_minion(ev.attacker) and not g.mine(me, ev)
    end,
    effect = function(g, me, ev)
      local n = g.return_to_hand(ev.attacker)
      if n then
        g.enchant(n, { cost = 2 })
      end
    end,
  },
}

-- Misdirection: when your hero is attacked, the attacker hits another random character.
cards.VAN_EX1_533 = {
  secret = {
    event = "attack",
    cond = lib.attacks_my_hero,
    effect = function(g, me, ev)
      local my_hero = g.hero(g.ctrl(me))
      local pool = {}
      for _, c in ipairs(g.all_chars()) do
        if c ~= ev.attacker and c ~= my_hero then
          table.insert(pool, c)
        end
      end
      local t = g.random_alive(pool)
      if t then
        ev.defender = t
      end
    end,
  },
}

-- Scavenging Hyena: whenever a friendly Beast dies, gain +2/+1.
cards.VAN_EX1_531 = {
  on = {
    death = function(g, me, ev)
      if ev.minion and g.mine(me, ev) and g.info(ev.card).race == "BEAST" then
        g.buff(me, 2, 1)
      end
    end,
  },
}

-- Snake Trap: when one of your minions is attacked, summon three 1/1 Snakes.
cards.VAN_EX1_554 = {
  secret = {
    event = "attack",
    cond = function(g, me, ev)
      local d = ev.defender
      return g.is_minion(d) and g.ctrl(d) == g.ctrl(me) and lib.room(g, me)
    end,
    effect = function(g, me)
      for _ = 1, 3 do
        g.summon(g.ctrl(me), "VAN_EX1_554t")
      end
    end,
  },
}

-- Snipe: when your opponent plays a minion, 4 damage to it.
cards.VAN_EX1_609 = {
  secret = {
    event = "after_summon",
    cond = function(g, me, ev)
      return ev.played and not g.mine(me, ev)
    end,
    effect = function(g, me, ev)
      g.damage(me, ev.entity, g.spell_dmg(me, 4))
    end,
  },
}

-- Starving Buzzard: whenever you summon a Beast, draw a card.
cards.VAN_CS2_237 = {
  on = {
    summon = function(g, me, ev)
      local e = ev.entity
      if g.mine(me, ev) and e ~= me and g.race(e) == "BEAST" then
        g.draw(g.ctrl(me), 1)
      end
    end,
  },
}

-- Animal Companion: summon a random Beast Companion.
cards.VAN_NEW1_031 = {
  spell = function(g, me)
    g.summon(g.ctrl(me), g.pick({ "VAN_NEW1_032", "VAN_NEW1_033", "VAN_NEW1_034" }))
  end,
}

cards.VAN_NEW1_033 = lib.others_aura(1, 0) -- Leokk

-- Deadly Shot: destroy a random enemy minion.
cards.VAN_EX1_617 = {
  can_play = has_enemy_minions,
  spell = function(g, me)
    g.destroy(g.random_alive(g.minions(g.enemy(me))))
  end,
}

-- Eaglehorn Bow: whenever a friendly Secret is revealed, gain +1 Durability.
cards.VAN_EX1_536 = {
  on = {
    secret_revealed = function(g, me, ev)
      if g.mine(me, ev) then
        g.add_tag(me, "DURABILITY", 1)
      end
    end,
  },
}

-- Kill Command: 3 damage; 5 if you have a Beast.
cards.VAN_EX1_539 = {
  target = "any",
  spell = function(g, me, t)
    local n = 3
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if g.race(m) == "BEAST" then
        n = 5
      end
    end
    g.damage(me, t, g.spell_dmg(me, n))
  end,
}

-- Unleash the Hounds: a 1/1 Hound with Charge for each enemy minion.
cards.VAN_EX1_538 = {
  can_play = has_enemy_minions,
  spell = function(g, me)
    for _ = 1, #g.minions(g.enemy(me)) do
      g.summon(g.ctrl(me), "EX1_538t")
    end
  end,
}

-- Houndmaster: a friendly Beast gets +2/+2 and Taunt.
cards.VAN_DS1_070 = {
  target = { base = "friendly_minion", filter = is_beast },
  battlecry = function(g, me, t)
    g.buff(t, 2, 2)
    g.give_tag(t, "TAUNT")
  end,
}

-- Multi-Shot: 3 damage to two random enemy minions (2014: needs two, as Fireplace).
cards.VAN_DS1_183 = {
  can_play = function(g, me)
    return #g.minions(g.enemy(me)) >= 2
  end,
  spell = function(g, me)
    local pool = g.shuffle(g.minions(g.enemy(me)))
    for i = 1, math.min(2, #pool) do
      g.damage(me, pool[i], g.spell_dmg(me, 3))
    end
  end,
}

-- Explosive Shot: 5 damage to a minion and 2 to its neighbours.
cards.VAN_EX1_537 = {
  target = "minion",
  spell = function(g, me, t)
    local near = g.adjacent(t)
    g.damage(me, t, g.spell_dmg(me, 5))
    for _, m in ipairs(near) do
      g.damage(me, m, g.spell_dmg(me, 2))
    end
  end,
}

-- Tundra Rhino: your Beasts have Charge.
cards.VAN_DS1_178 = {
  aura = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if g.race(m) == "BEAST" then
        g.aura_add(m, 0, 0, { CHARGE = true })
      end
    end
  end,
}

-- Savannah Highmane: Deathrattle: summon two 2/2 Hyenas.
cards.VAN_EX1_534 = {
  deathrattle = function(g, me)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), "EX1_534t", g.died_pos(me))
    end
  end,
}

cards.VAN_DS1_188 = { immune_while_attacking = true } -- Gladiator's Longbow

return cards
