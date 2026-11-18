-- The Boomsday Project (August 2018): its 135 cards and their tokens as at the release (build 25770, patch 12.0.0.25770
-- of 2018-08-02; hearthstone.wiki.gg, its card notes and its pages as they were in 2018). Magnetic is the engine's FUSE
-- (a Magnetic minion played left of a friendly Mech: rules.json MODULAR), Whizbang the Wonderful's decks are rules.json
-- `deck_recipes`; the player hooks (boom.lua) keep Dr. Boom's Rush and Hero Powers, Celestial Emissary, Electra
-- Stormsurge, Omega Mind and the Pogo-Hoppers played. Release-day bugs fixed later are not copied (the fixed behaviour).
-- @@HELPERS@@
local cards = {}

-- --- helpers (the same in every boom*.lua; gil.lua's) --------------------------------------------------------------

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


-- --- The Witchwood's helpers (the same in every boom*.lua) ------------------------------------------------------------

local GLINDA = "GIL_618"

-- A friendly Glinda Crowskin (not silenced; not the card e itself) is in play: "Minions in your hand have Echo".
local function glinda_on(g, p, e)
  return list.any(g.minions(p), function(m)
    return m ~= e and g.card(m) == GLINDA and not g.silenced(m)
  end)
end

-- The card e of player p has Echo now: its card's keyword, a given ECHO tag (Glinda Crowskin's aura in the hand, a
-- Zombeast made of a Hunting Mastiff), or a minion while a friendly Glinda Crowskin is in play (wiki, "Echo").
local function echo_card(g, e, p)
  p = p or g.ctrl(e)
  return has_kw(info(g, e), "ECHO") or g.has(e, "ECHO") or (g.type(e) == "MINION" and glinda_on(g, p, e))
end

-- "If your hero took damage this turn" (the player hooks' HURT_TURN: the last turn p's champion took damage).
local function hurt_this_turn(g, p)
  return g.count(p, "HURT_TURN") == g.turn()
end

