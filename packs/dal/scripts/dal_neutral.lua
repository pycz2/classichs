-- Rise of Shadows (April 2019): its neutral cards as at the release (build 30103, patch 14.0.0.30103 of 2019-04-09;
-- hearthstone.wiki.gg, its card notes and its pages as they were in 2019; docs/packs/api.md).
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

-- --- Rise of Shadows: the neutral cards ---------------------------------------------------------------------------------

local LACKEYS = { "DAL_613", "DAL_614", "DAL_615", "DAL_739", "DAL_741" }

local function add_lackey(g, p)
  return g.add_to_hand(p, LACKEYS[g.random(1, #LACKEYS)])
end

local function spell_power(g, p)
  return g.spell_dmg(g.hero(p), 0) > 0
end

-- Potion Vendor: Battlecry: restore 2 Health to all friendly characters.
cards.DAL_544 = {
  battlecry = function(g, me)
    for _, c in ipairs(g.chars(g.ctrl(me))) do
      g.heal(me, c, g.heal_amt(me, 2))
    end
  end,
}

-- Toxfin: Battlecry: give a friendly Murloc Poisonous.
cards.DAL_077 = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t)
      return t ~= me and g.race(t) == "MURLOC"
    end,
  },
  battlecry = function(g, me, t)
    g.give_tag(t, "POISONOUS")
  end,
}

-- Dalaran Librarian: Battlecry: Silence adjacent minions.
cards.DAL_735 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.adjacent(me)) do
      g.silence(m)
    end
  end,
}

-- EVIL Cable Rat: Battlecry: add a Lackey to your hand.
cards.DAL_400 = {
  battlecry = function(g, me)
    add_lackey(g, g.ctrl(me))
  end,
}

-- Hench-Clan Hogsteed: Rush; Deathrattle: summon a 1/1 Murloc (Hench-Clan Squire).
cards.DAL_743 = {
  deathrattle = function(g, me)
    summon_here(g, me, "DAL_743t")
  end,
}

-- Spellbook Binder: Battlecry: if you have Spell Damage, draw a card.
cards.DAL_089 = {
  glow = function(g, me)
    return spell_power(g, g.ctrl(me))
  end,
  battlecry = function(g, me)
    if spell_power(g, g.ctrl(me)) then
      g.draw(g.ctrl(me))
    end
  end,
}

-- Sunreaver Spy: Battlecry: if you control a Secret, gain +1/+1.
cards.DAL_086 = {
  glow = function(g, me)
    return #g.traps(g.ctrl(me)) > 0
  end,
  battlecry = function(g, me)
    if #g.traps(g.ctrl(me)) > 0 then
      g.buff(me, 1, 1)
    end
  end,
}

-- Arcane Watcher: can't attack unless you have Spell Damage.
cards.DAL_434 = {
  aura = function(g, me)
    if not spell_power(g, g.ctrl(me)) then
      g.aura_add(me, 0, 0, { CANT_ATTACK = true })
    end
  end,
}

-- Faceless Rager: Battlecry: copy a friendly minion's Health (its current Health becomes this one's Health).
cards.DAL_744 = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t)
      return t ~= me
    end,
  },
  battlecry = function(g, me, t)
    g.set_stats(me, nil, g.health(t))
  end,
}

-- Flight Master: Battlecry: summon a 2/2 Gryphon for each player.
cards.DAL_747 = {
  battlecry = function(g, me)
    g.summon_right(me, "DAL_747t")
    g.summon(g.enemy(me), "DAL_747t")
  end,
}

-- Magic Carpet: after you play a 1-Cost minion (its cost when played), give it +1 Attack and Rush.
cards.DAL_773 = {
  on = {
    after_summon = function(g, me, ev)
      if ev.played and g.mine(me, ev) and ev.entity ~= me and g.tag(ev.entity, "PLAYED_COST") == 1 then
        g.buff(ev.entity, 1, 0)
        g.give_tag(ev.entity, "RUSH")
      end
    end,
  },
}

cards["ench:dal_jeweler"] = {
  on = {
    turn_start = function(g, me, ev)
      if g.mine(me, ev) then
        g.erase_tag(me, "ELUSIVE")
        g.remove_enchant(me, "ench:dal_jeweler")
      end
    end,
  },
}

-- Spellward Jeweler: Battlecry: your hero can't be targeted by spells or Hero Powers until your next turn.
cards.DAL_081 = {
  battlecry = function(g, me)
    local h = g.hero(g.ctrl(me))
    g.give_tag(h, "ELUSIVE")
    g.enchant(h, { hooks = "ench:dal_jeweler", player = g.ctrl(me) })
  end,
}

-- Archmage Vargoth: at the end of your turn, cast a spell you've cast this turn (random targets; not a countered one).
-- The spells come from the player hooks' CAST_TURN (dal.lua): every spell of this turn that resolved, also before it came.
cards.DAL_558 = {
  on = {
    turn_end = function(g, me, ev)
      if not g.mine(me, ev) then
        return
      end
      local s = g.pick(list.filter(g.graveyard(g.ctrl(me)), function(e)
        return g.type(e) == "SPELL" and g.tag(e, "CAST_TURN") == g.turn()
      end))
      if s then
        g.cast_random(me, g.card(s))
      end
    end,
  },
}

