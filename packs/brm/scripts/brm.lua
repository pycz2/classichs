-- Blackrock Mountain (April 2015): the 31 cards and their tokens, as at the release (patch 2.4.0.8311 of
-- 2015-03-31, two days before the first wing; docs/packs/api.md). The Basic, Classic, Naxxramas and Goblins vs
-- Gnomes cards are those packs' scripts, copied in by the recipe; the few of them changed by then are at the end.
local cards = {}

-- --- helpers -----------------------------------------------------------------------------------

-- The items of a list that pass ok(e).
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

-- Collectible cards of the constructed sets whose data pass ok(info).
local function collectible(g, ok)
  return only(g.collectible(), function(c)
    return ok(g.info(c))
  end)
end

-- "If you're holding a Dragon": another card in me's controller's hand is a Dragon.
local function holding_dragon(g, me)
  for _, c in ipairs(g.hand(g.ctrl(me))) do
    if c ~= me and g.race(c) == "DRAGON" then
      return true
    end
  end
  return false
end

-- "If your hand is empty" (glow: this card is the only one in it).
local function hand_empty(g, me)
  for _, c in ipairs(g.hand(g.ctrl(me))) do
    if c ~= me then
      return false
    end
  end
  return true
end

-- How many minions died this turn (both sides; DIED_TURN is written because the pack names it).
local function died_this_turn(g)
  local n = 0
  for p = 0, 1 do
    for _, e in ipairs(g.graveyard(p)) do
      if g.died_pos(e) >= 0 and g.tag(e, "DIED_TURN") == g.turn() then
        n = n + 1
      end
    end
  end
  return n
end

-- "Costs (1) less for each minion that died this turn."
local function vigil_cost(g, me)
  return -died_this_turn(g)
end

-- "Whenever this minion takes damage": f(g, me) after each damage it takes (Divine Shield: no damage).
local function on_hurt(f)
  return {
    on = {
      damage = function(g, me, ev)
        if ev.target == me and ev.amount > 0 then
          f(g, me)
        end
      end,
    },
  }
end

-- A minion for me's side right of me (where it stood if it already left the board).
local function summon_beside(g, me, card)
  if g.board_pos(me) then
    return g.summon_right(me, card)
  end
  local pos = g.died_pos(me)
  return g.summon(g.ctrl(me), card, pos >= 0 and pos or nil)
end

-- --- Druid -------------------------------------------------------------------------------------

-- Volcanic Lumberer: Taunt; costs (1) less for each minion that died this turn.
cards.BRM_009 = { cost_mod = vigil_cost }

-- Druid of the Flame: Choose One - a 5/2 or a 2/5.
cards.BRM_010 = { choose_one = { "BRM_010a", "BRM_010b" } }
cards.BRM_010a = {
  effect = function(g, me)
    g.transform(me, "BRM_010t")
  end,
}
cards.BRM_010b = {
  effect = function(g, me)
    g.transform(me, "BRM_010t2")
  end,
}

-- --- Hunter ------------------------------------------------------------------------------------

-- Quick Shot: 3 damage (its damage triggers first); then, if your hand is empty, draw a card.
cards.BRM_013 = {
  target = "any",
  glow = hand_empty,
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 3))
    g.resolve()
    local p = g.ctrl(me)
    if #g.hand(p) == 0 then
      g.draw(p)
    end
  end,
}

-- Core Rager: if your hand is empty, +3/+3.
cards.BRM_014 = {
  glow = hand_empty,
  battlecry = function(g, me)
    if #g.hand(g.ctrl(me)) == 0 then
      g.buff(me, 3, 3)
    end
  end,
}

-- --- Mage --------------------------------------------------------------------------------------

-- Flamewaker: after you cast a spell, 2 damage randomly split among all enemies (one at a time; a character
-- already dying is not hit).
cards.BRM_002 = on_mine("after_spell", function(g, me)
  for _ = 1, 2 do
    local t = g.random_alive(g.chars(g.enemy(me)))
    if not t then
      return
    end
    g.damage(me, t, 1)
  end
end)

-- Dragon's Breath: 4 damage; costs (1) less for each minion that died this turn.
cards.BRM_003 = {
  target = "any",
  cost_mod = vigil_cost,
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
  end,
}

-- --- Paladin -----------------------------------------------------------------------------------

-- Solemn Vigil: draw 2 cards; costs (1) less for each minion that died this turn.
cards.BRM_001 = {
  cost_mod = vigil_cost,
  spell = function(g, me)
    g.draw(g.ctrl(me), 2)
  end,
}

-- Dragon Consort: the next Dragon you play costs (2) less (on any later turn too, until a Dragon is played).
cards.BRM_018 = {
  battlecry = function(g, me)
    g.add_cost_mod(g.ctrl(me), { kind = "minion", race = "DRAGON", delta = -2, ["until"] = "use", lasting = true })
  end,
}