-- "If a minion died this turn" (either side's; DIED_TURN of the dead).
local function minions_died_this_turn(g)
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

-- "If you played an Elemental last turn" (the player hooks' ELEM_LAST).
local function elemental_last_turn(g, p)
  return g.count(p, "ELEM_LAST") > 0
end

-- "If you're holding a <race>" (a minion of every type, Nightmare Amalgam's ALL, counts; not the card itself).
local function holding(g, me, race)
  return list.any(g.hand(g.ctrl(me)), function(e)
    return e ~= me and (g.race(e) == race or g.race(e) == "ALL")
  end)
end

-- "If your deck has only odd-Cost cards" / "only even-Cost cards": every card of p's deck now (an empty deck too), by
-- its printed Cost (DOUBT: the wiki is silent on a changed Cost; the Start of Game cards read the printed one).
local function deck_only(g, p, odd)
  return not list.any(g.deck(p), function(e)
    return (info(g, e).cost % 2 == 1) ~= odd
  end)
end

-- Each turn in the hand it becomes its other form (the worgen; Chameleos): a transform in the hand that keeps its
-- enchantments and given tags (before patch 12.0.0.25770 of 2018-08-02; `g.transform(e, card, true)`).
local function shift_to(g, me, card)
  return g.transform(me, card, true)
end

-- --- Echo (wiki, "Echo") ----------------------------------------------------------------------------------------------
-- A card with Echo played from the hand gives its player a new copy of itself (the printed card: no change made to the
-- one played; cost auras still apply), after its play is done (after its Battlecry, its Deathrattles…); the copy has
-- Echo too and goes away at the end of the turn (GHOSTLY; not a discard). No (1) floor on a copy's Cost on 2018-04-12
-- (patch 16.0.0.37060 of 2019 added it). Only a card played counts (not one cast by another card). The player hooks run
-- it: `play` marks the card (ECHOING), `after_summon` / `after_spell` give the copy.

local function echo_copy(g, p, e)
  if not g.has(e, "ECHOING") then
    return
  end
  g.set_tag(e, "ECHOING", nil)
  local c = g.add_to_hand(p, g.card(e))
  if c then
    g.set_tag(c, "GHOSTLY", true)
  end
end

local function echo_fade(g, p)
  for _, e in ipairs(g.hand(p)) do
    if g.has(e, "GHOSTLY") then
      g.remove(e, "SETASIDE")
      g.log({ type = "faded", player = p, entity = e, card = g.card(e) })
    end
  end
end

-- --- Start of Game (wiki, "Start of Game"; Baku the Mooneater and Genn Greymane notes) --------------------------------
-- From the deck the player started with (the 30 cards, the opening hand's too; after the mulligan nothing changed it),
-- before Prince Malchezaar's Legendaries come: Baku: no even-Cost card (printed Cost; 0 is even) → the basic Hero Power
-- becomes its upgraded one (Justicar Trueheart's); Genn: no odd-Cost card → the starting Hero Power costs (1) (an
-- enchantment of that power: a new one later is not cheaper). Both players' in turn; each shows itself to both.

local BAKU, GENN = "GIL_826", "GIL_692"
local UPGRADE = {
  VAN_HERO_01bp = "AT_132_WARRIOR", VAN_HERO_02bp = "AT_132_SHAMAN", VAN_HERO_03bp = "AT_132_ROGUE",
  VAN_HERO_04bp = "AT_132_PALADIN", VAN_HERO_05bp = "AT_132_HUNTER", VAN_HERO_06bp = "AT_132_DRUID",
  VAN_HERO_07bp = "AT_132_WARLOCK", VAN_HERO_08bp = "AT_132_MAGE", VAN_HERO_09bp = "AT_132_PRIEST",
}

local function start_of_game(g, p)
  local all = {}
  for _, zone in ipairs({ g.deck(p), g.hand(p) }) do
    for _, e in ipairs(zone) do
      all[#all + 1] = e
    end
  end
  local function has_card(c)
    return list.any(all, function(e)
      return g.card(e) == c
    end)
  end
  local function only(odd)
    return not list.any(all, function(e)
      return (info(g, e).cost % 2 == 1) ~= odd
    end)
  end
  if has_card(BAKU) and only(true) then
    g.log({ type = "start_of_game", player = p, card = BAKU })
    local up = UPGRADE[g.card(g.power(p))]
    if up then
      g.set_power(p, up)
    end
  end
  if has_card(GENN) and only(false) then
    g.log({ type = "start_of_game", player = p, card = GENN })
    g.enchant(g.power(p), { cost_set = 1 })
  end
end

-- --- The Boomsday Project's helpers (the same in every boom*.lua) -------------------------------------------------

-- The game is over (a champion died).
local function over(g)
  return g.health(g.hero(0)) <= 0 or g.health(g.hero(1)) <= 0
end

-- "If you have 10 Mana Crystals" (Omega; wiki: 10 permanent crystals, empty, spent or Overloaded ones too, never The
-- Coin's or other temporary mana).
local function omega(g, p)
  return g.max_mana(p) >= 10
end

-- A Mech (Nightmare Amalgam's ALL too: `every_race`).
local function is_mech(g, e)
  return g.race(e) == "MECHANICAL"
end

local function mech_card(i)
  return i.type == "MINION" and i.race == "MECHANICAL"
end

-- Treants (wiki "Treant": a minion named Treant, Mana Treant too).
local TREANTS = { FP1_019t = true, GIL_663t = true, UNG_111t1 = true, VAN_EX1_tk9 = true, VAN_EX1_tk9b = true }
local function is_treant(g, e)
  return TREANTS[g.card(e)] == true
end

-- Copies (patch 12.0.0.25770 of 2018-08-02, "Game Mechanics Updates"): a copy keeps the enchantments of the card it
-- copies, unless it goes "backward" (hand or play → deck, play → hand: a plain card). c: the new copy (or nil).
local function keep_enchants(g, from, c)
  if c then
    g.copy_enchants(from, c)
  end
  return c
end

local function copy_to_hand(g, p, e)
  return keep_enchants(g, e, g.add_to_hand(p, g.card(e)))
end

-- How many times p's Deathrattles run now (Necromechanic, Baron Rivendare: DOUBLE_DEATHRATTLE on the champion; two of
-- them still twice).
local function deathrattle_times(g, p)
  return g.has(g.hero(p), "DOUBLE_DEATHRATTLE") and 2 or 1
end

-- "Trigger its Deathrattle" (Fireworks Tech, Necrium Vial, Necrium Blade): m's Deathrattles run without it dying, twice
-- with Necromechanic (Baron Rivendare's notes: "also doubles Deathrattles triggered by other cards").
local function trigger_deathrattle(g, m)
  for _ = 1, deathrattle_times(g, g.ctrl(m)) do
    if alive(g, m) then
      g.deathrattle(m)
      g.resolve()
    end
  end
end

-- n minions of card summoned right of me (as many as fit).
local function summon_right_n(g, me, card, n)
  for _ = 1, n do
    if not g.summon_right(me, card) then
      break
    end
  end
end

-- Draws a random card of p's deck passing ok (an entity); returns it or nil.
local function draw_from_deck(g, p, ok)
  local e = g.pick(list.filter(g.deck(p), ok))
  if e then
    g.draw_entity(p, e)
  end
  return e
end

-- @@END_HELPERS@@

-- --- Druid -------------------------------------------------------------------------------------------------------------

-- Biology Project: each player gains 2 Mana Crystals (full ones), you first.
cards.BOT_054 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.gain_mana(p, 2)
    g.gain_mana(g.opponent(p), 2)
  end,
}

-- Floop's Glorious Gloop: this turn, whenever a minion dies (either side), 1 Mana this turn (not above 10).
cards.BOT_444 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.enchant(g.hero(p), { hooks = "ench:boom_gloop", player = p, eot = true })
  end,
}
cards["ench:boom_gloop"] = {
  on = {
    death = function(g, me, ev)
      if ev.minion then
        g.add_mana(g.ctrl(me), 1)
      end
    end,
  },
}

local function controls_treant(g, me)
  return list.any(g.others(me), function(m)
    return is_treant(g, m)
  end)
end

-- Dendrologist: if you control a Treant (a minion named Treant), Discover a spell (your class's).
cards.BOT_419 = {
  glow = function(g, me)
    return list.any(g.minions(g.ctrl(me)), function(m)
      return is_treant(g, m)
    end)
  end,
  battlecry = function(g, me)
    if controls_treant(g, me) then
      discover(g, me, function(i)
        return i.type == "SPELL"
      end)
    end
  end,
  on_choose = to_hand,
}

-- Landscaping: two 2/2 Treants.
cards.BOT_420 = {
  spell = function(g, me)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), "VAN_EX1_tk9")
    end
  end,
}

-- Flobbidinous Floop: in your hand, each time you play a minion it becomes a 3/4 copy of it (a transform: its
-- enchantments go; the copied card's Cost; "Floopy" keeps it changing).
local function floop(g, me, ev)
  if not g.mine(me, ev) or ev.kind ~= "minion" or ev.entity == me then
    return
  end
  local n = g.transform(me, ev.card)
  if n then
    g.enchant(n, { set_atk = 3, set_hp = 4 })
    g.enchant(n, { hooks = "ench:boom_floop", player = g.ctrl(n) })
  end
end
cards.BOT_434 = { hand = { play = floop } }
cards["ench:boom_floop"] = { hand = { play = floop } }

-- Juicy Psychmelon: draw a 7-, 8-, 9- and 10-Cost minion from your deck (their Cost now), in that order.
cards.BOT_404 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for c = 7, 10 do
      draw_from_deck(g, p, function(e)
        return g.type(e) == "MINION" and g.cost(e) == c
      end)
    end
  end,
}

-- Tending Tauren: Choose One: your other minions +1/+1; or two 2/2 Treants (right of it). Both: the buff first.
local function tauren_buff(g, me)
  for _, m in ipairs(g.others(me)) do
    g.buff(m, 1, 1)
  end
end
local function tauren_treants(g, me)
  summon_right_n(g, me, "VAN_EX1_tk9", 2)
end
cards.BOT_422 = {
  choose_one = { "BOT_422a", "BOT_422b" },
  both = function(g, me)
    tauren_buff(g, me)
    tauren_treants(g, me)
  end,
}
cards.BOT_422a = { effect = tauren_buff }
cards.BOT_422b = { effect = tauren_treants }

-- Dreampetal Florist: at the end of your turn a random minion in your hand that costs more than (0) costs (7) less.
cards.BOT_423 = end_of_my_turn(function(g, me)
  local e = g.pick(list.filter(g.hand(g.ctrl(me)), function(c)
    return g.type(c) == "MINION" and g.cost(c) > 0
  end))
  if e then
    g.enchant(e, { cost = -7 })
  end
end)

-- Gloop Sprayer: a copy of each adjacent minion, each right of its original (the left one first; play → play copies
-- keep their enchantments, not their damage).
local function copy_right_of(g, t)
  local c = g.summon_right(t, g.card(t))
  if c then
    c = g.copy_minion(c, t) or c
    g.set_damage(c, 0)
  end
  return c
end
cards.BOT_507 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.adjacent(me)) do
      copy_right_of(g, m)
    end
  end,
}

-- Mulchmuncher: Rush; costs (1) less for each friendly Treant that died this game.
cards.BOT_523 = {
  cost_mod = function(g, me)
    return -#dead_minions(g, g.ctrl(me), function(e)
      return is_treant(g, e)
    end)
  end,
}

-- --- Hunter ------------------------------------------------------------------------------------------------------------

-- Secret Plan: Discover a Secret.
cards.BOT_402 = {
  spell = function(g, me)
    discover(g, me, function(i)
      return i.trap
    end)
  end,
  on_choose = to_hand,
}

-- Bomb Toss: $2 damage, then a 0/2 Goblin Bomb (even if the target died).
cards.BOT_033 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
    g.summon(g.ctrl(me), "BOT_031")
  end,
}