-- Hecklebot: Taunt; Battlecry: your opponent summons a minion from their deck.
cards.DAL_058 = {
  battlecry = function(g, me)
    recruit(g, g.enemy(me))
  end,
}

-- Hench-Clan Hag: Battlecry: summon two 1/1 Amalgams with all minion types.
cards.DAL_087 = {
  battlecry = function(g, me)
    g.summon_right(me, "DAL_087t")
    g.summon_right(me, "DAL_087t")
  end,
}

-- Felhound Portal: Casts When Drawn: summon a 2/2 Felhound with Rush.
cards.DAL_582t = cast_when_drawn(function(g, me)
  g.summon(g.ctrl(me), "DAL_582t2")
end)

local function three_portals(g, me)
  for _ = 1, 3 do
    g.add_to_deck(g.ctrl(me), "DAL_582t")
  end
end

-- Portal Keeper / Portal Overfiend: Battlecry: shuffle 3 Portals into your deck.
cards.DAL_582 = { battlecry = three_portals }
cards.DAL_565 = { battlecry = three_portals }

-- Proud Defender: Taunt; +2 Attack while you have no other minions.
cards.DAL_551 = {
  aura = function(g, me)
    if #g.others(me) == 0 then
      g.aura_add(me, 2, 0)
    end
  end,
}

-- Soldier of Fortune: whenever it attacks, give your opponent a Coin.
cards.DAL_771 = {
  on = {
    attack = function(g, me, ev)
      if ev.attacker == me then
        g.add_to_hand(g.enemy(me), COIN)
      end
    end,
  },
}

-- Travelling Healer: Divine Shield; Battlecry: restore 3 Health.
cards.DAL_078 = {
  target = "any",
  battlecry = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 3))
  end,
}

local function spells_in_hand(g, p)
  return #list.filter(g.hand(p), function(e)
    return g.type(e) == "SPELL"
  end)
end

-- Violet Spellsword: Battlecry: +1 Attack for each spell in your hand.
cards.DAL_095 = {
  battlecry = function(g, me)
    local n = spells_in_hand(g, g.ctrl(me))
    if n > 0 then
      g.buff(me, n, 0)
    end
  end,
}

-- Azerite Elemental: at the start of your turn, gain Spell Damage +2.
cards.DAL_548 = on_mine("turn_start", function(g, me)
  g.add_tag(me, "SPELLPOWER", 2)
end)

-- Barista Lynchen: Battlecry: a copy of each of your other Battlecry minions to your hand (left to right; base cards).
cards.DAL_546 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _, m in ipairs(g.others(me)) do
      if has_kw(info(g, m), "BATTLECRY") then
        g.add_to_hand(p, g.card(m))
      end
    end
  end,
}

-- Recurring Villain: Deathrattle: if this minion has 4 or more Attack, resummon it.
cards.DAL_749 = {
  deathrattle = function(g, me)
    if g.atk(me) >= 4 then
      summon_here(g, me, "DAL_749")
    end
  end,
}

local function big_spell(g, p)
  return list.any(g.hand(p), function(e)
    return g.type(e) == "SPELL" and g.cost(e) >= 5
  end)
end

-- Sunreaver Warmage: Battlecry: if you're holding a spell that costs (5) or more, deal 4 damage.
cards.DAL_539 = {
  glow = function(g, me)
    return list.any(g.hand(g.ctrl(me)), function(e)
      return e ~= me and g.type(e) == "SPELL" and g.info(g.card(e)).cost >= 5
    end)
  end,
  target = {
    base = "any",
    when = function(g, me)
      return list.any(g.hand(g.ctrl(me)), function(e)
        return g.type(e) == "SPELL" and g.info(g.card(e)).cost >= 5
      end)
    end,
  },
  battlecry = function(g, me, t)
    if t and big_spell(g, g.ctrl(me)) then
      g.damage(me, t, 4)
    end
  end,
}

-- Eccentric Scribe: Deathrattle: summon four 1/1 Vengeful Scrolls.
cards.DAL_566 = {
  deathrattle = function(g, me)
    for _ = 1, 4 do
      summon_here(g, me, "DAL_566t")
    end
  end,
}

-- Mad Summoner: Battlecry: fill each player's board with 1/1 Imps (yours first, then the opponent's).
cards.DAL_751 = {
  battlecry = function(g, me)
    for _, p in ipairs({ g.ctrl(me), g.enemy(me) }) do
      while g.room(p) > 0 do
        if not g.summon(p, "DAL_751t") then
          break
        end
      end
    end
  end,
}

-- Safeguard: Taunt; Deathrattle: summon a 0/5 Vault Safe with Taunt.
cards.DAL_088 = {
  deathrattle = function(g, me)
    summon_here(g, me, "DAL_088t2")
  end,
}

