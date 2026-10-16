-- Druid cards, their Choose One options and tokens (was rust/engine/src/cards/druid.rs).
-- Option order follows the card text.
local cards = {}

-- The champion gets +n Attack this turn and n Armor.
local function hero_attack(n)
  return {
    spell = function(g, me)
      g.buff(g.hero(g.ctrl(me)), n, 0, true)
      g.gain_armor(g.ctrl(me), n)
    end,
  }
end

local function taunt_buff(g, t, atk, hp)
  g.buff(t, atk, hp)
  g.give_tag(t, "TAUNT")
end

-- Innervate: 2 mana this turn.
cards.VAN_EX1_169 = {
  spell = function(g, me)
    g.add_mana(g.ctrl(me), 2)
  end,
}

cards.VAN_CS2_008 = lib.hit("any", 1, true) -- Moonfire
cards.VAN_CS2_005 = hero_attack(2) -- Claw
cards.VAN_EX1_570 = hero_attack(4) -- Bite

-- Naturalize: destroy a minion; the opponent draws 2.
cards.VAN_EX1_161 = {
  target = "minion",
  spell = function(g, me, t)
    g.destroy(t)
    g.draw(g.enemy(me), 2)
  end,
}

-- Savagery: damage equal to the champion's attack.
cards.VAN_EX1_578 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, g.attack(g.hero(g.ctrl(me)))))
  end,
}

-- Mark of the Wild: +2/+2 and Taunt.
cards.VAN_CS2_009 = {
  target = "minion",
  spell = function(g, me, t)
    taunt_buff(g, t, 2, 2)
  end,
}

-- Power of the Wild
cards.VAN_EX1_160 = { choose_one = { "VAN_EX1_160b", "VAN_EX1_160a" } }

-- Leader of the Pack: your minions +1/+1.
cards.VAN_EX1_160b = {
  effect = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.buff(m, 1, 1)
    end
  end,
}

-- Summon a Panther
cards.VAN_EX1_160a = {
  effect = function(g, me)
    g.summon(g.ctrl(me), "EX1_160t")
  end,
}

-- Wild Growth: an empty crystal; at full crystals, Excess Mana instead.
cards.VAN_CS2_013 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    if g.max_mana(p) >= g.rule("max_mana") then
      g.add_to_hand(p, "CS2_013t")
    else
      g.gain_mana(p, 1, true)
    end
  end,
}

-- Excess Mana: draw a card.
cards.CS2_013t = {
  spell = function(g, me)
    g.draw(g.ctrl(me), 1)
  end,
}

-- Wrath
cards.VAN_EX1_154 = { choose_one = { "VAN_EX1_154a", "VAN_EX1_154b" } }

-- Solar Wrath: 3 damage to a minion.
cards.VAN_EX1_154a = {
  target = "minion",
  effect = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 3))
  end,
}

-- Nature's Wrath: 1 damage to a minion, draw a card.
cards.VAN_EX1_154b = {
  target = "minion",
  effect = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 1))
    g.draw(g.ctrl(me), 1)
  end,
}

-- Healing Touch: restore 8.
cards.VAN_CS2_007 = {
  target = "any",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 8))
  end,
}

-- Mark of Nature
cards.VAN_EX1_155 = { choose_one = { "VAN_EX1_155a", "VAN_EX1_155b" } }

-- Tiger's Fury: +4 Attack.
cards.VAN_EX1_155a = {
  target = "minion",
  effect = function(g, me, t)
    g.buff(t, 4, 0)
  end,
}

-- Thick Hide: +4 Health and Taunt.
cards.VAN_EX1_155b = {
  target = "minion",
  effect = function(g, me, t)
    taunt_buff(g, t, 0, 4)
  end,
}

-- Savage Roar: your characters +2 Attack this turn.
cards.VAN_CS2_011 = {
  spell = function(g, me)
    for _, c in ipairs(g.chars(g.ctrl(me))) do
      g.buff(c, 2, 0, true)
    end
  end,
}

-- Keeper of the Grove
cards.VAN_EX1_166 = { choose_one = { "VAN_EX1_166a", "VAN_EX1_166b" } }

-- Moonfire (option): 2 damage.
cards.VAN_EX1_166a = {
  target = "any",
  effect = function(g, me, t)
    g.damage(me, t, 2)
  end,
}

-- Dispel: silence a minion.
cards.VAN_EX1_166b = {
  target = "minion",
  effect = function(g, me, t)
    g.silence(t)
  end,
}

-- Soul of the Forest: your minions get "Deathrattle: summon a 2/2 Treant".
cards.VAN_EX1_158 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.enchant(m, { hooks = "ench:soul_of_the_forest" })
    end
  end,
}