-- Cybertech Chip: your minions get "Deathrattle: add a random Mech to your hand".
cards.BOT_438 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, m in ipairs(g.minions(p)) do
      g.enchant(m, { hooks = "ench:boom_chip", player = p })
    end
  end,
}
cards["ench:boom_chip"] = {
  deathrattle = function(g, me)
    local c = random_card(g, mech_card)
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Fireworks Tech: a friendly Mech +1/+1; if it has a Deathrattle, it runs (it does not die).
cards.BOT_038 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me and is_mech(g, t)
  end },
  battlecry = function(g, me, t)
    if not t then
      return
    end
    g.buff(t, 1, 1)
    if g.has_deathrattle(t) then
      trigger_deathrattle(g, t)
    end
  end,
}

-- Goblin Prank: a friendly minion +3/+3 and Rush; it dies at the end of the turn (Silence takes both).
cards.BOT_437 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.enchant(t, { atk = 3, hp = 3, hooks = "ench:boom_prank", player = g.ctrl(me) })
    g.give_tag(t, "RUSH")
  end,
}
cards["ench:boom_prank"] = {
  on = {
    turn_end = function(g, me)
      g.destroy(me)
    end,
  },
}

-- Spider Bomb: Magnetic; Deathrattle: destroy a random enemy minion.
cards.BOT_251 = {
  deathrattle = function(g, me)
    g.destroy(g.random_alive(g.minions(g.enemy(me))))
  end,
}

-- Necromechanic: your Deathrattles trigger twice (the minions' as Baron Rivendare: DOUBLE_DEATHRATTLE; a weapon's: the
-- player hooks' NECRO_WEAPONS; those triggered by cards: trigger_deathrattle).
cards.BOT_039 = {
  aura = function(g, me)
    g.aura_add(g.hero(g.ctrl(me)), 0, 0, { DOUBLE_DEATHRATTLE = true, NECRO_WEAPONS = true })
  end,
}

-- Boommaster Flark: four 0/2 Goblin Bombs.
cards.BOT_034 = {
  battlecry = function(g, me)
    summon_right_n(g, me, "BOT_031", 4)
  end,
}

-- Flark's Boom-Zooka: 3 minions of your deck come (a summon, at the right end); each in turn, from the left, attacks a
-- random enemy minion (past Taunt and Stealth; wiki notes: random, not the left-most), then the ones alive die together
-- and their Deathrattles run left to right.
cards.BOT_429 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local ms = {}
    for _ = 1, 3 do
      local m = recruit(g, p)
      if m then
        ms[#ms + 1] = m
      end
    end
    for _, m in ipairs(ms) do
      local d = g.random_alive(g.minions(g.enemy(me)))
      if alive(g, m) and d then
        g.force_attack(m, d)
        g.resolve()
      end
    end
    for _, m in ipairs(ms) do
      if g.zone(m) == "PLAY" then
        g.destroy(m)
      end
    end
  end,
}

-- --- Mage --------------------------------------------------------------------------------------------------------------

-- Shooting Star: $1 damage to a minion and the minions next to it.
cards.BOT_453 = {
  target = "minion",
  spell = function(g, me, t)
    local n = g.spell_dmg(me, 1)
    local all = { t }
    for _, m in ipairs(g.adjacent(t)) do
      all[#all + 1] = m
    end
    for _, m in ipairs(all) do
      g.damage(me, m, n)
    end
  end,
}

-- Astral Rift: 2 random minions to your hand.
cards.BOT_101 = {
  spell = function(g, me)
    for _ = 1, 2 do
      local c = random_card(g, minion_of())
      if c then
        g.add_to_hand(g.ctrl(me), c)
      end
    end
  end,
}

-- Celestial Emissary: your next spell this turn has Spell Damage +2 (the player hooks' CELESTIAL).
cards.BOT_531 = {
  battlecry = function(g, me)
    g.add_count(g.ctrl(me), "CELESTIAL")
    g.update_auras()
  end,
}

-- Research Project: each player draws 2 cards, you first.
cards.BOT_600 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.draw(p, 2)
    g.draw(g.opponent(p), 2)
  end,
}

-- Stargazer Luna: after you play the card that was the right-most of your hand, draw a card (once it resolved).
local function luna_draw(g, me, ev)
  if g.mine(me, ev) and g.has(ev.entity, "LUNA_" .. me) then
    g.set_tag(ev.entity, "LUNA_" .. me, nil)
    g.draw(g.ctrl(me))
  end
end
cards.BOT_103 = {
  on = {
    play = function(g, me, ev)
      if not g.mine(me, ev) or ev.entity == me then
        return
      end
      local i, n = g.hand_slot(ev.entity)
      if i and i == n - 1 then
        if ev.kind == "minion" or ev.kind == "spell" then
          g.set_tag(ev.entity, "LUNA_" .. me, true)
        else
          g.draw(g.ctrl(me))
        end
      end
    end,
    after_spell = luna_draw,
    after_summon = luna_draw,
  },
}

-- Unexpected Results: two random minions of Cost 2 plus your Spell Damage (Prophet Velen does not double it).
cards.BOT_254 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local cost = 2 + list.sum(g.chars(p), function(c)
      return g.tag(c, "SPELLPOWER")
    end)
    for _ = 1, 2 do
      local c = random_card(g, minion_of(function(i)
        return i.cost == cost
      end))
      if c then
        g.summon(p, c)
      end
    end
  end,
}

-- Meteorologist: for each card in your hand, 1 damage to a random enemy.
cards.BOT_601 = {
  battlecry = function(g, me)
    for _ = 1, #g.hand(g.ctrl(me)) do
      g.damage(me, g.random_alive(g.chars(g.enemy(me))), 1)
    end
  end,
}

-- Astromancer: a random minion whose Cost is your hand's size, next to her (the 2019 fix of the far right).
cards.BOT_256 = {
  battlecry = function(g, me)
    local n = #g.hand(g.ctrl(me))
    local c = random_card(g, minion_of(function(i)
      return i.cost == n
    end))
    if c then
      g.summon_right(me, c)
    end
  end,
}

-- Luna's Pocket Galaxy: the minions in your deck cost (1) (later changes still apply).
cards.BOT_257 = {
  spell = function(g, me)
    for _, e in ipairs(g.deck(g.ctrl(me))) do
      if g.type(e) == "MINION" then
        g.enchant(e, { cost_set = 1 })
      end
    end
  end,
}

-- --- Paladin -----------------------------------------------------------------------------------------------------------

-- Autodefense Matrix: when one of your minions is attacked (without Divine Shield), it gets Divine Shield.
cards.BOT_908 = {
  secret = {
    event = "attack",
    cond = function(g, me, ev)
      return not g.mine(me, ev) and ev.defender and ev.defender > 0 and g.is_minion(ev.defender)
        and g.ctrl(ev.defender) == g.ctrl(me) and not g.has(ev.defender, "DIVINE_SHIELD")
    end,
    effect = function(g, me, ev)
      g.give_tag(ev.defender, "DIVINE_SHIELD")
    end,
  },
}

-- Crystalsmith Kangor: Divine Shield, Lifesteal; your healing is doubled (HEALING_DOUBLE on your champion: every heal of
-- yours, Lifesteal too; with Auchenai Soulpriest the damage doubled: the 2019 fix).
cards.BOT_236 = {
  aura = function(g, me)
    g.aura_add(g.hero(g.ctrl(me)), 0, 0, { HEALING_DOUBLE = 1 })
  end,
}

-- Crystology: draw two 1-Attack minions from your deck.
cards.BOT_909 = {
  spell = function(g, me)
    for _ = 1, 2 do
      draw_from_deck(g, g.ctrl(me), function(e)
        return g.type(e) == "MINION" and g.atk(e) == 1
      end)
    end
  end,
}

-- Prismatic Lens: draw a minion, then a spell from your deck; if both are in your hand, they swap their Costs (2018:
-- a Bomb that explodes or a burned card: no swap).
cards.BOT_436 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local m = draw_from_deck(g, p, function(e)
      return g.type(e) == "MINION"
    end)
    local s = draw_from_deck(g, p, function(e)
      return g.type(e) == "SPELL"
    end)
    if m and s and g.zone(m) == "HAND" and g.zone(s) == "HAND" then
      local cm, cs = g.cost(m), g.cost(s)
      g.enchant(m, { cost_set = cs })
      g.enchant(s, { cost_set = cm })
    end
  end,
}

