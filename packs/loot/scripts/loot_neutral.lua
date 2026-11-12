-- Kobolds & Catacombs (December 2017): the neutral cards as at the release (patch 10.0.0.22611 of 2017-12-06;
-- hearthstone.wiki.gg and its card notes; docs/packs/api.md).
local cards = {}

-- --- helpers (the same in every loot*.lua) -------------------------------------------------------------------------

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
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

-- The collectible cards of the pack's constructed sets (a hero card too) whose data pass ok.
local function pool(g, ok)
  return list.filter(g.collectible(), function(c)
    return ok(g.info(c))
  end)
end

local function random_card(g, ok)
  return g.pick(pool(g, ok))
end

local function random_class_card(g, cls)
  return random_card(g, function(i)
    return of_class(i, cls)
  end)
end

local function minion_of(ok)
  return function(i)
    return i.type == "MINION" and (not ok or ok(i))
  end
end

local function info(g, e)
  return g.info(g.card(e))
end

local function alive(g, m)
  return g.zone(m) == "PLAY" and g.health(m) > 0 and not g.has(m, "TO_DESTROY")
end

local function summon_here(g, me, card)
  local pos = g.died_pos(me)
  return g.summon(g.ctrl(me), card, pos >= 0 and pos or nil)
end

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

-- The different card ids of a list of entities (in order).
local function distinct_cards(g, es)
  local seen, out = {}, {}
  for _, e in ipairs(es) do
    local c = g.card(e)
    if not seen[c] then
      seen[c] = true
      out[#out + 1] = c
    end
  end
  return out
end

-- An `on` hook set for one event of me's player (`ev.player` is me's controller).
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

local function end_of_my_turn(f)
  return on_mine("turn_end", f)
end

