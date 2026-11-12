-- The Witchwood (April 2018): the Druid, Hunter and Mage cards as at the release (build 23966 of patch 11.0.0.23966;
-- hearthstone.wiki.gg and its card notes; docs/packs/api.md). Echo and Rush are the player hooks' and data (gil.lua);
-- Hunting Mastiff, Vilebrood Skitterer and the Zombeast parts need no script.
local cards = {}

-- --- helpers (the same in every gil*.lua; loot.lua's) --------------------------------------------------------------

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


-- --- The Witchwood's helpers (the same in every gil*.lua) ------------------------------------------------------------

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

-- --- Druid ---------------------------------------------------------------------------------------------------------------

-- Witchwood Apple: three 2/2 Treants to your hand (a full hand: the rest are lost).
cards.GIL_663 = {
  spell = function(g, me)
    for _ = 1, 3 do
      g.add_to_hand(g.ctrl(me), "GIL_663t")
    end
  end,
}

-- Druid of the Scythe: Choose One: a 4/2 with Rush (Dire Panther Form) or a 2/4 with Taunt (Dire Wolf Form); with
-- Fandral Staghelm a 4/4 with both. On 2018-04-12 it is summoned as the 2/2, then transforms (patch 11.2 changed that).
cards.GIL_188 = {
  choose_one = { "GIL_188a", "GIL_188b" },
  both = function(g, me)
    g.transform(me, "GIL_188t3")
  end,
}
cards.GIL_188a = {
  effect = function(g, me)
    g.transform(me, "GIL_188t")
  end,
}
cards.GIL_188b = {
  effect = function(g, me)
    g.transform(me, "GIL_188t2")
  end,
}

-- Ferocious Howl: draw a card, then 1 Armor for each card in your hand (after the draw; the Howl has left it).
cards.GIL_637 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.draw(p)
    local n = #g.hand(p)
    if n > 0 then
      g.gain_armor(p, n)
    end
  end,
}

-- Witching Hour: a new copy (the base card) of a random friendly Beast that died this game (none died, a full board:
-- nothing).
cards.GIL_571 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local e = g.pick(dead_minions(g, p, function(d)
      return g.race(d) == "BEAST"
    end))
    if e then
      g.summon(p, g.card(e))
    end
  end,
}

-- Forest Guide: at the end of your turn, both players draw a card (DOUBT: its owner first).
cards.GIL_833 = end_of_my_turn(function(g, me)
  local p = g.ctrl(me)
  g.draw(p)
  g.draw(g.opponent(p))
end)

-- Wispering Woods: a 1/1 Wisp for each card in your hand (the spell itself is not counted), as many as there is room.
cards.GIL_553 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, #g.hand(p) do
      if not g.summon(p, "GIL_553t") then
        break
      end
    end
  end,
}

-- Bewitched Guardian: Taunt; Battlecry: +1 Health for each card in your hand (it has left the hand).
cards.GIL_507 = {
  battlecry = function(g, me)
    local n = #g.hand(g.ctrl(me))
    if n > 0 then
      g.buff(me, 0, n)
    end
  end,
}

-- Duskfallen Aviana: on each player's turn the first card that player plays costs (0) (wiki: Aviana herself counts as
-- the first card; the Hero Power is no card).
cards.GIL_800 = {
  cost_aura = function(g, me, card, cost)
    local p = g.current()
    if g.zone(card) == "HAND" and g.ctrl(card) == p and g.cards_played(p) == 0 then
      return 0
    end
    return cost
  end,
}

-- Gloom Stag: Taunt; Battlecry: +2/+2 if your deck (now; an empty one too) has only odd-Cost cards.
local function odd_deck(g, me)
  return deck_only(g, g.ctrl(me), true)
end
cards.GIL_130 = {
  glow = odd_deck,
  battlecry = function(g, me)
    if odd_deck(g, me) then
      g.buff(me, 2, 2)
    end
  end,
}

-- Splintergraft: Battlecry: a copy of another friendly minion (the base card) to your hand, 10/10 and costing (10).
cards.GIL_658 = {
  target = { base = "friendly_minion", filter = other_friendly },
  battlecry = function(g, me, t)
    if not t then
      return
    end
    local c = g.add_to_hand(g.ctrl(me), g.card(t))
    if c then
      g.enchant(c, { set_atk = 10, set_hp = 10 })
      g.enchant(c, { cost_set = 10 })
    end
  end,
}

