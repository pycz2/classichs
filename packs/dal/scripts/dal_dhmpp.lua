-- Rise of Shadows (April 2019, build 30103 of 2019-04-09): its Druid, Hunter, Mage, Paladin and Priest cards and their
-- tokens (hearthstone.wiki.gg and its card notes as at the release). Twinspell is the engine's (rules.json TWINSPELL: the
-- `<id>ts` copy shares its card's hooks); Commander Rhyssa is DOUBLE_SECRET; the counts (TURN_SPELLS, RESTORED,
-- DIED_ORDER) are the player hooks'.
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

-- --- Rise of Shadows' helpers ----------------------------------------------------------------------------------------

local LACKEYS = { "DAL_613", "DAL_614", "DAL_615", "DAL_739", "DAL_741" }

local function spell_of(cls)
  return function(i)
    return i.type == "SPELL" and of_class(i, cls)
  end
end

local function buff_all(g, p, a, h)
  for _, m in ipairs(g.minions(p)) do
    g.buff(m, a, h)
  end
end

local function summon_n(g, p, card, n)
  for _ = 1, n do
    if not g.summon(p, card) then
      break
    end
  end
end

-- --- Druid -------------------------------------------------------------------------------------------------------------

-- Acornbearer: Deathrattle: two 1/1 Squirrels to the hand.
cards.DAL_354 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    g.add_to_hand(p, "DAL_354t")
    g.add_to_hand(p, "DAL_354t")
  end,
}

-- Crystal Power: Choose One: 2 damage to a minion; or restore 5 Health (any character). Both (Fandral): the damage, then
-- the heal if it lives; a hero: only the heal (wiki).
local function thorns(g, me, t)
  g.damage(me, t, g.spell_dmg(me, 2))
end
local function blossom(g, me, t)
  g.heal(me, t, g.heal_amt(me, 5))
end
cards.DAL_350 = {
  choose_one = { "DAL_350a", "DAL_350b" },
  both = function(g, me, t)
    if g.is_minion(t) then
      thorns(g, me, t)
      g.resolve()
    end
    if alive(g, t) or g.is_champion(t) then
      blossom(g, me, t)
    end
  end,
}
-- The option cards also as spells of their own (Keeper Stalladris puts them in the hand).
cards.DAL_350a = { target = "minion", effect = thorns, spell = thorns }
cards.DAL_350b = { target = "any", effect = blossom, spell = blossom }

-- Crystalsong Portal: Discover a Druid minion (no neutrals); a hand with no minion (the Portal has left it): all 3.
cards.DAL_352 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local ids = pick_n(g, pool(g, minion_of(function(i)
      return of_class(i, "DRUID")
    end)), 3)
    local keep_all = not list.any(g.hand(p), function(e)
      return g.type(e) == "MINION"
    end)
    if keep_all then
      for _, c in ipairs(ids) do
        g.add_to_hand(p, c)
      end
    else
      offer_cards(g, me, ids)
    end
  end,
  on_choose = to_hand,
}

-- Dreamway Guardians: two 1/2 Lifesteal Dryads (a full board at release: nothing).
cards.DAL_733 = {
  spell = function(g, me)
    summon_n(g, g.ctrl(me), "DAL_733t", 2)
  end,
}

-- Keeper Stalladris: after you cast a Choose One spell, copies of both its option cards (`<id>a`, `<id>b`) to the hand,
-- each at the parent spell's cost (wiki).
cards.DAL_732 = on_mine("after_spell", function(g, me, ev)
  local i = g.info(ev.card)
  if not (i and i.type == "SPELL" and has_kw(i, "CHOOSE_ONE")) then
    return
  end
  for _, s in ipairs({ "a", "b" }) do
    if g.info(ev.card .. s) then
      local c = g.add_to_hand(g.ctrl(me), ev.card .. s)
      if c then
        g.enchant(c, { cost_set = i.cost })
      end
    end
  end
end)

-- Blessing of the Ancients (Twinspell: the engine): your minions +1/+1.
cards.DAL_351 = {
  spell = function(g, me)
    buff_all(g, g.ctrl(me), 1, 1)
  end,
}