-- "If it's your opponent's turn" (a Deathrattle: the dead minion's controller is not the one whose turn it is).
local function opponents_turn(g, me)
  return g.current() ~= g.ctrl(me)
end

-- The minions of p that died this game, in the order they died (the player hooks' DIED_ORDER), passing ok.
local function dead_minions(g, p, ok)
  local dead = list.filter(g.graveyard(p), function(e)
    return g.type(e) == "MINION" and g.died_pos(e) >= 0 and (not ok or ok(e))
  end)
  return list.sort_by(dead, function(e)
    return g.tag(e, "DIED_ORDER")
  end)
end

-- p's deck has no card of this Cost (the Princes: the cards' printed Cost).
local function no_cost_in_deck(g, p, cost)
  return not list.any(g.deck(p), function(e)
    return info(g, e).cost == cost
  end)
end

local function prince_glow(cost)
  return function(g, me)
    return no_cost_in_deck(g, g.ctrl(me), cost)
  end
end

local function random_from_deck(g, p, ok)
  return g.pick(list.filter(g.deck(p), ok))
end

-- Removes the top n cards of p's deck (not drawn: no draw, no fatigue; Keening Banshee, Gnomeferatu); returns them.
local function remove_top(g, p, n)
  local out = {}
  for _ = 1, n do
    local d = g.deck(p)
    local top = d[#d]
    if not top then
      break
    end
    g.remove(top, "GRAVEYARD")
    g.log({ type = "removed_from_deck", player = p, entity = top, card = g.card(top) })
    out[#out + 1] = top
  end
  return out
end

local function damage_all_minions(g, me, n)
  for _, m in ipairs(g.all_minions()) do
    g.damage(me, m, n)
  end
end

local function enemy_minions(g, me)
  return g.minions(g.enemy(me))
end

local function frozen_enemy(g, me)
  return list.any(g.chars(g.enemy(me)), function(c)
    return g.has(c, "FROZEN")
  end)
end

local function other_friendly(g, me, t)
  return t ~= me
end

local function has_weapon(g, me)
  return g.weapon(g.ctrl(me)) ~= nil
end

-- --- Discover (2017: the class cards four times as likely as the neutral ones) ----------------------------------

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

-- Three different cards of a list (each as likely), offered to me's player.
local function offer_cards(g, me, ids)
  local p = g.ctrl(me)
  local opts = {}
  for _, c in ipairs(pick_n(g, ids, 3)) do
    opts[#opts + 1] = g.create(p, c)
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

-- The choices of a Discover of cards passing ok: the class's cards (tri-class ones of it too) and the neutral ones; a
-- hero card too ("Hero cards can be randomly generated and Discovered, just like any other collectible card").
local function discover_choices(g, cls, ok)
  local choices = {}
  for _, c in ipairs(g.collectible()) do
    local i = g.info(c)
    if ok(i) then
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

-- --- Kobolds & Catacombs' helpers ------------------------------------------------------------------------------------

-- Recruit (wiki: "Recruit"): a random minion of p's deck that passes ok (an entity of the deck: `g.cost(e) <= 4`) is
-- summoned at the right end of the board (a summon, no Battlecry); none on a full board or when none matches (it stays in
-- the deck). Returns the minion or nil.
local function recruit(g, p, ok)
  if g.room(p) <= 0 then
    return nil
  end
  local e = g.pick(list.filter(g.deck(p), function(d)
    return g.type(d) == "MINION" and (not ok or ok(d))
  end))
  if not e then
    return nil
  end
  return g.summon_entity(e)
end

-- "Cast this when drawn" (TOPDECK): f(g, me) is the card's effect (with its "Draw a card"). Drawn, it leaves the hand,
-- shows itself to both players and casts itself; played from the hand (a copy of it: Psionic Probe), the same. Not in
-- the mulligan, not burnt on a full hand, not put into the hand otherwise (hand hooks: the `draw` event only).
local function cast_when_drawn(f, rest)
  local h = rest or {}
  h.spell = function(g, me)
    f(g, me)
  end
  h.hand = {
    draw = function(g, me, ev)
      if ev.entity == me then
        local p = g.ctrl(me)
        g.remove(me, "GRAVEYARD")
        g.log({ type = "cast_when_drawn", player = p, entity = me, card = g.card(me) })
        f(g, me)
      end
    end,
  }
  return h
end

-- A card that becomes another in its own player's hand (a Spellstone upgrades, an Unidentified item is identified,
-- Shifting Scroll): a new card (its cost changes are gone: wiki, "Transform in hand"); one that started in the deck
-- still did (Leyline Manipulator: a card that transforms itself keeps it).
local function self_transform(g, me, card)
  local started = g.has(me, "STARTED_IN_DECK")
  local n = g.transform(me, card)
  if n and started then
    g.set_tag(n, "STARTED_IN_DECK", true)
  end
  return n
end

-- Copies of friendly minion t summoned right of it (its stats, enchantments and keywords: g.copy_minion); returns them.
local function summon_copies(g, t, n)
  local out = {}
  for _ = 1, n do
    local c = g.summon_right(t, g.card(t))
    if not c then
      break
    end
    out[#out + 1] = g.copy_minion(c, t) or c
  end
  return out
end

-- --- the neutral cards -------------------------------------------------------------------------------------------------

local DARKNESS = "LOOT_526"

-- The collectible minions passing ok that a random summon may make: never The Darkness (wiki: it is left out of random
-- summons; it would only sleep for good).
local function random_minion(g, ok)
  return random_card(g, function(i)
    return i.type == "MINION" and i.id ~= DARKNESS and ok(i)
  end)
end

local function of_cost(n)
  return function(i)
    return i.cost == n
  end
end

-- Sewer Crawler: a 2/3 Giant Rat.
cards.LOOT_069 = {
  battlecry = function(g, me)
    g.summon_right(me, "LOOT_069t")
  end,
}

-- Scorp-o-matic: destroy a minion with 1 or less Attack.
cards.LOOT_111 = {
  target = {
    base = "minion",
    filter = function(g, me, t)
      return t ~= me and g.atk(t) <= 1
    end,
  },
  battlecry = function(g, me, t)
    if t then
      g.destroy(t)
    end
  end,
}

-- Ebon Dragonsmith: a random weapon in your hand costs (2) less.
cards.LOOT_118 = {
  battlecry = function(g, me)
    local w = g.pick(list.filter(g.hand(g.ctrl(me)), function(e)
      return g.type(e) == "WEAPON"
    end))
    if w then
      g.enchant(w, { cost = -2 })
    end
  end,
}

-- Corrosive Sludge: destroy your opponent's weapon.
cards.LOOT_122 = {
  battlecry = function(g, me)
    g.destroy(g.weapon(g.enemy(me)))
  end,
}

-- Lone Champion: if you control no other minions, Taunt and Divine Shield.
local function alone(g, me)
  return #g.others(me) == 0
end
cards.LOOT_124 = {
  glow = function(g, me)
    return #g.minions(g.ctrl(me)) == 0
  end,
  battlecry = function(g, me)
    if alone(g, me) then
      g.give_tag(me, "TAUNT")
      g.give_tag(me, "DIVINE_SHIELD")
    end
  end,
}

-- Arcane Tyrant: costs (0) if you've cast a spell of Cost 5 or more this turn (its paid cost: the player hooks'
-- BIG_SPELL_TURN).
local function big_spell_now(g, me)
  local p = g.ctrl(me)
  return g.count(p, "BIG_SPELLS") > 0 and g.count(p, "BIG_SPELL_TURN") == g.turn()
end
cards.LOOT_130 = {
  glow = big_spell_now,
  cost_mod = function(g, me)
    return big_spell_now(g, me) and -1000 or 0
  end,
}

-- Green Jelly: at the end of your turn, a 1/2 Ooze with Taunt.
cards.LOOT_131 = end_of_my_turn(function(g, me)
  g.summon_right(me, "LOOT_131t1")
end)

-- Dragonslayer: 6 damage to a Dragon.
cards.LOOT_132 = {
  target = {
    base = "minion",
    filter = function(g, me, t)
      return t ~= me and g.race(t) == "DRAGON"
    end,
  },
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, 6)
    end
  end,
}

-- Toothy Chest: at the start of your turn, its Attack becomes 4 (wiki: every turn, over other Attack-setting effects).
cards.LOOT_134 = on_mine("turn_start", function(g, me)
  g.set_stats(me, 4, nil)
end)

-- Sneaky Devil: your other minions have +1 Attack.
cards.LOOT_136 = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      g.aura_add(m, 1, 0)
    end
  end,
}

-- Hoarding Dragon: your opponent gets two Coins.
cards.LOOT_144 = {
  deathrattle = function(g, me)
    for _ = 1, 2 do
      g.add_to_hand(g.enemy(me), COIN)
    end
  end,
}

-- Corridor Creeper: costs (1) less whenever a minion dies while it is in your hand (CREEPER: how many).
cards.LOOT_149 = {
  hand = {
    death = function(g, me, ev)
      if ev.minion then
        g.add_tag(me, "CREEPER", 1)
      end
    end,
  },
  cost_mod = function(g, me)
    return -g.tag(me, "CREEPER")
  end,
}

-- Furbolg Mossbinder: a friendly minion becomes a 6/6 Moss Elemental.
cards.LOOT_150 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me
  end },
  battlecry = function(g, me, t)
    if t then
      g.transform(t, "LOOT_150t1")
    end
  end,
}

