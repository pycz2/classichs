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

-- --- Rastakhan's Rumble (2018-12-04, build 27845): Druid, Hunter, Mage, Paladin, Priest; Icicle, Tome of Intellect ----

-- "Stealth for 1 turn" (the Spirits): the Stealth goes at the start of its player's next turn.
local function spirit(h)
  h.on = h.on or {}
  h.on.turn_start = function(g, me, ev)
    if g.mine(me, ev) then
      g.erase_tag(me, "STEALTH")
    end
  end
  return h
end

-- Overkill (mechanics.md): this card's damage left a character below 0 Health (a minion is still there until the death
-- phase; a hero's Armor goes first, so its Health + Armor).
local function overkilled(g, t)
  return g.health(t) < 0
end

-- A minion's Overkill: it attacked (on its own turn) and left the defending minion below 0 Health.
local function overkill_attack(f)
  return {
    on = {
      damage = function(g, me, ev)
        if ev.source == me and g.current() == g.ctrl(me) and overkilled(g, ev.target) then
          f(g, me, ev)
        end
      end,
    },
  }
end

local function mage_spell(i)
  return i.type == "SPELL" and of_class(i, "MAGE")
end

local function is_beast(g, e)
  return g.race(e) == "BEAST"
end

-- "After your hero attacks and kills a minion".
local function hero_killed(g, me, ev)
  local p = g.ctrl(me)
  local d = ev.defender
  return ev.attacker == g.hero(p) and d and d >= 0 and g.is_minion(d) and (g.health(d) <= 0 or g.zone(d) ~= "PLAY")
end

-- --- Mage ----------------------------------------------------------------------------------------------------------

-- Icicle: 2 damage to a minion; if it's Frozen, draw a card.
cards.EX1_179 = {
  target = "minion",
  spell = function(g, me, t)
    local frozen = g.has(t, "FROZEN")
    g.damage(me, t, g.spell_dmg(me, 2))
    if frozen or g.has(t, "FROZEN") then
      g.draw(g.ctrl(me))
    end
  end,
}

-- Tome of Intellect: a random Mage spell.
cards.EX1_180 = {
  spell = function(g, me)
    g.add_to_hand(g.ctrl(me), random_card(g, mage_spell))
  end,
}

-- Elemental Evocation: the next Elemental you play this turn costs (2) less (several stack).
cards.TRL_310 = {
  spell = function(g, me)
    g.add_cost_mod(g.ctrl(me), { kind = "minion", race = "ELEMENTAL", delta = -2, ["until"] = "use" })
  end,
}

-- Arcanosaur: if you played an Elemental last turn, 3 damage to all other minions.
cards.TRL_311 = {
  glow = function(g, me)
    return elemental_last_turn(g, g.ctrl(me))
  end,
  battlecry = function(g, me)
    if elemental_last_turn(g, g.ctrl(me)) then
      for _, m in ipairs(g.all_minions()) do
        if m ~= me then
          g.damage(me, m, 3)
        end
      end
    end
  end,
}

-- Scorch: 4 damage to a minion; costs (1) if you played an Elemental last turn.
cards.TRL_313 = {
  target = "minion",
  cost_mod = function(g, me)
    return elemental_last_turn(g, g.ctrl(me)) and -3 or 0
  end,
  glow = function(g, me)
    return elemental_last_turn(g, g.ctrl(me))
  end,
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
  end,
}

-- Pyromaniac: whenever your Hero Power kills a minion, draw a card.
cards.TRL_315 = {
  on = {
    damage = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.source == g.power(p) and g.is_minion(ev.target) and g.health(ev.target) <= 0 then
        g.draw(p)
      end
    end,
  },
}

-- Jan'alai, the Dragonhawk: if your Hero Power dealt 8 damage this game, summon Ragnaros the Firelord.
local function janalai_left(g, me)
  local n = 8 - g.count(g.ctrl(me), "TRL_POWER_DMG")
  return n > 0 and n or 0