-- Lifeweaver: whenever your card restores Health (a character healed by more than 0), a random Druid spell to the hand.
cards.DAL_355 = {
  on = {
    heal = function(g, me, ev)
      if ev.amount > 0 and ev.source and ev.source >= 0 and g.ctrl(ev.source) == g.ctrl(me) then
        g.add_to_hand(g.ctrl(me), random_card(g, spell_of("DRUID")))
      end
    end,
  },
}

-- Crystal Stag: Rush; Battlecry: if you've restored 5 Health this game (the player hooks' count RESTORED), summon a copy.
local function stag_left(g, p)
  return 5 - g.count(p, "RESTORED")
end
cards.DAL_799 = {
  battlecry = function(g, me)
    if stag_left(g, g.ctrl(me)) <= 0 then
      summon_copies(g, me, 1)
    end
  end,
  glow = function(g, me)
    return stag_left(g, g.ctrl(me)) <= 0
  end,
}

-- Lucentbark: Taunt; Deathrattle: goes dormant (Spirit of Lucentbark where it died); the Spirit counts the Health your
-- cards restore while it is in play and at 5 turns back into Lucentbark.
cards.DAL_357 = {
  deathrattle = function(g, me)
    summon_here(g, me, "DAL_357t")
  end,
}
cards.DAL_357t = {
  on = {
    heal = function(g, me, ev)
      if ev.amount > 0 and ev.source and ev.source >= 0 and g.ctrl(ev.source) == g.ctrl(me) then
        g.add_tag(me, "LUCENT_HEALED", ev.amount)
        if g.tag(me, "LUCENT_HEALED") >= 5 then
          g.transform(me, "DAL_357")
        end
      end
    end,
  },
  text = function(g, me)
    local n = 5 - g.tag(me, "LUCENT_HEALED")
    return n > 0 and n or 0
  end,
}

-- The Forest's Aid (Twinspell): five 2/2 Treants.
cards.DAL_256 = {
  spell = function(g, me)
    summon_n(g, g.ctrl(me), "DAL_256t2", 5)
  end,
}

-- --- Hunter ------------------------------------------------------------------------------------------------------------

-- Rapid Fire (Twinspell): 1 damage.
cards.DAL_373 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 1))
  end,
}

-- Shimmerfly: Deathrattle: a random Hunter spell to the hand.
cards.DAL_587 = {
  deathrattle = function(g, me)
    g.add_to_hand(g.ctrl(me), random_card(g, spell_of("HUNTER")))
  end,
}

-- Nine Lives: Discover a friendly Deathrattle minion that died this game (different cards); the copy to the hand, and
-- its Deathrattle runs (from the hand: its summons go to the right end).
cards.DAL_377 = {
  spell = function(g, me)
    offer_cards(g, me, distinct_cards(g, dead_minions(g, g.ctrl(me), function(e)
      return has_kw(info(g, e), "DEATHRATTLE")
    end)))
  end,
  on_choose = function(g, me, option)
    local c = to_hand(g, me, option)
    for _ = 1, deathrattle_times(g, g.ctrl(me)) do
      g.deathrattle(c or option)
      g.resolve()
    end
  end,
}

-- Ursatron: Deathrattle: draw a random Mech from the deck.
cards.DAL_604 = {
  deathrattle = function(g, me)
    draw_from_deck(g, g.ctrl(me), function(e)
      return is_mech(g, e) and g.type(e) == "MINION"
    end)
  end,
}

-- Arcane Fletcher: whenever you play a minion that cost (1), draw a random spell from the deck.
cards.DAL_372 = on_mine("play", function(g, me, ev)
  if ev.kind == "minion" and ev.entity ~= me and g.tag(ev.entity, "PLAYED_COST") == 1 then
    draw_from_deck(g, g.ctrl(me), function(e)
      return g.type(e) == "SPELL"
    end)
  end
end)

-- Marked Shot: 4 damage to a minion, then Discover a spell.
cards.DAL_371 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
    discover(g, me, function(i)
      return i.type == "SPELL"
    end)
  end,
  on_choose = to_hand,
}

-- Hunting Party: a copy of each Beast in the hand (keeps its enchantments).
cards.DAL_589 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local beasts = list.filter(g.hand(p), function(e)
      return g.type(e) == "MINION" and g.race(e) == "BEAST"
    end)
    for _, e in ipairs(beasts) do
      copy_to_hand(g, p, e)
    end
  end,
}