-- Boisterous Bard: your other minions +1 Health.
cards.LOOT_152 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.others(me)) do
      g.buff(m, 0, 1)
    end
  end,
}

-- Violet Wurm: seven 1/1 Grubs where it was.
cards.LOOT_153 = {
  deathrattle = function(g, me)
    for _ = 1, 7 do
      summon_here(g, me, "LOOT_153t1")
    end
  end,
}

-- Gravelsnout Knight: a random 1-Cost minion for your opponent; Hungry Ettin: a 2-Cost one.
local function gift_minion(cost)
  return {
    battlecry = function(g, me)
      local c = random_minion(g, of_cost(cost))
      if c then
        g.summon(g.enemy(me), c)
      end
    end,
  }
end
cards.LOOT_154 = gift_minion(1)
cards.LOOT_383 = gift_minion(2)

-- Carnivorous Cube: destroy a friendly minion; Deathrattle: two copies of it (wiki: plain copies; a Cube that ate
-- nothing is empty). The eaten minions are CUBE_1, CUBE_2… (CUBE_N of them: a doubled Battlecry eats two).
cards.LOOT_161 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me
  end },
  battlecry = function(g, me, t)
    if not t then
      return
    end
    local n = g.tag(me, "CUBE_N") + 1
    g.set_tag(me, "CUBE_N", n)
    g.set_tag(me, "CUBE_" .. n, t)
    g.destroy(t)
  end,
  deathrattle = function(g, me)
    for i = 1, g.tag(me, "CUBE_N") do
      local c = g.card(g.tag(me, "CUBE_" .. i))
      for _ = 1, 2 do
        summon_here(g, me, c)
      end
    end
  end,
}