end
cards.TRL_316 = {
  glow = function(g, me)
    return janalai_left(g, me) == 0
  end,
  battlecry = function(g, me)
    if janalai_left(g, me) == 0 then
      g.summon_right(me, "VAN_EX1_298")
    end
  end,
}

-- Blast Wave: 2 damage to all minions; Overkill (once per minion killed with excess): a random Mage spell.
cards.TRL_317 = {
  spell = function(g, me)
    local ms = g.all_minions()
    damage_all_minions(g, me, g.spell_dmg(me, 2))
    for _, m in ipairs(ms) do
      if overkilled(g, m) then
        g.add_to_hand(g.ctrl(me), random_card(g, mage_spell))
      end
    end
  end,
}

-- Hex Lord Malacrass: a copy (base card) of each card of your opening hand but this one, in order (the player hooks'
-- TRL_OPEN / TRL_OPEN_<i>: the hand after the mulligan, before The Coin).
cards.TRL_318 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for i = 1, g.count(p, "TRL_OPEN") do
      local e = g.count(p, "TRL_OPEN_" .. i)
      if e ~= me then
        g.add_to_hand(p, g.card(e))
      end
    end
  end,
}

-- Daring Fire-Eater: your next Hero Power this turn deals 2 more damage (several stack: TRL_FLAME on the hero, added to
-- the power's damage before it applies; the engine's POWER_DAMAGE is an aura tag only).
local function flame_off(g, me)
  g.set_tag(me, "TRL_FLAME", nil)
  g.remove_enchant(me, "ench:trl_flameweaving")
end
cards["ench:trl_flameweaving"] = {
  now = {
    predamage = function(g, me, ev)
      if ev.source == g.power(g.ctrl(me)) and ev.amount > 0 then
        ev.amount = ev.amount + g.tag(me, "TRL_FLAME")
      end
    end,
  },
  on = {
    hero_power = function(g, me, ev)
      if g.mine(me, ev) then
        flame_off(g, me)
      end
    end,
    turn_end = function(g, me, ev)
      flame_off(g, me)
    end,
  },
}
cards.TRL_390 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local h = g.hero(p)
    g.add_tag(h, "TRL_FLAME", 2)
    g.remove_enchant(h, "ench:trl_flameweaving")
    g.enchant(h, { hooks = "ench:trl_flameweaving", player = p })
  end,
}

-- Splitting Image: when one of your minions is attacked, summon a copy of it.
cards.TRL_400 = {
  secret = {
    event = "attack",
    cond = function(g, me, ev)
      local d = ev.defender
      return d and d >= 0 and g.is_minion(d) and g.ctrl(d) == g.ctrl(me) and g.room(g.ctrl(me)) > 0
    end,
    effect = function(g, me, ev)
      summon_copies(g, ev.defender, 1)
    end,
  },
}

-- --- Hunter --------------------------------------------------------------------------------------------------------

-- Zul'jin: cast all spells you've played this game (the player hooks' TRL_SPELLS list), targets chosen randomly.
cards.TRL_065 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for i = 1, g.count(p, "TRL_SPELLS") do
      if over(g) then
        break
      end
      g.cast_random(me, g.card(g.count(p, "TRL_SPELLS_" .. i)))
      g.resolve()
    end
  end,
}

-- Berserker Throw: 2 damage.
cards.TRL_065h = {
  target = "any",
  hero_power = function(g, me, t)
    g.damage(me, t, g.hp_dmg(me, 2))
  end,
}

-- Headhunter's Hatchet: if you control a Beast, +1 Durability.
cards.TRL_111 = {
  glow = function(g, me)
    return list.any(g.minions(g.ctrl(me)), function(m)
      return is_beast(g, m)
    end)
  end,
  battlecry = function(g, me)
    if list.any(g.minions(g.ctrl(me)), function(m)
      return is_beast(g, m)
    end) then
      g.add_tag(me, "DURABILITY", 1)
    end
  end,
}

