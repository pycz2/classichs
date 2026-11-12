-- Journey to Un'Goro (April 2017): the 135 cards and their tokens as at the release (patch 8.0.0.18336 of 2017-04-04,
-- two days before the release; hearthstone.wiki.gg and its card notes; docs/packs/api.md). The older sets' cards are
-- those packs' scripts, copied in by the recipe; the ones that changed by then are in cards.patch.json (patch 7.1.0.17720
-- of February 2017: Small-Time Buccaneer 1 Health, Spirit Claws 2 mana; patch 8.0: the Elemental tribe of older minions).
--
-- New here: Adapt (three of ten upgrades to choose from, only its player sees them), Quests (a TASK card: it starts in the
-- opening hand, waits in the Secret zone in sight of both players and counts toward its goal, then its reward goes to the
-- hand), "if you played an Elemental last turn" (each player's counts of Elementals played this turn and the last), the
-- Dormant Sherazin seed and Nether Portal (DORMANT), Time Warp's extra turn (g.extra_turn) and Swamp King Dred's attack
-- (g.force_attack).
local cards = {}

-- --- helpers -----------------------------------------------------------------------------------

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local RECRUIT = "VAN_CS2_101t"
local COIN = "GAME_005"

local function playable(class)
  return list.any(CLASSES, function(c)
    return c == class
  end)
end

-- A card (its g.info) of the class: a tri-class card is one of each of its classes (cards.md `classes`).
local function of_class(i, cls)
  if i.classes then
    return list.any(i.classes, function(c)
      return c == cls
    end)
  end
  return i.class == cls
end

local function is_neutral(i)
  return i.class == "NEUTRAL" and not i.classes
end

local function has_kw(i, k)
  return list.any(i.keywords, function(x)
    return x == k
  end)
end

local function not_hero(i)
  return i.type ~= "CHAMPION" and i.type ~= "POWER"
end

-- The collectible cards (of the pack's constructed sets) whose data pass ok.
local function pool(g, ok)
  return list.filter(g.collectible(), function(c)
    return ok(g.info(c))
  end)
end

local function random_card(g, ok)
  return g.pick(pool(g, function(i)
    return not_hero(i) and ok(i)
  end))
end

-- An entity's card data.
local function info(g, e)
  return g.info(g.card(e))
end

-- Alive: not dying.
local function alive(g, m)
  return g.zone(m) == "PLAY" and g.health(m) > 0 and not g.has(m, "TO_DESTROY")
end

local function summon_here(g, me, card)
  local pos = g.died_pos(me)
  return g.summon(g.ctrl(me), card, pos >= 0 and pos or nil)
end

-- Up to n different random items of a list.
local function pick_n(g, items, n)
  local left = {}
  for _, x in ipairs(items) do
    left[#left + 1] = x
  end
  local out = {}
  for _ = 1, n do
    if #left == 0 then
      break
    end
    local i = g.random(1, #left)
    out[#out + 1] = left[i]
    table.remove(left, i)
  end
  return out
end

-- The minions of p's hand (passing ok, if given).
local function hand_minions(g, p, ok)
  return list.filter(g.hand(p), function(e)
    return g.is_minion(e) and (not ok or ok(e))
  end)
end

-- "If you played an Elemental last turn" (the player hooks keep the counts: ELEM_NOW, ELEM_LAST).
local function elemental_last_turn(g, p)
  return g.count(p, "ELEM_LAST") > 0
end

local function elemental_glow(g, me)
  return elemental_last_turn(g, g.ctrl(me))
end

-- --- Discover (2017: the class cards four times as likely as the neutral ones; a tri-class card is a class card) ---

local function offer(g, me, choices)
  local p = g.ctrl(me)
  local left = {}
  for _, x in ipairs(choices) do
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
  return #opts
end

local function discover_class(g, me)
  local c = g.class(g.hero(g.ctrl(me)))
  if playable(c) then
    return c
  end
  c = info(g, me).class
  if playable(c) then
    return c
  end
  return CLASSES[g.random(1, #CLASSES)]
end

-- The choices of a Discover of cards passing ok: the class's cards (tri-class ones of it too) and the neutral ones.
local function discover_choices(g, cls, ok)
  local choices = {}
  for _, c in ipairs(g.collectible()) do
    local i = g.info(c)
    if not_hero(i) and ok(i) then
      if of_class(i, cls) then
        choices[#choices + 1] = { c, 4 }
      elseif is_neutral(i) then
        choices[#choices + 1] = { c, 1 }
      end
    end
  end
  return choices
end

local function discover(g, me, ok)
  return offer(g, me, discover_choices(g, discover_class(g, me), ok))
end

local function to_hand(g, me, option)
  return g.add_to_hand(g.ctrl(me), g.card(option))
end

local function is_type(t)
  return function(i)
    return i.type == t
  end
end

-- --- Adapt --------------------------------------------------------------------------------------------------------
-- Three different adaptations of the ten, at random; the one chosen applies to the minion (or to each of the minions)
-- the card adapts, as they are when it is chosen; only its player sees the three (g.create). Several Adapts of one
-- card (Volcanosaur, Galvadon) are choices one after another, each of three new ones. A minion that died or left the
-- board meanwhile gets nothing.

local ADAPTS = { "UNG_999t2", "UNG_999t3", "UNG_999t4", "UNG_999t5", "UNG_999t6", "UNG_999t7", "UNG_999t8",
  "UNG_999t10", "UNG_999t13", "UNG_999t14" }

local ADAPT = {
  UNG_999t2 = function(g, m) -- Living Spores: Deathrattle: two 1/1 Plants
    g.enchant(m, { hooks = "ench:spores" })
  end,
  UNG_999t3 = function(g, m) -- Flaming Claws
    g.buff(m, 3, 0)
  end,
  UNG_999t4 = function(g, m) -- Rocky Carapace
    g.buff(m, 0, 3)
  end,
  UNG_999t5 = function(g, m) -- Liquid Membrane
    g.give_tag(m, "ELUSIVE")
  end,
  UNG_999t6 = function(g, m) -- Massive
    g.give_tag(m, "TAUNT")
  end,
  UNG_999t7 = function(g, m) -- Lightning Speed
    g.give_tag(m, "WINDFURY")
  end,
  UNG_999t8 = function(g, m) -- Crackling Shield
    g.give_tag(m, "DIVINE_SHIELD")
  end,
  UNG_999t10 = function(g, m) -- Shrouding Mist: Stealth until its player's next turn
    g.give_tag(m, "STEALTH")
    g.enchant(m, { hooks = "ench:mist", player = g.ctrl(m) })
  end,
  UNG_999t13 = function(g, m) -- Poison Spit
    g.give_tag(m, "POISONOUS")
  end,
  UNG_999t14 = function(g, m) -- Volcanic Might
    g.buff(m, 1, 1)
  end,
}

-- The ten adaptations as cards (they are only ever offered; played from a hand, each adapts a friendly minion).
local function adaptation(c)
  return {
    target = "friendly_minion",
    spell = function(g, me, t)
      ADAPT[c](g, t)
    end,
  }
end
cards.UNG_999t2 = adaptation("UNG_999t2")
cards.UNG_999t3 = adaptation("UNG_999t3")
cards.UNG_999t4 = adaptation("UNG_999t4")
cards.UNG_999t5 = adaptation("UNG_999t5")
cards.UNG_999t6 = adaptation("UNG_999t6")
cards.UNG_999t7 = adaptation("UNG_999t7")
cards.UNG_999t8 = adaptation("UNG_999t8")
cards.UNG_999t10 = adaptation("UNG_999t10")
cards.UNG_999t13 = adaptation("UNG_999t13")
cards.UNG_999t14 = adaptation("UNG_999t14")

cards["ench:spores"] = {
  deathrattle = function(g, me)
    for _ = 1, 2 do
      summon_here(g, me, "UNG_999t2t1")
    end
  end,
}

cards["ench:mist"] = {
  on = {
    turn_start = function(g, me, ev)
      local p = g.enchants(me, "ench:mist")[1]
      if p ~= nil and ev.player == p then
        g.erase_tag(me, "STEALTH")
        g.remove_enchant(me, "ench:mist")
      end
    end,
  },
}

-- Offers me's player an Adapt of `who` (ADAPT_WHO, a tag on me: a minion's id, or a kind of friendly minions: the
-- negative ADAPT_KINDS).
local ADAPT_KINDS = { ALL = -1, MURLOC = -2, RECRUIT = -3 }

local function adapt(g, me, who)
  g.set_tag(me, "ADAPT_WHO", who)
  local p = g.ctrl(me)
  local opts = {}
  for _, c in ipairs(pick_n(g, ADAPTS, 3)) do
    opts[#opts + 1] = g.create(p, c)
  end
  g.request_choice(me, opts)
end

local function adapted(g, me)
  local who = g.tag(me, "ADAPT_WHO")
  if who > 0 then
    return { who }
  end
  return list.filter(g.minions(g.ctrl(me)), function(m)
    return who == ADAPT_KINDS.ALL or (who == ADAPT_KINDS.MURLOC and g.race(m) == "MURLOC")
      or (who == ADAPT_KINDS.RECRUIT and g.card(m) == RECRUIT)
  end)
end

local function adapt_choose(g, me, option)
  local f = ADAPT[g.card(option)]
  for _, m in ipairs(adapted(g, me)) do
    if alive(g, m) then
      f(g, m)
    end
  end
end

-- A minion that adapts itself n times when played (Battlecry).
local function adapt_self(n)
  return {
    battlecry = function(g, me)
      for _ = 1, n do
        adapt(g, me, me)
      end
    end,
    on_choose = adapt_choose,
  }
end

-- --- Quests -------------------------------------------------------------------------------------------------------
-- A TASK card: played (it costs 1), it waits in its player's Secret zone in sight of both players; its `spell` hook sets
-- the goal (QUEST_PROGRESS_TOTAL), its `on` hooks count (QUEST_PROGRESS); at the goal it leaves play and its reward goes
-- to the hand (a full hand: none). The engine puts it into the opening hand and allows one at a time.

local function quest_progress(g, me, n, reward)
  if n <= 0 or g.zone(me) ~= "SECRET" then
    return
  end
  local goal = g.tag(me, "QUEST_PROGRESS_TOTAL")
  local v = math.min(g.tag(me, "QUEST_PROGRESS") + n, goal)
  g.set_tag(me, "QUEST_PROGRESS", v)
  if v >= goal then
    local p = g.ctrl(me)
    g.remove(me, "GRAVEYARD")
    g.log({ type = "quest_done", player = p, entity = me, card = g.card(me) })
    g.add_to_hand(p, reward)
  end
end

-- A Quest: `goal`, the reward card, and for each event a function that says how much it adds (0 or nil: nothing).
local function quest(goal, reward, counts)
  local on = {}
  for event, f in pairs(counts) do
    on[event] = function(g, me, ev)
      local n = f(g, me, ev)
      if n then
        quest_progress(g, me, n, reward)
      end
    end
  end
  return {
    spell = function(g, me)
      g.set_tag(me, "QUEST_PROGRESS", 0)
      g.set_tag(me, "QUEST_PROGRESS_TOTAL", goal)
    end,
    on = on,
  }
end

local function my_summon(g, me, ev, ok)
  return g.mine(me, ev) and g.is_minion(ev.entity) and (not ok or ok(ev.entity)) and 1 or 0
end

-- The Caverns Below (Rogue): play four minions with the same name (the most of one card played since it began).
cards.UNG_067 = {
  spell = function(g, me)
    g.set_tag(me, "QUEST_PROGRESS", 0)
    g.set_tag(me, "QUEST_PROGRESS_TOTAL", 4)
  end,
  on = {
    play = function(g, me, ev)
      if ev.kind == "minion" and g.mine(me, ev) then
        local key = "CAVERNS_" .. ev.card
        local n = g.tag(me, key) + 1
        g.set_tag(me, key, n)
        local d = n - g.tag(me, "QUEST_PROGRESS")
        quest_progress(g, me, d, "UNG_067t1")
      end
    end,
  },
}

-- Crystal Core: for the rest of the game, its player's minions are 5/5: in play and in the hand now, and each one
-- summoned or drawn later (the player hooks; deck cards when drawn); new base stats, so buffs go on top and Silence
-- keeps it (a `base` enchantment; CORED marks one already set).
local function core(g, m)
  if not g.has(m, "CORED") then
    g.enchant(m, { set_atk = 5, set_hp = 5, base = true })
    g.set_tag(m, "CORED", true)
  end
end
cards.UNG_067t1 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.add_count(p, "CRYSTAL_CORE")
    for _, zone in ipairs({ g.minions(p), g.hand(p) }) do
      for _, e in ipairs(zone) do
        if g.is_minion(e) then
          core(g, e)
        end
      end
    end
  end,
}

-- Open the Waygate (Mage): cast 6 spells that didn't start in your deck (the Coin and every made card count).
cards.UNG_028 = quest(6, "UNG_028t", {
  play = function(g, me, ev)
    return ev.kind == "spell" and g.mine(me, ev) and not g.has(ev.entity, "STARTED_IN_DECK") and 1 or 0
  end,
})
cards.UNG_028t = { -- Time Warp
  spell = function(g, me)
    g.extra_turn(g.ctrl(me))
  end,
}

-- Lakkari Sacrifice (Warlock): discard 6 cards.
cards.UNG_829 = quest(6, "UNG_829t1", {
  discard = function(g, me, ev)
    return g.mine(me, ev) and 1 or 0
  end,
})
cards.UNG_829t1 = { -- Nether Portal: opens a permanent portal (a Dormant 0/1) that summons two 3/2 Imps each turn
  spell = function(g, me)
    g.summon(g.ctrl(me), "UNG_829t2")
  end,
}
cards.UNG_829t2 = {
  on = {
    turn_end = function(g, me, ev)
      if g.mine(me, ev) then
        for _ = 1, 2 do
          g.summon_right(me, "UNG_829t3")
        end
      end
    end,
  },
}

-- Jungle Giants (Druid): summon 5 minions with 5 or more Attack.
cards.UNG_116 = quest(5, "UNG_116t", {
  summon = function(g, me, ev)
    return my_summon(g, me, ev, function(m)
      return g.atk(m) >= 5
    end)
  end,
})
cards.UNG_116t = { -- Barnabus the Stomper: the minions in your deck cost (0)
  battlecry = function(g, me)
    for _, e in ipairs(g.deck(g.ctrl(me))) do
      if g.is_minion(e) then
        g.enchant(e, { cost_set = 0 })
      end
    end
  end,
}

-- The Marsh Queen (Hunter): play seven 1-Cost minions (their cards' Cost, after they were played: a Sheep counts).
cards.UNG_920 = quest(7, "UNG_920t1", {
  after_summon = function(g, me, ev)
    return ev.played and my_summon(g, me, ev, function(m)
      return info(g, m).cost == 1
    end) or 0
  end,
})
cards.UNG_920t1 = { -- Queen Carnassa: shuffle 15 Raptors (Carnassa's Brood) into your deck
  battlecry = function(g, me)
    for _ = 1, 15 do
      g.add_to_deck(g.ctrl(me), "UNG_920t2")
    end
  end,
}
cards.UNG_920t2 = lib.draw_battlecry(1) -- Carnassa's Brood

-- Fire Plume's Heart (Warrior): play 7 Taunt minions (Taunt after they were played: Nesting Roc's counts).
cards.UNG_934 = quest(7, "UNG_934t1", {
  after_summon = function(g, me, ev)
    return ev.played and my_summon(g, me, ev, function(m)
      return g.has(m, "TAUNT")
    end) or 0
  end,
})
cards.UNG_934t1 = { -- Sulfuras: your Hero Power becomes "Deal 8 damage to a random enemy."
  battlecry = function(g, me)
    g.set_power(g.ctrl(me), "UNG_934t2")
  end,
}
cards.UNG_934t2 = { -- DIE, INSECT!
  hero_power = function(g, me)
    local t = g.random_alive(g.chars(g.enemy(me)))
    if t then
      g.damage(me, t, g.hp_dmg(me, 8))
    end
  end,
}

-- Awaken the Makers (Priest): summon 7 Deathrattle minions.
cards.UNG_940 = quest(7, "UNG_940t8", {
  summon = function(g, me, ev)
    return my_summon(g, me, ev, function(m)
      return has_kw(info(g, m), "DEATHRATTLE")
    end)
  end,
})
cards.UNG_940t8 = { -- Amara, Warden of Hope: your hero's Health becomes 40
  battlecry = function(g, me)
    g.set_stats(g.hero(g.ctrl(me)), nil, 40)
  end,
}

-- Unite the Murlocs (Shaman): summon 10 Murlocs.
cards.UNG_942 = quest(10, "UNG_942t", {
  summon = function(g, me, ev)
    return my_summon(g, me, ev, function(m)
      return g.race(m) == "MURLOC"
    end)
  end,
})
cards.UNG_942t = { -- Megafin: fill your hand with random Murlocs
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local murlocs = pool(g, function(i)
      return i.type == "MINION" and i.race == "MURLOC"
    end)
    while #g.hand(p) < g.rule("hand") do
      local c = g.pick(murlocs)
      if not c or not g.add_to_hand(p, c) then
        break
      end
    end
  end,
}

-- The Last Kaleidosaur (Paladin): cast 6 spells on your minions.
cards.UNG_954 = quest(6, "UNG_954t1", {
  play = function(g, me, ev)
    local t = ev.target or -1
    return ev.kind == "spell" and g.mine(me, ev) and t >= 0 and g.is_minion(t) and g.ctrl(t) == g.ctrl(me) and 1 or 0
  end,
})
cards.UNG_954t1 = adapt_self(5) -- Galvadon

-- --- the game's counts and its start (rules.json player_hooks) -------------------------------------
-- Mean Streets of Gadgetzan's (spells cast, Totems summoned, the order friendly minions died in, Secrets played from the
-- hand, Patches the Pirate from the deck, Prince Malchezaar after the mulligan), and Journey to Un'Goro's: Elementals
-- played this turn and the last (ELEM_NOW, ELEM_LAST: "if you played an Elemental last turn" means its player's
-- previous turn, an extra one too), the cards that started in the deck (STARTED_IN_DECK: Open the Waygate), the
-- cards played from another class (Obsidian Shard), the discarded cards (DISCARDED: Cruel Dinomancer) and Crystal Core.

local MALCHEZAAR = "KAR_096"
local PATCHES = "CFM_637"

local function malchezaar(g, p)
  local hero_class = g.class(g.hero(p))
  local n = 0
  for _, zone in ipairs({ g.deck(p), g.hand(p) }) do
    n = n + #list.filter(zone, function(e)
      return g.card(e) == MALCHEZAAR
    end)
  end
  for _ = 1, 5 * n do
    local have = {}
    for _, zone in ipairs({ g.deck(p), g.hand(p) }) do
      for _, e in ipairs(zone) do
        have[g.card(e)] = true
      end
    end
    local c = g.pick(pool(g, function(i)
      return i.type == "MINION" and i.rarity == "LEGENDARY" and (of_class(i, hero_class) or is_neutral(i))
        and not have[i.id]
    end))
    if c then
      g.add_to_deck(p, c)
    end
  end
end

-- A card of a class other than its player's (a neutral card is of none; a tri-class card of its classes).
local function other_class(g, e, p)
  local i = info(g, e)
  if is_neutral(i) then
    return false
  end
  return not of_class(i, g.class(g.hero(p)))
end

cards["player:ungoro"] = {
  on = {
    after_spell = function(g, me, ev)
      if g.mine(me, ev) then
        g.add_count(g.ctrl(me), "SPELLS")
      end
    end,
    summon = function(g, me, ev)
      if g.mine(me, ev) then
        local p = g.ctrl(me)
        if g.race(ev.entity) == "TOTEM" then
          g.add_count(p, "TOTEMS")
        end
        if g.count(p, "CRYSTAL_CORE") > 0 and g.is_minion(ev.entity) then
          core(g, ev.entity)
        end
      end
    end,
    death = function(g, me, ev)
      if ev.minion and g.mine(me, ev) then
        g.set_tag(ev.entity, "DIED_ORDER", g.add_count(g.ctrl(me), "DEATHS"))
      end
    end,
    play = function(g, me, ev)
      if not g.mine(me, ev) then
        return
      end
      local p = g.ctrl(me)
      if ev.kind == "spell" and ev.secret then
        g.add_count(p, "SECRETS")
      end
      if ev.kind == "minion" and g.race(ev.entity) == "ELEMENTAL" then
        g.add_count(p, "ELEM_NOW")
      end
      if other_class(g, ev.entity, p) then
        g.add_count(p, "OTHER_CLASS")
      end
    end,
    discard = function(g, me, ev)
      if g.mine(me, ev) then
        g.set_tag(ev.entity, "DISCARDED", true)
      end
    end,
    draw = function(g, me, ev)
      if g.mine(me, ev) and g.count(g.ctrl(me), "CRYSTAL_CORE") > 0 and g.is_minion(ev.entity) then
        core(g, ev.entity)
      end
    end,
    turn_start = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.player == p then
        g.add_count(p, "ELEM_LAST", g.count(p, "ELEM_NOW") - g.count(p, "ELEM_LAST"))
        g.add_count(p, "ELEM_NOW", -g.count(p, "ELEM_NOW"))
      end
    end,
    -- Patches the Pirate: after you play a Pirate (after its Battlecry), it comes from your deck (room needed)
    after_summon = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.played and g.mine(me, ev) and g.race(ev.entity) == "PIRATE" and g.room(p) > 0 then
        local e = list.filter(g.deck(p), function(d)
          return g.card(d) == PATCHES
        end)[1]
        if e then
          g.summon_entity(e)
        end
      end
    end,
    game_start = function(g, me)
      local p = g.ctrl(me)
      for _, zone in ipairs({ g.deck(p), g.hand(p) }) do
        for _, e in ipairs(zone) do
          g.set_tag(e, "STARTED_IN_DECK", true)
        end
      end
      malchezaar(g, p)
    end,
  },
}

-- --- Mage -------------------------------------------------------------------------------------------------------------

-- Flame Geyser: 2 damage; a 1/2 Elemental (Flame Elemental) to your hand.
cards.UNG_018 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
    g.add_to_hand(g.ctrl(me), "UNG_809t1")
  end,
}

-- Arcanologist: draw a Secret from your deck.
local function draw_from_deck(g, p, ok, n)
  local got = 0
  for _ = 1, n or 1 do
    local e = g.pick(list.filter(g.deck(p), ok))
    if not e then
      break
    end
    g.draw_entity(p, e)
    got = got + 1
  end
  return got
end
cards.UNG_020 = {
  battlecry = function(g, me)
    draw_from_deck(g, g.ctrl(me), function(e)
      return info(g, e).trap
    end)
  end,
}

-- Steam Surger: if you played an Elemental last turn, a Flame Geyser to your hand.
cards.UNG_021 = {
  battlecry = function(g, me)
    if elemental_last_turn(g, g.ctrl(me)) then
      g.add_to_hand(g.ctrl(me), "UNG_018")
    end
  end,
  glow = elemental_glow,
}

-- Mana Bind (Secret): when your opponent casts a spell, a copy that costs (0) to your hand.
cards.UNG_024 = {
  secret = {
    event = "play",
    cond = function(g, me, ev)
      return lib.enemy_spell(g, me, ev) -- (a full hand: the copy is burned)
    end,
    effect = function(g, me, ev)
      local c = g.add_to_hand(g.ctrl(me), ev.card)
      if c then
        g.enchant(c, { cost_set = 0 })
      end
    end,
  },
}

-- Pyros: Deathrattle: back to your hand as a 6/6 that costs (6); that one as a 10/10 that costs (10).
cards.UNG_027 = {
  deathrattle = function(g, me)
    g.add_to_hand(g.ctrl(me), "UNG_027t2")
  end,
}
cards.UNG_027t2 = {
  deathrattle = function(g, me)
    g.add_to_hand(g.ctrl(me), "UNG_027t4")
  end,
}

-- Primordial Glyph: Discover a spell; it costs (2) less.
cards.UNG_941 = {
  spell = function(g, me)
    discover(g, me, is_type("SPELL"))
  end,
  on_choose = function(g, me, option)
    local c = to_hand(g, me, option)
    if c then
      g.enchant(c, { cost = -2 })
    end
  end,
}

-- Shimmering Tempest: Deathrattle: a random Mage spell to your hand.
cards.UNG_846 = {
  deathrattle = function(g, me)
    local c = random_card(g, function(i)
      return i.type == "SPELL" and of_class(i, "MAGE")
    end)
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Copies a friendly minion (Molten Reflection, Mirage Caller): a new minion right of it with its stats, enchantments
-- and damage (g.copy_minion); nil on a full board.
local function copy_right(g, t)
  local c = g.summon_right(t, g.card(t))
  if c then
    c = g.copy_minion(c, t)
  end
  return c
end

-- Molten Reflection: choose a friendly minion, summon a copy of it.
cards.UNG_948 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    copy_right(g, t)
  end,
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
}

-- Meteor: 15 damage to a minion and 3 to the adjacent ones.
cards.UNG_955 = {
  target = "minion",
  spell = function(g, me, t)
    local adj = g.adjacent(t)
    g.damage(me, t, g.spell_dmg(me, 15))
    for _, m in ipairs(adj) do
      g.damage(me, m, g.spell_dmg(me, 3))
    end
  end,
}

-- --- Priest -----------------------------------------------------------------------------------------------------------

-- Mirage Caller: choose a friendly minion; summon a 1/1 copy of it.
cards.UNG_022 = {
  target = "friendly_minion",
  battlecry = function(g, me, t)
    local c = copy_right(g, t)
    if c then
      g.set_stats(c, 1, 1)
    end
  end,
}

-- Shadow Visions: Discover a copy of a spell in your deck.
cards.UNG_029 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local seen = {}
    local choices = {}
    for _, e in ipairs(g.deck(p)) do
      local c = g.card(e)
      if g.is_spell(e) and not seen[c] then
        seen[c] = true
        choices[#choices + 1] = { c, 1 }
      end
    end
    offer(g, me, choices)
  end,
  on_choose = to_hand,
}

-- Binding Heal: 5 Health to a minion and your hero.
cards.UNG_030 = {
  target = "minion",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 5))
    g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 5))
  end,
}

-- Crystalline Oracle: Deathrattle: a copy of a card of your opponent's deck to your hand.
cards.UNG_032 = {
  deathrattle = function(g, me)
    local e = g.pick(g.deck(g.enemy(me)))
    if e then
      g.add_to_hand(g.ctrl(me), g.card(e))
    end
  end,
}

-- Radiant Elemental: your spells cost (1) less.
cards.UNG_034 = {
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.is_spell(card) and g.zone(card) == "HAND" then
      return cost - 1
    end
    return cost
  end,
}

-- The cards p's deck started with that are still to be found (in the deck, the hand, in play, the graveyard: tagged
-- STARTED_IN_DECK by the player hooks when the game started).
local function started_in_deck(g, p)
  local out = {}
  local w = g.weapon(p)
  for _, zone in ipairs({ g.deck(p), g.hand(p), g.minions(p), g.traps(p), g.tasks(p), g.graveyard(p), { w } }) do
    for _, e in ipairs(zone) do
      if g.has(e, "STARTED_IN_DECK") then
        out[#out + 1] = e
      end
    end
  end
  return out
end

-- Curious Glimmerroot: look at 3 cards (one of the opponent's starting deck, two other cards of their class); guess the
-- one from their deck to get a copy of it.
cards.UNG_035 = {
  battlecry = function(g, me)
    local p, foe = g.ctrl(me), g.enemy(me)
    local start = {}
    local list_ = {}
    local cls = g.class(g.hero(foe))
    local started = started_in_deck(g, foe)
    -- a class card of theirs (none in their deck: a neutral one) and two others of that kind not in it
    local function kind(i)
      return of_class(i, cls)
    end
    if not list.any(started, function(e)
      return of_class(info(g, e), cls)
    end) then
      kind = is_neutral
    end
    for _, e in ipairs(started) do
      local c = g.card(e)
      start[c] = true
      if kind(info(g, e)) and g.info(c).collectible and not list.any(list_, function(x)
        return x == c
      end) then
        list_[#list_ + 1] = c
      end
    end
    local right = g.pick(list_)
    if not right then
      return
    end
    local wrong = pick_n(g, pool(g, function(i)
      return not_hero(i) and kind(i) and not start[i.id]
    end), 2)
    local opts = { right, wrong[1], wrong[2] }
    g.shuffle(opts)
    local ids = {}
    for _, c in ipairs(opts) do
      if c then
        local e = g.create(p, c)
        if c == right then
          g.set_tag(e, "GLIMMER_RIGHT", true)
        end
        ids[#ids + 1] = e
      end
    end
    g.request_choice(me, ids)
  end,
  on_choose = function(g, me, option)
    if g.has(option, "GLIMMER_RIGHT") then
      to_hand(g, me, option)
    end
  end,
}

-- Tortollan Shellraiser: Deathrattle: a random friendly minion +1/+1.
cards.UNG_037 = {
  deathrattle = function(g, me)
    g.buff(g.random_alive(g.minions(g.ctrl(me))), 1, 1)
  end,
}

-- Free From Amber: Discover a minion that costs (8) or more; summon it.
cards.UNG_854 = {
  spell = function(g, me)
    discover(g, me, function(i)
      return i.type == "MINION" and i.cost >= 8
    end)
  end,
  on_choose = function(g, me, option)
    g.summon(g.ctrl(me), g.card(option))
  end,
}

-- Lyra the Sunshard: whenever you cast a spell, a random Priest spell to your hand.
cards.UNG_963 = {
  on = {
    play = function(g, me, ev)
      if lib.my_spell(g, me, ev) then
        local c = random_card(g, function(i)
          return i.type == "SPELL" and of_class(i, "PRIEST")
        end)
        if c then
          g.add_to_hand(g.ctrl(me), c)
        end
      end
    end,
  },
}

-- --- Rogue ------------------------------------------------------------------------------------------------------------

-- Razorpetal Volley: two Razorpetals to your hand; Razorpetal Lasher: one.
cards.UNG_057 = {
  spell = function(g, me)
    for _ = 1, 2 do
      g.add_to_hand(g.ctrl(me), "UNG_057t1")
    end
  end,
}
cards.UNG_057t1 = lib.hit("any", 1, true) -- Razorpetal
cards.UNG_058 = {
  battlecry = function(g, me)
    g.add_to_hand(g.ctrl(me), "UNG_057t1")
  end,
}

-- Mimic Pod: draw a card, then a copy of it to your hand.
cards.UNG_060 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local d = g.draw(p)[1]
    if d then
      g.add_to_hand(p, g.card(d))
    end
  end,
}

-- Obsidian Shard: costs (1) less for each card you've played from another class.
cards.UNG_061 = {
  cost_mod = function(g, me)
    return -g.count(g.ctrl(me), "OTHER_CLASS")
  end,
}

-- Biteweed: Combo: +1/+1 for each other card you've played this turn.
cards.UNG_063 = {
  combo = function(g, me)
    local n = g.cards_played(g.ctrl(me)) - 1
    if n > 0 then
      g.buff(me, n, n)
    end
  end,
}

-- Vilespine Slayer: Combo: destroy a minion.
cards.UNG_064 = {
  combo_target = "minion",
  combo = function(g, me, t)
    g.destroy(t)
  end,
}

-- Sherazin, Corpse Flower: Deathrattle: it goes Dormant (Sherazin, Seed); when you play 4 cards in a turn, it revives.
cards.UNG_065 = {
  deathrattle = function(g, me)
    summon_here(g, me, "UNG_065t")
  end,
}
-- (it counts the cards its player plays from when it appears, each turn anew: SEED_TURN, SEED_COUNT)
cards.UNG_065t = {
  on = {
    play = function(g, me, ev)
      if g.mine(me, ev) then
        if g.tag(me, "SEED_TURN") ~= g.turn() then
          g.set_tag(me, "SEED_TURN", g.turn())
          g.set_tag(me, "SEED_COUNT", 0)
        end
        local n = g.tag(me, "SEED_COUNT") + 1
        g.set_tag(me, "SEED_COUNT", n)
        if n >= 4 then
          g.transform(me, "UNG_065")
        end
      end
    end,
  },
}

-- Envenom Weapon: your weapon gets Poisonous.
cards.UNG_823 = {
  spell = function(g, me)
    local w = g.weapon(g.ctrl(me))
    if w then
      g.give_tag(w, "POISONOUS")
    end
  end,
  can_play = function(g, me)
    return g.weapon(g.ctrl(me)) ~= nil
  end,
}

-- Hallucination: Discover a card from your opponent's class.
cards.UNG_856 = {
  spell = function(g, me)
    local cls = g.class(g.hero(g.enemy(me)))
    if not playable(cls) then
      cls = "ROGUE"
    end
    local choices = {}
    for _, c in ipairs(g.collectible()) do
      local i = g.info(c)
      if not_hero(i) and of_class(i, cls) then
        choices[#choices + 1] = { c, 1 }
      end
    end
    offer(g, me, choices)
  end,
  on_choose = to_hand,
}

-- --- Shaman -----------------------------------------------------------------------------------------------------------

-- Volcano: 15 damage randomly split among all minions (one at a time, among those alive).
cards.UNG_025 = {
  spell = function(g, me)
    for _ = 1, g.spell_dmg(me, 15) do
      local t = g.random_alive(g.all_minions())
      if not t then
        break
      end
      g.damage(me, t, 1)
    end
  end,
}

-- Primalfin Totem: at the end of your turn, a 1/1 Murloc.
cards.UNG_201 = {
  on = {
    turn_end = function(g, me, ev)
      if g.mine(me, ev) then
        g.summon_right(me, "UNG_201t")
      end
    end,
  },
}

-- Fire Plume Harbinger: the Elementals in your hand cost (1) less.
cards.UNG_202 = {
  battlecry = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      if g.race(e) == "ELEMENTAL" then
        g.enchant(e, { cost = -1 })
      end
    end
  end,
}

-- Stone Sentinel: if you played an Elemental last turn, two 2/3 Elementals with Taunt.
cards.UNG_208 = {
  battlecry = function(g, me)
    if elemental_last_turn(g, g.ctrl(me)) then
      for _ = 1, 2 do
        g.summon_right(me, "UNG_208t")
      end
    end
  end,
  glow = elemental_glow,
}

-- Kalimos, Primal Lord: if you played an Elemental last turn, choose an Elemental Invocation and cast it.
local INVOCATIONS = { "UNG_211a", "UNG_211b", "UNG_211c", "UNG_211d" }
cards.UNG_211 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if elemental_last_turn(g, p) then
      local opts = {}
      for _, c in ipairs(INVOCATIONS) do
        opts[#opts + 1] = g.create(p, c)
      end
      g.request_choice(me, opts)
    end
  end,
  on_choose = function(g, me, option)
    g.cast(me, option, nil)
  end,
  glow = elemental_glow,
}
cards.UNG_211a = { -- Invocation of Earth: fill your board with 1/1 Elementals
  spell = function(g, me)
    local p = g.ctrl(me)
    while g.room(p) > 0 do
      if not g.summon(p, "UNG_211aa") then
        break
      end
    end
  end,
}
cards.UNG_211b = { -- Invocation of Water: 12 Health to your hero
  spell = function(g, me)
    g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 12))
  end,
}
cards.UNG_211c = { -- Invocation of Fire: 6 damage to the enemy hero
  spell = function(g, me)
    g.damage(me, g.hero(g.enemy(me)), 6)
  end,
}
cards.UNG_211d = { -- Invocation of Air: 3 damage to all enemy minions
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.damage(me, m, 3)
    end
  end,
}

-- Tidal Surge: 4 damage to a minion, 4 Health to your hero.
cards.UNG_817 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
    g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 4))
  end,
}