-- Fungalmancer: adjacent minions +2/+2.
cards.LOOT_167 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.adjacent(me)) do
      g.buff(m, 2, 2)
    end
  end,
}

-- Silver Vanguard: Recruit an 8-Cost minion.
cards.LOOT_184 = {
  deathrattle = function(g, me)
    recruit(g, g.ctrl(me), function(e)
      return g.cost(e) == 8
    end)
  end,
}

-- Feral Gibberer: after it attacks a hero, a copy of it in your hand.
cards.LOOT_218 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == me and g.is_champion(ev.defender) then
        g.add_to_hand(g.ctrl(me), g.card(me))
      end
    end,
  },
}

-- Cursed Disciple: a 5/1 Cursed Revenant.
cards.LOOT_233 = {
  deathrattle = function(g, me)
    summon_here(g, me, "LOOT_233t")
  end,
}

-- Shroom Brewer: restore 4 Health.
cards.LOOT_291 = {
  target = "any",
  battlecry = function(g, me, t)
    if t then
      g.heal(me, t, 4)
    end
  end,
}

-- Kobold Apprentice: 3 damage randomly split among all enemies.
cards.LOOT_347 = {
  battlecry = function(g, me)
    for _ = 1, 3 do
      g.damage(me, g.random_alive(g.chars(g.enemy(me))), 1)
    end
  end,
}

-- Marin the Fox: a 0/8 Master Chest for your opponent; its Deathrattle gives the chest's opponent (Marin's player) one
-- of four treasures.
cards.LOOT_357 = {
  battlecry = function(g, me)
    g.summon(g.enemy(me), "LOOT_357l")
  end,
}
cards.LOOT_357l = {
  deathrattle = function(g, me)
    g.add_to_hand(g.enemy(me), g.pick({ "LOOT_998h", "LOOT_998j", "LOOT_998k", "LOOT_998l" }))
  end,
}

-- Tolin's Goblet: draw a card, fill your hand with plain copies of it (until patch 30.2 of 2024 not the buffed card).
-- The card p draws now as it is in the hand (an Unidentified one identified), or nil (burnt, cast when drawn, fatigue).
local function draw_one(g, p)
  local n = #g.hand(p)
  g.draw(p)
  local h = g.hand(p)
  return #h > n and h[#h] or nil
end

cards.LOOT_998h = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local d = draw_one(g, p)
    if not d then
      return
    end
    local c = g.card(d)
    while #g.hand(p) < g.rule("hand") do
      if not g.add_to_hand(p, c) then
        break
      end
    end
  end,
}

