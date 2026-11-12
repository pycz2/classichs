-- The League of Explorers (November 2015): the 45 cards and their 15 tokens as at the release (patch 4.0.0.10833 of
-- 2015-11-10, two days before the first wing; hearthstone.wiki.gg and its card notes; docs/packs/api.md). The Basic,
-- Classic, Naxxramas, Goblins vs Gnomes, Blackrock Mountain and Grand Tournament cards are those packs' scripts,
-- copied in by the recipe; the few of them that changed by then are at the end.
local cards = {}

-- --- helpers -----------------------------------------------------------------------------------

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }

local function playable(class)
  return list.any(CLASSES, function(c)
    return c == class
  end)
end

local function has_kw(info, kw)
  return list.any(info.keywords, function(k)
    return k == kw
  end)
end

-- A random collectible card whose data pass ok, or nil.
local function random_card(g, ok)
  return g.pick(list.filter(g.collectible(), function(c)
    return ok(g.info(c))
  end))
end

-- me's side has a minion other than me that passes ok(m).
local function have(g, me, ok)
  return list.any(g.minions(g.ctrl(me)), function(m)
    return m ~= me and ok(m)
  end)
end

local function race_is(g, race)
  return function(m)
    return g.race(m) == race
  end
end

local function random_enemy(g, me)
  return g.random_alive(g.chars(g.enemy(me)))
end

-- A death hook that summons card where me stood.
local function summon_here(g, me, card)
  local pos = g.died_pos(me)
  return g.summon(g.ctrl(me), card, pos >= 0 and pos or nil)
end

-- --- Discover ----------------------------------------------------------------------------------
-- Three different cards of a kind to choose from; the one chosen goes into the hand (a full hand burns it). The
-- pool: the collectible neutral cards and those of the class of its player's champion (a champion of no class,
-- Ragnaros: the Discover card's own class, or a random one), class cards four times as likely as neutral ones (as
-- in 2015: the class bonus went in 2019). A Discover card may offer itself (until 2020). Only its player sees the
-- options (g.create).