-- Spirit Echo: your minions get "Deathrattle: return this to your hand".
cards.UNG_956 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.enchant(m, { hooks = "ench:echo" })
    end
  end,
}
cards["ench:echo"] = {
  deathrattle = function(g, me)
    g.add_to_hand(g.ctrl(me), g.card(me))
  end,
}

-- Hot Spring Guardian: Taunt; Battlecry: 3 Health.
cards.UNG_938 = {
  target = "any",
  battlecry = function(g, me, t)
    g.heal(me, t, 3)
  end,
}

-- --- Warlock ----------------------------------------------------------------------------------------------------------

-- Ravenous Pterrordax: destroy a friendly minion to Adapt twice.
cards.UNG_047 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me
  end },
  battlecry = function(g, me, t)
    g.destroy(t)
    g.resolve() -- it dies (its Deathrattle too) before the two Adapts
    for _ = 1, 2 do
      adapt(g, me, me)
    end
  end,
  on_choose = adapt_choose,
}

-- Tar Creeper, Tar Lurker, Tar Lord: more Attack during the opponent's turn.
local function tar(n)
  return {
    aura = function(g, me)
      if g.current() ~= g.ctrl(me) then
        g.aura_add(me, n, 0)
      end
    end,
  }
end
cards.UNG_049 = tar(3)
cards.UNG_838 = tar(4)
cards.UNG_928 = tar(2)