-- Mechano-Egg: Deathrattle: an 8/8 Robosaur.
cards.BOT_537 = {
  deathrattle = function(g, me)
    summon_here(g, me, "BOT_537t")
  end,
}

-- Shrink Ray: every minion's Attack and Health become 1 (auras still add).
cards.BOT_234 = {
  spell = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      g.set_stats(m, 1, 1)
    end
  end,
}

-- Glowstone Technician: the minions in your hand +2/+2.
cards.BOT_910 = {
  battlecry = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      if g.type(e) == "MINION" then
        g.buff(e, 2, 2)
      end
    end
  end,
}

-- Kangor's Endless Army: 3 friendly Mechs that died this game (each death once), fresh, with the Magnetic upgrades they
-- had when they died (g.fused: a Silence before had taken them).
local function dead_mechs(g, p)
  return dead_minions(g, p, function(e)
    return is_mech(g, e)
  end)
end
cards.BOT_912 = {
  can_play = function(g, me)
    return #dead_mechs(g, g.ctrl(me)) > 0
  end,
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, d in ipairs(pick_n(g, dead_mechs(g, p), 3)) do
      local m = g.summon(p, g.card(d))
      if not m then
        break
      end
      for _, x in ipairs(g.fused(d)) do
        g.fuse(m, x)
      end
    end
  end,
}

-- --- Priest ------------------------------------------------------------------------------------------------------------

-- Topsy Turvy: a minion's Attack and Health swap (0 Attack: it dies).
cards.BOT_517 = {
  target = "minion",
  spell = function(g, me, t)
    g.set_stats(t, g.health(t), g.atk(t))
  end,
}

-- The spells its player cast on it (the player hooks' PLAY_TARGET), after they resolved: Test Subject's list, Zerek's
-- mark.
local function cast_on_me(f)
  return {
    after_spell = function(g, me, ev)
      if g.mine(me, ev) and g.tag(ev.entity, "PLAY_TARGET") == me then
        f(g, me, ev)
      end
    end,
  }
end

-- Test Subject: Deathrattle: the spells you cast on it back to your hand (new cards), in the order cast (stored as they
-- target it: a spell that kills it comes back too).
cards.BOT_558 = {
  on = {
    play = function(g, me, ev)
      if g.mine(me, ev) and ev.kind == "spell" and ev.target == me then
        local n = g.tag(me, "STORED") + 1
        g.set_tag(me, "STORED", n)
        g.set_tag(me, "STORED_" .. n, ev.entity)
      end
    end,
  },
  deathrattle = function(g, me)
    for i = 1, g.tag(me, "STORED") do
      local s = g.tag(me, "STORED_" .. i)
      if s > 0 then
        g.add_to_hand(g.ctrl(me), g.card(s))
      end
    end
  end,
}

-- Cloning Device: Discover a copy of a minion in your opponent's deck (deck → hand: with its enchantments).
cards.BOT_435 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local by = {}
    for _, e in ipairs(g.deck(g.enemy(me))) do
      if g.type(e) == "MINION" then
        local c = g.card(e)
        by[c] = by[c] or {}
        by[c][#by[c] + 1] = e
      end
    end
    local ids = {}
    for _, e in ipairs(g.deck(g.enemy(me))) do
      if g.type(e) == "MINION" and by[g.card(e)] and not list.any(ids, function(x)
        return x == g.card(e)
      end) then
        ids[#ids + 1] = g.card(e)
      end
    end
    local opts = {}
    for _, c in ipairs(pick_n(g, ids, 3)) do
      local o = g.create(p, c)
      g.set_tag(o, "SRC", g.pick(by[c]))
      opts[#opts + 1] = o
    end
    if #opts > 0 then
      g.request_choice(me, opts)
    end
  end,
  on_choose = function(g, me, option)
    keep_enchants(g, g.tag(option, "SRC"), g.add_to_hand(g.ctrl(me), g.card(option)))
  end,
}

-- Dead Ringer: Deathrattle: draw a Deathrattle minion from your deck.
cards.BOT_509 = {
  deathrattle = function(g, me)
    draw_from_deck(g, g.ctrl(me), function(e)
      return g.type(e) == "MINION" and has_kw(info(g, e), "DEATHRATTLE")
    end)
  end,
}

-- Extra Arms: a minion +2/+2; More Arms! (+2/+2) to your hand.
cards.BOT_219 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 2, 2)
    g.add_to_hand(g.ctrl(me), "BOT_219t")
  end,
}
cards.BOT_219t = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 2, 2)
  end,
}

-- Omega Medic: with 10 Mana Crystals, restore #10 Health to your hero.
cards.BOT_216 = {
  glow = function(g, me)
    return omega(g, g.ctrl(me))
  end,
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if omega(g, p) then
      g.heal(me, g.hero(p), 10)
    end
  end,
}

-- Power Word: Replicate: a 5/5 copy of a friendly minion right of it (its enchantments, not its damage).
cards.BOT_529 = {
  target = "friendly_minion",
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
  spell = function(g, me, t)
    local c = copy_right_of(g, t)
    if c then
      g.set_stats(c, 5, 5)
    end
  end,
}

-- Reckless Experimenter: Deathrattle minions in your hand cost (3) less (down to 0 in 2018); those you play die at the
-- end of the turn (an enchantment: even without her then).
cards.BOT_566 = {
  cost_aura = function(g, me, card, cost)
    if g.zone(card) == "HAND" and g.ctrl(card) == g.ctrl(me) and g.type(card) == "MINION"
        and has_kw(info(g, card), "DEATHRATTLE") then
      return math.max(0, cost - 3)
    end
    return cost
  end,
  on = {
    play = function(g, me, ev)
      if g.mine(me, ev) and ev.kind == "minion" and has_kw(info(g, ev.entity), "DEATHRATTLE") then
        g.enchant(ev.entity, { hooks = "ench:boom_reckless", player = g.ctrl(me) })
      end
    end,
  },
}
cards["ench:boom_reckless"] = {
  on = {
    turn_end = function(g, me)
      g.destroy(me)
    end,
  },
}

