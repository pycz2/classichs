-- Paladin cards and their tokens (was rust/engine/src/cards/paladin.rs).
local cards = {}

-- A spell on a minion: gives it +atk/+hp.
local function bless(atk, hp)
  return {
    target = "minion",
    spell = function(g, me, t)
      g.buff(t, atk, hp)
    end,
  }
end

cards.VAN_CS2_087 = bless(3, 0) -- Blessing of Might
cards.VAN_CS2_092 = bless(4, 4) -- Blessing of Kings

-- Blessing of Wisdom: whenever the minion attacks, the caster draws a card.
cards.VAN_EX1_363 = {
  target = "minion",
  spell = function(g, me, t)
    g.enchant(t, { hooks = "ench:blessing_of_wisdom", player = g.ctrl(me) })
  end,
}

cards["ench:blessing_of_wisdom"] = {
  on = {
    attack = function(g, me, ev)
      if ev.attacker == me then
        for _, p in ipairs(g.enchants(me, "ench:blessing_of_wisdom")) do
          g.draw(p, 1)
        end
      end
    end,
  },
}

-- Eye for an Eye: when your hero takes damage, deal that much to the enemy hero.
cards.VAN_EX1_132 = {
  secret = {
    event = "damage",
    cond = function(g, me, ev)
      return ev.target == g.hero(g.ctrl(me))
    end,
    effect = function(g, me, ev)
      g.damage(me, g.hero(g.enemy(me)), ev.amount)
    end,
  },
}

-- Hand of Protection: Divine Shield.
cards.VAN_EX1_371 = {
  target = "minion",
  spell = function(g, me, t)
    g.give_tag(t, "DIVINE_SHIELD")
  end,
}

-- Humility: Attack becomes 1.
cards.VAN_EX1_360 = {
  target = "minion",
  spell = function(g, me, t)
    g.set_stats(t, 1, nil)
  end,
}

-- Noble Sacrifice: when an enemy attacks, summon a 2/1 defender as the new target.
cards.VAN_EX1_130 = {
  secret = {
    event = "attack",
    cond = function(g, me, ev)
      return not g.mine(me, ev) and lib.room(g, me)
    end,
    effect = function(g, me, ev)
      local n = g.summon(g.ctrl(me), "VAN_EX1_130a")
      if n then
        ev.defender = n
      end
    end,
  },
}

-- Redemption: when a friendly minion dies, return it to life with 1 Health.
cards.VAN_EX1_136 = {
  secret = {
    event = "death",
    cond = function(g, me, ev)
      return ev.minion and g.mine(me, ev)
    end,
    effect = function(g, me, ev)
      local n = g.summon(g.ctrl(me), ev.card, g.died_pos(ev.entity))
      if n then
        g.set_damage(n, g.max_health(n) - 1)
      end
    end,
  },
}

-- Repentance: when the opponent plays a minion, its Health becomes 1.
cards.VAN_EX1_379 = {
  secret = {
    event = "after_summon",
    cond = function(g, me, ev)
      return ev.played and not g.mine(me, ev)
    end,
    effect = function(g, me, ev)
      g.set_stats(ev.entity, nil, 1)
    end,
  },
}

-- Argent Protector: give another friendly minion Divine Shield.
cards.VAN_EX1_362 = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t)
      return t ~= me
    end,
  },
  battlecry = function(g, me, t)
    g.give_tag(t, "DIVINE_SHIELD")
  end,
}

-- Equality: change the Health of ALL minions to 1.
cards.VAN_EX1_619 = {
  spell = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      g.set_stats(m, nil, 1)
    end
  end,
}

-- Holy Light: restore 6 Health.
cards.VAN_CS2_089 = {
  target = "any",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 6))
  end,
}

-- Aldor Peacekeeper: an enemy minion's Attack becomes 1.
cards.VAN_EX1_382 = {
  target = "enemy_minion",
  battlecry = function(g, me, t)
    g.set_stats(t, 1, nil)
  end,
}

-- Divine Favor: draw until you have as many cards as your opponent.
cards.VAN_EX1_349 = {
  spell = function(g, me)
    local n = #g.hand(g.enemy(me)) - #g.hand(g.ctrl(me))
    if n > 0 then
      g.draw(g.ctrl(me), n)
    end
  end,
}

-- Sword of Justice: after you summon a minion, give it +1/+1 and lose 1 Durability.
cards.VAN_EX1_366 = {
  on = {
    after_summon = function(g, me, ev)
      if g.mine(me, ev) then
        g.buff(ev.entity, 1, 1)
        g.add_tag(me, "DURABILITY", -1)
      end
    end,
  },
}

-- Consecration: 2 damage to all enemies.
cards.VAN_CS2_093 = {
  spell = function(g, me)
    for _, c in ipairs(g.chars(g.enemy(me))) do
      g.damage(me, c, g.spell_dmg(me, 2))
    end
  end,
}

-- Hammer of Wrath: 3 damage, draw a card.
cards.VAN_CS2_094 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 3))
    g.draw(g.ctrl(me), 1)
  end,
}

-- Truesilver Champion: whenever your hero attacks, restore 2 Health to it.
cards.VAN_CS2_097 = {
  on = {
    attack = function(g, me, ev)
      local hero = g.hero(g.ctrl(me))
      if ev.attacker == hero then
        g.heal(me, hero, g.heal_amt(me, 2))
      end
    end,
  },
}

-- Blessed Champion: double a minion's Attack.
cards.VAN_EX1_355 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, g.atk(t), 0)
  end,
}

-- Holy Wrath: draw a card and deal damage equal to its cost.
cards.VAN_EX1_365 = {
  target = "any",
  spell = function(g, me, t)
    local c = g.draw(g.ctrl(me), 1)[1]
    if c then
      g.damage(me, t, g.spell_dmg(me, g.cost(c)))
    end
  end,
}

-- Avenging Wrath: 8 missiles of 1 damage at random enemies; spell power adds missiles.
cards.VAN_EX1_384 = {
  spell = function(g, me)
    for _ = 1, g.spell_dmg(me, 8) do
      g.damage(me, g.random_alive(g.chars(g.enemy(me))), 1)
    end
  end,
}

-- Guardian of Kings: restore 6 Health to your hero.
cards.VAN_CS2_088 = {
  battlecry = function(g, me)
    g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 6))
  end,
}

-- Lay on Hands: restore 8 Health, draw 3 cards.
cards.VAN_EX1_354 = {
  target = "any",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 8))
    g.draw(g.ctrl(me), 3)
  end,
}

-- Tirion Fordring: Deathrattle: equip Ashbringer.
cards.VAN_EX1_383 = {
  deathrattle = function(g, me)
    g.equip(g.ctrl(me), "EX1_383t")
  end,
}

return cards