-- The Beast Within: a friendly Beast +1/+1, then it attacks a random enemy minion.
cards.TRL_119 = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t)
      return is_beast(g, t)
    end,
  },
  spell = function(g, me, t)
    g.buff(t, 1, 1)
    local d = g.random_alive(g.minions(g.enemy(me)))
    if d and alive(g, t) then
      g.force_attack(t, d)
    end
  end,
}

-- Ironhide Direhorn: Overkill: summon a 5/5 Ironhide Runt.
cards.TRL_232 = overkill_attack(function(g, me)
  g.summon_right(me, "TRL_232t")
end)

-- Stampeding Roar (Druid): summon a random Beast from your hand and give it Rush.
cards.TRL_255 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    if g.room(p) <= 0 then
      return
    end
    local e = g.pick(list.filter(g.hand(p), function(c)
      return g.type(c) == "MINION" and is_beast(g, c)
    end))
    if e then
      local m = g.summon_entity(e)
      if m then
        g.give_tag(m, "RUSH")
      end
    end
  end,
}

-- Master's Call: Discover a minion in your deck; if all 3 are Beasts, draw them all.
cards.TRL_339 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local by, ids = {}, {}
    for _, e in ipairs(g.deck(p)) do
      if g.type(e) == "MINION" then
        local c = g.card(e)
        if not by[c] then
          by[c] = {}
          ids[#ids + 1] = c
        end
        by[c][#by[c] + 1] = e
      end
    end
    local es = {}
    for _, c in ipairs(pick_n(g, ids, 3)) do
      es[#es + 1] = g.pick(by[c])
    end
    if #es == 3 and list.all(es, function(e)
      return is_beast(g, e)
    end) then
      for _, e in ipairs(es) do
        g.draw_entity(p, e)
      end
      return
    end
    local opts = {}
    for _, e in ipairs(es) do
      local o = g.create(p, g.card(e))
      g.set_tag(o, "COPY_OF", e)
      opts[#opts + 1] = o
    end
    if #opts > 0 then
      g.request_choice(me, opts)
    end
  end,
  on_choose = function(g, me, option)
    local e = g.tag(option, "COPY_OF")
    if g.zone(e) == "DECK" then
      g.draw_entity(g.ctrl(me), e)
    end
  end,
}

-- Baited Arrow: 3 damage; Overkill: summon a 5/5 Devilsaur.
cards.TRL_347 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 3))
    if overkilled(g, t) then
      g.summon(g.ctrl(me), "TRL_347t")
    end
  end,
}

-- Springpaw: a 1/1 Lynx with Rush.
cards.TRL_348 = {
  battlecry = function(g, me)
    g.add_to_hand(g.ctrl(me), "TRL_348t")
  end,
}

-- Bloodscalp Strategist: if you have a weapon equipped, Discover a spell.
cards.TRL_349 = {
  glow = has_weapon,
  battlecry = function(g, me)
    if has_weapon(g, me) then
      discover(g, me, function(i)
        return i.type == "SPELL"
      end)
    end
  end,
  on_choose = to_hand,
}

-- Revenge of the Wild: summon your Beasts that died this turn (in the order they died).
cards.TRL_566 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, e in ipairs(dead_minions(g, p, function(e)
      return is_beast(g, e) and g.tag(e, "DIED_TURN") == g.turn()
    end)) do
      if not g.summon(p, g.card(e)) then
        break
      end
    end
  end,
}

-- Halazzi, the Lynx: fill your hand with 1/1 Lynxes with Rush.
cards.TRL_900 = {
  battlecry = function(g, me)
    while g.add_to_hand(g.ctrl(me), "TRL_348t") do
    end
  end,
}