-- Cruel Dinomancer: Deathrattle: a random minion you discarded this game.
cards.UNG_830 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    local d = g.pick(list.filter(g.graveyard(p), function(e)
      return g.is_minion(e) and g.has(e, "DISCARDED")
    end))
    if d then
      summon_here(g, me, g.card(d))
    end
  end,
}

-- Corrupting Mist: corrupt every minion; destroy them at the start of your next turn.
cards.UNG_831 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, m in ipairs(g.all_minions()) do
      g.enchant(m, { hooks = "ench:mist_corrupt", player = p })
    end
  end,
}
cards["ench:mist_corrupt"] = {
  on = {
    turn_start = function(g, me, ev)
      for _, p in ipairs(g.enchants(me, "ench:mist_corrupt")) do
        if ev.player == p then
          g.destroy(me)
        end
      end
    end,
  },
}

-- Bloodbloom: the next spell you cast this turn costs Health instead of Mana.
cards.UNG_832 = {
  spell = function(g, me)
    g.add_cost_mod(g.ctrl(me), { kind = "spell", delta = 0, ["until"] = "use", health = true })
  end,
}

-- Lakkari Felhound: Battlecry: discard two random cards.
cards.UNG_833 = {
  battlecry = function(g, me)
    g.discard_random(g.ctrl(me), 2)
  end,
}