-- Up to three different items of pool ({card, weight} pairs), drawn by weight, offered to me's player.
local function offer(g, me, pool)
  local p = g.ctrl(me)
  local left = {}
  for _, x in ipairs(pool) do
    left[#left + 1] = x
  end
  local opts = {}
  for _ = 1, 3 do
    local total = list.sum(left, function(x)
      return x[2]
    end)
    if total <= 0 then
      break
    end
    local r = g.random(1, total)
    for i, x in ipairs(left) do
      r = r - x[2]
      if r <= 0 then
        opts[#opts + 1] = g.create(p, x[1])
        table.remove(left, i)
        break
      end
    end
  end
  if #opts > 0 then
    g.request_choice(me, opts)
  end
end

local function discover_class(g, me)
  local c = g.class(g.hero(g.ctrl(me)))
  if playable(c) then
    return c
  end
  c = g.info(g.card(me)).class
  if playable(c) then
    return c
  end
  return CLASSES[g.random(1, #CLASSES)]
end

-- Discover a card whose data pass ok.
local function discover(g, me, ok)
  local cls = discover_class(g, me)
  local pool = {}
  for _, c in ipairs(g.collectible()) do
    local i = g.info(c)
    if (i.class == cls or i.class == "NEUTRAL") and i.type ~= "CHAMPION" and i.type ~= "POWER" and ok(i) then
      pool[#pool + 1] = { c, i.class == cls and 4 or 1 }
    end
  end
  offer(g, me, pool)
end

local function to_hand(g, me, option)
  g.add_to_hand(g.ctrl(me), g.card(option))
end

-- A minion whose Battlecry Discovers a card passing ok.
local function discover_battlecry(ok)
  return {
    battlecry = function(g, me)
      discover(g, me, ok)
    end,
    on_choose = to_hand,
  }
end

local function cost_is(n)
  return function(i)
    return i.cost == n
  end
end

local function is_type(t)
  return function(i)
    return i.type == t
  end
end

-- --- Discover cards ----------------------------------------------------------------------------

cards.LOE_003 = discover_battlecry(is_type("SPELL")) -- Ethereal Conjurer
cards.LOE_006 = discover_battlecry(function(i) -- Museum Curator: any card with a Deathrattle (weapons too)
  return has_kw(i, "DEATHRATTLE")
end)
cards.LOE_023 = discover_battlecry(cost_is(1)) -- Dark Peddler
cards.LOE_029 = discover_battlecry(cost_is(3)) -- Jeweled Scarab
cards.LOE_047 = discover_battlecry(function(i) -- Tomb Spider
  return i.type == "MINION" and i.race == "BEAST"
end)

local function is_mech(i)
  return i.type == "MINION" and i.race == "MECHANICAL"
end

-- Gorillabot A-3: if you control another Mech, Discover a Mech (it glows in the hand while you control one).
cards.LOE_039 = {
  battlecry = function(g, me)
    if have(g, me, race_is(g, "MECHANICAL")) then
      discover(g, me, is_mech)
    end
  end,
  on_choose = to_hand,
  glow = function(g, me)
    return have(g, me, race_is(g, "MECHANICAL"))
  end,
}

-- Raven Idol: Choose One - Discover a minion; or Discover a spell.
cards.LOE_115 = { choose_one = { "LOE_115a", "LOE_115b" }, on_choose = to_hand }
cards.LOE_115a = {
  effect = function(g, me)
    discover(g, me, is_type("MINION"))
  end,
}
cards.LOE_115b = {
  effect = function(g, me)
    discover(g, me, is_type("SPELL"))
  end,
}

-- Sir Finley Mrrgglton: Discover a basic Hero Power other than the one you have (an upgraded or other power: any of
-- the nine); it replaces yours, ready to use.
local BASIC_POWERS = { "VAN_HERO_06bp", "VAN_HERO_05bp", "VAN_HERO_08bp", "VAN_HERO_04bp", "VAN_HERO_09bp",
  "VAN_HERO_03bp", "VAN_HERO_02bp", "VAN_HERO_07bp", "VAN_HERO_01bp" }
cards.LOE_076 = {
  battlecry = function(g, me)
    local now = g.card(g.power(g.ctrl(me)))
    local pool = {}
    for _, c in ipairs(BASIC_POWERS) do
      if c ~= now then
        pool[#pool + 1] = { c, 1 }
      end
    end
    offer(g, me, pool)
  end,
  on_choose = function(g, me, option)
    g.set_power(g.ctrl(me), g.card(option))
  end,
}

-- Arch-Thief Rafaam: Discover one of the three Legendary Artifacts.
cards.LOE_092 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    g.request_choice(me, { g.create(p, "LOEA16_3"), g.create(p, "LOEA16_4"), g.create(p, "LOEA16_5") })
  end,
  on_choose = to_hand,
}

-- Lantern of Power: a minion +10/+10.
cards.LOEA16_3 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 10, 10)
  end,
}

-- Timepiece of Horror: 10 missiles of 1 damage at random enemies (spell power adds missiles).
cards.LOEA16_4 = {
  spell = function(g, me)
    for _ = 1, g.spell_dmg(me, 10) do
      g.damage(me, random_enemy(g, me), 1)
    end
  end,
}

-- Mirror of Doom: fill your board with 3/3 Mummy Zombies.
cards.LOEA16_5 = {
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
  spell = function(g, me)
    local p = g.ctrl(me)
    while g.room(p) > 0 do
      g.summon(p, "LOEA16_5t")
    end
  end,
}

-- --- Explorers ---------------------------------------------------------------------------------

-- Reno Jackson: if your deck has no two copies of a card, restore your hero's maximum Health (with Auchenai
-- Soulpriest: that much damage). It glows in the hand while that holds (a later client's help, not in 2015).
local function no_duplicates(g, p)
  local seen = {}
  for _, e in ipairs(g.deck(p)) do
    local c = g.card(e)
    if seen[c] then
      return false
    end
    seen[c] = true
  end
  return true
end

cards.LOE_011 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if no_duplicates(g, p) then
      g.heal(me, g.hero(p), g.max_health(g.hero(p)))
    end
  end,
  glow = function(g, me)
    return no_duplicates(g, g.ctrl(me))
  end,
}

-- Brann Bronzebeard: your Battlecries trigger twice (DOUBLE_BATTLECRY on your hero).
cards.LOE_077 = {
  aura = function(g, me)
    g.aura_add(g.hero(g.ctrl(me)), 0, 0, { DOUBLE_BATTLECRY = true })
  end,
}

-- Elise Starseeker: shuffle the Map to the Golden Monkey into your deck.
cards.LOE_079 = {
  battlecry = function(g, me)
    g.add_to_deck(g.ctrl(me), "LOE_019t")
  end,
}

-- Map to the Golden Monkey: shuffle the Golden Monkey into your deck, then draw (it may be the Monkey).
cards.LOE_019t = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.add_to_deck(p, "LOE_019t2")
    g.draw(p)
  end,
}

-- Golden Monkey: every card in your hand and deck becomes a random collectible Legendary minion (repeats possible;
-- the hand keeps its size and order).
cards.LOE_019t2 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local pool = list.filter(g.collectible(), function(c)
      local i = g.info(c)
      return i.type == "MINION" and i.rarity == "LEGENDARY"
    end)
    local hand, deck = g.hand(p), g.deck(p)
    for _, e in ipairs(hand) do
      g.remove(e, "SETASIDE")
    end
    for _ = 1, #hand do
      g.add_to_hand(p, g.pick(pool))
    end
    for _, e in ipairs(deck) do
      g.remove(e, "SETASIDE")
    end
    for _ = 1, #deck do
      g.add_to_deck(p, g.pick(pool))
    end
  end,
}