-- Zerek, Master Cloner: Deathrattle: if you cast a spell on it ("Cloning Vector", after the spell), a new Zerek.
cards.BOT_258 = {
  on = cast_on_me(function(g, me)
    g.set_tag(me, "CLONING_VECTOR", true)
  end),
  deathrattle = function(g, me)
    if g.has(me, "CLONING_VECTOR") then
      summon_here(g, me, "BOT_258")
    end
  end,
}

-- Zerek's Cloning Gallery: a 1/1 copy of each minion in your deck (deck → play: its enchantments), random ones when the
-- board has no room for all.
cards.BOT_567 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local ms = list.filter(g.deck(p), function(e)
      return g.type(e) == "MINION"
    end)
    for _, e in ipairs(g.shuffle(ms)) do
      local c = keep_enchants(g, e, g.summon(p, g.card(e)))
      if not c then
        break
      end
      g.set_stats(c, 1, 1)
    end
  end,
}

-- --- Rogue -------------------------------------------------------------------------------------------------------------

-- Lab Recruiter: 3 copies of another friendly minion into your deck (play → deck: plain cards).
cards.BOT_288 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me
  end },
  battlecry = function(g, me, t)
    if t then
      for _ = 1, 3 do
        g.add_to_deck(g.ctrl(me), g.card(t))
      end
    end
  end,
}

-- Pogo-Hopper: +2/+2 for each other Pogo-Hopper you played this game (the player hooks' POGOS counts this one too).
cards.BOT_283 = {
  battlecry = function(g, me)
    local n = g.count(g.ctrl(me), "POGOS") - 1
    if n > 0 then
      g.buff(me, 2 * n, 2 * n)
    end
  end,
}

-- Necrium Blade: Deathrattle: the Deathrattle of a random friendly minion with one runs (it does not die).
cards.BOT_286 = {
  deathrattle = function(g, me)
    local m = g.pick(list.filter(g.minions(g.ctrl(me)), function(x)
      return alive(g, x) and g.has_deathrattle(x)
    end))
    if m then
      trigger_deathrattle(g, m)
    end
  end,
}

-- Violet Haze: 2 random Deathrattle cards to your hand.
cards.BOT_084 = {
  spell = function(g, me)
    for _ = 1, 2 do
      local c = random_card(g, function(i)
        return has_kw(i, "DEATHRATTLE")
      end)
      if c then
        g.add_to_hand(g.ctrl(me), c)
      end
    end
  end,
}

-- Academic Espionage: 10 random cards of your opponent's class into your deck; they cost (1).
cards.BOT_087 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local cls = g.class(g.hero(g.enemy(me)))
    for _ = 1, 10 do
      local c = random_card(g, function(i)
        return of_class(i, cls) and not is_neutral(i)
      end)
      if c then
        g.enchant(g.add_to_deck(p, c), { cost_set = 1 })
      end
    end
  end,
}

-- Blightnozzle Crawler: Deathrattle: a 1/1 Poisonous, Rush Ooze.
cards.BOT_565 = {
  deathrattle = function(g, me)
    summon_here(g, me, "BOT_565t")
  end,
}

-- Crazed Chemist: Combo: a friendly minion +4 Attack.
cards.BOT_576 = {
  combo_target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me
  end },
  combo = function(g, me, t)
    if t then
      g.buff(t, 4, 0)
    end
  end,
}

-- Myra Rotspring: Discover a Deathrattle minion (to your hand); she also gets its Deathrattle (a full hand too).
cards.BOT_243 = {
  battlecry = function(g, me)
    discover(g, me, minion_of(function(i)
      return has_kw(i, "DEATHRATTLE")
    end))
  end,
  on_choose = function(g, me, option)
    g.add_to_hand(g.ctrl(me), g.card(option))
    if g.zone(me) == "PLAY" then
      g.enchant(me, { deathrattle = g.card(option) })
    end
  end,
}

-- Myra's Unstable Element: draw as many cards as your deck has (no fatigue; a full hand burns them).
cards.BOT_242 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.draw(p, #g.deck(p))
  end,
}

-- Necrium Vial: a friendly minion's Deathrattle runs twice (four times with Necromechanic).
cards.BOT_508 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return g.has_deathrattle(t)
  end },
  spell = function(g, me, t)
    for _ = 1, 2 do
      trigger_deathrattle(g, t)
    end
  end,
}

-- --- Shaman ------------------------------------------------------------------------------------------------------------

-- Beakered Lightning: $1 damage to all minions. Overload (2).
cards.BOT_246 = {
  spell = function(g, me)
    local n = g.spell_dmg(me, 1)
    for _, m in ipairs(g.all_minions()) do
      g.damage(me, m, n)
    end
  end,
}

-- Voltaic Burst: two 1/1 Rush Sparks. Overload (1).
cards.BOT_451 = {
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
  spell = function(g, me)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), "BOT_102t")
    end
  end,
}

-- Elementary Reaction: draw a card; if you played an Elemental last turn, a copy of it (hand → hand: its enchantments).
cards.BOT_093 = {
  glow = function(g, me)
    return elemental_last_turn(g, g.ctrl(me))
  end,
  spell = function(g, me)
    local p = g.ctrl(me)
    local d = g.draw(p)[1]
    if d and g.zone(d) == "HAND" and elemental_last_turn(g, p) then
      copy_to_hand(g, p, d)
    end
  end,
}

-- Menacing Nimbus: a random Elemental to your hand.
cards.BOT_533 = {
  battlecry = function(g, me)
    local c = random_card(g, minion_of(function(i)
      return i.race == "ELEMENTAL"
    end))
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Omega Mind: with 10 Mana Crystals, your spells have Lifesteal this turn (the player hooks' OMEGA_MIND).
cards.BOT_543 = {
  glow = function(g, me)
    return omega(g, g.ctrl(me))
  end,
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if omega(g, p) then
      g.add_count(p, "OMEGA_MIND", g.turn() - g.count(p, "OMEGA_MIND"))
    end
  end,
}

-- Electra Stormsurge: your next spell this turn casts twice (the player hooks' ELECTRA; two Electras: still twice).
cards.BOT_411 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if g.count(p, "ELECTRA") == 0 then
      g.add_count(p, "ELECTRA")
    end
  end,
}

-- Storm Chaser: draw a spell that costs (5) or more from your deck.
cards.BOT_291 = {
  battlecry = function(g, me)
    draw_from_deck(g, g.ctrl(me), function(e)
      return g.type(e) == "SPELL" and g.cost(e) >= 5
    end)
  end,
}

-- Thunderhead: after you play a card with Overload, two 1/1 Rush Sparks.
cards.BOT_407 = {
  on = {
    play = function(g, me, ev)
      if g.mine(me, ev) and ev.entity ~= me and g.info(ev.card).mana_lock > 0 then
        summon_right_n(g, me, "BOT_102t", 2)
      end
    end,
  },
}

-- Eureka!: a copy of a random minion in your hand (hand → play: its enchantments; a summon, no Battlecry).
cards.BOT_099 = {
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
  spell = function(g, me)
    local p = g.ctrl(me)
    local m = g.pick(list.filter(g.hand(p), function(e)
      return g.type(e) == "MINION"
    end))
    if m then
      keep_enchants(g, m, g.summon(p, g.card(m)))
    end
  end,
}

-- The Storm Bringer: your minions become random Legendary minions.
cards.BOT_245 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      local c = random_card(g, minion_of(function(i)
        return i.rarity == "LEGENDARY"
      end))
      if c then
        g.transform(m, c)
      end
    end
  end,
}

-- --- Warlock -----------------------------------------------------------------------------------------------------------

-- Soul Infusion: the left-most minion in your hand +2/+2.
cards.BOT_263 = {
  spell = function(g, me)
    local m = list.filter(g.hand(g.ctrl(me)), function(e)
      return g.type(e) == "MINION"
    end)[1]
    if m then
      g.buff(m, 2, 2)
    end
  end,
}

-- The Soularium: draw 3 cards; at the end of your turn those still in your hand are discarded ("Fleeting Soul").
cards.BOT_568 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, e in ipairs(g.draw(p, 3)) do
      if g.zone(e) == "HAND" then
        g.enchant(e, { hooks = "ench:boom_soul", player = p })
      end
    end
  end,
}
cards["ench:boom_soul"] = {
  hand = {
    turn_end = function(g, me, ev)
      if ev.player == g.ctrl(me) then
        g.discard(me)
      end
    end,
  },
}