-- Feeding Time: 3 damage to a minion; three 1/1 Pterrordaxes.
cards.UNG_834 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 3))
    for _ = 1, 3 do
      g.summon(g.ctrl(me), "UNG_834t1")
    end
  end,
}

-- Chittering Tunneler: Discover a spell; damage to your hero equal to its Cost.
cards.UNG_835 = {
  battlecry = function(g, me)
    discover(g, me, is_type("SPELL"))
  end,
  on_choose = function(g, me, option)
    local p = g.ctrl(me)
    local cost = g.info(g.card(option)).cost
    to_hand(g, me, option)
    g.damage(me, g.hero(p), cost)
  end,
}

-- Clutchmother Zavas: whenever you discard this, +2/+2 and back to your hand (the buffs add up).
cards.UNG_836 = {
  hand = {
    discard = function(g, me, ev)
      if ev.entity == me then
        local c = g.add_to_hand(g.ctrl(me), g.card(me))
        if c then
          local n = g.tag(me, "ZAVAS") + 1
          g.set_tag(c, "ZAVAS", n)
          g.buff(c, 2 * n, 2 * n)
        end
      end
    end,
  },
}

-- --- Warrior ----------------------------------------------------------------------------------------------------------

-- Explore Un'Goro: your deck becomes copies of "Discover a card" (Choose Your Path).
cards.UNG_922 = {
  spell = function(g, me)
    for _, e in ipairs(g.deck(g.ctrl(me))) do
      g.transform(e, "UNG_922t1")
    end
  end,
}
cards.UNG_922t1 = { -- Choose Your Path: Discover a card
  spell = function(g, me)
    discover(g, me, function()
      return true
    end)
  end,
  on_choose = to_hand,
}