-- --- Druid -------------------------------------------------------------------------------------

-- Mounted Raptor: Deathrattle: a random 1-Cost minion.
cards.LOE_050 = {
  deathrattle = function(g, me)
    local c = random_card(g, function(i)
      return i.type == "MINION" and i.cost == 1
    end)
    if c then
      summon_here(g, me, c)
    end
  end,
}

-- Jungle Moonkin: Spell Damage +2 (its own, by its data) and +2 for the opponent too (on their hero).
cards.LOE_051 = {
  aura = function(g, me)
    g.aura_add(g.hero(g.enemy(me)), 0, 0, { SPELLPOWER = 2 })
  end,
}

-- --- Hunter ------------------------------------------------------------------------------------

-- Desert Camel: a minion of base Cost 1 from each deck into play (yours first); none in a deck: none for that side.
cards.LOE_020 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _, q in ipairs({ p, g.opponent(p) }) do
      local e = g.pick(list.filter(g.deck(q), function(c)
        local i = g.info(g.card(c))
        return i.type == "MINION" and i.cost == 1
      end))
      if e and g.room(q) > 0 then
        g.summon_entity(e)
      end
    end
  end,
}

-- Dart Trap: after an opposing Hero Power is used, 5 damage (spell power adds) to a random enemy.
cards.LOE_021 = {
  secret = {
    event = "hero_power",
    cond = function(g, me, ev)
      return not g.mine(me, ev)
    end,
    effect = function(g, me)
      g.damage(me, random_enemy(g, me), g.spell_dmg(me, 5))
    end,
  },
}

-- Explorer's Hat: a minion +1/+1 and "Deathrattle: add an Explorer's Hat to your hand" (its controller's when it
-- dies; each Hat its own).
cards.LOE_105 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 1, 1)
    g.enchant(t, { hooks = "ench:explorers_hat" })
  end,
}
cards["ench:explorers_hat"] = {
  deathrattle = function(g, me)
    g.add_to_hand(g.ctrl(me), "LOE_105")
  end,
}