-- --- Hunter --------------------------------------------------------------------------------------------------------------

-- Rat Trap: after your opponent plays a third card in a turn (the cards played before the Secret came count too), a
-- 6/6 Doom Rat. On 2018-04-12 it goes off with a full board as well (no Rat; patch 11.2 changed that). The third card
-- is marked when it is played; the trap goes off after it resolved: a minion's after_summon, a spell's after_spell, a
-- weapon's equip (a hero card: at once).
local function rat_trap(g, me)
  g.reveal(me)
  g.summon(g.ctrl(me), "GIL_577t")
end
local function rat_after(g, me, ev)
  if g.trap_ready(me) and g.tag(me, "RAT_TRAP_CARD") == ev.entity then
    rat_trap(g, me)
  end
end
cards.GIL_577 = {
  on = {
    play = function(g, me, ev)
      local foe = g.enemy(me)
      if ev.player == foe and g.trap_ready(me) and g.cards_played(foe) >= 3 then
        if ev.kind == "champion" then
          rat_trap(g, me)
        else
          g.set_tag(me, "RAT_TRAP_CARD", ev.entity)
        end
      end
    end,
    after_summon = rat_after,
    after_spell = rat_after,
    equip = rat_after,
  },
}

-- Duskhaven Hunter: Stealth; at the start of each of its player's turns in the hand it becomes its other form (2/5 ⇄
-- 5/2), keeping its enchantments (2018).
local function swap_each_turn(other)
  return {
    hand = {
      turn_start = function(g, me, ev)
        if ev.player == g.ctrl(me) then
          shift_to(g, me, other)
        end
      end,
    },
  }
end
cards.GIL_200 = swap_each_turn("GIL_200t")
cards.GIL_200t = swap_each_turn("GIL_200")

-- Dire Frenzy: a Beast (either side) +3/+3; 3 copies of it (the base card, +3/+3) shuffled into your deck.
cards.GIL_828 = {
  target = { base = "minion", filter = function(g, me, t)
    return g.race(t) == "BEAST"
  end },
  spell = function(g, me, t)
    g.buff(t, 3, 3)
    for _ = 1, 3 do
      local c = g.add_to_deck(g.ctrl(me), g.card(t))
      if c then
        g.buff(c, 3, 3)
      end
    end
  end,
}

-- Houndmaster Shaw: your other minions have Rush (gone with Shaw: one summoned this turn can't attack then).
cards.GIL_650 = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      g.aura_add(m, 0, 0, { RUSH = true })
    end
  end,
}

-- Toxmonger: whenever you play a minion that costs (1) as it is played (the Cost paid), it gets Poisonous (as it is
-- summoned: its own Battlecry is Poisonous already).
cards.GIL_607 = on_mine("play", function(g, me, ev)
  if ev.kind == "minion" and ev.entity ~= me and g.tag(ev.entity, "PLAYED_COST") == 1 then
    g.give_tag(ev.entity, "POISONOUS")
  end
end)

-- Wing Blast: 4 damage to a minion; costs (1) while a minion (either side) died this turn (DOUBT: after the other cost
-- changes, cost_last: a change of -3 from its (4)).
local function died_now(g)
  return minions_died_this_turn(g) > 0
end
cards.GIL_518 = {
  target = "minion",
  cost_last = true,
  cost_mod = function(g, me)
    return died_now(g) and 1 - info(g, me).cost or 0
  end,
  glow = died_now,
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
  end,
}

-- Carrion Drake: Battlecry: Poisonous if a minion (either side) died this turn.
cards.GIL_905 = {
  glow = died_now,
  battlecry = function(g, me)
    if died_now(g) then
      g.give_tag(me, "POISONOUS")
    end
  end,
}

-- Emeriss: Battlecry: the minions in your hand get their current Attack and Health doubled (a +X/+Y buff).
cards.GIL_128 = {
  battlecry = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      if g.type(e) == "MINION" then
        g.buff(e, g.atk(e), g.health(e))
      end
    end
  end,
}

-- --- Mage ----------------------------------------------------------------------------------------------------------------