-- Iron Hide: 5 Armor.
cards.UNG_923 = {
  spell = function(g, me)
    g.gain_armor(g.ctrl(me), 5)
  end,
}

-- Ornery Direhorn: Taunt; Battlecry: Adapt.
cards.UNG_925 = adapt_self(1)

-- Cornered Sentry: Taunt; Battlecry: three 1/1 Raptors for your opponent.
cards.UNG_926 = {
  battlecry = function(g, me)
    for _ = 1, 3 do
      g.summon(g.enemy(me), "UNG_076t1")
    end
  end,
}

-- Sudden Genesis: copies of your damaged minions.
cards.UNG_927 = {
  spell = function(g, me)
    for _, m in ipairs(list.filter(g.minions(g.ctrl(me)), function(x)
      return g.dmg(x) > 0
    end)) do
      if alive(g, m) then
        copy_right(g, m)
      end
    end
  end,
}

-- Molten Blade: at the start of each of your turns while it is in your hand (not the turn it came), it becomes a random
-- weapon that keeps changing until it leaves the hand.
local function reforge(g, me, ev)
  if g.mine(me, ev) then
    local w = random_card(g, is_type("WEAPON"))
    local n = w and g.transform(me, w)
    if n then
      g.enchant(n, { hooks = "ench:molten" })
    end
  end