-- --- Mage --------------------------------------------------------------------------------------

-- Forgotten Torch: 3 damage, then a Roaring Torch (6 damage) into your deck.
cards.LOE_002 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 3))
    g.add_to_deck(g.ctrl(me), "LOE_002t")
  end,
}
cards.LOE_002t = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 6))
  end,
}

-- Animated Armor: your hero takes at most 1 damage at a time (with Cursed Blade: Cursed Blade does both, in order).
local function wields(g, p, card)
  local w = g.weapon(p)
  return w ~= nil and g.card(w) == card
end

local function armored(g, p)
  return list.any(g.minions(p), function(m)
    return g.card(m) == "LOE_119" and not g.silenced(m)
  end)
end

cards.LOE_119 = {
  now = {
    predamage = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.target == g.hero(p) and ev.amount > 1 and not wields(g, p, "LOE_118") then
        ev.amount = 1
      end
    end,
  },
}

-- --- Paladin -----------------------------------------------------------------------------------

-- Keeper of Uldaman: a minion's Attack and Health become 3.
cards.LOE_017 = {
  target = "minion",
  battlecry = function(g, me, t)
    g.set_stats(t, 3, 3)
  end,
}

-- Anyfin Can Happen: up to 7 random Murlocs of those that died this game (both sides; each as often as it died).
cards.LOE_026 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local dead = {}
    for _, q in ipairs({ 0, 1 }) do
      for _, e in ipairs(g.graveyard(q)) do
        if g.died_pos(e) >= 0 and g.race(e) == "MURLOC" then
          dead[#dead + 1] = g.card(e)
        end
      end
    end
    g.shuffle(dead)
    for i = 1, math.min(#dead, 7) do
      if g.room(p) <= 0 then
        break
      end
      g.summon(p, dead[i])
    end
  end,
}

-- Sacred Trial: after your opponent plays a minion while they have at least 3 others, destroy it.
cards.LOE_027 = {
  secret = {
    event = "after_summon",
    cond = function(g, me, ev)
      return ev.played and not g.mine(me, ev) and #g.others(ev.entity) >= 3
    end,
    effect = function(g, me, ev)
      g.destroy(ev.entity)
    end,
  },
}

-- --- Priest ------------------------------------------------------------------------------------

-- Entomb: an enemy minion (as it is now, a fresh card) shuffled into your deck; it leaves play without dying.
cards.LOE_104 = {
  target = "enemy_minion",
  spell = function(g, me, t)
    local c = g.card(t)
    g.remove(t, "SETASIDE")
    g.add_to_deck(g.ctrl(me), c)
  end,
}

-- Excavated Evil: 3 damage to all minions, then it is shuffled into your opponent's deck.
cards.LOE_111 = {
  spell = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      g.damage(me, m, g.spell_dmg(me, 3))
    end
    g.add_to_deck(g.enemy(me), "LOE_111")
  end,
}

-- --- Rogue -------------------------------------------------------------------------------------

-- Tomb Pillager: Deathrattle: a Coin into your hand.
cards.LOE_012 = {
  deathrattle = function(g, me)
    g.add_to_hand(g.ctrl(me), "GAME_005")
  end,
}

-- Unearthed Raptor: a copy of a friendly minion's Deathrattle (its card's own, unless silenced).
cards.LOE_019 = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t)
      return t ~= me and not g.silenced(t) and has_kw(g.info(g.card(t)), "DEATHRATTLE")
    end,
  },
  battlecry = function(g, me, t)
    g.enchant(me, { deathrattle = g.card(t) })
  end,
}

-- --- Shaman ------------------------------------------------------------------------------------

