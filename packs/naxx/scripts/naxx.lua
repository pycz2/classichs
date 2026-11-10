-- Curse of Naxxramas (July 2014): the 30 cards and their tokens, as at the release
-- (docs/packs/api.md). The Basic and Classic cards are Classic's scripts, copied in by the recipe.
local cards = {}

-- The card (an id) has the mechanic in its data (DEATHRATTLE, BATTLECRY).
local function has_keyword(g, card, kw)
  for _, k in ipairs(g.info(card).keywords) do
    if k == kw then
      return true
    end
  end
  return false
end

-- The cards of a list (entities) that pass ok(e).
local function only(list, ok)
  local out = {}
  for _, e in ipairs(list) do
    if ok(e) then
      out[#out + 1] = e
    end
  end
  return out
end

-- An `on` hook that runs only on its controller's events (ev.player).
local function on_mine(event, f)
  return {
    on = {
      [event] = function(g, me, ev)
        if g.mine(me, ev) then
          f(g, me, ev)
        end
      end,
    },
  }
end

-- A deathrattle that summons these tokens where it died.
local function leaves(...)
  local tokens = { ... }
  return {
    deathrattle = function(g, me)
      for _, t in ipairs(tokens) do
        g.summon(g.ctrl(me), t, g.died_pos(me))
      end
    end,
  }
end

-- 1 damage to all minions (Unstable Ghoul, Death's Bite).
local function one_to_all(g, me)
  for _, m in ipairs(g.all_minions()) do
    g.damage(me, m, 1)
  end
end

-- Feugen and Stalagg: Thaddius if the other one died this game, on either side.
local function thaddius_if(other)
  return {
    deathrattle = function(g, me)
      for p = 0, 1 do
        for _, e in ipairs(g.graveyard(p)) do
          if g.card(e) == other and g.died_pos(e) >= 0 then
            g.summon(g.ctrl(me), "FP1_014t")
            return
          end
        end
      end
    end,
  }
end

-- Zombie Chow: restore 5 Health to the enemy hero.
cards.FP1_001 = {
  deathrattle = function(g, me)
    g.heal(me, g.hero(g.enemy(me)), 5)
  end,
}

cards.FP1_002 = leaves("FP1_002t", "FP1_002t") -- Haunted Creeper: two 1/1 Spectral Spiders

-- Echoing Ooze: an exact copy of it at the end of the turn (none if it is gone or silenced by then).
cards.FP1_003 = {
  battlecry = function(g, me)
    g.enchant(me, { hooks = "ench:echoing_ooze", player = g.ctrl(me) })
  end,
}

cards["ench:echoing_ooze"] = {
  on = {
    turn_end = function(g, me)
      g.remove_enchant(me, "ench:echoing_ooze")
      local n = g.summon_right(me, g.card(me))
      if n then
        g.copy_minion(n, me)
      end
    end,
  },
}

-- Mad Scientist: a Secret from the deck into play (not one already there).
cards.FP1_004 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    local active = {}
    for _, s in ipairs(g.traps(p)) do
      active[g.card(s)] = true
    end
    local e = g.pick(only(g.deck(p), function(e)
      return g.info(g.card(e)).trap and not active[g.card(e)]
    end))
    if e then
      g.put_trap(e)
    end
  end,
}

-- Shade of Naxxramas: at the start of your turn, +1/+1.
cards.FP1_005 = on_mine("turn_start", function(g, me)
  g.buff(me, 1, 1)
end)

cards.FP1_007 = leaves("FP1_007t") -- Nerubian Egg: a 4/4 Nerubian

-- Deathlord: the opponent puts a minion from their deck into play.
cards.FP1_009 = {
  deathrattle = function(g, me)
    local e = g.pick(only(g.deck(g.enemy(me)), function(e)
      return g.type(e) == "MINION"
    end))
    if e then
      g.summon_entity(e)
    end
  end,
}

-- Webspinner: a random Beast card.
cards.FP1_011 = {
  deathrattle = function(g, me)
    local beasts = {}
    for _, c in ipairs(g.collectible()) do
      local i = g.info(c)
      if i.type == "MINION" and i.race == "BEAST" then
        beasts[#beasts + 1] = c
      end
    end
    local c = g.pick(beasts)
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

cards.FP1_012 = leaves("FP1_012t") -- Sludge Belcher: a 1/2 Slime with Taunt

-- Kel'Thuzad: at the end of each turn, summon all friendly minions that died this turn.
-- ponytail: in the order they entered play (= death order within a death phase); a later death phase's
-- minion that came into play earlier comes back first. A death sequence number would fix it.
cards.FP1_013 = {
  on = {
    turn_end = function(g, me)
      local p = g.ctrl(me)
      for _, e in ipairs(g.graveyard(p)) do
        if g.is_minion(e) and g.tag(e, "DIED_TURN") == g.turn() then
          g.summon(p, g.card(e))
        end
      end
    end,
  },
}

cards.FP1_014 = thaddius_if("FP1_015") -- Stalagg
cards.FP1_015 = thaddius_if("FP1_014") -- Feugen

-- Wailing Soul: Silence your other minions.
cards.FP1_016 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.others(me)) do
      g.silence(m)
    end
  end,
}

-- Nerub'ar Weblord: minions with Battlecry cost (2) more (both players').
cards.FP1_017 = {
  cost_aura = function(g, me, card, cost)
    if g.type(card) == "MINION" and has_keyword(g, g.card(card), "BATTLECRY") then
      return cost + 2
    end
    return cost
  end,
}