-- Zarog's Crown: Discover a Legendary minion, summon two copies of it (only summoned until patch 26.6 of 2023).
local function legendary_minion(i)
  return i.type == "MINION" and i.rarity == "LEGENDARY" and i.id ~= DARKNESS
end
cards.LOOT_998j = {
  spell = function(g, me)
    discover(g, me, legendary_minion)
  end,
  on_choose = function(g, me, option)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), g.card(option))
    end
  end,
}

-- Golden Kobold: every card of your hand becomes a random Legendary minion (no cost change until 2024).
cards.LOOT_998k = {
  battlecry = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      local c = random_card(g, legendary_minion)
      if c then
        g.transform(e, c)
      end
    end
  end,
}

-- Wondrous Wand: draw 3 cards, they cost (0).
cards.LOOT_998l = {
  spell = function(g, me)
    for _ = 1, 3 do
      local d = draw_one(g, g.ctrl(me))
      if d then
        g.enchant(d, { cost_set = 0 })
      end
    end
  end,
}

-- Guild Recruiter: Recruit a minion of Cost 4 or less.
cards.LOOT_375 = {
  battlecry = function(g, me)
    recruit(g, g.ctrl(me), function(e)
      return g.cost(e) <= 4
    end)
  end,
}

-- Kobold Monk: your champion can't be targeted by spells or Hero Powers (either player's: ELUSIVE).
cards.LOOT_382 = {
  aura = function(g, me)
    g.aura_add(g.hero(g.ctrl(me)), 0, 0, { ELUSIVE = true })
  end,
}

-- Fungal Enchanter: restore 2 Health to all friendly characters.
cards.LOOT_388 = {
  battlecry = function(g, me)
    for _, c in ipairs(g.chars(g.ctrl(me))) do
      g.heal(me, c, 2)
    end
  end,
}

-- Rummaging Kobold: a fresh copy of one of your destroyed weapons (WEAPON_DESTROYED; Kingsbane went back to the deck).
cards.LOOT_389 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local w = g.pick(list.filter(g.graveyard(p), function(e)
      return g.has(e, "WEAPON_DESTROYED")
    end))
    if w then
      g.add_to_hand(p, g.card(w))
    end
  end,
}

-- Shrieking Shroom: at the end of your turn, a random 1-Cost minion.
cards.LOOT_394 = end_of_my_turn(function(g, me)
  local c = random_minion(g, of_cost(1))
  if c then
    g.summon_right(me, c)
  end
end)

-- Plated Beetle: 3 Armor.
cards.LOOT_413 = {
  deathrattle = function(g, me)
    g.gain_armor(g.ctrl(me), 3)
  end,
}

-- Grand Archivist: at the end of your turn, a random spell of your deck is cast with random targets (wiki: it leaves the
-- deck; only one that can be cast is picked: one that fizzles goes back and another is tried; an Unidentified one is
-- the plain card).
-- ponytail: a spell that could not be cast goes back to a random place of the deck, not its own.
cards.LOOT_414 = end_of_my_turn(function(g, me)
  local p = g.ctrl(me)
  local spells = g.shuffle(list.filter(g.deck(p), function(e)
    return g.type(e) == "SPELL"
  end))
  for _, e in ipairs(spells) do
    g.remove(e, "GRAVEYARD")
    if g.cast_random(me, g.card(e)) then
      g.resolve()
      return
    end
    g.to_deck(e, p)
  end
end)

-- Zola the Gorgon: a (Golden: plain) copy of a friendly minion in your hand.
cards.LOOT_516 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me
  end },
  battlecry = function(g, me, t)
    if t then
      g.add_to_hand(g.ctrl(me), g.card(t))
    end
  end,
}

-- Master Oakheart: Recruit a 1-, a 2- and a 3-Attack minion.
cards.LOOT_521 = {
  battlecry = function(g, me)
    for a = 1, 3 do
      recruit(g, g.ctrl(me), function(e)
        return g.atk(e) == a
      end)
    end
  end,
}

