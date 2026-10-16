-- Warlock cards, their tokens and enchantments (was rust/engine/src/cards/warlock.rs).
local cards = {}

local function is_demon(g, me, t)
  return g.race(t) == "DEMON"
end

-- Damage, then true if the target is now dying (Mortal Coil, Bane of Doom).
local function kills(g, me, t, n)
  g.damage(me, t, n)
  return g.zone(t) == "PLAY" and g.health(t) <= 0
end

-- A battlecry: n damage to your own hero.
local function hurt_own_hero(n)
  return {
    battlecry = function(g, me)
      g.damage(me, g.hero(g.ctrl(me)), n)
    end,
  }
end

-- A battlecry: discard n random cards.
local function discard_battlecry(n)
  return {
    battlecry = function(g, me)
      g.discard_random(g.ctrl(me), n)
    end,
  }
end

-- Sacrificial Pact: destroy a Demon (Lord Jaraxxus as hero included), restore 5 Health.
cards.VAN_NEW1_003 = {
  target = { base = "any", filter = is_demon },
  spell = function(g, me, t)
    g.destroy(t)
    g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 5))
  end,
}

-- Soulfire: 4 damage, discard a random card.
cards.VAN_EX1_308 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
    g.discard_random(g.ctrl(me), 1)
  end,
}

-- Blood Imp: at the end of your turn, give another random friendly minion +1 Health.
cards.VAN_CS2_059 = {
  on = {
    turn_end = function(g, me, ev)
      if g.mine(me, ev) then
        g.buff(g.random_alive(g.others(me)), 0, 1)
      end
    end,
  },
}

-- Corruption: at the start of the caster's turn, destroy the minion.
cards.VAN_CS2_063 = {
  target = "enemy_minion",
  spell = function(g, me, t)
    g.enchant(t, { hooks = "ench:corruption", player = g.ctrl(me) })
  end,
}

cards["ench:corruption"] = {
  on = {
    turn_start = function(g, me, ev)
      for _, p in ipairs(g.enchants(me, "ench:corruption")) do
        if ev.player == p then
          g.destroy(me)
        end
      end
    end,
  },
}

cards.VAN_EX1_319 = hurt_own_hero(3) -- Flame Imp

-- Mortal Coil: 1 damage to a minion; if that kills it, draw a card.
cards.VAN_EX1_302 = {
  target = "minion",
  spell = function(g, me, t)
    if kills(g, me, t, g.spell_dmg(me, 1)) then
      g.draw(g.ctrl(me), 1)
    end
  end,
}

-- Power Overwhelming: +4/+4 this turn, it dies at the end of the turn.
cards.VAN_EX1_316 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.buff(t, 4, 4, true)
    g.enchant(t, { hooks = "ench:power_overwhelming" })
  end,
}

cards["ench:power_overwhelming"] = {
  on = {
    turn_end = function(g, me)
      g.destroy(me)
    end,
  },
}

-- Demonfire: 2 damage to a minion; a friendly Demon gets +2/+2 instead.
cards.VAN_EX1_596 = {
  target = "minion",
  spell = function(g, me, t)
    if g.ctrl(t) == g.ctrl(me) and g.race(t) == "DEMON" then
      g.buff(t, 2, 2)
    else
      g.damage(me, t, g.spell_dmg(me, 2))
    end
  end,
}

cards.VAN_EX1_306 = discard_battlecry(1) -- Felstalker

-- Drain Life: 2 damage, restore 2 Health to your hero.
cards.VAN_CS2_061 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
    g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 2))
  end,
}

-- Felguard: destroy one of your mana crystals.
cards.VAN_EX1_301 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local max = math.max(0, g.max_mana(p) - 1)
    g.set_mana(p, math.min(g.mana(p), max), max)
  end,
}

-- Sense Demons: draw 2 Demons from your deck; missing ones become Worthless Imps.
cards.VAN_EX1_317 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local demons = {}
    for _, e in ipairs(g.deck(p)) do
      if g.race(e) == "DEMON" then
        table.insert(demons, e)
      end
    end
    g.shuffle(demons)
    for i = 1, 2 do
      if demons[i] then
        g.draw_entity(p, demons[i])
      else
        g.add_to_hand(p, "EX1_317t")
      end
    end
  end,
}

-- Shadow Bolt: 4 damage to a minion.
cards.VAN_CS2_057 = lib.hit("minion", 4, true)

-- Void Terror: destroy the adjacent minions and gain their Attack and Health.
cards.VAN_EX1_304 = {
  battlecry = function(g, me)
    local atk, hp = 0, 0
    for _, m in ipairs(g.adjacent(me)) do
      atk = atk + g.atk(m)
      hp = hp + g.health(m)
      g.destroy(m)
    end
    g.buff(me, atk, hp)
  end,
}

-- Hellfire: 3 damage to ALL characters.
cards.VAN_CS2_062 = {
  spell = function(g, me)
    for _, c in ipairs(g.all_chars()) do
      g.damage(me, c, g.spell_dmg(me, 3))
    end
  end,
}

cards.VAN_EX1_313 = hurt_own_hero(5) -- Pit Lord

-- Shadowflame: destroy a friendly minion and deal its Attack to all enemy minions.
cards.VAN_EX1_303 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    local n = g.spell_dmg(me, g.atk(t))
    g.destroy(t)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.damage(me, m, n)
    end
  end,
}

-- Summoning Portal: your minions cost (2) less, but not less than (1).
cards.VAN_EX1_315 = {
  cost_aura = function(g, me, card, c)
    if g.ctrl(card) ~= g.ctrl(me) or not g.is_minion(card) or g.zone(card) ~= "HAND" or c <= 1 then
      return c
    end
    return math.max(1, c - 2)
  end,
}

-- Bane of Doom: 3 damage (as the Rust engine had it); if that kills the character, summon a random Demon.
cards.VAN_EX1_320 = {
  target = "any",
  spell = function(g, me, t)
    if kills(g, me, t, g.spell_dmg(me, 3)) then
      local demons = {}
      for _, id in ipairs(g.collectible()) do
        local c = g.info(id)
        if c.type == "MINION" and c.race == "DEMON" then
          table.insert(demons, id)
        end
      end
      g.summon(g.ctrl(me), g.pick(demons))
    end
  end,
}

cards.VAN_EX1_310 = discard_battlecry(2) -- Doomguard

-- Dread Infernal: 1 damage to ALL other characters.
cards.VAN_CS2_064 = {
  battlecry = function(g, me)
    for _, c in ipairs(g.all_chars()) do
      if c ~= me then
        g.damage(me, c, 1)
      end
    end
  end,
}

-- Siphon Soul: destroy a minion, restore 3 Health to your hero.
cards.VAN_EX1_309 = {
  target = "minion",
  spell = function(g, me, t)
    g.destroy(t)
    g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 3))
  end,
}

-- Twisting Nether: destroy all minions.
cards.VAN_EX1_312 = {
  spell = function(g)
    for _, m in ipairs(g.all_minions()) do
      g.destroy(m)
    end
  end,
}

-- Lord Jaraxxus: becomes the hero (15/15), Blood Fury, INFERNO!; secrets stay.
cards.VAN_EX1_323 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    g.remove(me, "SETASIDE")
    g.replace_hero(p, "EX1_323h")
    g.equip(p, "EX1_323w")
    g.set_power(p, "VAN_EX1_tk33")
  end,
}

return cards
