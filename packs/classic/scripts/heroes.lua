-- Champion powers (was rust/engine/src/cards/heroes.rs); Fireblast is in mage.lua,
-- The Coin in neutral.lua. Upgraded powers and Demon Hunter powers are
-- unreachable in Classic: no hooks.
local cards = {}

local BASIC_TOTEMS = { "VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009" }

-- The basic totems me's side does not have on the board.
local function missing_totems(g, me)
  local board = g.minions(g.ctrl(me))
  return list.filter(BASIC_TOTEMS, function(id)
    return not list.any(board, function(m) return g.card(m) == id end)
  end)
end

-- A power that summons a token (needs room).
local function summoner(card)
  return {
    can_play = lib.room,
    hero_power = function(g, me)
      g.summon(g.ctrl(me), card)
    end,
  }
end

-- A targeted power that deals n damage.
local function zap(n)
  return {
    target = "any",
    hero_power = function(g, me, t)
      g.damage(me, t, g.hp_dmg(me, n))
    end,
  }
end

-- Armor Up!: 2 Armor.
cards.VAN_HERO_01bp = {
  hero_power = function(g, me)
    g.gain_armor(g.ctrl(me), 2)
  end,
}

-- Totemic Call: summon a random basic totem you don't have.
cards.VAN_HERO_02bp = {
  can_play = function(g, me)
    return lib.room(g, me) and #missing_totems(g, me) > 0
  end,
  hero_power = function(g, me)
    g.summon(g.ctrl(me), g.pick(missing_totems(g, me)))
  end,
}

-- Healing Totem (from Totemic Call): at the end of your turn, restore 1 Health to all friendly minions.
cards.VAN_NEW1_009 = {
  on = {
    turn_end = function(g, me, ev)
      if g.mine(me, ev) then
        for _, m in ipairs(g.minions(g.ctrl(me))) do
          g.heal(me, m, g.heal_amt(me, 1))
        end
      end
    end,
  },
}

-- Dagger Mastery: equip a 1/2 Dagger.
cards.VAN_HERO_03bp = {
  hero_power = function(g, me)
    g.equip(g.ctrl(me), "VAN_CS2_082")
  end,
}

cards.VAN_HERO_04bp = summoner("VAN_CS2_101t") -- Reinforce

-- Steady Shot: 2 damage to the enemy hero.
cards.VAN_HERO_05bp = {
  hero_power = function(g, me)
    g.damage(me, g.hero(g.enemy(me)), g.hp_dmg(me, 2))
  end,
}

-- Shapeshift: +1 Attack this turn and 1 Armor.
cards.VAN_HERO_06bp = {
  hero_power = function(g, me)
    g.buff(g.hero(g.ctrl(me)), 1, 0, true)
    g.gain_armor(g.ctrl(me), 1)
  end,
}

-- Life Tap. 2014: damage first, then draw (as Fireplace).
cards.VAN_HERO_07bp = {
  hero_power = function(g, me)
    g.damage(me, g.hero(g.ctrl(me)), g.hp_dmg(me, 2))
    g.draw(g.ctrl(me), 1)
  end,
}

-- Lesser Heal: restore 2 Health.
cards.VAN_HERO_09bp = {
  target = "any",
  hero_power = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 2))
  end,
}

cards.VAN_EX1_tk33 = summoner("VAN_EX1_tk34") -- INFERNO! (Lord Jaraxxus)
cards.EX1_625t = zap(2) -- Mind Spike
cards.EX1_625t2 = zap(3) -- Mind Shatter

return cards