-- The Darkness: it enters Dormant (UNTOUCHABLE, any summon: wiki, summoned without being played it sleeps for good);
-- Battlecry: 3 Darkness Candles into the enemy deck (CANDLES: those not snuffed yet). A Candle cast for a player (drawn,
-- or cast from the deck by Grand Archivist) snuffs one of the opponent's sleeping Darkness's candles (the oldest with
-- some left), then draws; the third wakes it. One its own player gets (Psionic Probe) snuffs none, but draws.
cards.LOOT_526 = {
  on = {
    summon = function(g, me, ev)
      if ev.entity == me then
        g.give_tag(me, "UNTOUCHABLE")
      end
    end,
  },
  battlecry = function(g, me)
    local p = g.ctrl(me)
    g.set_tag(me, "CANDLES", 3)
    g.add_count(p, "DARKNESS_" .. g.add_count(p, "DARKNESSES"), me)
    for _ = 1, 3 do
      g.add_to_deck(g.enemy(me), "LOOT_526t")
    end
  end,
}
-- (a dormant minion is in no list: p's Darknesses with candles are the counts DARKNESS_1, DARKNESS_2…)
local function sleeping_darkness(g, p)
  for i = 1, g.count(p, "DARKNESSES") do
    local d = g.count(p, "DARKNESS_" .. i)
    if g.zone(d) == "PLAY" and g.ctrl(d) == p and g.card(d) == DARKNESS and g.has(d, "UNTOUCHABLE")
      and g.tag(d, "CANDLES") > 0 then
      return d
    end
  end
  return nil
end
cards.LOOT_526t = cast_when_drawn(function(g, me)
  local p = g.ctrl(me)
  local d = sleeping_darkness(g, g.opponent(p))
  if d then
    g.add_tag(d, "CANDLES", -1)
    if g.tag(d, "CANDLES") <= 0 then
      g.erase_tag(d, "UNTOUCHABLE")
      g.log({ type = "awaken", player = g.ctrl(d), entity = d, card = DARKNESS })
    end
  end
  g.draw(p)
end)

-- Void Ripper: every other minion's Attack and Health swap (a 0-Attack one dies).
cards.LOOT_529 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if m ~= me then
        g.set_stats(m, g.health(m), g.atk(m))
      end
    end
  end,
}

-- Spiteful Summoner: reveal a random spell of your deck (it stays there; both players see it), summon a random minion
-- of its Cost (its Cost now).
cards.LOOT_539 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local s = g.pick(list.filter(g.deck(p), function(e)
      return g.type(e) == "SPELL"
    end))
    if not s then
      return
    end
    g.log({ type = "reveal", player = p, card = g.card(s) }) -- (no entity: a deck card's would be hidden)
    local c = random_minion(g, of_cost(g.cost(s)))
    if c then
      g.summon_right(me, c)
    end
  end,
}

-- Dragonhatcher: at the end of your turn, Recruit a Dragon.
cards.LOOT_540 = end_of_my_turn(function(g, me)
  recruit(g, g.ctrl(me), function(e)
    return g.race(e) == "DRAGON"
  end)
end)

-- King Togwaggle: the decks swap (not the hands, not the boards); the opponent gets King's Ransom (none on a full hand),
-- which swaps them back.
local function swap_decks(g, me)
  local p = g.ctrl(me)
  local o = g.opponent(p)
  local mine, theirs = g.deck(p), g.deck(o)
  for _, e in ipairs(mine) do
    g.to_deck(e, o)
  end
  for _, e in ipairs(theirs) do
    g.to_deck(e, p)
  end
end
cards.LOOT_541 = {
  battlecry = function(g, me)
    swap_decks(g, me)
    g.add_to_hand(g.enemy(me), "LOOT_541t")
  end,
}
cards.LOOT_541t = {
  spell = swap_decks,
}

return cards