-- --- Priest ------------------------------------------------------------------------------------

-- Twilight Whelp: if you're holding a Dragon, +2 Health.
cards.BRM_004 = {
  glow = holding_dragon,
  battlecry = function(g, me)
    if holding_dragon(g, me) then
      g.buff(me, 0, 2)
    end
  end,
}

-- Resurrect: a random friendly minion that died this game (each death one chance; 2015: playable with none).
cards.BRM_017 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local dead = only(g.graveyard(p), function(e)
      return g.died_pos(e) >= 0 and g.type(e) == "MINION"
    end)
    local e = g.pick(dead)
    if e then
      g.summon(p, g.card(e))
    end
  end,
}

-- --- Rogue -------------------------------------------------------------------------------------

-- Gang Up: shuffle 3 copies of a minion into your deck.
cards.BRM_007 = {
  target = "minion",
  spell = function(g, me, t)
    local c = g.card(t)
    for _ = 1, 3 do
      g.add_to_deck(g.ctrl(me), c)
    end
  end,
}

-- Dark Iron Skulker: 2 damage to each undamaged enemy minion; in 2015 one after another, each hit's triggers
-- resolving before the next (patch 5.0.0.12574 made it one area hit).
cards.BRM_008 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      if g.zone(m) == "PLAY" and g.health(m) > 0 and g.dmg(m) == 0 then
        g.damage(me, m, 2)
        g.resolve()
      end
    end
  end,
}

-- --- Shaman ------------------------------------------------------------------------------------

-- Lava Shock: 2 damage, then your Overloaded crystals are unlocked.
cards.BRM_011 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
    g.resolve()
    g.unlock_mana(g.ctrl(me))
  end,
}

-- Fireguard Destroyer: gain 1-4 Attack (Overload: (1) is its data).
cards.BRM_012 = {
  battlecry = function(g, me)
    g.buff(me, g.random(1, 4), 0)
  end,
}

-- --- Warlock -----------------------------------------------------------------------------------

-- Demonwrath: 2 damage to all non-Demon minions.
cards.BRM_005 = {
  spell = function(g, me)
    local n = g.spell_dmg(me, 2)
    for _, m in ipairs(g.all_minions()) do
      if g.race(m) ~= "DEMON" then
        g.damage(me, m, n)
      end
    end
  end,
}

-- Imp Gang Boss: whenever it takes damage, a 1/1 Imp.
cards.BRM_006 = on_hurt(function(g, me)
  summon_beside(g, me, "BRM_006t")
end)

-- --- Warrior -----------------------------------------------------------------------------------

-- Revenge: 1 damage to all minions; 3 if you have 12 or less Health.
local function revenge_low(g, me)
  return g.health(g.hero(g.ctrl(me))) <= 12
end
cards.BRM_015 = {
  glow = revenge_low,
  spell = function(g, me)
    local n = g.spell_dmg(me, revenge_low(g, me) and 3 or 1)
    for _, m in ipairs(g.all_minions()) do
      g.damage(me, m, n)
    end
  end,
}

-- Axe Flinger: whenever it takes damage, 2 damage to the enemy hero.
cards.BRM_016 = on_hurt(function(g, me)
  g.damage(me, g.hero(g.enemy(me)), 2)
end)

-- --- Neutral -----------------------------------------------------------------------------------

-- Grim Patron: whenever it survives damage, another Grim Patron (checked when its trigger runs: one that is
-- dying or already destroyed by then summons none).
cards.BRM_019 = on_hurt(function(g, me)
  if g.zone(me) == "PLAY" and g.health(me) > 0 and not g.has(me, "TO_DESTROY") then
    g.summon_right(me, "BRM_019")
  end
end)

-- Dragonkin Sorcerer: whenever you target it with a spell, +1/+1 (as the spell is cast, before it resolves).
cards.BRM_020 = {
  on = {
    play = function(g, me, ev)
      if ev.kind == "spell" and ev.target == me and g.mine(me, ev) then
        g.buff(me, 1, 1)
      end
    end,
  },
}

-- Dragon Egg: whenever it takes damage, a 2/1 Black Whelp.
cards.BRM_022 = on_hurt(function(g, me)
  summon_beside(g, me, "BRM_022t")
end)

-- Drakonid Crusher: if your opponent has 15 or less Health, +3/+3.
local function foe_low(g, me)
  return g.health(g.hero(g.enemy(me))) <= 15
end
cards.BRM_024 = {
  glow = foe_low,
  battlecry = function(g, me)
    if foe_low(g, me) then
      g.buff(me, 3, 3)
    end
  end,
}

-- Volcanic Drake: costs (1) less for each minion that died this turn.
cards.BRM_025 = { cost_mod = vigil_cost }