-- Spirit of the Dragonhawk: Stealth for 1 turn; your Hero Power also targets adjacent minions (POWER_ADJACENT on your
-- hero: the engine hits the minions next to a minion target too; several Spirits do not stack).
cards.TRL_319 = spirit({
  aura = function(g, me)
    g.aura_add(g.hero(g.ctrl(me)), 0, 0, { POWER_ADJACENT = true })
  end,
})

-- Spirit of the Lynx: Stealth for 1 turn; whenever you summon a Beast, give it +1/+1.
cards.TRL_901 = spirit({
  on = {
    summon = function(g, me, ev)
      if g.mine(me, ev) and ev.entity ~= me and is_beast(g, ev.entity) then
        g.buff(ev.entity, 1, 1)
      end
    end,
  },
})

-- --- Druid ---------------------------------------------------------------------------------------------------------

-- Spirit of the Raptor: Stealth for 1 turn; after your hero attacks and kills a minion, draw a card.
cards.TRL_223 = spirit({
  on = {
    after_attack = function(g, me, ev)
      if hero_killed(g, me, ev) then
        g.draw(g.ctrl(me))
      end
    end,
  },
})

-- Savage Striker: damage to an enemy minion equal to your hero's Attack.
cards.TRL_240 = {
  target = "enemy_minion",
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, g.attack(g.hero(g.ctrl(me))))
    end
  end,
}

-- Gonk, the Raptor: after your hero attacks and kills a minion, it may attack again.
cards.TRL_241 = {
  on = {
    after_attack = function(g, me, ev)
      if hero_killed(g, me, ev) then
        local h = g.hero(g.ctrl(me))
        if g.tag(h, "ATTACKS") > 0 then
          g.add_tag(h, "ATTACKS", -1)
        end
      end
    end,
  },
}

-- Pounce: your hero +2 Attack this turn.
cards.TRL_243 = {
  spell = function(g, me)
    g.buff(g.hero(g.ctrl(me)), 2, 0, true)
  end,
}

-- Predatory Instincts: draw a Beast from your deck; double its Health.
cards.TRL_244 = {
  spell = function(g, me)
    local e = draw_from_deck(g, g.ctrl(me), function(d)
      return g.type(d) == "MINION" and is_beast(g, d)
    end)
    if e and g.zone(e) == "HAND" then
      g.buff(e, 0, g.max_health(e))
    end
  end,
}

-- Mark of the Loa: Choose One: +2/+4 and Taunt; or two 3/2 Raptors.
cards.TRL_254 = { choose_one = { "TRL_254a", "TRL_254b" } }
cards.TRL_254a = {
  target = "minion",
  effect = function(g, me, t)
    if t then
      g.buff(t, 2, 4)
      g.give_tag(t, "TAUNT")
    end
  end,
}
cards.TRL_254b = {
  effect = function(g, me)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), "TRL_254t")
    end
  end,
}

-- Treespeaker: transform your Treants into 5/5 Ancients.
local MORE_TREANTS = { VAN_EX1_158t = true, VAN_EX1_573t = true, EX1_158t = true, EX1_573t = true, EX1_tk9 = true }
cards.TRL_341 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if is_treant(g, m) or MORE_TREANTS[g.card(m)] then
        g.transform(m, "TRL_341t")
      end
    end
  end,
}

-- Wardruid Loti: Choose One of four forms. DOUBT: the engine's choose_one takes two options, so the four forms are a
-- choice after the play (g.request_choice of the four option minions); with Fandral Staghelm (BOTH_CHOICES) the
-- combined form at once.
local LOTI = { TRL_343at1 = "TRL_343at2", TRL_343bt1 = "TRL_343bt2", TRL_343ct1 = "TRL_343ct2", TRL_343dt1 = "TRL_343dt2" }
cards.TRL_343 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if g.has(g.hero(p), "BOTH_CHOICES") then
      g.transform(me, "TRL_343et1")
      return
    end
    local opts = {}
    for _, c in ipairs({ "TRL_343at1", "TRL_343bt1", "TRL_343ct1", "TRL_343dt1" }) do
      opts[#opts + 1] = g.create(p, c)
    end
    g.request_choice(me, opts)
  end,
  on_choose = function(g, me, option)
    if g.zone(me) == "PLAY" then
      g.transform(me, LOTI[g.card(option)])
    end
  end,
}