-- Oblivitron: Deathrattle: a random Mech of the hand is summoned where it stood, and its Deathrattle runs.
cards.DAL_376 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    local e = g.pick(list.filter(g.hand(p), function(c)
      return g.type(c) == "MINION" and is_mech(g, c)
    end))
    if not e or g.room(p) <= 0 then
      return
    end
    local pos = g.died_pos(me)
    local m = g.summon_entity(e, pos >= 0 and pos or nil)
    if m then
      g.resolve()
      trigger_deathrattle(g, m)
    end
  end,
}

-- Unleash the Beast (Twinspell): a 5/5 Rush Wyvern.
cards.DAL_378 = {
  spell = function(g, me)
    g.summon(g.ctrl(me), "DAL_378t1")
  end,
}

-- Vereesa Windrunner: Battlecry: equip Thori'dal. Thori'dal: after your hero attacks, Spell Damage +2 this turn (an aura
-- of the weapon on its champion, for the turn it marked).
cards.DAL_379 = {
  battlecry = function(g, me)
    g.equip(g.ctrl(me), "DAL_379t")
  end,
}
cards.DAL_379t = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == g.hero(g.ctrl(me)) then
        g.add_tag(me, "THORIDAL", 2)
        g.set_tag(me, "THORIDAL_TURN", g.turn())
      end
    end,
  },
  aura = function(g, me)
    if g.tag(me, "THORIDAL_TURN") == g.turn() then
      g.aura_add(g.hero(g.ctrl(me)), 0, 0, { SPELLPOWER = g.tag(me, "THORIDAL") })
    end
  end,
}

-- --- Mage --------------------------------------------------------------------------------------------------------------

-- Magic Trick: Discover a spell that costs (3) or less.
cards.DAL_608 = {
  spell = function(g, me)
    discover(g, me, function(i)
      return i.type == "SPELL" and i.cost <= 3
    end)
  end,
  on_choose = to_hand,
}

-- Ray of Frost (Twinspell): Freeze a minion; already Frozen: 2 damage to it (it stays Frozen).
cards.DAL_577 = {
  target = "minion",
  spell = function(g, me, t)
    if g.has(t, "FROZEN") then
      g.damage(me, t, g.spell_dmg(me, 2))
    else
      g.freeze(t)
    end
  end,
}

-- Magic Dart Frog: after you cast a spell, 1 damage to a random enemy minion.
cards.DAL_182 = on_mine("after_spell", function(g, me)
  g.damage(me, g.random_alive(g.minions(g.enemy(me))), 1)
end)

-- Mana Cyclone: Battlecry: a random Mage spell for each spell you cast this turn (the player hooks' TURN_SPELLS).
cards.DAL_603 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, g.count(p, "TURN_SPELLS") do
      g.add_to_hand(p, random_card(g, spell_of("MAGE")))
    end
  end,
}

-- Conjurer's Calling (Twinspell): destroy a minion (its Deathrattle resolves), then 2 random minions of its printed Cost
-- for its owner where it stood.
cards.DAL_177 = {
  target = "minion",
  spell = function(g, me, t)
    local p, cost = g.ctrl(t), info(g, t).cost
    g.destroy(t)
    g.resolve()
    local pos = g.died_pos(t)
    local ids = pool(g, minion_of(function(i)
      return i.cost == cost
    end))
    for _ = 1, 2 do
      local c = g.pick(ids)
      if c then
        g.summon(p, c, pos >= 0 and pos or nil)
      end
    end
  end,
}

-- Messenger Raven: Battlecry: Discover a Mage minion.
cards.DAL_163 = {
  battlecry = function(g, me)
    discover(g, me, minion_of(function(i)
      return of_class(i, "MAGE")
    end))
  end,
  on_choose = to_hand,
}

-- Kirin Tor Tricaster: Spell Damage +3 (card data); your spells cost (1) more.
cards.DAL_576 = {
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.type(card) == "SPELL" and g.zone(card) == "HAND" then
      return cost + 1
    end
    return cost
  end,
}