end
local function reforge_drawn(g, me, ev)
  if ev.entity == me then
    reforge(g, me, ev)
  end
end
cards.UNG_929 = { hand = { turn_start = reforge, draw = reforge_drawn } }
cards["ench:molten"] = { hand = { turn_start = reforge } }

-- King Mosh: destroy all damaged minions.
cards.UNG_933 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if g.dmg(m) > 0 then
        g.destroy(m)
      end
    end
  end,
}

-- Direhorn Hatchling: Deathrattle: shuffle a 6/9 Direhorn with Taunt into your deck.
cards.UNG_957 = {
  deathrattle = function(g, me)
    g.add_to_deck(g.ctrl(me), "UNG_957t1")
  end,
}

-- --- Paladin ----------------------------------------------------------------------------------------------------------

-- Dinosize: a minion's Attack and Health become 10.
cards.UNG_004 = {
  target = "minion",
  spell = function(g, me, t)
    g.set_stats(t, 10, 10)
  end,
}

-- Hydrologist: Discover a Secret.
local SECRET_CLASSES = { MAGE = true, HUNTER = true, PALADIN = true }
cards.UNG_011 = {
  battlecry = function(g, me)
    local cls = g.class(g.hero(g.ctrl(me)))
    if not SECRET_CLASSES[cls] then
      cls = "PALADIN" -- a Paladin's, or the Secrets of a class that has them; else the Paladin's
    end
    offer(g, me, discover_choices(g, cls, function(i)
      return i.trap and not is_neutral(i)
    end))
  end,
  on_choose = to_hand,
}

-- Sunkeeper Tarim: Taunt; Battlecry: all other minions become 3/3.
cards.UNG_015 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if m ~= me then
        g.set_stats(m, 3, 3)
      end
    end
  end,
}

-- Vinecleaver: after your hero attacks, two 1/1 Silver Hand Recruits.
cards.UNG_950 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == g.hero(g.ctrl(me)) then
        for _ = 1, 2 do
          g.summon(g.ctrl(me), RECRUIT)
        end
      end
    end,
  },
}

-- Spikeridged Steed: a minion +2/+6 and Taunt; when it dies, a Stegodon.
cards.UNG_952 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 2, 6)
    g.give_tag(t, "TAUNT")
    g.enchant(t, { hooks = "ench:steed" })
  end,
}
cards["ench:steed"] = {
  deathrattle = function(g, me)
    summon_here(g, me, "UNG_810")
  end,
}

-- Primalfin Champion: Deathrattle: the spells you cast on it back to your hand (PRIMALFIN_<n>: their cards).
cards.UNG_953 = {
  on = {
    play = function(g, me, ev)
      if lib.my_spell(g, me, ev) and ev.target == me then
        local n = g.tag(me, "PRIMALFIN") + 1
        g.set_tag(me, "PRIMALFIN", n)
        g.set_tag(me, "PRIMALFIN_" .. n, ev.entity)
      end
    end,
  },
  deathrattle = function(g, me)
    for i = 1, g.tag(me, "PRIMALFIN") do
      local s = g.tag(me, "PRIMALFIN_" .. i)
      if s > 0 then
        g.add_to_hand(g.ctrl(me), g.card(s))
      end
    end
  end,
}

-- Lost in the Jungle: two 1/1 Silver Hand Recruits.
cards.UNG_960 = {
  spell = function(g, me)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), RECRUIT)
    end
  end,
}

-- Adaptation: Adapt a friendly minion.
cards.UNG_961 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    adapt(g, me, t)
  end,
  on_choose = adapt_choose,
}

-- Lightfused Stegodon: Adapt your Silver Hand Recruits (one choice for all).
cards.UNG_962 = {
  battlecry = function(g, me)
    if #list.filter(g.minions(g.ctrl(me)), function(m)
      return g.card(m) == RECRUIT
    end) > 0 then
      adapt(g, me, ADAPT_KINDS.RECRUIT)
    end
  end,
  on_choose = adapt_choose,
}

-- --- Hunter -----------------------------------------------------------------------------------------------------------

-- Terrorscale Stalker: trigger a friendly minion's Deathrattle.
cards.UNG_800 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me and has_kw(info(g, t), "DEATHRATTLE")
  end },
  battlecry = function(g, me, t)
    g.deathrattle(t)
  end,
}

-- Grievous Bite: 2 damage to a minion and 1 to the adjacent ones.
cards.UNG_910 = {
  target = "minion",
  spell = function(g, me, t)
    local adj = g.adjacent(t)
    g.damage(me, t, g.spell_dmg(me, 2))
    for _, m in ipairs(adj) do
      g.damage(me, m, g.spell_dmg(me, 1))
    end
  end,
}

-- Jeweled Macaw: a random Beast to your hand.
local function random_beast(g)
  return random_card(g, function(i)
    return i.type == "MINION" and i.race == "BEAST"
  end)