-- Demonic Project: each player's random minion in hand becomes a random Demon (a transform: its enchantments go).
cards.BOT_913 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, q in ipairs({ p, g.opponent(p) }) do
      local m = g.pick(list.filter(g.hand(q), function(e)
        return g.type(e) == "MINION"
      end))
      local c = random_card(g, minion_of(function(i)
        return i.race == "DEMON"
      end))
      if m and c then
        g.transform(m, c)
      end
    end
  end,
}

-- Spirit Bomb: $4 damage to a minion and your hero.
cards.BOT_222 = {
  target = "minion",
  spell = function(g, me, t)
    local n = g.spell_dmg(me, 4)
    g.damage(me, t, n)
    g.damage(me, g.hero(g.ctrl(me)), n)
  end,
}

-- Void Analyst: Deathrattle: the Demons in your hand +1/+1.
cards.BOT_443 = {
  deathrattle = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      if g.type(e) == "MINION" and g.race(e) == "DEMON" then
        g.buff(e, 1, 1)
      end
    end
  end,
}

-- Doubling Imp: a copy of itself (play → play: its enchantments).
cards.BOT_224 = {
  battlecry = function(g, me)
    copy_right_of(g, me)
  end,
}

-- Nethersoul Buster: +1 Attack for each damage your hero took this turn.
cards.BOT_226 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local n = g.count(p, "HURT_AMT_TURN") == g.turn() and g.count(p, "HURT_AMT") or 0
    if n > 0 then
      g.buff(me, n, 0)
    end
  end,
}

-- Omega Agent: with 10 Mana Crystals, 2 copies of itself.
cards.BOT_536 = {
  glow = function(g, me)
    return omega(g, g.ctrl(me))
  end,
  battlecry = function(g, me)
    if omega(g, g.ctrl(me)) then
      for _ = 1, 2 do
        copy_right_of(g, me)
      end
    end
  end,
}

-- Ectomancy: a copy of each Demon you control, right of it.
cards.BOT_521 = {
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
  spell = function(g, me)
    for _, m in ipairs(list.filter(g.minions(g.ctrl(me)), function(x)
      return g.race(x) == "DEMON"
    end)) do
      copy_right_of(g, m)
    end
  end,
}

-- Dr. Morrigan: Deathrattle: a random minion of your deck comes in her place (a summon) and she takes its place in the
-- deck (not shuffled; a fresh card); a second run (Necromechanic) brings another minion but no second Morrigan.
cards.BOT_433 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    local deck = g.deck(p)
    local idx = {}
    for i, e in ipairs(deck) do
      if g.type(e) == "MINION" then
        idx[#idx + 1] = i
      end
    end
    local i = g.pick(idx)
    if not i then
      return
    end
    local m = deck[i]
    local pos = g.died_pos(me)
    g.summon_entity(m, pos >= 0 and pos or nil)
    if not g.has(me, "SWAPPED") then
      g.set_tag(me, "SWAPPED", true)
      local n = g.add_to_deck(p, g.card(me))
      g.to_deck(n, p, i - 1)
    end
  end,
}

-- --- Warrior -----------------------------------------------------------------------------------------------------------

-- Eternium Rover: whenever it takes damage, 2 Armor.
cards.BOT_059 = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me and ev.amount > 0 then
        g.gain_armor(g.ctrl(me), 2)
      end
    end,
  },
}

-- The weighted draw of a Discover without the choice: n different cards of the choices (Omega Assembly).
local function weighted_n(g, choices, n)
  local left = {}
  for _, x in ipairs(choices) do
    left[#left + 1] = x
  end
  local out = {}
  for _ = 1, n do
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
        out[#out + 1] = x[1]
        table.remove(left, i)
        break
      end
    end
  end
  return out
end

-- Omega Assembly: Discover a Mech; with 10 Mana Crystals, all three to your hand.
cards.BOT_299 = {
  glow = function(g, me)
    return omega(g, g.ctrl(me))
  end,
  spell = function(g, me)
    local p = g.ctrl(me)
    if omega(g, p) then
      for _, c in ipairs(weighted_n(g, discover_choices(g, discover_class(g, me), mech_card), 3)) do
        g.add_to_hand(p, c)
      end
      return
    end
    discover(g, me, mech_card)
  end,
  on_choose = to_hand,
}

-- Rocket Boots: a friendly minion gets Rush; draw a card.
cards.BOT_067 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.give_tag(t, "RUSH")
    g.draw(g.ctrl(me))
  end,
}

-- Weapons Project: each player equips a 2/3 Gearblade and gains 6 Armor, you first.
cards.BOT_042 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, q in ipairs({ p, g.opponent(p) }) do
      g.equip(q, "BOT_042t")
      g.gain_armor(q, 6)
    end
  end,
}

-- Dyn-o-matic: 5 damage split among the minions that are not Mechs (1 at a time, at random).
cards.BOT_104 = {
  battlecry = function(g, me)
    for _ = 1, 5 do
      local t = g.random_alive(list.filter(g.all_minions(), function(m)
        return not is_mech(g, m)
      end))
      if not t then
        break
      end
      g.damage(me, t, 1)
    end
  end,
}

-- Supercollider: after your hero attacks a minion (it lives), that minion attacks a random neighbour of it.
cards.BOT_406 = {
  on = {
    after_attack = function(g, me, ev)
      local p = g.ctrl(me)
      local d = ev.defender
      if ev.attacker == g.hero(p) and d and d > 0 and g.is_minion(d) and alive(g, d) then
        local n = g.random_alive(g.adjacent(d))
        if n then
          g.force_attack(d, n)
        end
      end
    end,
  },
}