-- Power of Creation: Discover a 6-Cost minion, summon two copies of it.
cards.DAL_578 = {
  spell = function(g, me)
    discover(g, me, minion_of(function(i)
      return i.cost == 6
    end))
  end,
  on_choose = function(g, me, option)
    summon_n(g, g.ctrl(me), g.card(option), 2)
  end,
}

-- Kalecgos: your first spell each of your turns costs (0) (no spell played yet this turn: TURN_SPELLS); Battlecry:
-- Discover a spell.
cards.DAL_609 = {
  cost_aura = function(g, me, card, cost)
    local p = g.ctrl(me)
    if g.ctrl(card) == p and g.type(card) == "SPELL" and g.zone(card) == "HAND" and g.current() == p
        and g.count(p, "TURN_SPELLS") == 0 then
      return 0
    end
    return cost
  end,
  battlecry = function(g, me)
    discover(g, me, function(i)
      return i.type == "SPELL"
    end)
  end,
  on_choose = to_hand,
}

-- --- Paladin -----------------------------------------------------------------------------------------------------------

-- Desperate Measures (Twinspell): cast a random Paladin Secret you don't control.
cards.DAL_141 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local have = {}
    for _, s in ipairs(g.traps(p)) do
      have[g.card(s)] = true
    end
    local c = random_card(g, function(i)
      return i.type == "SPELL" and i.trap and of_class(i, "PALADIN") and not have[i.id]
    end)
    if c then
      g.cast_random(me, c)
    end
  end,
}

-- Never Surrender!: Secret: when your opponent casts a spell, your minions +2 Health.
cards.DAL_570 = {
  secret = {
    event = "play",
    cond = function(g, me, ev)
      return ev.kind == "spell" and #g.minions(g.ctrl(me)) > 0
    end,
    effect = function(g, me)
      buff_all(g, g.ctrl(me), 0, 2)
    end,
  },
}

-- Lightforged Blessing (Twinspell): a friendly minion gets Lifesteal.
cards.DAL_568 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.give_tag(t, "LIFESTEAL")
  end,
}

-- Mysterious Blade: Battlecry: +1 Attack if you control a Secret.
cards.DAL_571 = {
  battlecry = function(g, me)
    if #g.traps(g.ctrl(me)) > 0 then
      g.buff(me, 1, 0)
    end
  end,
  glow = function(g, me)
    return #g.traps(g.ctrl(me)) > 0
  end,
}

-- Bronze Herald: Deathrattle: two 4/4 Bronze Dragons to the hand.
cards.DAL_146 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    g.add_to_hand(p, "DAL_146t")
    g.add_to_hand(p, "DAL_146t")
  end,
}

-- Call to Adventure: draw the lowest-Cost minion of the deck (a random one of the ties), +2/+2.
cards.DAL_727 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local ms = list.filter(g.deck(p), function(e)
      return g.type(e) == "MINION"
    end)
    if #ms == 0 then
      return
    end
    local low = g.cost(ms[1])
    for _, e in ipairs(ms) do
      if g.cost(e) < low then
        low = g.cost(e)
      end
    end
    local e = g.pick(list.filter(ms, function(x)
      return g.cost(x) == low
    end))
    g.draw_entity(p, e)
    if g.zone(e) == "HAND" then
      g.buff(e, 2, 2)
    end
  end,
}

-- Commander Rhyssa: your Secrets trigger twice (DOUBLE_SECRET, the engine's DOUBLE_TRAP, on the champion).
cards.DAL_573 = {
  aura = function(g, me)
    g.aura_add(g.hero(g.ctrl(me)), 0, 0, { DOUBLE_SECRET = 1 })
  end,
}

-- Dragon Speaker: Battlecry: the Dragons in your hand +3/+3.
cards.DAL_147 = {
  battlecry = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      if g.type(e) == "MINION" and g.race(e) == "DRAGON" then
        g.buff(e, 3, 3)
      end
    end
  end,
}

-- Duel!: a random minion of each player's deck is summoned; yours attacks theirs (not one that Can't Attack).
cards.DAL_731 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local function pull(q)
      if g.room(q) <= 0 then
        return nil
      end
      local e = g.pick(list.filter(g.deck(q), function(d)
        return g.type(d) == "MINION"
      end))
      return e and g.summon_entity(e)
    end
    local mine = pull(p)
    local theirs = pull(g.opponent(p))
    g.resolve()
    if mine and theirs and alive(g, mine) and alive(g, theirs) and not g.has(mine, "CANT_ATTACK") then
      g.force_attack(mine, theirs)
    end
  end,
}

