-- Neutral cards and their tokens (rust/engine/src/cards/neutral.rs: the
-- Basic set is here; the rest is still Rust, to be ported).
local cards = {}

-- The Coin: one mana crystal this turn.
cards.GAME_005 = {
  spell = function(g, me)
    g.add_mana(g.ctrl(me), 1)
  end,
}

-- --- Basic ---------------------------------------------------------------------------

cards.VAN_CS2_189 = lib.hit("any", 1) -- Elven Archer

-- Grimscale Oracle: ALL other Murlocs have +1 Attack.
cards.VAN_EX1_508 = {
  aura = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if m ~= me and g.race(m) == "MURLOC" then
        g.aura_add(m, 1, 0)
      end
    end
  end,
}

-- Voodoo Doctor
cards.VAN_EX1_011 = {
  target = "any",
  battlecry = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 2))
  end,
}

-- Acidic Swamp Ooze: destroy the opponent's weapon.
cards.VAN_EX1_066 = {
  battlecry = function(g, me)
    g.destroy(g.weapon(g.enemy(me)))
  end,
}

cards.VAN_EX1_506 = lib.summon_right("VAN_EX1_506a") -- Murloc Tidehunter
cards.VAN_EX1_015 = lib.draw_battlecry(1) -- Novice Engineer
cards.VAN_CS2_147 = lib.draw_battlecry(1) -- Gnomish Inventor
cards.VAN_CS2_141 = lib.hit("any", 1) -- Ironforge Rifleman
cards.VAN_CS2_122 = lib.others_aura(1, 0) -- Raid Leader
cards.VAN_CS2_196 = lib.summon_right("VAN_CS2_boar") -- Razorfen Hunter

-- Shattered Sun Cleric
cards.VAN_EX1_019 = {
  target = "friendly_minion",
  battlecry = function(g, me, t)
    g.buff(t, 1, 1)
  end,
}

cards.VAN_EX1_025 = lib.summon_right("EX1_025t") -- Dragonling Mechanic

-- Darkscale Healer: restore 2 Health to all friendly characters.
cards.VAN_DS1_055 = {
  battlecry = function(g, me)
    for _, c in ipairs(g.chars(g.ctrl(me))) do
      g.heal(me, c, g.heal_amt(me, 2))
    end
  end,
}

-- Frostwolf Warlord: +1/+1 for each other friendly minion.
cards.VAN_CS2_226 = {
  battlecry = function(g, me)
    local n = #g.others(me)
    g.buff(me, n, n)
  end,
}

-- Gurubashi Berserker: whenever this minion takes damage, gain +3 Attack.
cards.VAN_EX1_399 = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me then
        g.buff(me, 3, 0)
      end
    end,
  },
}

-- Nightblade: 3 damage to the enemy hero.
cards.VAN_EX1_593 = {
  battlecry = function(g, me)
    g.damage(me, g.hero(g.enemy(me)), 3)
  end,
}

cards.VAN_CS2_150 = lib.hit("any", 2) -- Stormpike Commando
cards.VAN_CS2_222 = lib.others_aura(1, 1) -- Stormwind Champion

return cards