cards["ench:soul_of_the_forest"] = {
  deathrattle = function(g, me)
    g.summon(g.ctrl(me), "VAN_EX1_tk9", g.died_pos(me))
  end,
}

-- Swipe: 4 damage to an enemy, 1 to all other enemies.
cards.VAN_CS2_012 = {
  target = "enemy_char",
  spell = function(g, me, t)
    local others = {}
    for _, c in ipairs(g.chars(g.ctrl(t))) do
      if c ~= t then
        others[#others + 1] = c
      end
    end
    g.damage(me, t, g.spell_dmg(me, 4))
    for _, c in ipairs(others) do
      g.damage(me, c, g.spell_dmg(me, 1))
    end
  end,
}

-- Druid of the Claw
cards.VAN_EX1_165 = { choose_one = { "VAN_EX1_165a", "VAN_EX1_165b" } }

-- Cat Form
cards.VAN_EX1_165a = {
  effect = function(g, me)
    g.transform(me, "VAN_EX1_165t1")
  end,
}

-- Bear Form
cards.VAN_EX1_165b = {
  effect = function(g, me)
    g.transform(me, "VAN_EX1_165t2")
  end,
}

-- Nourish
cards.VAN_EX1_164 = { choose_one = { "VAN_EX1_164a", "VAN_EX1_164b" } }

-- Rampant Growth: 2 mana crystals.
cards.VAN_EX1_164a = {
  effect = function(g, me)
    g.gain_mana(g.ctrl(me), 2)
  end,
}

-- Enrich: draw 3 cards.
cards.VAN_EX1_164b = {
  effect = function(g, me)
    g.draw(g.ctrl(me), 3)
  end,
}

-- Starfall
cards.VAN_NEW1_007 = { choose_one = { "VAN_NEW1_007b", "VAN_NEW1_007a" } }

-- Starlord: 5 damage to a minion.
cards.VAN_NEW1_007b = {
  target = "minion",
  effect = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 5))
  end,
}

-- Stellar Drift: 2 damage to all enemy minions.
cards.VAN_NEW1_007a = {
  effect = function(g, me)
    lib.each_enemy_minion(g, me, 2)
  end,
}

-- Force of Nature: three Treants.
cards.VAN_EX1_571 = {
  spell = function(g, me)
    for _ = 1, 3 do
      g.summon(g.ctrl(me), "VAN_EX1_tk9b")
    end
  end,
}

-- Treant (Force of Nature): destroyed at the end of the turn.
cards.VAN_EX1_tk9b = {
  on = {
    turn_end = function(g, me)
      g.destroy(me)
    end,
  },
}

-- Starfire: 5 damage, draw a card.
cards.VAN_EX1_173 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 5))
    g.draw(g.ctrl(me), 1)
  end,
}

-- Ancient of Lore
cards.VAN_NEW1_008 = { choose_one = { "VAN_NEW1_008a", "VAN_NEW1_008b" } }

-- Ancient Teachings: draw 2 cards.
cards.VAN_NEW1_008a = {
  effect = function(g, me)
    g.draw(g.ctrl(me), 2)
  end,
}

-- Ancient Secrets: restore 5.
cards.VAN_NEW1_008b = {
  target = "any",
  effect = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 5))
  end,
}

-- Ancient of War
cards.VAN_EX1_178 = { choose_one = { "VAN_EX1_178b", "VAN_EX1_178a" } }

-- Uproot: +5 Attack.
cards.VAN_EX1_178b = {
  effect = function(g, me)
    g.buff(me, 5, 0)
  end,
}

-- Rooted: +5 Health and Taunt.
cards.VAN_EX1_178a = {
  effect = function(g, me)
    taunt_buff(g, me, 0, 5)
  end,
}

-- Cenarius
cards.VAN_EX1_573 = { choose_one = { "VAN_EX1_573a", "VAN_EX1_573b" } }

-- Demigod's Favor: your other minions +2/+2.
cards.VAN_EX1_573a = {
  effect = function(g, me)
    for _, m in ipairs(g.others(me)) do
      g.buff(m, 2, 2)
    end
  end,
}

-- Shan'do's Lesson: Treants with Taunt on both sides.
cards.VAN_EX1_573b = {
  effect = function(g, me)
    local right = g.summon_right(me, "VAN_EX1_tk9")
    local left = g.summon(g.ctrl(me), "VAN_EX1_tk9", g.board_pos(me))
    g.give_tag(right, "TAUNT") -- nil (board full): does nothing
    g.give_tag(left, "TAUNT")
  end,
}

return cards