-- Hungry Dragon: a random 1-Cost minion for your opponent.
cards.BRM_026 = {
  battlecry = function(g, me)
    local c = g.pick(collectible(g, function(i)
      return i.type == "MINION" and i.cost == 1
    end))
    if c then
      g.summon(g.enemy(me), c)
    end
  end,
}

-- Majordomo Executus: your hero becomes Ragnaros the Firelord (8 Health, DIE, INSECT!); Armor and Immune go with
-- the old hero, the weapon and Secrets stay.
cards.BRM_027 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    g.replace_hero(p, "BRM_027h")
    g.set_power(p, "BRM_027p")
  end,
}

-- DIE, INSECT!: 8 damage to a random enemy.
cards.BRM_027p = {
  hero_power = function(g, me)
    g.damage(me, g.random_alive(g.chars(g.enemy(me))), g.hp_dmg(me, 8))
  end,
}

-- Emperor Thaurissan: at the end of your turn, the cards in your hand cost (1) less (the enchantments stay).
cards.BRM_028 = on_mine("turn_end", function(g, me)
  for _, c in ipairs(g.hand(g.ctrl(me))) do
    g.enchant(c, { cost = -1 })
  end
end)

-- Rend Blackhand: if you're holding a Dragon, destroy a Legendary minion (not himself; with no Dragon, no target).
cards.BRM_029 = {
  glow = holding_dragon,
  target = { base = "minion", when = holding_dragon, filter = function(g, me, t)
    return t ~= me and g.info(g.card(t)).rarity == "LEGENDARY"
  end },
  battlecry = function(g, me, t)
    if t then
      g.destroy(t)
    end
  end,
}

-- Nefarian: 2 random spells of your opponent's class (Tail Swipes against a hero without a class: Ragnaros).
cards.BRM_030 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local class = g.class(g.hero(g.enemy(me)))
    local pool = collectible(g, function(i)
      return i.type == "SPELL" and i.class == class
    end)
    for _ = 1, 2 do
      g.add_to_hand(p, (class ~= "" and class ~= "NEUTRAL" and g.pick(pool)) or "BRM_030t")
    end
  end,
}

-- Tail Swipe: 4 damage.
cards.BRM_030t = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
  end,
}

-- Chromaggus: whenever you draw a card, another copy into your hand (a burned card is no draw).
cards.BRM_031 = on_mine("draw", function(g, me, ev)
  g.add_to_hand(g.ctrl(me), ev.card)
end)

-- Blackwing Technician: if you're holding a Dragon, +1/+1.
cards.BRM_033 = {
  glow = holding_dragon,
  battlecry = function(g, me)
    if holding_dragon(g, me) then
      g.buff(me, 1, 1)
    end
  end,
}

-- Blackwing Corruptor: if you're holding a Dragon, 3 damage (a target only then).
cards.BRM_034 = {
  glow = holding_dragon,
  target = { base = "any", when = holding_dragon },
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, 3)
    end
  end,
}

-- --- Older cards as on 2015-04-02 --------------------------------------------------------------

-- Undertaker (patch 2.1.0.7628, 2015-01-29): +1 Attack (was +1/+1).
cards.FP1_028 = on_mine("summon", function(g, me, ev)
  if ev.entity ~= me then
    for _, k in ipairs(g.info(ev.card).keywords) do
      if k == "DEATHRATTLE" then
        g.buff(me, 1, 0)
        return
      end
    end
  end
end)

-- Bane of Doom (patch 2.4.0.8311): if that kills it, a random collectible Demon (was a few Basic and Classic ones).
cards.VAN_EX1_320 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
    if g.zone(t) == "PLAY" and g.health(t) <= 0 then
      local c = g.pick(collectible(g, function(i)
        return i.type == "MINION" and i.race == "DEMON"
      end))
      if c then
        g.summon(g.ctrl(me), c)
      end
    end
  end,
}

-- Houndmaster (patch 2.4.0.8311 lights it while you have a Beast): a friendly Beast +2/+2 and Taunt.
local function is_beast(g, me, t)
  return g.race(t) == "BEAST"
end
cards.VAN_DS1_070 = {
  glow = function(g, me)
    return #only(g.minions(g.ctrl(me)), function(m)
      return g.race(m) == "BEAST"
    end) > 0
  end,
  target = { base = "friendly_minion", filter = is_beast },
  battlecry = function(g, me, t)
    g.buff(t, 2, 2)
    g.give_tag(t, "TAUNT")
  end,
}

-- Screwjank Clunker (patch 2.4.0.8311 lights it while you have a Mech): a friendly Mech +2/+2.
cards.GVG_055 = {
  glow = function(g, me)
    return #only(g.minions(g.ctrl(me)), function(m)
      return m ~= me and g.race(m) == "MECHANICAL"
    end) > 0
  end,
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me and g.race(t) == "MECHANICAL"
  end },
  battlecry = function(g, me, t)
    g.buff(t, 2, 2)
  end,
}

return cards
