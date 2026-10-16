-- Chromehead (Mother Rust): cards and the Shakedown power. Heat is the card field mana_lock.
local cards = {}

-- Shakedown: 2 damage to the enemy champion, 1 Plating.
cards.shakedown = {
  hero_power = function(g, me)
    local p = g.ctrl(me)
    g.damage(me, g.hero(g.opponent(p)), g.hp_dmg(me, 2))
    g.gain_armor(p, 1)
  end,
}

-- Rust Shiv: after your champion attacks, gain 1 Plating.
cards.rust_shiv = {
  on = {
    after_attack = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.attacker == g.hero(p) then
        g.gain_armor(p, 1)
      end
    end,
  },
}

-- Nitro Shot: a friendly minion +2 Attack and Overclock.
cards.nitro_shot = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.buff(t, 2, 0)
    g.give_tag(t, "HASTE")
  end,
}

-- Stim Junkie: Redline: Dual-Core.
cards.stim_junkie = lib.redline({ DOUBLE_ATTACK = true })

-- Chrome Up: 3 Plating; your champion +2 Attack this turn.
cards.chrome_up = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.gain_armor(p, 3)
    g.buff(g.hero(p), 2, 0, true)
  end,
}

-- Fence the Goods: discard a random card, draw 3.
cards.fence_the_goods = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.discard_random(p, 1)
    g.draw(p, 3)
  end,
}

-- Back-Alley Bomb: 5 damage to a minion, 2 to your champion.
cards.back_alley_bomb = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 5))
    g.damage(me, g.hero(g.ctrl(me)), g.spell_dmg(me, 2))
  end,
}

-- Scrap Bruiser: Boot: 1 damage to all other minions.
cards.scrap_bruiser = {
  battlecry = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if m ~= me then
        g.damage(me, m, 1)
      end
    end
  end,
}

-- Pawn Shark: Boot: discard a random card, gain +3/+3.
cards.pawn_shark = {
  battlecry = function(g, me)
    g.discard_random(g.ctrl(me), 1)
    g.buff(me, 3, 3)
  end,
}

-- Hydraulic Maul: Boot: 5 Plating.
cards.hydraulic_maul = {
  battlecry = function(g, me) g.gain_armor(g.ctrl(me), 5) end,
}

-- Vulka: whenever this takes damage, 2 Plating.
cards.vulka = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me then
        g.gain_armor(g.ctrl(me), 2)
      end
    end,
  },
}

return cards