-- --- Paladin -------------------------------------------------------------------------------------------------------

-- Shirvallah, the Tiger: costs (1) less for each Mana you've spent on spells.
cards.TRL_300 = {
  cost_mod = function(g, me)
    return -g.count(g.ctrl(me), "TRL_SPELL_MANA")
  end,
}

-- Time Out!: your hero is Immune until your next turn.
cards["ench:trl_timeout"] = {
  on = {
    turn_start = function(g, me, ev)
      if g.mine(me, ev) then
        g.erase_tag(me, "IMMUNE")
        g.remove_enchant(me, "ench:trl_timeout")
      end
    end,
  },
}
cards.TRL_302 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local h = g.hero(p)
    g.give_tag(h, "IMMUNE")
    g.remove_enchant(h, "ench:trl_timeout")
    g.enchant(h, { hooks = "ench:trl_timeout", player = p })
  end,
}

-- Farraki Battleaxe: Overkill (your hero attacking with it): a random minion in your hand +2/+2.
cards.TRL_304 = {
  on = {
    damage = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.source == g.hero(p) and g.current() == p and overkilled(g, ev.target) then
        local m = g.pick(list.filter(g.hand(p), function(e)
          return g.type(e) == "MINION"
        end))
        if m then
          g.buff(m, 2, 2)
        end
      end
    end,
  },
}

-- A New Challenger...: Discover a 6-Cost minion; summon it with Taunt and Divine Shield.
cards.TRL_305 = {
  spell = function(g, me)
    discover(g, me, minion_of(function(i)
      return i.cost == 6
    end))
  end,
  on_choose = function(g, me, option)
    local m = g.summon(g.ctrl(me), g.card(option))
    if m then
      g.give_tag(m, "TAUNT")
      g.give_tag(m, "DIVINE_SHIELD")
    end
  end,
}

-- Immortal Prelate: Deathrattle: shuffle this into your deck; it keeps any enchantments.
cards.TRL_306 = {
  deathrattle = function(g, me)
    g.to_deck(me)
  end,
}

-- Flash of Light: restore 4 Health; draw a card.
cards.TRL_307 = {
  target = "any",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 4))
    g.draw(g.ctrl(me))
  end,
}

-- High Priest Thekal: all but 1 of your hero's Health into Armor (not damage: DOUBT, no damage triggers).
cards.TRL_308 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local h = g.hero(p)
    local n = g.health(h) - 1
    if n > 0 then
      g.gain_armor(p, n)
      g.set_damage(h, g.max_health(h) - 1)
    end
  end,
}

-- Spirit of the Tiger: Stealth for 1 turn; after you cast a spell, summon a Tiger with stats equal to its Cost.
cards.TRL_309 = spirit({
  on = {
    after_spell = function(g, me, ev)
      if g.mine(me, ev) then
        local c = g.cost(ev.entity)
        local s = g.summon_right(me, "TRL_309t")
        if s then
          if c > 0 then
            g.set_stats(s, c, c)
          else
            g.set_stats(s, 0, nil)
            g.destroy(s)
          end
        end
      end
    end,
  },
})

-- Bloodclaw: 5 damage to your hero.
cards.TRL_543 = {
  battlecry = function(g, me)
    g.damage(me, g.hero(g.ctrl(me)), 5)
  end,
}