-- Security Rover: whenever it takes damage, a 2/3 Taunt Guard Bot right of it.
cards.BOT_218 = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me and ev.amount > 0 then
        local pos = g.board_pos(me)
        g.summon(g.ctrl(me), "BOT_218t", pos and pos + 1 or nil)
      end
    end,
  },
}

-- Dr. Boom, Mad Genius: for the rest of the game your Mechs have Rush (the player hooks' BOOM_RUSH); his Hero Power is
-- a random one of five (Big Red Button only shows in the hand), another one at the end of each of your turns.
local BOOM_POWERS = { "BOT_238p1", "BOT_238p2", "BOT_238p3", "BOT_238p4", "BOT_238p6" }
cards.BOT_238 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if g.count(p, "BOOM_RUSH") == 0 then
      g.add_count(p, "BOOM_RUSH")
    end
    g.set_power(p, g.pick(BOOM_POWERS))
    g.update_auras()
  end,
}
cards.BOT_238p1 = {
  target = "any",
  hero_power = function(g, me, t)
    g.damage(me, t, g.hp_dmg(me, 3))
  end,
}
cards.BOT_238p2 = {
  hero_power = function(g, me)
    g.gain_armor(g.ctrl(me), 7)
  end,
}
cards.BOT_238p3 = {
  hero_power = function(g, me)
    local n = g.hp_dmg(me, 1)
    for _, c in ipairs(g.chars(g.enemy(me))) do
      g.damage(me, c, n)
    end
  end,
}
cards.BOT_238p4 = {
  can_play = function(g, me)
    return #g.hand(g.ctrl(me)) < g.rule("hand")
  end,
  hero_power = function(g, me)
    discover(g, me, mech_card)
  end,
  on_choose = to_hand,
}
cards.BOT_238p6 = {
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
  hero_power = function(g, me)
    for _ = 1, 3 do
      g.summon(g.ctrl(me), "BOT_312t")
    end
  end,
}

-- The Boomship: 3 random minions of your hand come into play (a summon: no Battlecry; their enchantments stay) with
-- Rush.
cards.BOT_069 = {
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
  spell = function(g, me)
    local p = g.ctrl(me)
    local ms = g.shuffle(list.filter(g.hand(p), function(e)
      return g.type(e) == "MINION"
    end))
    for i, m in ipairs(ms) do
      if i > 3 or g.room(p) <= 0 then
        break
      end
      if g.summon_entity(m) then
        g.give_tag(m, "RUSH")
      end
    end
  end,
}

-- --- Neutral -----------------------------------------------------------------------------------------------------------

-- Crystallizer: 5 damage to your hero, then 5 Armor.
cards.BOT_447 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    g.damage(me, g.hero(p), 5)
    g.gain_armor(p, 5)
  end,
}

-- Faithful Lumi: another friendly Mech +1/+1.
cards.BOT_079 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me and is_mech(g, t)
  end },
  battlecry = function(g, me, t)
    if t then
      g.buff(t, 1, 1)
    end
  end,
}

-- Goblin Bomb: Deathrattle: 2 damage to the enemy hero.
cards.BOT_031 = {
  deathrattle = function(g, me)
    g.damage(me, g.hero(g.enemy(me)), 2)
  end,
}

-- Mecharoo: Deathrattle: a 1/1 Jo-E Bot.
cards.BOT_445 = {
  deathrattle = function(g, me)
    summon_here(g, me, "BOT_445t")
  end,
}

-- Galvanizer: the Mechs in your hand cost (1) less.
cards.BOT_907 = {
  battlecry = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      if g.type(e) == "MINION" and is_mech(g, e) then
        g.enchant(e, { cost = -1 })
      end
    end
  end,
}

-- Spark Engine: a 1/1 Rush Spark to your hand.
cards.BOT_538 = {
  battlecry = function(g, me)
    g.add_to_hand(g.ctrl(me), "BOT_102t")
  end,
}

-- Toxicologist: your weapon +1 Attack.
cards.BOT_083 = {
  battlecry = function(g, me)
    local w = g.weapon(g.ctrl(me))
    if w then
      g.buff(w, 1, 0)
    end
  end,
}

-- Unpowered Mauler: can attack only if you cast a spell this turn (the player hooks' TURN_SPELLS).
cards.BOT_098 = {
  aura = function(g, me)
    local p = g.ctrl(me)
    if g.current() ~= p or g.count(p, "TURN_SPELLS") == 0 then
      g.aura_add(me, 0, 0, { CANT_ATTACK = true })
    end
  end,
}

-- Whirliglider: a 0/2 Goblin Bomb.
cards.BOT_431 = {
  battlecry = function(g, me)
    g.summon_right(me, "BOT_031")
  end,
}

-- Augmented Elekk: whenever an effect of yours shuffles a card into a deck, an extra copy of it goes in too (deck → deck:
-- its enchantments; Elekk's copies do not set off more; a swap is no shuffle: King Togwaggle, Dr. Morrigan).
local NOT_SHUFFLES = { LOOT_541 = true, BOT_433 = true }
local function elekk(g, me, ev)
  local src = ev.by_id
  if not src or src <= 0 or g.ctrl(src) ~= g.ctrl(me) or NOT_SHUFFLES[ev.by or ""] or g.has(ev.entity, "ELEKK_COPY") then
    return
  end
  local c = keep_enchants(g, ev.entity, g.add_to_deck(ev.player, g.card(ev.entity)))
  if c then
    g.set_tag(c, "ELEKK_COPY", true)
  end
end
cards.BOT_559 = { on = { add_to_deck = elekk, to_deck = elekk } }

-- Brainstormer: +1 Health for each spell in your hand.
cards.BOT_413 = {
  battlecry = function(g, me)
    local n = list.count(g.hand(g.ctrl(me)), function(e)
      return g.type(e) == "SPELL"
    end)
    if n > 0 then
      g.buff(me, 0, n)
    end
  end,
}

local function big_spell_in_hand(g, me)
  return list.any(g.hand(g.ctrl(me)), function(e)
    return e ~= me and g.type(e) == "SPELL" and g.cost(e) >= 5
  end)
end

-- Electrowright: if you're holding a spell that costs (5) or more, +1/+1.
cards.BOT_550 = {
  glow = function(g, me)
    return list.any(g.hand(g.ctrl(me)), function(e)
      return g.type(e) == "SPELL" and g.info(g.card(e)).cost >= 5
    end)
  end,
  battlecry = function(g, me)
    if big_spell_in_hand(g, me) then
      g.buff(me, 1, 1)
    end
  end,
}

-- Kaboom Bot: Deathrattle: 4 damage to a random enemy minion.
cards.BOT_606 = {
  deathrattle = function(g, me)
    local t = g.random_alive(g.minions(g.enemy(me)))
    if t then
      g.damage(me, t, 4)
    end
  end,
}

-- Microtech Controller: two 1/1 Microbots.
cards.BOT_535 = {
  battlecry = function(g, me)
    summon_right_n(g, me, "BOT_312t", 2)
  end,
}

-- Spring Rocket: 2 damage.
cards.BOT_308 = {
  target = "any",
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, 2)
    end
  end,
}

-- Coppertail Imposter: Stealth until your next turn.
cards.BOT_562 = {
  battlecry = function(g, me)
    g.give_tag(me, "STEALTH")
    g.set_tag(me, "IMPOSTER_STEALTH", true)
  end,
  on = {
    turn_start = function(g, me, ev)
      if g.mine(me, ev) and g.has(me, "IMPOSTER_STEALTH") then
        g.set_tag(me, "IMPOSTER_STEALTH", nil)
        g.erase_tag(me, "STEALTH")
      end
    end,
  },
}

-- Explodinator: two 0/2 Goblin Bombs.
cards.BOT_532 = {
  battlecry = function(g, me)
    summon_right_n(g, me, "BOT_031", 2)
  end,
}

-- The minion the opponent of me just played (an `after_summon` of a played minion that is still in play; a Magnetic one
-- that fused never came into play).
local function enemy_played(g, me, ev)
  return ev.played and not g.mine(me, ev) and alive(g, ev.entity)
end

-- Harbinger Celestia: Stealth; after your opponent plays a minion, she becomes a copy of it (play → play: its
-- enchantments and damage).
cards.BOT_555 = {
  on = {
    after_summon = function(g, me, ev)
      if enemy_played(g, me, ev) then
        g.copy_minion(me, ev.entity)
      end
    end,
  },
}

-- Omega Defender: Taunt; with 10 Mana Crystals, +10 Attack.
cards.BOT_296 = {
  glow = function(g, me)
    return omega(g, g.ctrl(me))
  end,
  battlecry = function(g, me)
    if omega(g, g.ctrl(me)) then
      g.buff(me, 10, 0)
    end
  end,
}

-- Piloted Reaper: Deathrattle: a random minion of your hand that costs (2) or less comes into play in its place.
cards.BOT_267 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    local m = g.pick(list.filter(g.hand(p), function(e)
      return g.type(e) == "MINION" and g.cost(e) <= 2
    end))
    if m then
      local pos = g.died_pos(me)
      g.summon_entity(m, pos >= 0 and pos or nil)
    end
  end,
}