end
cards.UNG_912 = {
  battlecry = function(g, me)
    local c = random_beast(g)
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Tol'vir Warden: draw two 1-Cost minions from your deck.
cards.UNG_913 = {
  battlecry = function(g, me)
    draw_from_deck(g, g.ctrl(me), function(e)
      return g.is_minion(e) and info(g, e).cost == 1
    end, 2)
  end,
}

-- Raptor Hatchling: Deathrattle: shuffle a 4/3 Raptor (Raptor Patriarch) into your deck.
cards.UNG_914 = {
  deathrattle = function(g, me)
    g.add_to_deck(g.ctrl(me), "UNG_914t1")
  end,
}

-- Crackling Razormaw: Adapt a friendly Beast.
cards.UNG_915 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me and g.race(t) == "BEAST"
  end },
  battlecry = function(g, me, t)
    adapt(g, me, t)
  end,
  on_choose = adapt_choose,
}

-- Stampede: each time you play a Beast this turn, a random Beast to your hand.
cards.UNG_916 = {
  spell = function(g, me)
    local h = g.hero(g.ctrl(me))
    g.enchant(h, { hooks = "ench:stampede", eot = true })
  end,
}
cards["ench:stampede"] = {
  on = {
    play = function(g, me, ev)
      if ev.kind == "minion" and g.mine(me, ev) and g.race(ev.entity) == "BEAST" then
        local c = random_beast(g)
        if c then
          g.add_to_hand(g.ctrl(me), c)
        end
      end
    end,
  },
}

-- Dinomancy: your Hero Power becomes "Give a Beast +2/+2."
cards.UNG_917 = {
  spell = function(g, me)
    g.set_power(g.ctrl(me), "UNG_917t1")
  end,
}
cards.UNG_917t1 = {
  target = { base = "minion", filter = function(g, me, t)
    return g.race(t) == "BEAST"
  end },
  hero_power = function(g, me, t)
    g.buff(t, 2, 2)
  end,
}

-- Swamp King Dred: after your opponent plays a minion, it attacks it.
cards.UNG_919 = {
  on = {
    after_summon = function(g, me, ev)
      if ev.played and not g.mine(me, ev) and not g.has(me, "FROZEN") and not g.has(me, "CANT_ATTACK") then
        g.force_attack(me, ev.entity)
      end
    end,
  },
}

-- --- Druid ------------------------------------------------------------------------------------------------------------

-- Tortollan Forager: a random minion with 5 or more Attack to your hand.
cards.UNG_078 = {
  battlecry = function(g, me)
    local c = random_card(g, function(i)
      return i.type == "MINION" and i.attack >= 5
    end)
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Giant Anaconda: Deathrattle: a minion from your hand with 5 or more Attack.
cards.UNG_086 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    local e = g.pick(hand_minions(g, p, function(m)
      return g.atk(m) >= 5
    end))
    if e then
      local pos = g.died_pos(me)
      g.summon_entity(e, pos >= 0 and pos or nil)
    end
  end,
}

-- Verdant Longneck: Adapt.
cards.UNG_100 = adapt_self(1)

-- Shellshifter: Choose One: a 5/3 with Stealth, or a 3/5 with Taunt (both: a 5/5 with both).
cards.UNG_101 = {
  choose_one = { "UNG_101a", "UNG_101b" },
  both = function(g, me)
    g.transform(me, "UNG_101t3")
  end,
}
cards.UNG_101a = {
  effect = function(g, me)
    g.transform(me, "UNG_101t")
  end,
}
cards.UNG_101b = {
  effect = function(g, me)
    g.transform(me, "UNG_101t2")
  end,
}

-- Evolving Spores: Adapt your minions (one choice for all).
cards.UNG_103 = {
  spell = function(g, me)
    adapt(g, me, ADAPT_KINDS.ALL)
  end,
  on_choose = adapt_choose,
}

-- Earthen Scales: a friendly minion +1/+1, then Armor equal to its Attack.
cards.UNG_108 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.buff(t, 1, 1)
    g.gain_armor(g.ctrl(me), g.atk(t))
  end,
}

-- Elder Longneck: if you're holding a minion with 5 or more Attack, Adapt.
local function holding_big(g, me)
  return #hand_minions(g, g.ctrl(me), function(m)
    return m ~= me and g.atk(m) >= 5
  end) > 0
end
cards.UNG_109 = {
  battlecry = function(g, me)
    if holding_big(g, me) then
      adapt(g, me, me)
    end
  end,
  on_choose = adapt_choose,
  glow = holding_big,
}

-- Living Mana: your Mana Crystals become 2/2 Mana Treants (as many as fit); each gives back an empty crystal when it
-- dies.
cards.UNG_111 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local n = math.min(g.max_mana(p), g.room(p))
    if n <= 0 then
      return
    end
    -- the empty crystals go first, then full ones (temporary mana, the Coin's, stays)
    local empty = math.max(0, g.max_mana(p) - g.mana(p))
    g.set_mana(p, g.mana(p) - math.max(0, n - empty), g.max_mana(p) - n)
    for _ = 1, n do
      g.summon(p, "UNG_111t1")
    end
  end,
}
cards.UNG_111t1 = {
  deathrattle = function(g, me)
    g.gain_mana(g.ctrl(me), 1, true)
  end,
}

-- --- Neutral ----------------------------------------------------------------------------------------------------------

cards.UNG_001 = adapt_self(1) -- Pterrordax Hatchling
cards.UNG_002 = adapt_self(2) -- Volcanosaur

-- Ravasaur Runt: if you control at least 2 other minions, Adapt.
local function two_others(g, me)
  return #g.others(me) >= 2
end
cards.UNG_009 = {
  battlecry = function(g, me)
    if two_others(g, me) then
      adapt(g, me, me)
    end
  end,
  on_choose = adapt_choose,
  glow = two_others,
}

-- Sated Threshadon: Deathrattle: three 1/1 Murlocs.
cards.UNG_010 = {
  deathrattle = function(g, me)
    for _ = 1, 3 do
      summon_here(g, me, "UNG_201t")
    end
  end,
}

-- Tol'vir Stoneshaper: if you played an Elemental last turn, Taunt and Divine Shield.
cards.UNG_070 = {
  battlecry = function(g, me)
    if elemental_last_turn(g, g.ctrl(me)) then
      g.give_tag(me, "TAUNT")
      g.give_tag(me, "DIVINE_SHIELD")
    end
  end,
  glow = elemental_glow,
}

-- Stonehill Defender: Taunt; Battlecry: Discover a Taunt minion.
cards.UNG_072 = {
  battlecry = function(g, me)
    discover(g, me, function(i)
      return i.type == "MINION" and has_kw(i, "TAUNT")
    end)
  end,
  on_choose = to_hand,
}

-- Rockpool Hunter: a friendly Murloc +1/+1.
cards.UNG_073 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me and g.race(t) == "MURLOC"
  end },
  battlecry = function(g, me, t)
    g.buff(t, 1, 1)
  end,
}

-- Vicious Fledgling: after it attacks a hero, Adapt.
cards.UNG_075 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == me and g.is_champion(ev.defender) and alive(g, me) then
        adapt(g, me, me)
      end
    end,
  },
  on_choose = adapt_choose,
}

-- Eggnapper: Deathrattle: two 1/1 Raptors.
cards.UNG_076 = {
  deathrattle = function(g, me)
    for _ = 1, 2 do
      summon_here(g, me, "UNG_076t1")
    end
  end,
}

-- Frozen Crusher: after it attacks, it is Frozen.
cards.UNG_079 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == me then
        g.freeze(me)
      end
    end,
  },
}

-- Thunder Lizard: if you played an Elemental last turn, Adapt.
cards.UNG_082 = {
  battlecry = function(g, me)
    if elemental_last_turn(g, g.ctrl(me)) then
      adapt(g, me, me)
    end
  end,
  on_choose = adapt_choose,
  glow = elemental_glow,
}

-- Devilsaur Egg: Deathrattle: a 5/5 Devilsaur.
cards.UNG_083 = {
  deathrattle = function(g, me)
    summon_here(g, me, "UNG_083t1")
  end,
}

-- Fire Plume Phoenix: Battlecry: 2 damage.
cards.UNG_084 = lib.hit("any", 2)

