-- Mage cards, their tokens and Fireblast (was rust/engine/src/cards/mage.rs).
local cards = {}

-- Fireblast: 1 damage.
cards.VAN_HERO_08bp = {
  target = "any",
  hero_power = function(g, me, t)
    g.damage(me, t, g.hp_dmg(me, 1))
  end,
}

-- Arcane Missiles: 3 missiles of 1 damage at random enemies; spell power adds missiles.
cards.VAN_EX1_277 = {
  spell = function(g, me)
    for _ = 1, g.spell_dmg(me, 3) do
      g.damage(me, g.random_alive(g.chars(g.enemy(me))), 1)
    end
  end,
}

-- Ice Lance: freeze a character; if it was already Frozen, 4 damage instead.
cards.VAN_CS2_031 = {
  target = "any",
  spell = function(g, me, t)
    if g.has(t, "FROZEN") then
      g.damage(me, t, g.spell_dmg(me, 4))
    else
      g.freeze(t)
    end
  end,
}

-- Mana Wyrm: whenever you cast a spell, gain +1 Attack.
cards.VAN_NEW1_012 = {
  on = {
    play = function(g, me, ev)
      if lib.my_spell(g, me, ev) then
        g.buff(me, 1, 0)
      end
    end,
  },
}

-- Mirror Image: two 0/2 Taunt minions.
cards.VAN_CS2_027 = {
  spell = function(g, me)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), "VAN_CS2_mirror")
    end
  end,
}

-- Arcane Explosion: 1 damage to all enemy minions.
cards.VAN_CS2_025 = {
  spell = function(g, me)
    lib.each_enemy_minion(g, me, 1)
  end,
}

-- Frostbolt: 3 damage and freeze.
cards.VAN_CS2_024 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 3))
    g.freeze(t)
  end,
}

-- Sorcerer's Apprentice: your spells cost (1) less.
cards.VAN_EX1_608 = {
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.is_spell(card) and g.zone(card) == "HAND" then
      return cost - 1
    end
    return cost
  end,
}

-- Arcane Intellect: draw 2 cards.
cards.VAN_CS2_023 = {
  spell = function(g, me)
    g.draw(g.ctrl(me), 2)
  end,
}

-- Counterspell: when your opponent casts a spell, counter it.
cards.VAN_EX1_287 = {
  secret = {
    event = "play",
    cond = lib.enemy_spell,
    effect = function(g, me, ev)
      ev.countered = true
    end,
  },
}

-- Frost Nova: freeze all enemy minions.
cards.VAN_CS2_026 = {
  spell = function(g, me)
    lib.each_enemy_minion(g, me, nil, g.freeze)
  end,
}

-- Ice Barrier: when your hero is attacked, gain 8 Armor.
cards.VAN_EX1_289 = {
  secret = {
    event = "attack",
    cond = lib.attacks_my_hero,
    effect = function(g, me)
      g.gain_armor(g.ctrl(me), 8)
    end,
  },
}

-- Ice Block: when your hero takes fatal damage, prevent it and become Immune this turn.
-- A replacement effect: it runs at once, inside the damage, and may change the amount.
cards.VAN_EX1_295 = {
  now = {
    predamage = function(g, me, ev)
      local hero = g.hero(g.ctrl(me))
      local fatal = ev.amount >= g.health(hero) + g.tag(hero, "ARMOR")
      if g.trap_ready(me) and ev.target == hero and fatal then
        ev.amount = 0
        g.reveal(me)
        g.give_tag(hero, "IMMUNE", true)
      end
    end,
  },
}

-- Kirin Tor Mage: the next Secret you play this turn costs (0).
cards.VAN_EX1_612 = {
  battlecry = function(g, me)
    g.add_cost_mod(g.ctrl(me), { kind = "secret", set = 0, ["until"] = "use" })
  end,
}

-- Mirror Entity: when your opponent plays a minion, summon a copy of it.
cards.VAN_EX1_294 = {
  secret = {
    event = "after_summon",
    cond = function(g, me, ev)
      return ev.played and not g.mine(me, ev) and lib.room(g, me)
    end,
    effect = function(g, me, ev)
      g.summon(g.ctrl(me), ev.card)
    end,
  },
}

-- Spellbender: when an enemy casts a spell on a minion, summon a 1/3 as the new target.
cards.VAN_tt_010 = {
  secret = {
    event = "play",
    cond = function(g, me, ev)
      local t = ev.target
      return lib.enemy_spell(g, me, ev) and t >= 0 and g.is_minion(t) and lib.room(g, me)
    end,
    effect = function(g, me, ev)
      local n = g.summon(g.ctrl(me), "VAN_tt_010a")
      if n then
        ev.target = n
      end
    end,
  },
}

-- Vaporize: when a minion attacks your hero, destroy it.
cards.VAN_EX1_594 = {
  secret = {
    event = "attack",
    cond = function(g, me, ev)
      return lib.attacks_my_hero(g, me, ev) and g.is_minion(ev.attacker)
    end,
    effect = function(g, me, ev)
      g.destroy(ev.attacker)
    end,
  },
}

-- Cone of Cold: 1 damage and freeze to a minion and its neighbours.
cards.VAN_EX1_275 = {
  target = "minion",
  spell = function(g, me, t)
    local group = { t }
    for _, m in ipairs(g.adjacent(t)) do
      table.insert(group, m)
    end
    for _, m in ipairs(group) do
      g.damage(me, m, g.spell_dmg(me, 1))
      g.freeze(m)
    end
  end,
}

-- Ethereal Arcanist: if you control a Secret at the end of your turn, gain +2/+2.
cards.VAN_EX1_274 = {
  on = {
    turn_end = function(g, me, ev)
      if g.mine(me, ev) and #g.traps(g.ctrl(me)) > 0 then
        g.buff(me, 2, 2)
      end
    end,
  },
}

cards.VAN_CS2_029 = lib.hit("any", 6, true) -- Fireball

-- Polymorph: transform a minion into a 1/1 Sheep.
cards.VAN_CS2_022 = {
  target = "minion",
  spell = function(g, me, t)
    g.transform(t, "VAN_CS2_tk1")
  end,
}

-- Water Elemental: freeze any character damaged by this minion.
cards.VAN_CS2_033 = {
  on = {
    damage = function(g, me, ev)
      if ev.source == me then
        g.freeze(ev.target)
      end
    end,
  },
}

-- Blizzard: 2 damage to all enemy minions and freeze them.
cards.VAN_CS2_028 = {
  spell = function(g, me)
    lib.each_enemy_minion(g, me, 2, g.freeze)
  end,
}

-- Archmage Antonidas: whenever you cast a spell, put a Fireball into your hand.
cards.VAN_EX1_559 = {
  on = {
    play = function(g, me, ev)
      if lib.my_spell(g, me, ev) then
        g.add_to_hand(g.ctrl(me), "VAN_CS2_029")
      end
    end,
  },
}

-- Flamestrike: 4 damage to all enemy minions.
cards.VAN_CS2_032 = {
  spell = function(g, me)
    lib.each_enemy_minion(g, me, 4)
  end,
}

cards.VAN_EX1_279 = lib.hit("any", 10, true) -- Pyroblast

return cards