-- Rumbling Elemental: after you play a Battlecry minion (still in play), 2 damage to a random enemy.
cards.LOE_016 = {
  on = {
    after_summon = function(g, me, ev)
      if ev.played and g.mine(me, ev) and ev.entity ~= me and has_kw(g.info(ev.card), "BATTLECRY") then
        g.damage(me, random_enemy(g, me), 2)
      end
    end,
  },
}

-- Tunnel Trogg: whenever you Overload, +1 Attack per Mana Crystal it locks (a countered spell locks none).
local function trogg(g, me, ev)
  local n = g.info(ev.card).mana_lock
  if g.mine(me, ev) and n > 0 then
    g.buff(me, n, 0)
  end
end
cards.LOE_018 = {
  on = {
    play = function(g, me, ev)
      if ev.kind ~= "spell" and ev.entity ~= me then
        trogg(g, me, ev)
      end
    end,
    after_spell = trogg,
  },
}

-- Everyfin is Awesome: your minions +2/+2; costs (1) less per Murloc you control.
cards.LOE_113 = {
  cost_mod = function(g, me)
    return -list.count(g.minions(g.ctrl(me)), function(m)
      return g.race(m) == "MURLOC"
    end)
  end,
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.buff(m, 2, 2)
    end
  end,
}

-- --- Warlock -----------------------------------------------------------------------------------

-- Curse of Rafaam: your opponent gets a Cursed!
cards.LOE_007 = {
  spell = function(g, me)
    g.add_to_hand(g.enemy(me), "LOE_007t")
  end,
}

-- Cursed!: while it is in your hand, 2 damage to you at the start of your turn (playing it only gets rid of it).
cards.LOE_007t = {
  hand = {
    turn_start = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.player == p then
        g.damage(me, g.hero(p), 2)
      end
    end,
  },
}

-- Reliquary Seeker: with 6 other minions, +4/+4 (glows while you have six).
cards.LOE_116 = {
  battlecry = function(g, me)
    if #g.others(me) >= 6 then
      g.buff(me, 4, 4)
    end
  end,
  glow = function(g, me)
    return #g.minions(g.ctrl(me)) >= 6
  end,
}

-- --- Warrior -----------------------------------------------------------------------------------

-- Obsidian Destroyer: at the end of your turn, a 1/1 Scarab with Taunt.
cards.LOE_009 = {
  on = {
    turn_end = function(g, me, ev)
      if g.mine(me, ev) then
        g.summon_right(me, "LOE_009t")
      end
    end,
  },
}

-- Cursed Blade: damage to your hero is doubled, after everything else (Animated Armor first: 1, then 2).
cards.LOE_118 = {
  now = {
    predamage = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.target == g.hero(p) then
        local n = ev.amount
        if armored(g, p) then
          n = math.min(n, 1)
        end
        ev.amount = n * 2
      end
    end,
  },
}

-- --- Neutral -----------------------------------------------------------------------------------

-- Ancient Shade: an Ancient Curse into your deck. Ancient Curse: when you draw it, 7 damage to you, it goes away and
-- you draw a card (played as a copy, it does nothing).
cards.LOE_110 = {
  battlecry = function(g, me)
    g.add_to_deck(g.ctrl(me), "LOE_110t")
  end,
}
cards.LOE_110t = {
  hand = {
    draw = function(g, me, ev)
      if ev.entity == me then
        local p = g.ctrl(me)
        g.damage(me, g.hero(p), 7)
        g.remove(me, "GRAVEYARD")
        g.draw(p)
      end
    end,
  },
}

-- Naga Sea Witch: your cards cost (5) (an aura in play order with the other cost changes, as until 2017).
cards.LOE_038 = {
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.zone(card) == "HAND" then
      return 5
    end
    return cost
  end,
}

-- Huge Toad: Deathrattle: 1 damage to a random enemy.
cards.LOE_046 = {
  deathrattle = function(g, me)
    g.damage(me, random_enemy(g, me), 1)
  end,
}