-- Nozari: Battlecry: both heroes restored to full Health.
cards.DAL_581 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _, h in ipairs({ g.hero(p), g.hero(g.opponent(p)) }) do
      if g.dmg(h) > 0 then
        g.heal(me, h, g.dmg(h))
      end
    end
  end,
}

-- --- Priest ------------------------------------------------------------------------------------------------------------

-- Forbidden Words: spend all your Mana; destroy a minion with that much Attack or less.
cards.DAL_723 = {
  target = { base = "minion", filter = function(g, me, t)
    return g.atk(t) <= g.mana(g.ctrl(me))
  end },
  spell = function(g, me, t)
    local p = g.ctrl(me)
    local n = g.mana(p)
    g.set_mana(p, 0)
    if g.atk(t) <= n then
      g.destroy(t)
    end
  end,
}

-- Lazul's Scheme: an enemy minion's Attack -X until your next turn (X: 1, +1 at the start of each of your turns while
-- it is in the hand).
local function lazul_x(g, me)
  return 1 + g.tag(me, "SCHEME")
end
cards.DAL_011 = {
  target = "enemy_minion",
  hand = {
    turn_start = function(g, me, ev)
      if ev.player == g.ctrl(me) then
        g.add_tag(me, "SCHEME", 1)
      end
    end,
  },
  text = function(g, me)
    return lazul_x(g, me)
  end,
  spell = function(g, me, t)
    g.enchant(t, { atk = -lazul_x(g, me), hooks = "ench:dal_lazul", player = g.ctrl(me) })
  end,
}
-- Its enchantment ends at the start of the caster's next turn.
cards["ench:dal_lazul"] = {
  on = {
    turn_start = function(g, me, ev)
      for _, p in ipairs(g.enchants(me, "ench:dal_lazul")) do
        if p == ev.player then
          g.remove_enchant(me, "ench:dal_lazul", p)
        end
      end
    end,
  },
}

-- EVIL Conscripter: Deathrattle: a random Lackey to the hand.
cards.DAL_413 = {
  deathrattle = function(g, me)
    g.add_to_hand(g.ctrl(me), g.pick(LACKEYS))
  end,
}

-- Shadowy Figure: Battlecry: becomes a 2/2 copy of another friendly Deathrattle minion.
cards.DAL_030 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me and g.has_deathrattle(t)
  end },
  battlecry = function(g, me, t)
    if t and alive(g, me) then
      local c = g.copy_minion(me, t) or me
      g.set_stats(c, 2, 2)
    end
  end,
}

-- Madame Lazul: Battlecry: Discover a copy of a card in the opponent's hand (different cards).
cards.DAL_729 = {
  battlecry = function(g, me)
    offer_copies(g, me, g.hand(g.enemy(me)))
  end,
  on_choose = take_copy,
}

-- Hench-Clan Shadequill: Deathrattle: restore 5 Health to the enemy hero.
cards.DAL_040 = {
  deathrattle = function(g, me)
    g.heal(me, g.hero(g.enemy(me)), 5)
  end,
}

-- Unsleeping Soul: Silence a friendly minion, then summon a (silenced) copy of it.
cards.DAL_065 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.silence(t)
    summon_copies(g, t, 1)
  end,
}

-- Convincing Infiltrator: Taunt; Deathrattle: destroy a random enemy minion.
cards.DAL_039 = {
  deathrattle = function(g, me)
    g.destroy(g.random_alive(g.minions(g.enemy(me))))
  end,
}

-- Catrina Muerte: at the end of your turn, a random friendly minion that died this game is summoned (a fresh card).
cards.DAL_721 = end_of_my_turn(function(g, me)
  local e = g.pick(dead_minions(g, g.ctrl(me)))
  if e then
    g.summon(g.ctrl(me), g.card(e))
  end
end)

-- Mass Resurrection: 3 different friendly minions that died this game (a minion that died twice is in the list twice).
cards.DAL_724 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, e in ipairs(pick_n(g, dead_minions(g, p), 3)) do
      g.summon(p, g.card(e))
    end
  end,
}

return cards