-- Archmage Arugal: whenever you draw a minion, a copy of it (the base card, 2018) to your hand.
cards.GIL_691 = on_mine("draw", function(g, me, ev)
  if g.type(ev.entity) == "MINION" then
    g.add_to_hand(g.ctrl(me), g.card(ev.entity))
  end
end)

-- Book of Specters: draw 3 cards; the spells drawn are discarded (a Cast When Drawn card casts first: it is gone).
cards.GIL_548 = {
  spell = function(g, me)
    local drawn = g.draw(g.ctrl(me), 3)
    g.resolve()
    for _, e in ipairs(drawn) do
      if g.zone(e) == "HAND" and g.type(e) == "SPELL" then
        g.discard(e)
      end
    end
  end,
}

-- Snap Freeze: Freeze a minion; if it is Frozen already, destroy it.
cards.GIL_801 = {
  target = "minion",
  spell = function(g, me, t)
    if g.has(t, "FROZEN") then
      g.destroy(t)
    else
      g.freeze(t)
    end
  end,
}

-- Black Cat: Spell Damage +1; Battlecry: draw a card if your deck has only odd-Cost cards.
cards.GIL_838 = {
  glow = odd_deck,
  battlecry = function(g, me)
    if odd_deck(g, me) then
      g.draw(g.ctrl(me))
    end
  end,
}

-- Cinderstorm: 5 damage randomly split among all enemies (one at a time; Spell Damage adds hits, as Arcane Missiles).
cards.GIL_147 = {
  spell = function(g, me)
    for _ = 1, g.spell_dmg(me, 5) do
      g.damage(me, g.random_alive(g.chars(g.enemy(me))), 1)
    end
  end,
}

-- Arcane Keysmith: Battlecry: Discover a Secret (of your class; not one you have in play) and put it into the
-- battlefield (5 Secrets already: it fizzles).
cards.GIL_116 = {
  battlecry = function(g, me)
    local have = {}
    for _, s in ipairs(g.traps(g.ctrl(me))) do
      have[g.card(s)] = true
    end
    discover(g, me, function(i)
      return i.trap and not have[i.id]
    end)
  end,
  on_choose = function(g, me, option)
    g.put_trap(option)
  end,
}

-- Vex Crow: whenever you cast a spell, a random 2-Cost minion right of it (before the spell resolves).
cards.GIL_664 = on_mine("play", function(g, me, ev)
  if ev.kind == "spell" then
    local c = random_card(g, minion_of(function(i)
      return i.cost == 2
    end))
    if c then
      g.summon_right(me, c)
    end
  end
end)

-- Bonfire Elemental: Battlecry: draw a card if you played an Elemental last turn.
local function elem_last(g, me)
  return elemental_last_turn(g, g.ctrl(me))
end
cards.GIL_645 = {
  glow = elem_last,
  battlecry = function(g, me)
    if elem_last(g, me) then
      g.draw(g.ctrl(me))
    end
  end,
}

-- Curio Collector: whenever you draw a card, +1/+1 (a burned card is not drawn).
cards.GIL_640 = on_mine("draw", function(g, me)
  g.buff(me, 1, 1)
end)

-- Toki, Time-Tinker: Battlecry: a random Legendary minion "from the past" to your hand: of any class, from the sets that
-- were Wild only on 2018-04-12 (Naxxramas, Goblins vs Gnomes, Blackrock Mountain, The Grand Tournament, The League of
-- Explorers, Whispers of the Old Gods, One Night in Karazhan, Mean Streets of Gadgetzan) and the Hall of Fame's two
-- Legendaries (Sylvanas Windrunner and Ragnaros the Firelord, Wild since 2017-04-07).
local PAST_SETS = { NAXX = true, GVG = true, BRM = true, TGT = true, LOE = true, OG = true, KARA = true, GANGS = true }
local HALL_OF_FAME = { VAN_EX1_016 = true, VAN_EX1_298 = true }
cards.GIL_549 = {
  battlecry = function(g, me)
    local c = random_card(g, function(i)
      return i.type == "MINION" and i.rarity == "LEGENDARY" and (PAST_SETS[i.set] or HALL_OF_FAME[i.id])
    end)
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

return cards