-- Duplicate: when a friendly minion dies, 2 copies of it into your hand.
cards.FP1_018 = {
  secret = {
    event = "death",
    cond = function(g, me, ev)
      return ev.minion and g.mine(me, ev)
    end,
    effect = function(g, me, ev)
      g.add_to_hand(g.ctrl(me), ev.card)
      g.add_to_hand(g.ctrl(me), ev.card)
    end,
  },
}

-- Poison Seeds: destroy all minions (their Deathrattles go first), then a 2/2 Treant for each, on its side.
cards.FP1_019 = {
  spell = function(g, me)
    local n0, n1 = 0, 0
    for _, m in ipairs(g.all_minions()) do
      if g.ctrl(m) == 0 then
        n0 = n0 + 1
      else
        n1 = n1 + 1
      end
      g.destroy(m)
    end
    g.resolve()
    for p = 0, 1 do
      for _ = 1, (p == 0 and n0 or n1) do
        g.summon(p, "FP1_019t")
      end
    end
  end,
}

-- A friendly minion of p that is alive (Avenge's condition: no randomness here).
local function any_alive(g, p)
  for _, m in ipairs(g.minions(p)) do
    if g.health(m) > 0 then
      return true
    end
  end
  return false
end

-- Avenge: when one of your minions dies, a random friendly minion gets +3/+2.
cards.FP1_020 = {
  secret = {
    event = "death",
    cond = function(g, me, ev)
      return ev.minion and g.mine(me, ev) and any_alive(g, g.ctrl(me))
    end,
    effect = function(g, me)
      g.buff(g.random_alive(g.minions(g.ctrl(me))), 3, 2)
    end,
  },
}

cards.FP1_021 = { deathrattle = one_to_all } -- Death's Bite

-- Voidcaller: a random Demon from your hand into play.
cards.FP1_022 = {
  deathrattle = function(g, me)
    local e = g.pick(only(g.hand(g.ctrl(me)), function(e)
      return g.type(e) == "MINION" and g.race(e) == "DEMON"
    end))
    if e then
      g.summon_entity(e)
    end
  end,
}

-- Dark Cultist: a random friendly minion gets +3 Health.
cards.FP1_023 = {
  deathrattle = function(g, me)
    g.buff(g.random_alive(g.minions(g.ctrl(me))), 0, 3)
  end,
}

cards.FP1_024 = { deathrattle = one_to_all } -- Unstable Ghoul

-- Reincarnate: destroy a minion (its Deathrattle goes first), then it comes back fresh, at the right.
cards.FP1_025 = {
  target = "minion",
  spell = function(g, me, t)
    local p, c = g.ctrl(t), g.card(t)
    g.destroy(t)
    g.resolve()
    g.summon(p, c)
  end,
}

-- Anub'ar Ambusher: a random friendly minion back to your hand.
cards.FP1_026 = {
  deathrattle = function(g, me)
    g.return_to_hand(g.random_alive(g.minions(g.ctrl(me))))
  end,
}

-- Stoneskin Gargoyle: at the start of your turn, back to full Health.
cards.FP1_027 = on_mine("turn_start", function(g, me)
  if g.dmg(me) > 0 then
    g.heal(me, me, g.dmg(me))
  end
end)

-- Undertaker (release, until January 2015): whenever you summon a minion with Deathrattle, +1/+1.
cards.FP1_028 = on_mine("summon", function(g, me, ev)
  if ev.entity ~= me and has_keyword(g, ev.card, "DEATHRATTLE") then
    g.buff(me, 1, 1)
  end
end)

-- Dancing Swords: your opponent draws a card.
cards.FP1_029 = {
  deathrattle = function(g, me)
    g.draw(g.enemy(me))
  end,
}

-- Loatheb: enemy spells cost (5) more next turn.
cards.FP1_030 = {
  battlecry = function(g, me)
    g.add_cost_mod(g.enemy(me), { kind = "spell", delta = 5, ["until"] = "turn_end", turn = g.turn() + 1 })
  end,
}

-- Baron Rivendare: your minions trigger their Deathrattles twice (DOUBLE_ON_DEATH on your champion).
cards.FP1_031 = {
  aura = function(g, me)
    g.aura_add(g.hero(g.ctrl(me)), 0, 0, { DOUBLE_DEATHRATTLE = true })
  end,
}

return cards