-- Zandalari Templar: if you've restored 10 Health this game, +4/+4 and Taunt (the player hooks' TRL_HEALED).
cards.TRL_545 = {
  glow = function(g, me)
    return g.count(g.ctrl(me), "TRL_HEALED") >= 10
  end,
  battlecry = function(g, me)
    if g.count(g.ctrl(me), "TRL_HEALED") >= 10 then
      g.buff(me, 4, 4)
      g.give_tag(me, "TAUNT")
    end
  end,
}

-- --- Priest --------------------------------------------------------------------------------------------------------

-- Seance: a copy of a minion in your hand (base card: play → hand is "backward").
cards.TRL_097 = {
  target = "minion",
  spell = function(g, me, t)
    g.add_to_hand(g.ctrl(me), g.card(t))
  end,
}

-- Regenerate: restore 3 Health.
cards.TRL_128 = {
  target = "any",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 3))
  end,
}

-- TRL_131: whenever you cast a spell, summon a 1/1 Zombie with Taunt.
cards.TRL_131 = {
  on = {
    play = function(g, me, ev)
      if g.mine(me, ev) and ev.kind == "spell" then
        g.summon_right(me, "TRL_131t")
      end
    end,
  },
}

-- Mass Hysteria: each minion (in play order) attacks another random minion. force_attack needs two sides, so an
-- attack on a friendly minion is the two damages of an attack.
cards.TRL_258 = {
  spell = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if alive(g, m) then
        local d = g.pick(list.filter(g.all_minions(), function(x)
          return x ~= m and alive(g, x)
        end))
        if d then
          if g.ctrl(d) ~= g.ctrl(m) then
            g.force_attack(m, d)
          else
            local a, b = g.atk(m), g.atk(d)
            g.damage(m, d, a)
            g.damage(d, m, b)
          end
          g.resolve()
        end
      end
    end
  end,
}

-- Princess Talanji: summon all minions from your hand that didn't start in your deck (random ones when out of room).
cards.TRL_259 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local es = g.shuffle(list.filter(g.hand(p), function(e)
      return g.type(e) == "MINION" and not g.has(e, "STARTED_IN_DECK")
    end))
    for _, e in ipairs(es) do
      if g.room(p) <= 0 then
        break
      end
      g.summon_entity(e)
    end
  end,
}

-- Bwonsamdi, the Dead: draw 1-Cost minions from your deck until your hand is full.
cards.TRL_260 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    while #g.hand(p) < g.rule("hand") do
      if not draw_from_deck(g, p, function(d)
        return g.type(d) == "MINION" and info(g, d).cost == 1
      end) then
        break
      end
    end
  end,
}

-- Grave Horror: costs (1) less for each spell you've cast this game.
cards.TRL_408 = {
  cost_mod = function(g, me)
    return -g.count(g.ctrl(me), "TRL_SPELLS")
  end,
}

-- Surrender to Madness: destroy 3 of your Mana Crystals (empty ones first); all minions in your deck +2/+2.
cards.TRL_500 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local mx = g.max_mana(p) - 3
    if mx < 0 then
      mx = 0
    end
    local mana = g.mana(p)
    g.set_mana(p, mana < mx and mana or mx, mx)
    for _, e in ipairs(g.deck(p)) do
      if g.type(e) == "MINION" then
        g.buff(e, 2, 2)
      end
    end
  end,
}

-- TRL_501: this turn, your healing effects deal damage instead.
cards.TRL_501 = {
  battlecry = function(g, me)
    g.give_tag(g.hero(g.ctrl(me)), "HEAL_IS_DAMAGE", true)
  end,
}

-- Spirit of the Dead: Stealth for 1 turn; after a friendly minion dies, shuffle a 1-Cost copy of it into your deck.
cards.TRL_502 = spirit({
  on = {
    death = function(g, me, ev)
      if g.mine(me, ev) and ev.minion and ev.entity ~= me then
        local c = g.add_to_deck(g.ctrl(me), ev.card)
        if c then
          g.enchant(c, { cost_set = 1 })
        end
      end
    end,
  },
})

return cards
