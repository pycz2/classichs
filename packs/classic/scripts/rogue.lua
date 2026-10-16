-- Rogue cards, their tokens and enchantments (was rust/engine/src/cards/rogue.rs).
local cards = {}

local function has_weapon(g, me)
  return g.weapon(g.ctrl(me)) ~= nil
end

-- For each of me's `hooks` enchantments whose player is the event's player:
-- removes it, then calls f(g, me, player).
local function remove_mine(g, me, ev, hooks, f)
  for _, p in ipairs(g.enchants(me, hooks)) do
    if p == ev.player then
      g.remove_enchant(me, hooks, p)
      f(g, me, p)
    end
  end
end

-- Backstab: 2 damage to an undamaged minion.
cards.VAN_CS2_072 = {
  target = {
    base = "minion",
    filter = function(g, me, t)
      return g.dmg(t) == 0
    end,
  },
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
  end,
}

-- Preparation: the next spell you cast this turn costs (3) less.
cards.VAN_EX1_145 = {
  spell = function(g, me)
    g.add_cost_mod(g.ctrl(me), { kind = "spell", delta = -3, ["until"] = "use" })
  end,
}

-- Shadowstep: return a friendly minion to your hand; it costs (2) less.
cards.VAN_EX1_144 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    local n = g.return_to_hand(t)
    if n then
      g.enchant(n, { cost = -2 })
    end
  end,
}

-- Cold Blood: +2 Attack; Combo: +4 instead.
cards.VAN_CS2_073 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 2, 0)
  end,
  combo = function(g, me, t)
    g.buff(t, 4, 0)
  end,
}

-- Conceal: your minions have Stealth until your next turn.
cards.VAN_EX1_128 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, m in ipairs(g.minions(p)) do
      if not g.has(m, "STEALTH") then -- natural Stealth is not Conceal's to remove
        g.give_tag(m, "STEALTH")
        g.enchant(m, { hooks = "ench:conceal", player = p })
      end
    end
  end,
}

cards["ench:conceal"] = {
  on = {
    turn_start = function(g, me, ev)
      remove_mine(g, me, ev, "ench:conceal", function(g, m)
        g.erase_tag(m, "STEALTH")
      end)
    end,
  },
}

-- Deadly Poison: your weapon gets +2 Attack.
cards.VAN_CS2_074 = {
  can_play = has_weapon,
  spell = function(g, me)
    g.buff(g.weapon(g.ctrl(me)), 2, 0)
  end,
}

-- Sinister Strike: 3 damage to the enemy hero.
cards.VAN_CS2_075 = {
  spell = function(g, me)
    g.damage(me, g.hero(g.enemy(me)), g.spell_dmg(me, 3))
  end,
}

-- Betrayal: an enemy minion deals its damage to the minions next to it.
cards.VAN_EX1_126 = {
  target = "enemy_minion",
  spell = function(g, me, t)
    for _, m in ipairs(g.adjacent(t)) do
      g.damage(t, m, g.atk(t))
    end
  end,
}

-- Blade Flurry: destroy your weapon and deal its damage to all enemies.
cards.VAN_CS2_233 = {
  can_play = has_weapon,
  spell = function(g, me)
    local w = g.weapon(g.ctrl(me))
    local n = g.spell_dmg(me, g.atk(w))
    g.destroy(w)
    for _, c in ipairs(g.chars(g.enemy(me))) do
      g.damage(me, c, n)
    end
  end,
}

-- Defias Ringleader: Combo: summon a 2/1 Defias Bandit.
cards.VAN_EX1_131 = {
  combo = function(g, me)
    g.summon_right(me, "EX1_131t")
  end,
}

-- Eviscerate: 2 damage; Combo: 4 instead.
cards.VAN_EX1_124 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
  end,
  combo = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
  end,
}

-- Patient Assassin: destroy any minion damaged by this minion.
cards.VAN_EX1_522 = {
  on = {
    damage = function(g, me, ev)
      if ev.source == me and g.is_minion(ev.target) then
        g.destroy(ev.target)
      end
    end,
  },
}

-- Sap: return an enemy minion to its owner's hand.
cards.VAN_EX1_581 = {
  target = "enemy_minion",
  spell = function(g, me, t)
    g.return_to_hand(t)
  end,
}

-- Shiv: 1 damage, draw a card.
cards.VAN_EX1_278 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 1))
    g.draw(g.ctrl(me), 1)
  end,
}

-- Edwin VanCleef: Combo: +2/+2 for each other card played this turn.
cards.VAN_EX1_613 = {
  combo = function(g, me)
    local n = 2 * (g.cards_played(g.ctrl(me)) - 1)
    g.buff(me, n, n)
  end,
}

-- Fan of Knives: 1 damage to all enemy minions, draw a card.
cards.VAN_EX1_129 = {
  spell = function(g, me)
    lib.each_enemy_minion(g, me, 1)
    g.draw(g.ctrl(me), 1)
  end,
}

-- Headcrack: 2 damage to the enemy hero; Combo: return it to your hand next turn.
cards.VAN_EX1_137 = {
  spell = function(g, me)
    g.damage(me, g.hero(g.enemy(me)), g.spell_dmg(me, 2))
  end,
  combo = function(g, me)
    g.damage(me, g.hero(g.enemy(me)), g.spell_dmg(me, 2))
    local p = g.ctrl(me)
    g.enchant(g.hero(p), { hooks = "ench:headcrack", player = p })
  end,
}

-- Returns Headcrack to the hand at the start of the next own turn.
cards["ench:headcrack"] = {
  on = {
    turn_start = function(g, me, ev)
      remove_mine(g, me, ev, "ench:headcrack", function(g, _, p)
        g.add_to_hand(p, "VAN_EX1_137")
      end)
    end,
  },
}

-- Perdition's Blade: 1 damage; Combo: 2 instead.
cards.VAN_EX1_133 = {
  target = "any",
  battlecry = function(g, me, t)
    g.damage(me, t, 1)
  end,
  combo = function(g, me, t)
    g.damage(me, t, 2)
  end,
}

-- SI:7 Agent: Combo: 2 damage (targets only with Combo).
cards.VAN_EX1_134 = {
  combo_target = "any",
  combo = function(g, me, t)
    g.damage(me, t, 2)
  end,
}

-- Master of Disguise: give another friendly minion Stealth.
cards.VAN_NEW1_014 = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t)
      return t ~= me
    end,
  },
  battlecry = function(g, me, t)
    g.give_tag(t, "STEALTH")
  end,
}

-- Assassinate: destroy an enemy minion.
cards.VAN_CS2_076 = {
  target = "enemy_minion",
  spell = function(g, me, t)
    g.destroy(t)
  end,
}

-- Kidnapper: Combo: return a minion to its owner's hand.
cards.VAN_NEW1_005 = {
  combo_target = "minion",
  combo = function(g, me, t)
    g.return_to_hand(t)
  end,
}

-- Vanish: return all minions to their owner's hand.
cards.VAN_NEW1_004 = {
  spell = function(g)
    for _, m in ipairs(g.all_minions()) do
      g.return_to_hand(m)
    end
  end,
}

-- Sprint: draw 4 cards.
cards.VAN_CS2_077 = {
  spell = function(g, me)
    g.draw(g.ctrl(me), 4)
  end,
}

return cards
