-- Kobolds & Catacombs (December 2017): the Paladin, Priest and Rogue cards as at the release (patch 10.0.0.22611 of
-- 2017-12-06; hearthstone.wiki.gg; docs/packs/api.md). Their Spellstones and Unidentified items are in loot.lua.
local cards = {}

-- --- helpers (the same in every loot*.lua) -------------------------------------------------------------------------

-- --- helpers -----------------------------------------------------------------------------------

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

-- --- Paladin --------------------------------------------------------------------------------------------------------

local SILVER_HAND = "VAN_CS2_101t"

local function is_recruit(g, m)
  return g.card(m) == SILVER_HAND
end

-- Potion of Heroism: Divine Shield, draw a card.
cards.LOOT_088 = {
  target = "minion",
  spell = function(g, me, t)
    g.give_tag(t, "DIVINE_SHIELD")
    g.draw(g.ctrl(me))
  end,
}

-- Call to Arms: Recruit 3 minions that cost (2) or less (one at a time: a summon trigger sees each).
cards.LOOT_093 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 3 do
      recruit(g, p, function(e)
        return g.cost(e) <= 2
      end)
    end
  end,
}

-- Lynessa Sunsorrow: every spell its player played on their own minion this game (ON_OWN_MINION, the player hooks), in
-- the order they were played, cast again on her. The release (until patch 11.2 of 2018-06-05): no cap of 30, the
-- original order, no Choose One spell. Each resolves (deaths too) before the next; it stops once she is gone.
cards.LOOT_216 = {
  battlecry = function(g, me)
    for _, s in ipairs(g.graveyard(g.ctrl(me))) do
      if not alive(g, me) then
        break
      end
      if g.is_spell(s) and g.has(s, "ON_OWN_MINION") and g.choice(s) < 0 then
        g.cast(me, s, me)
        g.resolve()
      end
    end
  end,
}

-- Crystal Lion: costs (1) less for each Silver Hand Recruit you control.
cards.LOOT_313 = {
  cost_mod = function(g, me)
    return -list.count(g.minions(g.ctrl(me)), function(m)
      return is_recruit(g, m)
    end)
  end,
}

-- Level Up!: your Silver Hand Recruits +2/+2 and Taunt.
cards.LOOT_333 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if is_recruit(g, m) then
        g.buff(m, 2, 2)
        g.give_tag(m, "TAUNT")
      end
    end
  end,
}

-- Drygulch Jailor: Deathrattle: 3 Silver Hand Recruits to your hand.
cards.LOOT_363 = {
  deathrattle = function(g, me)
    for _ = 1, 3 do
      g.add_to_hand(g.ctrl(me), SILVER_HAND)
    end
  end,
}

-- Benevolent Djinn: at the end of your turn, restore 3 Health to your hero.
cards.LOOT_398 = end_of_my_turn(function(g, me)
  g.heal(me, g.hero(g.ctrl(me)), 3)
end)

-- Val'anyr: Deathrattle: a random minion in your hand +4/+2 and "Deathrattle: equip a 4/2 Val'anyr" (LOOT_500e; a new
-- Val'anyr with the same Deathrattle, so it goes on). No minion in the hand: nothing.
local VALANYR = "LOOT_500"
cards.LOOT_500 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    local m = g.pick(list.filter(g.hand(p), function(e)
      return g.is_minion(e)
    end))
    if m then
      g.buff(m, 4, 2)
      g.enchant(m, { hooks = "ench:loot_ppr_valanyr", player = p })
    end
  end,
}
cards["ench:loot_ppr_valanyr"] = {
  deathrattle = function(g, me)
    g.equip(g.ctrl(me), VALANYR)
  end,
}

-- --- Priest ---------------------------------------------------------------------------------------------------------

local function holding_dragon(g, me)
  return list.any(g.hand(g.ctrl(me)), function(e)
    return e ~= me and g.race(e) == "DRAGON"
  end)
end

