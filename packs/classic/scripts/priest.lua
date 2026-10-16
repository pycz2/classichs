-- Priest cards, their tokens and enchantments (was rust/engine/src/cards/priest.rs).
local cards = {}

local function destroy(g, me, t)
  g.destroy(t)
end

-- A target: a minion of `base` whose Attack passes ok(atk).
local function by_atk(base, ok)
  return {
    base = base,
    filter = function(g, me, t)
      return ok(g.atk(t))
    end,
  }
end

-- Circle of Healing: restore 4 Health to ALL minions.
cards.VAN_EX1_621 = {
  spell = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      g.heal(me, m, g.heal_amt(me, 4))
    end
  end,
}

-- Silence
cards.VAN_EX1_332 = {
  target = "minion",
  spell = function(g, me, t)
    g.silence(t)
  end,
}

cards.VAN_CS1_130 = lib.hit("any", 2, true) -- Holy Smite

-- Inner Fire: a minion's Attack becomes its Health.
cards.VAN_CS1_129 = {
  target = "minion",
  spell = function(g, me, t)
    g.set_stats(t, g.health(t), nil)
  end,
}

-- Mind Vision: a copy of a random card in the opponent's hand.
cards.VAN_CS2_003 = {
  spell = function(g, me)
    local e = g.pick(g.hand(g.enemy(me)))
    if e then
      g.add_to_hand(g.ctrl(me), g.card(e))
    end
  end,
}

-- Northshire Cleric: whenever a minion is healed, draw a card.
cards.VAN_CS2_235 = {
  on = {
    heal = function(g, me, ev)
      if g.is_minion(ev.target) then
        g.draw(g.ctrl(me), 1)
      end
    end,
  },
}

-- Power Word: Shield: +2 Health, draw a card.
cards.VAN_CS2_004 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 0, 2)
    g.draw(g.ctrl(me), 1)
  end,
}

-- Divine Spirit: double a minion's Health.
cards.VAN_CS2_236 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 0, g.health(t))
  end,
}

-- Lightwell: at the start of your turn, restore 3 Health to a damaged friendly character.
cards.VAN_EX1_341 = {
  on = {
    turn_start = function(g, me, ev)
      if g.mine(me, ev) then
        local hurt = {}
        for _, c in ipairs(g.chars(g.ctrl(me))) do
          if g.dmg(c) > 0 and g.health(c) > 0 then
            table.insert(hurt, c)
          end
        end
        local t = g.pick(hurt)
        if t then
          g.heal(me, t, g.heal_amt(me, 3))
        end
      end
    end,
  },
}

-- Mind Blast: 5 damage to the enemy hero.
cards.VAN_DS1_233 = {
  spell = function(g, me)
    g.damage(me, g.hero(g.enemy(me)), g.spell_dmg(me, 5))
  end,
}

-- Shadow Word: Pain: destroy a minion with 3 or less Attack.
cards.VAN_CS2_234 = {
  target = by_atk("minion", function(a)
    return a <= 3
  end),
  spell = destroy,
}

-- Shadow Word: Death: destroy a minion with 5 or more Attack.
cards.VAN_EX1_622 = {
  target = by_atk("minion", function(a)
    return a >= 5
  end),
  spell = destroy,
}

-- Shadowform: the power becomes Mind Spike, then Mind Shatter. The new power is unused.
cards.VAN_EX1_625 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local cur = g.card(g.power(p))
    g.set_power(p, string.sub(cur, 1, 8) == "EX1_625t" and "EX1_625t2" or "EX1_625t")
  end,
}

-- Thoughtsteal: copies of 2 random cards in the opponent's deck.
cards.VAN_EX1_339 = {
  spell = function(g, me)
    local deck = g.shuffle(g.deck(g.enemy(me)))
    for i = 1, math.min(2, #deck) do
      g.add_to_hand(g.ctrl(me), g.card(deck[i]))
    end
  end,
}

-- Auchenai Soulpriest: your healing deals damage instead.
cards.VAN_EX1_591 = {
  aura = function(g, me)
    g.aura_add(g.hero(g.ctrl(me)), 0, 0, { HEAL_IS_DAMAGE = true })
  end,
}

-- Lightspawn: Attack always equals Health (after every other aura).
cards.VAN_EX1_335 = {
  aura_final = function(g, me)
    g.aura_add(me, g.health(me) - g.atk(me), 0)
  end,
}

-- Mass Dispel: silence all enemy minions, draw a card.
cards.VAN_EX1_626 = {
  spell = function(g, me)
    lib.each_enemy_minion(g, me, nil, g.silence)
    g.draw(g.ctrl(me), 1)
  end,
}

-- Mindgames: a copy of a random minion from the opponent's deck (none: a 0/1 Shadow of Nothing).
cards.VAN_EX1_345 = {
  spell = function(g, me)
    local pool = {}
    for _, e in ipairs(g.deck(g.enemy(me))) do
      if g.is_minion(e) then
        table.insert(pool, e)
      end
    end
    local e = g.pick(pool)
    g.summon(g.ctrl(me), e and g.card(e) or "VAN_EX1_345t")
  end,
}

-- Shadow Madness: control an enemy minion with 3 or less Attack until end of turn; it can attack.
cards.VAN_EX1_334 = {
  target = by_atk("enemy_minion", function(a)
    return a <= 3
  end),
  can_play = lib.room,
  spell = function(g, me, t)
    local owner = g.ctrl(t)
    g.take_control(t, g.ctrl(me))
    g.erase_tag(t, "EXHAUSTED")
    g.enchant(t, { hooks = "ench:shadow_madness", player = owner })
  end,
}

cards["ench:shadow_madness"] = {
  on = {
    turn_end = function(g, me)
      for _, p in ipairs(g.enchants(me, "ench:shadow_madness")) do
        g.remove_enchant(me, "ench:shadow_madness", p)
        g.take_control(me, p)
      end
    end,
  },
}

-- Holy Nova: 2 damage to all enemies, restore 2 Health to all friendly characters.
cards.VAN_CS1_112 = {
  spell = function(g, me)
    for _, c in ipairs(g.chars(g.enemy(me))) do
      g.damage(me, c, g.spell_dmg(me, 2))
    end
    for _, c in ipairs(g.chars(g.ctrl(me))) do
      g.heal(me, c, g.heal_amt(me, 2))
    end
  end,
}

-- Cabal Shadow Priest: take control of an enemy minion with 2 or less Attack.
cards.VAN_EX1_091 = {
  target = by_atk("enemy_minion", function(a)
    return a <= 2
  end),
  battlecry = function(g, me, t)
    g.take_control(t, g.ctrl(me))
  end,
}

-- Holy Fire: 5 damage, restore 5 Health to your hero.
cards.VAN_EX1_624 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 5))
    g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 5))
  end,
}

-- Temple Enforcer: another friendly minion gets +3 Health.
cards.VAN_EX1_623 = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t)
      return t ~= me
    end,
  },
  battlecry = function(g, me, t)
    g.buff(t, 0, 3)
  end,
}

-- Prophet Velen: double the damage and healing of your spells and powers.
cards.VAN_EX1_350 = {
  aura = function(g, me)
    g.aura_add(g.hero(g.ctrl(me)), 0, 0, { DOUBLE_HEAL_DAMAGE = 1 })
  end,
}

-- Mind Control: take control of an enemy minion.
cards.VAN_CS1_113 = {
  target = "enemy_minion",
  can_play = lib.room,
  spell = function(g, me, t)
    g.take_control(t, g.ctrl(me))
  end,
}

return cards