-- Emerald Hive Queen: your minions cost (2) more.
cards.UNG_085 = {
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.is_minion(card) and g.zone(card) == "HAND" then
      return cost + 2
    end
    return cost
  end,
}

-- Bittertide Hydra: whenever it takes damage, 3 damage to your hero.
cards.UNG_087 = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me then
        g.damage(me, g.hero(g.ctrl(me)), 3)
      end
    end,
  },
}

-- Tortollan Primalist: Discover a spell and cast it with random targets.
cards.UNG_088 = {
  battlecry = function(g, me)
    discover(g, me, is_type("SPELL"))
  end,
  on_choose = function(g, me, option)
    g.cast_random(me, g.card(option))
  end,
}

-- Gentle Megasaur: Adapt your Murlocs (one choice for all).
cards.UNG_089 = {
  battlecry = function(g, me)
    if #list.filter(g.minions(g.ctrl(me)), function(m)
      return g.race(m) == "MURLOC"
    end) > 0 then
      adapt(g, me, ADAPT_KINDS.MURLOC)
    end
  end,
  on_choose = adapt_choose,
}

-- Charged Devilsaur: Charge; Battlecry: it can't attack heroes this turn.
cards.UNG_099 = {
  battlecry = function(g, me)
    g.give_tag(me, "CANNOT_ATTACK_HEROES", true)
  end,
}

-- Bright-Eyed Scout: draw a card; its Cost becomes (5).
cards.UNG_113 = {
  battlecry = function(g, me)
    local d = g.draw(g.ctrl(me))[1]
    if d then
      g.enchant(d, { cost_set = 5 })
    end
  end,
}

-- Glacial Shard: Freeze an enemy.
cards.UNG_205 = {
  target = "enemy_char",
  battlecry = function(g, me, t)
    g.freeze(t)
  end,
}

-- Nesting Roc: if you control at least 2 other minions, Taunt.
cards.UNG_801 = {
  battlecry = function(g, me)
    if two_others(g, me) then
      g.give_tag(me, "TAUNT")
    end
  end,
  glow = two_others,
}

-- Emerald Reaver: 1 damage to each hero.
cards.UNG_803 = {
  battlecry = function(g, me)
    for _, p in ipairs({ g.ctrl(me), g.enemy(me) }) do
      g.damage(me, g.hero(p), 1)
    end
  end,
}

-- Golakka Crawler: destroy a Pirate and gain +1/+1.
cards.UNG_807 = {
  target = { base = "minion", filter = function(g, me, t)
    return t ~= me and g.race(t) == "PIRATE"
  end },
  battlecry = function(g, me, t)
    g.destroy(t)
    g.buff(me, 1, 1)
  end,
}

-- Fire Fly: a 1/2 Elemental to your hand.
cards.UNG_809 = {
  battlecry = function(g, me)
    g.add_to_hand(g.ctrl(me), "UNG_809t1")
  end,
}

-- Servant of Kalimos: if you played an Elemental last turn, Discover an Elemental.
cards.UNG_816 = {
  battlecry = function(g, me)
    if elemental_last_turn(g, g.ctrl(me)) then
      discover(g, me, function(i)
        return i.type == "MINION" and i.race == "ELEMENTAL"
      end)
    end
  end,
  on_choose = to_hand,
  glow = elemental_glow,
}

-- Volatile Elemental: Deathrattle: 3 damage to a random enemy minion.
cards.UNG_818 = {
  deathrattle = function(g, me)
    local t = g.random_alive(g.minions(g.enemy(me)))
    if t then
      g.damage(me, t, 3)
    end
  end,
}

-- Hemet, Jungle Hunter: destroy all cards in your deck that cost (3) or less.
cards.UNG_840 = {
  battlecry = function(g, me)
    for _, e in ipairs(g.deck(g.ctrl(me))) do
      if info(g, e).cost <= 3 then
        g.remove(e, "GRAVEYARD")
      end
    end
  end,
}

-- The Voraxx: after you cast a spell on it, a 1/1 Plant, and another copy of the spell cast on it.
cards.UNG_843 = {
  on = {
    after_spell = function(g, me, ev)
      if g.mine(me, ev) and g.tag(ev.entity, "VORAXX_ON") == me and alive(g, me) then
        local plant = g.summon_right(me, "UNG_999t2t1")
        if plant then
          g.cast(me, ev.entity, plant)
        end
      end
    end,
    play = function(g, me, ev)
      if lib.my_spell(g, me, ev) and ev.target == me then
        g.set_tag(ev.entity, "VORAXX_ON", me)
      end
    end,
  },
}

-- Igneous Elemental: Deathrattle: two 1/2 Elementals to your hand.
cards.UNG_845 = {
  deathrattle = function(g, me)
    for _ = 1, 2 do
      g.add_to_hand(g.ctrl(me), "UNG_809t1")
    end
  end,
}

-- Blazecaller: if you played an Elemental last turn, 5 damage.
cards.UNG_847 = {
  target = { base = "any", when = elemental_glow },
  battlecry = function(g, me, t)
    if t and elemental_last_turn(g, g.ctrl(me)) then
      g.damage(me, t, 5)
    end
  end,
  glow = elemental_glow,
}

-- Primordial Drake: Taunt; Battlecry: 2 damage to all other minions.
cards.UNG_848 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if m ~= me then
        g.damage(me, m, 2)
      end
    end
  end,
}

-- Elise the Trailblazer: shuffle a sealed Un'Goro pack into your deck; it adds 5 Journey to Un'Goro cards to the hand.
cards.UNG_851 = {
  battlecry = function(g, me)
    g.add_to_deck(g.ctrl(me), "UNG_851t1")
  end,
}
cards.UNG_851t1 = {
  spell = function(g, me)
    -- five cards of the set (no Quest: g.collectible has none), any class, one of them at least Epic
    local set = pool(g, function(i)
      return i.set == "UNGORO" and not_hero(i)
    end)
    local picked = {}
    local high = false
    for k = 1, 5 do
      local c = g.pick((k == 5 and not high) and list.filter(set, function(x)
        local r = g.info(x).rarity
        return r == "EPIC" or r == "LEGENDARY"
      end) or set)
      if c then
        local r = g.info(c).rarity
        high = high or r == "EPIC" or r == "LEGENDARY"
        picked[#picked + 1] = c
      end
    end
    for _, c in ipairs(picked) do
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Spiritsinger Umbra: after you summon a minion, trigger its Deathrattle.
cards.UNG_900 = {
  on = {
    after_summon = function(g, me, ev)
      if g.mine(me, ev) and ev.entity ~= me and alive(g, ev.entity) then
        g.deathrattle(ev.entity)
      end
    end,
  },
}

-- Ozruk: Taunt; Battlecry: +5 Health for each Elemental you played last turn.
cards.UNG_907 = {
  battlecry = function(g, me)
    local n = g.count(g.ctrl(me), "ELEM_LAST")
    if n > 0 then
      g.buff(me, 0, 5 * n)
    end
  end,
  glow = elemental_glow,
}

-- Primalfin Lookout: if you control another Murloc, Discover a Murloc.
local function other_murloc(g, me)
  return list.any(g.others(me), function(m)
    return g.race(m) == "MURLOC"
  end)
end
cards.UNG_937 = {
  battlecry = function(g, me)
    if other_murloc(g, me) then
      discover(g, me, function(i)
        return i.type == "MINION" and i.race == "MURLOC"
      end)
    end
  end,
  on_choose = to_hand,
  glow = other_murloc,
}

-- Gluttonous Ooze: destroy your opponent's weapon and gain Armor equal to its Attack.
cards.UNG_946 = {
  battlecry = function(g, me)
    local w = g.weapon(g.enemy(me))
    if w then
      local a = g.atk(w)
      g.destroy(w)
      g.gain_armor(g.ctrl(me), a)
    end
  end,
}

return cards
