-- The tutorial bosses' cards (was rust/engine/src/cards/tutorial.rs) and the
-- missions' hooks (missions/<n>.json `script`).
local cards = {}

-- Missions 1 and 2 (their `script`): the player's champion can't drop below 1 Health.
cards["ench:tutorial_guard"] = {
  now = {
    predamage = function(g, me, ev)
      if ev.target == me then
        ev.amount = math.min(ev.amount, math.max(0, g.health(me) - 1 + g.tag(me, "ARMOR")))
      end
    end,
  },
}

cards.TU4a_004 = lib.hit("any", 4, true) -- Hogger SMASH!
cards.TU4c_002 = lib.hit("any", 2, true) -- Barrel Toss

-- Barrel: Deathrattle: summon a broken Barrel.
cards.TU4c_003 = {
  deathrattle = function(g, me)
    g.summon(g.ctrl(me), "TU4c_005", g.died_pos(me))
  end,
}

-- Stomp: 2 damage to all enemies.
cards.TU4c_004 = {
  spell = function(g, me)
    for _, c in ipairs(g.chars(g.enemy(me))) do
      g.damage(me, c, g.spell_dmg(me, 2))
    end
  end,
}

-- Bananas (tutorial): +1/+1 to a friendly minion.
cards.TU4c_006 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.buff(t, 1, 1)
  end,
}

-- Will of Mukla: restore 8 Health.
cards.TU4c_008 = {
  target = "any",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 8))
  end,
}

-- Crazy Monkey: put Bananas into your hand.
cards.TU4f_007 = {
  battlecry = function(g, me)
    g.add_to_hand(g.ctrl(me), "TU4c_006")
  end,
}

-- Shotgun Blast: 1 damage.
cards.TU4d_003 = {
  target = "any",
  hero_power = function(g, me, t)
    g.damage(me, t, g.hp_dmg(me, 1))
  end,
}

-- Flames of Azzinoth (Illidan): two 2/1 Flames of Azzinoth.
cards.TU4e_002 = {
  can_play = lib.room,
  hero_power = function(g, me)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), "TU4e_002t")
    end
  end,
}

-- Flame Burst: 5 missiles of 1 damage; spell damage boosts each one.
cards.TU4e_005 = {
  spell = function(g, me)
    for _ = 1, 5 do
      local t = g.random_alive(g.chars(g.enemy(me)))
      g.damage(me, t, g.spell_dmg(me, 1))
    end
  end,
}

-- Legacy of the Emperor: your minions get +2/+2.
cards.TU4f_004 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.buff(m, 2, 2)
    end
  end,
}

-- Transcendence: Cho can't be attacked or targeted until his minions are dead.
cards.TU4f_006 = {
  can_play = function(g, me)
    return #g.minions(g.ctrl(me)) > 0
  end,
  spell = function(g, me)
    local hero = g.hero(g.ctrl(me))
    if #g.minions(g.ctrl(me)) > 0 then
      g.give_tag(hero, "STEALTH")
      g.enchant(hero, { hooks = "ench:transcendence" })
    end
  end,
}

cards["ench:transcendence"] = {
  on = {
    death = function(g, me)
      if #g.minions(g.ctrl(me)) == 0 then
        g.erase_tag(me, "STEALTH")
        g.remove_enchant(me, "ench:transcendence")
      end
    end,
  },
}

return cards