-- Psychic Scream: every minion (both sides, in play order) into the opponent's deck as a fresh card: it leaves the board
-- without dying (no Deathrattle), its enchantments gone.
cards.LOOT_008 = {
  spell = function(g, me)
    local foe = g.enemy(me)
    for _, m in ipairs(g.all_minions()) do
      local c = g.card(m)
      g.remove(m, "SETASIDE")
      g.add_to_deck(foe, c)
    end
  end,
}

-- Twilight's Call: 1/1 copies of 2 random friendly minions with a Deathrattle (their card's) that died this game;
-- playable only once a friendly minion died.
cards.LOOT_187 = {
  can_play = function(g, me)
    local p = g.ctrl(me)
    return list.any(g.graveyard(p), function(e)
      return g.type(e) == "MINION" and g.died_pos(e) >= 0
    end)
  end,
  spell = function(g, me)
    local p = g.ctrl(me)
    local dead = dead_minions(g, p, function(e)
      return has_kw(info(g, e), "DEATHRATTLE")
    end)
    for _, e in ipairs(pick_n(g, dead, 2)) do
      local n = g.summon(p, g.card(e))
      if n then
        g.set_stats(n, 1, 1)
      end
    end
  end,
}

-- Dragon Soul: after you cast your 3rd, 6th, … spell in a turn (TURN_SPELLS, the player hooks: the ones before it was
-- equipped too), a 5/5 Dragon Spirit.
cards.LOOT_209 = on_mine("after_spell", function(g, me)
  local n = g.count(g.ctrl(me), "TURN_SPELLS")
  if n > 0 and n % 3 == 0 then
    g.summon(g.ctrl(me), "LOOT_209t")
  end
end)

-- Psionic Probe: a copy of a random spell of your opponent's deck (the plain card: patch 12.0 made it keep enchantments).
cards.LOOT_353 = {
  spell = function(g, me)
    local s = random_from_deck(g, g.enemy(me), function(e)
      return g.is_spell(e)
    end)
    if s then
      g.add_to_hand(g.ctrl(me), g.card(s))
    end
  end,
}

-- Duskbreaker: if you're holding a Dragon, 3 damage to all other minions.
cards.LOOT_410 = {
  glow = holding_dragon,
  battlecry = function(g, me)
    if holding_dragon(g, me) then
      for _, m in ipairs(g.all_minions()) do
        if m ~= me then
          g.damage(me, m, 3)
        end
      end
    end
  end,
}

-- Twilight Acolyte: if you're holding a Dragon, swap its Attack with another minion's (a target only then).
cards.LOOT_528 = {
  glow = holding_dragon,
  target = { base = "minion", when = holding_dragon, filter = function(g, me, t)
    return t ~= me
  end },
  battlecry = function(g, me, t)
    if t then
      local a = g.atk(me)
      g.set_stats(me, g.atk(t), nil)
      g.set_stats(t, a, nil)
    end
  end,
}

-- Gilded Gargoyle: Deathrattle: a Coin to your hand.
cards.LOOT_534 = {
  deathrattle = function(g, me)
    g.add_to_hand(g.ctrl(me), COIN)
  end,
}

-- Temporus: your opponent takes two turns, then you take two. Each Battlecry queues the 4 turns after the current one
-- (wiki; with Brann: A-B-B-A-A-B-B-A-A-B…; patch 10.2 made several Temporus queue as well, the intended rule played here).
-- Its player's count TEMPORUS is the extra turns still owed (2 a Battlecry), given one by one at the start of a turn that
-- follows the other player's (TEMPORUS_LAST: 1 + the player of the last turn start); an extra turn itself gives none.
-- The player hooks of loot.lua give them (they stay with a new champion: a hero card).
cards.LOOT_538 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if g.count(p, "TEMPORUS") <= 0 then
      g.add_count(p, "TEMPORUS_LAST", g.current() + 1 - g.count(p, "TEMPORUS_LAST"))
    end
    g.add_count(p, "TEMPORUS", 2)
  end,
}