-- Unseen Saboteur: Battlecry: your opponent casts a random spell from their hand (targets chosen randomly).
cards.DAL_538 = {
  battlecry = function(g, me)
    local foe = g.enemy(me)
    local s = g.pick(list.filter(g.hand(foe), function(e)
      return g.type(e) == "SPELL"
    end))
    if s then
      g.remove(s, "GRAVEYARD")
      g.cast_random(g.hero(foe), g.card(s), true)
    end
  end,
}

-- Chef Nomi: Battlecry: if your deck is empty, summon six 6/6 Greasefire Elementals.
cards.DAL_554 = {
  glow = function(g, me)
    return #g.deck(g.ctrl(me)) == 0
  end,
  battlecry = function(g, me)
    if #g.deck(g.ctrl(me)) == 0 then
      for _ = 1, 6 do
        g.summon_right(me, "DAL_554t")
      end
    end
  end,
}

-- Exotic Mountseller: whenever you cast a spell, summon a random 3-Cost Beast.
cards.DAL_774 = {
  on = {
    play = function(g, me, ev)
      if g.mine(me, ev) and ev.kind == "spell" then
        local c = random_card(g, minion_of(function(i)
          return i.cost == 3 and i.race == "BEAST"
        end))
        if c then
          g.summon_right(me, c)
        end
      end
    end,
  },
}

-- Tunnel Blaster: Taunt; Deathrattle: deal 3 damage to all minions.
cards.DAL_775 = {
  deathrattle = function(g, me)
    damage_all_minions(g, me, 3)
  end,
}

-- Underbelly Ooze: after this minion survives damage, summon an exact copy of it (damage and enchantments).
cards.DAL_550 = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me and ev.amount > 0 and alive(g, me) then
        summon_copies(g, me, 1)
      end
    end,
  },
}

-- Archivist Elysiana: Battlecry: Discover 5 cards; replace your deck with 2 copies of each.
local function elysiana_round(g, me)
  local n = g.tag(me, "ELYSIANA_LEFT")
  if n <= 0 then
    return
  end
  g.set_tag(me, "ELYSIANA_LEFT", n - 1)
  if discover(g, me, function()
    return true
  end) == 0 then
    g.set_tag(me, "ELYSIANA_LEFT", 0)
  end
end

cards.DAL_736 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _, e in ipairs(g.deck(p)) do
      g.remove(e, "SETASIDE")
    end
    g.set_tag(me, "ELYSIANA_LEFT", 5)
    elysiana_round(g, me)
  end,
  on_choose = function(g, me, option)
    for _ = 1, 2 do
      g.add_to_deck(g.ctrl(me), g.card(option))
    end
    elysiana_round(g, me)
  end,
}

-- Batterhead: Rush; after this attacks and kills a minion, it may attack again.
cards.DAL_592 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == me and ev.defender >= 0 and g.is_minion(ev.defender) and not alive(g, ev.defender) then
        g.set_tag(me, "ATTACKS", 0)
      end
    end,
  },
}

-- Heroic Innkeeper: Taunt; Battlecry: gain +2/+2 for each other friendly minion.
cards.DAL_560 = {
  battlecry = function(g, me)
    local n = #g.others(me)
    if n > 0 then
      g.buff(me, 2 * n, 2 * n)
    end
  end,
}

-- Jepetto Joybuzz: Battlecry: draw 2 minions from your deck; set their Attack, Health and Cost to 1.
cards.DAL_752 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 2 do
      local e = random_from_deck(g, p, function(d)
        return g.type(d) == "MINION"
      end)
      if not e then
        break
      end
      g.draw_entity(p, e)
      if g.zone(e) == "HAND" then
        g.enchant(e, { set_atk = 1, set_hp = 1, cost_set = 1 })
      end
    end
  end,
}

-- Whirlwind Tempest: your minions with Windfury have Mega-Windfury (four attacks a turn).
cards.DAL_742 = {
  on = {
    after_attack = function(g, me, ev)
      local a = ev.attacker
      if a ~= me and g.is_minion(a) and g.ctrl(a) == g.ctrl(me) and g.has(a, "WINDFURY") then
        local n = g.tag(a, "DAL_MEGA") + 1
        g.set_tag(a, "DAL_MEGA", n)
        if n >= 2 and n < 4 then
          g.set_tag(a, "ATTACKS", 1)
        end
      end
    end,
    turn_start = function(g, me)
      for _, m in ipairs(g.minions(g.ctrl(me))) do
        g.set_tag(m, "DAL_MEGA", nil)
      end
    end,
  },
}

-- Big Bad Archmage: at the end of your turn, summon a random 6-Cost minion.
cards.DAL_553 = end_of_my_turn(function(g, me)
  local c = random_card(g, minion_of(function(i)
    return i.cost == 6
  end))
  if c then
    g.summon_right(me, c)
  end
end)

-- The Lackeys -------------------------------------------------------------------------------------------------------------


return cards
