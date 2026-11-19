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

-- Discover a copy of one of these cards (entities: three different cards, a random one of each; the copy keeps the
-- enchantments of the one offered: `take_copy` is the on_choose).
local function offer_copies(g, me, es)
  local p = g.ctrl(me)
  local by, ids = {}, {}
  for _, e in ipairs(es) do
    local c = g.card(e)
    if not by[c] then
      by[c] = {}
      ids[#ids + 1] = c
    end
    by[c][#by[c] + 1] = e
  end
  local opts = {}
  for _, c in ipairs(pick_n(g, ids, 3)) do
    local o = g.create(p, c)
    g.set_tag(o, "COPY_OF", g.pick(by[c]))
    opts[#opts + 1] = o
  end
  if #opts > 0 then
    g.request_choice(me, opts)
  end
  return #opts
end

local function take_copy(g, me, option)
  return keep_enchants(g, g.tag(option, "COPY_OF"), g.add_to_hand(g.ctrl(me), g.card(option)))
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

-- --- Rastakhan's Rumble helpers (trl_b) -------------------------------------------------------------------------------

local TOTEMS = { "VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009" }

-- Overkill: ev (a `damage` event) is me's own hit on a minion it took below 0 Health, on its controller's turn.
local function overkill(g, me, ev, src)
  return ev.source == (src or me) and g.is_minion(ev.target) and g.health(ev.target) < 0 and g.current() == g.ctrl(me)
end

-- Spells p played this turn (the player hooks' TRL_SPELLS list, PLAYED_TURN of each).
local function spells_on_turn(g, p, turn)
  local out = {}
  for i = 1, g.count(p, "TRL_SPELLS") do
    local e = g.count(p, "TRL_SPELLS_" .. i)
    if g.tag(e, "PLAYED_TURN") == turn then
      out[#out + 1] = e
    end
  end
  return out
end

-- "Stealth for 1 turn" (the Spirits): Stealth until its controller's next turn starts.
local function spirit(h)
  h.battlecry = function(g, me)
    g.give_tag(me, "STEALTH")
    g.set_tag(me, "SPIRIT_STEALTH", true)
  end
  h.on = h.on or {}
  local start = h.on.turn_start
  h.on.turn_start = function(g, me, ev)
    if g.mine(me, ev) and g.has(me, "SPIRIT_STEALTH") then
      g.set_tag(me, "SPIRIT_STEALTH", nil)
      g.erase_tag(me, "STEALTH")
    end
    if start then
      start(g, me, ev)
    end
  end
  return h
end

-- Discards p's lowest Cost card (ties: a random one).
local function discard_lowest(g, p)
  local hand = g.hand(p)
  if #hand == 0 then
    return
  end
  local best = nil
  for _, e in ipairs(hand) do
    if not best or g.cost(e) < best then
      best = g.cost(e)
    end
  end
  g.discard(g.pick(list.filter(hand, function(e)
    return g.cost(e) == best
  end)))
end

local function holding_dragon(g, me)
  return holding(g, me, "DRAGON")
end

local function pirates(g, p, but)
  return #list.filter(g.minions(p), function(m)
    return m ~= but and g.race(m) == "PIRATE"
  end)
end

local function summon_random_cost(g, p, cost, pos)
  local c = random_card(g, minion_of(function(i)
    return i.cost == cost
  end))
  if c then
    return g.summon(p, c, pos)
  end
end

-- --- Classic, 2018-11-05 ---------------------------------------------------------------------------------------------

-- Call of the Void: a random Demon.
cards.EX1_181 = {
  spell = function(g, me)
    local c = random_card(g, minion_of(function(i)
      return i.race == "DEMON"
    end))
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Pilfer: a random card of the opponent's class.
cards.EX1_182 = {
  spell = function(g, me)
    local c = random_class_card(g, g.class(g.hero(g.enemy(me))))
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- --- Rogue -------------------------------------------------------------------------------------------------------------

-- Serrated Tooth: Deathrattle: your minions get Rush.
cards.TRL_074 = {
  deathrattle = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.give_tag(m, "RUSH")
    end
  end,
}

-- Bloodsail Howler: +1/+1 for each other Pirate.
cards.TRL_071 = {
  battlecry = function(g, me)
    local n = pirates(g, g.ctrl(me), me)
    if n > 0 then
      g.buff(me, n, n)
    end
  end,
}

-- Stolen Steel: Discover a weapon of another class.
cards.TRL_156 = {
  spell = function(g, me)
    local mine = g.class(g.hero(g.ctrl(me)))
    offer_cards(g, me, list.filter(g.collectible(), function(c)
      local i = g.info(c)
      return i.type == "WEAPON" and playable(i.class) and i.class ~= mine
    end))
  end,
  on_choose = to_hand,
}

-- Raiding Party: draw 2 Pirates (Combo: and a weapon).
local function raid(g, me, weapon)
  local p = g.ctrl(me)
  for _ = 1, 2 do
    draw_from_deck(g, p, function(e)
      return g.type(e) == "MINION" and g.race(e) == "PIRATE"
    end)
  end
  if weapon then
    draw_from_deck(g, p, function(e)
      return g.type(e) == "WEAPON"
    end)
  end
end
cards.TRL_124 = {
  spell = function(g, me)
    raid(g, me, false)
  end,
  combo = function(g, me)
    raid(g, me, true)
  end,
}

-- Spirit of the Shark: your minions' Battlecries trigger twice (DOUBLE_BATTLECRY on the champion, as Brann).
-- ponytail: Combos are not doubled (the engine doubles only `on_play`); needs an engine DOUBLE_COMBO.
cards.TRL_092 = spirit({
  aura = function(g, me)
    g.aura_add(g.hero(g.ctrl(me)), 0, 0, { DOUBLE_BATTLECRY = true })
  end,
})

-- Walk the Plank: destroy an undamaged minion.
cards.TRL_157 = {
  target = { base = "minion", filter = function(g, me, t)
    return g.dmg(t) == 0
  end },
  spell = function(g, me, t)
    g.destroy(t)
  end,
}

-- Gral, the Shark: eat a random minion of the deck (its printed stats); Deathrattle: the eaten cards to the hand.
cards.TRL_409 = {
  battlecry = function(g, me)
    local e = random_from_deck(g, g.ctrl(me), function(d)
      return g.type(d) == "MINION"
    end)
    if not e then
      return
    end
    local i = info(g, e)
    g.remove(e, "GRAVEYARD")
    g.log({ type = "removed_from_deck", player = g.ctrl(me), entity = e, card = g.card(e) })
    g.buff(me, i.attack, i.health)
    local n = g.tag(me, "GRAL_N") + 1
    g.set_tag(me, "GRAL_N", n)
    g.set_tag(me, "GRAL_" .. n, g.card(e))
  end,
  deathrattle = function(g, me)
    for k = 1, g.tag(me, "GRAL_N") do
      g.add_to_hand(g.ctrl(me), g.tag(me, "GRAL_" .. k))
    end
  end,
}

-- Cannon Barrage: 3 damage to a random enemy, once more for each of your Pirates.
cards.TRL_127 = {
  spell = function(g, me)
    local n = 1 + pirates(g, g.ctrl(me))
    for _ = 1, n do
      local t = g.random_alive(g.chars(g.enemy(me)))
      if not t then
        break
      end
      g.damage(me, t, g.spell_dmg(me, 3))
    end
  end,
}

-- Gurubashi Hypemon: Discover a Battlecry minion; a 1/1 copy that costs (1).
cards.TRL_077 = {
  battlecry = function(g, me)
    discover(g, me, minion_of(function(i)
      return has_kw(i, "BATTLECRY")
    end))
  end,
  on_choose = function(g, me, option)
    local c = to_hand(g, me, option)
    if c then
      g.enchant(c, { set_atk = 1, set_hp = 1 })
      g.enchant(c, { cost_set = 1 })
    end
  end,
}

-- Captain Hooktusk: summon 3 Pirates from your deck with Rush.
cards.TRL_126 = {
  battlecry = function(g, me)
    for _ = 1, 3 do
      local m = recruit(g, g.ctrl(me), function(d)
        return g.race(d) == "PIRATE"
      end)
      if m then
        g.give_tag(m, "RUSH")
      end
    end
  end,
}

-- --- Shaman ------------------------------------------------------------------------------------------------------------

-- Totemic Smash: 2 damage; Overkill: a random basic Totem.
cards.TRL_012 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
    if g.is_minion(t) and g.health(t) < 0 then
      g.summon(g.ctrl(me), g.pick(TOTEMS))
    end
  end,
}

-- Wartbringer: if you played 2 spells this turn, 2 damage.
local function two_spells(g, me)
  return #spells_on_turn(g, g.ctrl(me), g.turn()) >= 2
end
cards.TRL_522 = {
  target = { base = "any", when = two_spells },
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, 2)
    end
  end,
  glow = two_spells,
}

-- Big Bad Voodoo: "Deathrattle: summon a random minion that costs (1) more" (its card's Cost).
cards.TRL_082 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.enchant(t, { hooks = "ench:trl_voodoo", player = g.ctrl(me) })
  end,
}
cards["ench:trl_voodoo"] = {
  deathrattle = function(g, me)
    local pos = g.died_pos(me)
    summon_random_cost(g, g.ctrl(me), info(g, me).cost + 1, pos >= 0 and pos or nil)
  end,
}

-- Likkim: +2 Attack while you have Overloaded crystals (locked this turn, or owed: an Overload card played this turn).
-- ponytail: an Overload played before Likkim came is not seen as owed; needs a g query of mana_lock_owed.
cards.TRL_352 = {
  aura = function(g, me)
    local p = g.ctrl(me)
    if g.locked(p) > 0 or g.tag(me, "LIKKIM_OWED") == g.turn() then
      g.aura_add(me, 2, 0)
    end
  end,
  on = {
    play = function(g, me, ev)
      if g.mine(me, ev) and (g.info(ev.card).mana_lock or 0) > 0 then
        g.set_tag(me, "LIKKIM_OWED", g.turn())
      end
    end,
  },
}

-- Bog Slosher: return another friendly minion to your hand with +2/+2.
cards.TRL_059 = {
  target = { base = "friendly_minion", filter = other_friendly },
  battlecry = function(g, me, t)
    if t and g.zone(t) == "PLAY" then
      local c = g.return_to_hand(t)
      if c then
        g.buff(c, 2, 2)
      end
    end
  end,
}

-- Haunting Visions: your next spell this turn costs (3) less; Discover a spell.
cards.TRL_058 = {
  spell = function(g, me)
    g.add_cost_mod(g.ctrl(me), { kind = "spell", delta = -3, ["until"] = "use" })
    discover(g, me, function(i)
      return i.type == "SPELL"
    end)
  end,
  on_choose = to_hand,
}

-- Spirit of the Frog: whenever you cast a spell, draw a spell that costs (1) more.
cards.TRL_060 = spirit({
  on = {
    play = function(g, me, ev)
      if g.mine(me, ev) and ev.kind == "spell" then
        local c = g.tag(ev.entity, "PLAYED_COST") + 1
        draw_from_deck(g, g.ctrl(me), function(e)
          return g.type(e) == "SPELL" and g.cost(e) == c
        end)
      end
    end,
  },
})

-- Krag'wa, the Frog: the spells you played last turn back to your hand (random order).
cards.TRL_345 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local es = spells_on_turn(g, p, g.turn() - 2)
    g.shuffle(es)
    for _, e in ipairs(es) do
      g.add_to_hand(p, g.card(e))
    end
  end,
}

-- Rain of Toads: three 2/4 Taunt Toads.
cards.TRL_351 = {
  spell = function(g, me)
    for _ = 1, 3 do
      g.summon(g.ctrl(me), "TRL_351t")
    end
  end,
}

-- Zentimo: a spell you target a minion with is cast again on that minion's neighbours (as they stood when it was
-- played; 2018: even ones that are no valid target), after it; each extra cast owes its Overload. Two Zentimos: once.
local function first_zentimo(g, me)
  for _, m in ipairs(g.minions(g.ctrl(me))) do
    if g.card(m) == "TRL_085" and not g.silenced(m) then
      return m == me
    end
  end
  return false
end
cards.TRL_085 = {
  on = {
    play = function(g, me, ev)
      if g.mine(me, ev) and ev.kind == "spell" and not ev.secret and ev.target >= 0 and g.is_minion(ev.target)
        and first_zentimo(g, me) then
        local adj = g.adjacent(ev.target)
        g.set_tag(ev.entity, "ZEN_N", #adj)
        for i, m in ipairs(adj) do
          g.set_tag(ev.entity, "ZEN_" .. i, m)
        end
      end
    end,
    after_spell = function(g, me, ev)
      if g.mine(me, ev) and g.tag(ev.entity, "ZEN_N") > 0 then
        for i = 1, g.tag(ev.entity, "ZEN_N") do
          local m = g.tag(ev.entity, "ZEN_" .. i)
          if alive(g, m) then
            g.cast(me, ev.entity, m, true)
            g.resolve()
          end
        end
        g.set_tag(ev.entity, "ZEN_N", nil)
      end
    end,
  },
}

-- --- Warlock -----------------------------------------------------------------------------------------------------------

-- Grim Rally: destroy a friendly minion; your other minions +1/+1.
cards.TRL_249 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.destroy(t)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if m ~= t then
        g.buff(m, 1, 1)
      end
    end
  end,
}

-- Shriek: discard your lowest Cost card; 2 damage to all minions.
cards.TRL_245 = {
  spell = function(g, me)
    discard_lowest(g, g.ctrl(me))
    damage_all_minions(g, me, g.spell_dmg(me, 2))
  end,
}

-- Spirit of the Bat: after a friendly minion dies, a minion in your hand +1/+1.
cards.TRL_251 = spirit({
  on = {
    death = function(g, me, ev)
      if g.mine(me, ev) and ev.minion and ev.entity ~= me then
        local c = g.pick(list.filter(g.hand(g.ctrl(me)), function(e)
          return g.type(e) == "MINION"
        end))
        if c then
          g.buff(c, 1, 1)
        end
      end
    end,
  },
})

-- Reckless Diretroll: discard your lowest Cost card.
cards.TRL_551 = {
  battlecry = function(g, me)
    discard_lowest(g, g.ctrl(me))
  end,
}

-- High Priestess Jeklik: when you discard this, 2 copies of it to your hand (its buffs and cost changes too).
cards.TRL_252 = {
  hand = {
    discard = function(g, me, ev)
      if ev.entity == me then
        for _ = 1, 2 do
          copy_to_hand(g, g.ctrl(me), me)
        end
      end
    end,
  },
}

-- Soulwarden: 3 random cards you discarded this game (the player hooks mark them DISCARDED).
cards.TRL_247 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local es = list.filter(g.graveyard(p), function(e)
      return g.has(e, "DISCARDED")
    end)
    for _, e in ipairs(pick_n(g, es, 3)) do
      g.add_to_hand(p, g.card(e))
    end
  end,
}

-- Blood Troll Sapper: after a friendly minion dies, 2 damage to the enemy hero.
cards.TRL_257 = {
  on = {
    death = function(g, me, ev)
      if g.mine(me, ev) and ev.minion and ev.entity ~= me then
        g.damage(me, g.hero(g.enemy(me)), 2)
      end
    end,
  },
}

-- Demonbolt: destroy a minion; (1) less for each minion you control.
cards.TRL_555 = {
  target = "minion",
  spell = function(g, me, t)
    g.destroy(t)
  end,
  cost_mod = function(g, me)
    return -#g.minions(g.ctrl(me))
  end,
}

-- Hir'eek, the Bat: fill your board with copies of it.
cards.TRL_253 = {
  battlecry = function(g, me)
    summon_copies(g, me, g.room(g.ctrl(me)))
  end,
}

-- Void Contract: destroy half of each deck (rounded up), at random.
cards.TRL_246 = {
  spell = function(g, me)
    for p = 0, 1 do
      local d = g.deck(p)
      for _, e in ipairs(pick_n(g, d, (#d + 1) // 2)) do
        g.remove(e, "GRAVEYARD")
        g.log({ type = "removed_from_deck", player = p, entity = e, card = g.card(e) })
      end
    end
  end,
}

-- --- Warrior -----------------------------------------------------------------------------------------------------------

-- Devastate: 4 damage to a damaged minion.
cards.TRL_321 = {
  target = { base = "minion", filter = function(g, me, t)
    return g.dmg(t) > 0
  end },
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
  end,
}

-- Spirit of the Rhino: your Rush minions are Immune the turn they're summoned.
-- ponytail: only minions summoned while the Spirit is in play are marked (RHINO_TURN); an engine "summoned this turn"
-- tag would cover the ones before it.
cards.TRL_327 = spirit({
  aura = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if g.has(m, "RUSH") and g.tag(m, "RHINO_TURN") == g.turn() then
        g.aura_add(m, 0, 0, { IMMUNE = true })
      end
    end
  end,
  on = {
    summon = function(g, me, ev)
      if g.mine(me, ev) then
        g.set_tag(ev.entity, "RHINO_TURN", g.turn())
      end
    end,
  },
})

-- Dragon Roar: 2 random Dragons.
cards.TRL_362 = {
  spell = function(g, me)
    for _ = 1, 2 do
      local c = random_card(g, minion_of(function(i)
        return i.race == "DRAGON"
      end))
      if c then
        g.add_to_hand(g.ctrl(me), c)
      end
    end
  end,
}

-- Overlord's Whip: after you play a minion, 1 damage to it.
cards.TRL_360 = {
  on = {
    after_summon = function(g, me, ev)
      if g.mine(me, ev) and ev.played and alive(g, ev.entity) then
        g.damage(me, ev.entity, 1)
      end
    end,
  },
}

-- Smolderthorn Lancer: if you're holding a Dragon, destroy a damaged enemy minion.
cards.TRL_326 = {
  target = { base = "enemy_minion", when = holding_dragon, filter = function(g, me, t)
    return g.dmg(t) > 0
  end },
  battlecry = function(g, me, t)
    if t then
      g.destroy(t)
    end
  end,
  glow = holding_dragon,
}

-- War Master Voone: copy all Dragons in your hand.
cards.TRL_328 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _, e in ipairs(list.filter(g.hand(p), function(e)
      return g.race(e) == "DRAGON"
    end)) do
      copy_to_hand(g, p, e)
    end
  end,
}

-- Emberscale Drake: if you're holding a Dragon, 5 Armor.
cards.TRL_323 = {
  battlecry = function(g, me)
    if holding_dragon(g, me) then
      g.gain_armor(g.ctrl(me), 5)
    end
  end,
  glow = holding_dragon,
}

-- Heavy Metal!: a random minion that costs your Armor (up to 10).
cards.TRL_324 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    summon_random_cost(g, p, math.min(g.tag(g.hero(p), "ARMOR"), 10))
  end,
}

-- Sul'thraze: Overkill: you may attack again.
cards.TRL_325 = {
  on = {
    damage = function(g, me, ev)
      local h = g.hero(g.ctrl(me))
      if overkill(g, me, ev, h) and g.tag(h, "ATTACKS") > 0 then
        g.add_tag(h, "ATTACKS", -1)
      end
    end,
  },
}

-- Akali, the Rhino: Overkill: draw a Rush minion, +5/+5.
cards.TRL_329 = {
  on = {
    damage = function(g, me, ev)
      if overkill(g, me, ev) then
        local e = draw_from_deck(g, g.ctrl(me), function(d)
          return g.type(d) == "MINION" and has_kw(info(g, d), "RUSH")
        end)
        if e and g.zone(e) == "HAND" then
          g.buff(e, 5, 5)
        end
      end
    end,
  },
}

return cards
