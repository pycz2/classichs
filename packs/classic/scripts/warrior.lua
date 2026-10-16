-- Warrior cards and their tokens (was rust/engine/src/cards/warrior.rs).
local cards = {}

local function damaged(g, me, t)
  return g.dmg(t) > 0
end

-- 1 damage (a spell: with spell power) and +2 Attack.
local function hit_and_rage(g, me, t)
  g.damage(me, t, g.is_spell(me) and g.spell_dmg(me, 1) or 1)
  g.buff(t, 2, 0)
end

cards.VAN_EX1_607 = { target = "minion", spell = hit_and_rage } -- Inner Rage
cards.VAN_EX1_603 = { target = "minion", battlecry = hit_and_rage } -- Cruel Taskmaster

-- Execute: destroy a damaged enemy minion.
cards.VAN_CS2_108 = {
  target = { base = "enemy_minion", filter = damaged },
  spell = function(g, me, t)
    g.destroy(t)
  end,
}

-- Shield Slam: damage equal to your Armor.
cards.VAN_EX1_410 = {
  target = "minion",
  spell = function(g, me, t)
    local armor = g.tag(g.hero(g.ctrl(me)), "ARMOR")
    g.damage(me, t, g.spell_dmg(me, armor))
  end,
}

-- Upgrade!: your weapon gets +1/+1, or equip a 1/3 weapon.
cards.VAN_EX1_409 = {
  spell = function(g, me)
    local w = g.weapon(g.ctrl(me))
    if w then
      g.buff(w, 1, 0)
      g.add_tag(w, "DURABILITY", 1)
    else
      g.equip(g.ctrl(me), "EX1_409t")
    end
  end,
}

-- Whirlwind: 1 damage to ALL minions.
cards.VAN_EX1_400 = {
  spell = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      g.damage(me, m, g.spell_dmg(me, 1))
    end
  end,
}

-- Armorsmith: whenever a friendly minion takes damage, gain 1 Armor.
cards.VAN_EX1_402 = {
  on = {
    damage = function(g, me, ev)
      if g.is_minion(ev.target) and g.ctrl(ev.target) == g.ctrl(me) then
        g.gain_armor(g.ctrl(me), 1)
      end
    end,
  },
}

-- Battle Rage: draw a card for each damaged friendly character.
cards.VAN_EX1_392 = {
  spell = function(g, me)
    local n = 0
    for _, c in ipairs(g.chars(g.ctrl(me))) do
      if g.dmg(c) > 0 then
        n = n + 1
      end
    end
    g.draw(g.ctrl(me), n)
  end,
}

-- Cleave: 2 damage to two random enemy minions.
cards.VAN_CS2_114 = {
  can_play = function(g, me)
    return #g.minions(g.enemy(me)) >= 2
  end,
  spell = function(g, me)
    local pool = g.shuffle(g.minions(g.enemy(me)))
    for i = 1, math.min(2, #pool) do
      g.damage(me, pool[i], g.spell_dmg(me, 2))
    end
  end,
}

-- Commanding Shout: lives on the hero this turn, so later minions count too.
cards.VAN_NEW1_036 = {
  spell = function(g, me)
    g.enchant(g.hero(g.ctrl(me)), { hooks = "ench:commanding_shout", eot = true })
    g.draw(g.ctrl(me), 1)
  end,
}

-- Your minions can't be reduced below 1 Health.
cards["ench:commanding_shout"] = {
  now = {
    predamage = function(g, me, ev)
      local t = ev.target
      if g.is_minion(t) and g.ctrl(t) == g.ctrl(me) then
        ev.amount = math.min(ev.amount, math.max(0, g.health(t) - 1))
      end
    end,
  },
}

-- Heroic Strike: +4 Attack this turn.
cards.VAN_CS2_105 = {
  spell = function(g, me)
    g.buff(g.hero(g.ctrl(me)), 4, 0, true)
  end,
}

-- Rampage: a damaged minion gets +3/+3.
cards.VAN_CS2_104 = {
  target = { base = "minion", filter = damaged },
  spell = function(g, me, t)
    g.buff(t, 3, 3)
  end,
}

-- Slam: 2 damage; draw a card if it survives.
cards.VAN_EX1_391 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
    if g.zone(t) == "PLAY" and g.health(t) > 0 then
      g.draw(g.ctrl(me), 1)
    end
  end,
}

-- Charge: a friendly minion gets +2 Attack and Charge.
cards.VAN_CS2_103 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.buff(t, 2, 0)
    g.give_tag(t, "CHARGE")
  end,
}

-- Frothing Berserker: whenever a minion takes damage, gain +1 Attack.
cards.VAN_EX1_604 = {
  on = {
    damage = function(g, me, ev)
      if g.is_minion(ev.target) then
        g.buff(me, 1, 0)
      end
    end,
  },
}

-- Shield Block: gain 5 Armor, draw a card.
cards.VAN_EX1_606 = {
  spell = function(g, me)
    g.gain_armor(g.ctrl(me), 5)
    g.draw(g.ctrl(me), 1)
  end,
}

-- Warsong Commander (2014): your summoned minions with 3 or less Attack get Charge.
cards.VAN_EX1_084 = {
  on = {
    summon = function(g, me, ev)
      local m = ev.entity
      if g.mine(me, ev) and m ~= me and g.atk(m) <= 3 then
        g.give_tag(m, "CHARGE")
      end
    end,
  },
}

-- Arathi Weaponsmith: equip a 2/2 weapon.
cards.VAN_EX1_398 = {
  battlecry = function(g, me)
    g.equip(g.ctrl(me), "EX1_398t")
  end,
}

-- Mortal Strike: 4 damage, 6 if your hero has 12 or less Health.
cards.VAN_EX1_408 = {
  target = "any",
  spell = function(g, me, t)
    local n = g.health(g.hero(g.ctrl(me))) <= 12 and 6 or 4
    g.damage(me, t, g.spell_dmg(me, n))
  end,
}

-- Brawl: destroy all minions except one (chosen randomly).
cards.VAN_EX1_407 = {
  can_play = function(g, me)
    return #g.all_minions() >= 2
  end,
  spell = function(g, me)
    local all = g.all_minions()
    local keep = g.pick(all)
    for _, m in ipairs(all) do
      if m ~= keep then
        g.destroy(m)
      end
    end
  end,
}

-- Gorehowl: attacking a minion costs 1 Attack instead of 1 Durability.
cards.VAN_EX1_411 = {
  durability_on_attack = function(g, w, defender)
    if not g.is_minion(defender) then
      return true
    end
    g.buff(w, -1, 0)
    if g.atk(w) <= 0 then
      g.destroy(w)
    end
    return false
  end,
}

-- Grommash Hellscream: Enrage: +6 Attack.
cards.VAN_EX1_414 = {
  aura = function(g, me)
    if g.dmg(me) > 0 then
      g.aura_add(me, 6, 0)
    end
  end,
}

return cards