-- Replicating Menace: Magnetic; Deathrattle: three 1/1 Microbots.
cards.BOT_312 = {
  deathrattle = function(g, me)
    for _ = 1, 3 do
      summon_here(g, me, "BOT_312t")
    end
  end,
}

-- Weaponized Piñata: Deathrattle: a random Legendary minion to your hand.
cards.BOT_401 = {
  deathrattle = function(g, me)
    local c = random_card(g, minion_of(function(i)
      return i.rarity == "LEGENDARY"
    end))
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- E.M.P. Operative: destroy a Mech.
cards.BOT_540 = {
  target = { base = "minion", filter = function(g, me, t)
    return t ~= me and is_mech(g, t)
  end },
  battlecry = function(g, me, t)
    if t then
      g.destroy(t)
    end
  end,
}

-- Giggling Inventor: two 1/2 Taunt, Divine Shield Annoy-o-Trons.
cards.BOT_270 = {
  battlecry = function(g, me)
    summon_right_n(g, me, "BOT_270t", 2)
  end,
}

-- Holomancer: after your opponent plays a minion, a 1/1 copy of it for you (its enchantments, then 1/1).
cards.BOT_280 = {
  on = {
    after_summon = function(g, me, ev)
      if enemy_played(g, me, ev) then
        local c = g.summon(g.ctrl(me), g.card(ev.entity))
        if c then
          c = g.copy_minion(c, ev.entity) or c
          g.set_damage(c, 0)
          g.set_stats(c, 1, 1)
        end
      end
    end,
  },
}

-- Loose Specimen: 6 damage split among your other minions (1 at a time, at random).
cards.BOT_544 = {
  battlecry = function(g, me)
    for _ = 1, 6 do
      local t = g.random_alive(g.others(me))
      if not t then
        break
      end
      g.damage(me, t, 1)
    end
  end,
}

-- Seaforium Bomber: a Bomb into your opponent's deck.
cards.BOT_511 = {
  battlecry = function(g, me)
    g.add_to_deck(g.enemy(me), "BOT_511t")
  end,
}

-- Bomb: when drawn it explodes: its player takes 5 damage (no Spell Damage), then draws a card.
cards.BOT_511t = cast_when_drawn(function(g, me)
  local p = g.ctrl(me)
  g.damage(me, g.hero(p), 5)
  g.draw(p)
end)

-- Subject 9: draw 5 different Secrets from your deck (a random copy of each).
cards.BOT_573 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local secrets = list.filter(g.deck(p), function(e)
      return g.info(g.card(e)).trap
    end)
    for i, c in ipairs(g.shuffle(distinct_cards(g, secrets))) do
      if i > 5 then
        break
      end
      draw_from_deck(g, p, function(e)
        return g.card(e) == c
      end)
    end
  end,
}

-- Arcane Dynamo: Discover a spell that costs (5) or more.
cards.BOT_539 = {
  battlecry = function(g, me)
    discover(g, me, function(i)
      return i.type == "SPELL" and i.cost >= 5
    end)
  end,
  on_choose = to_hand,
}

-- Damaged Stegotron: Taunt; 6 damage to itself.
cards.BOT_448 = {
  battlecry = function(g, me)
    g.damage(me, me, 6)
  end,
}

-- Mechanical Whelp: Deathrattle: a 7/7 Mechanical Dragon.
cards.BOT_066 = {
  deathrattle = function(g, me)
    summon_here(g, me, "BOT_066t")
  end,
}

-- Missile Launcher: Magnetic; at the end of your turn, 1 damage to all other characters.
cards.BOT_107 = end_of_my_turn(function(g, me)
  for _, c in ipairs(g.all_chars()) do
    if c ~= me then
      g.damage(me, c, 1)
    end
  end
end)

-- Spark Drill: Rush; Deathrattle: two 1/1 Rush Sparks to your hand.
cards.BOT_102 = {
  deathrattle = function(g, me)
    for _ = 1, 2 do
      g.add_to_hand(g.ctrl(me), "BOT_102t")
    end
  end,
}

-- Star Aligner: if you control 3 minions with 7 Health (it counts), 7 damage to all enemies.
cards.BOT_552 = {
  glow = function(g, me)
    return list.count(g.minions(g.ctrl(me)), function(m)
      return g.health(m) == 7
    end) >= 2
  end,
  battlecry = function(g, me)
    if list.count(g.minions(g.ctrl(me)), function(m)
      return g.health(m) == 7
    end) >= 3 then
      for _, c in ipairs(g.chars(g.enemy(me))) do
        g.damage(me, c, 7)
      end
    end
  end,
}

-- Mecha'thun: Deathrattle: after the other Deathrattles of its batch (they resolve first), if your deck, hand and board
-- are empty (weapon, Secrets, Quests and Dormant minions do not count), the enemy hero is destroyed (Immune or not).
cards.BOT_424 = {
  deathrattle = function(g, me)
    g.resolve()
    local p = g.ctrl(me)
    if #g.deck(p) == 0 and #g.hand(p) == 0 and #g.minions(p) == 0 then
      g.destroy(g.hero(g.enemy(me)))
    end
  end,
}

return cards