-- Djinni of Zephyrs: whenever you cast a spell on another friendly minion, a copy of it is cast on this one after
-- it (not when countered; the target must still be yours; its Choose One option and Combo as cast).
cards.LOE_053 = {
  on = {
    play = function(g, me, ev)
      if ev.kind == "spell" and g.mine(me, ev) and ev.target >= 0 and ev.target ~= me and g.is_minion(ev.target) then
        g.set_tag(ev.entity, "ZEPHYR_TARGET", ev.target)
      end
    end,
    after_spell = function(g, me, ev)
      local t = g.tag(ev.entity, "ZEPHYR_TARGET")
      if g.mine(me, ev) and t > 0 and g.ctrl(t) == g.ctrl(me) then
        g.cast(me, ev.entity, me)
      end
    end,
  },
}

-- Anubisath Sentinel: Deathrattle: a random friendly minion +3/+3.
cards.LOE_061 = {
  deathrattle = function(g, me)
    g.buff(g.random_alive(g.minions(g.ctrl(me))), 3, 3)
  end,
}

-- Fossilized Devilsaur: if you control a Beast, Taunt (it is no Beast itself; glows while you have one).
cards.LOE_073 = {
  battlecry = function(g, me)
    if have(g, me, race_is(g, "BEAST")) then
      g.give_tag(me, "TAUNT")
    end
  end,
  glow = function(g, me)
    return have(g, me, race_is(g, "BEAST"))
  end,
}

-- Summoning Stone: whenever you cast a spell, a random minion whose base Cost is the mana paid for it.
cards.LOE_086 = {
  on = {
    play = function(g, me, ev)
      if ev.kind == "spell" and g.mine(me, ev) and not ev.countered then
        local paid = g.tag(ev.entity, "PLAYED_COST")
        local c = random_card(g, function(i)
          return i.type == "MINION" and i.cost == paid
        end)
        if c then
          g.summon(g.ctrl(me), c)
        end
      end
    end,
  },
}

-- Wobbling Runts: Deathrattle: three 2/2 Runts.
cards.LOE_089 = {
  deathrattle = function(g, me)
    for _, c in ipairs({ "LOE_089t", "LOE_089t2", "LOE_089t3" }) do
      summon_here(g, me, c)
    end
  end,
}

-- Eerie Statue: can't attack unless it is the only minion in the battlefield.
cards.LOE_107 = {
  aura = function(g, me)
    if #g.all_minions() > 1 then
      g.aura_add(me, 0, 0, { CANT_ATTACK = true })
    end
  end,
}

-- --- older cards as on 2015-11-12 --------------------------------------------------------------

-- Warsong Commander (patch 3.2.0.10604 of 2015-10-20): your Charge minions have +1 Attack.
cards.VAN_EX1_084 = {
  aura = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if g.has(m, "CHARGE") then
        g.aura_add(m, 1, 0)
      end
    end
  end,
}

-- Bear Trap: after your hero is attacked, an Ironfur Grizzly; with a full board it does not go off (patch 4.0.0.10833).
cards.AT_060 = {
  secret = {
    event = "after_attack",
    cond = function(g, me, ev)
      return ev.defender == g.hero(g.ctrl(me)) and g.room(g.ctrl(me)) > 0
    end,
    effect = function(g, me)
      g.summon(g.ctrl(me), "VAN_CS2_125")
    end,
  },
}

-- Duplicate: when a friendly minion dies, 2 copies of it into your hand; with a full hand it does not go off (patch
-- 4.0.0.10833).
cards.FP1_018 = {
  secret = {
    event = "death",
    cond = function(g, me, ev)
      return ev.minion and g.mine(me, ev) and #g.hand(g.ctrl(me)) < g.rule("hand")
    end,
    effect = function(g, me, ev)
      g.add_to_hand(g.ctrl(me), ev.card)
      g.add_to_hand(g.ctrl(me), ev.card)
    end,
  },
}

return cards