-- --- Rogue ----------------------------------------------------------------------------------------------------------

-- Fal'dorei Strider: 3 Spider Ambush! into your deck.
cards.LOOT_026 = {
  battlecry = function(g, me)
    for _ = 1, 3 do
      g.add_to_deck(g.ctrl(me), "LOOT_026e")
    end
  end,
}

-- Spider Ambush!: a 4/4 Leyline Spider, draw a card; cast when drawn.
cards.LOOT_026e = cast_when_drawn(function(g, me)
  local p = g.ctrl(me)
  g.summon(p, "LOOT_026t")
  g.draw(p)
end)

-- Cavern Shinyfinder: draw a random weapon from your deck.
cards.LOOT_033 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local w = random_from_deck(g, p, function(e)
      return g.is_weapon(e)
    end)
    if w then
      g.draw_entity(p, w)
    end
  end,
}

-- Sonya Shadowdancer: after a friendly minion dies (not she), a 1/1 copy of it (the plain card) costing (1) to your hand.
cards.LOOT_165 = {
  on = {
    death = function(g, me, ev)
      if ev.minion and g.mine(me, ev) and ev.entity ~= me then
        local n = g.add_to_hand(g.ctrl(me), ev.card)
        if n then
          g.set_stats(n, 1, 1)
          g.enchant(n, { cost_set = 1 })
        end
      end
    end,
  },
}

-- Cheat Death: Secret: when a friendly minion dies, it returns to your hand (a fresh card) costing (2) less.
cards.LOOT_204 = {
  secret = {
    event = "death",
    cond = function(g, me, ev)
      return ev.minion and g.mine(me, ev)
    end,
    effect = function(g, me, ev)
      local n = g.add_to_hand(g.ctrl(me), ev.card)
      if n then
        g.enchant(n, { cost = -2 })
      end
    end,
  },
}

-- Sudden Betrayal: Secret: when a minion attacks your hero, it attacks a random one of its neighbours instead (none: the
-- Secret waits).
local function neighbours(g, m)
  return list.filter(g.adjacent(m), function(x)
    return alive(g, x)
  end)
end
cards.LOOT_210 = {
  secret = {
    event = "attack",
    cond = function(g, me, ev)
      return ev.defender == g.hero(g.ctrl(me)) and g.is_minion(ev.attacker) and #neighbours(g, ev.attacker) > 0
    end,
    effect = function(g, me, ev)
      ev.defender = g.pick(neighbours(g, ev.attacker))
    end,
  },
}

-- Elven Minstrel: Combo: draw 2 random minions from your deck.
cards.LOOT_211 = {
  combo = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 2 do
      local m = random_from_deck(g, p, function(e)
        return g.is_minion(e)
      end)
      if not m then
        break
      end
      g.draw_entity(p, m)
    end
  end,
}

-- Evasion: Secret: after your hero takes damage, Immune this turn (the damage is taken).
cards.LOOT_214 = {
  secret = {
    event = "damage",
    cond = function(g, me, ev)
      return ev.target == g.hero(g.ctrl(me)) and ev.amount > 0
    end,
    effect = function(g, me)
      g.give_tag(g.hero(g.ctrl(me)), "IMMUNE", true)
    end,
  },
}

-- Kobold Illusionist: Deathrattle: a 1/1 copy of a random minion in your hand (the card stays; the plain card: patch 12.0
-- made the copy keep the card's enchantments).
cards.LOOT_412 = {
  deathrattle = function(g, me)
    local m = g.pick(list.filter(g.hand(g.ctrl(me)), function(e)
      return g.is_minion(e)
    end))
    if m then
      local n = summon_here(g, me, g.card(m))
      if n then
        g.set_stats(n, 1, 1)
      end
    end
  end,
}

-- Kingsbane: Deathrattle: shuffled into your deck, its enchantments kept (g.to_deck: its durability back).
cards.LOOT_542 = {
  deathrattle = function(g, me)
    g.to_deck(me)
  end,
}

return cards
