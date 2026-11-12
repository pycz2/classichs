-- The Witchwood (April 2018): the first half of the neutral cards as at the release (build 23966 of patch 11.0.0.23966;
-- hearthstone.wiki.gg; docs/packs/api.md), with the worgen tokens. Echo (Phantom Militia, Walnut Sprite), Rush and
-- Nightmare Amalgam's every race need no hooks here (gil.lua's player hooks; the data).
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

-- --- the cards ---------------------------------------------------------------------------------------------------------

local function random_minion(g, ok)
  return random_card(g, minion_of(ok))
end

local function of_cost(n)
  return function(i)
    return i.cost == n
  end
end

-- The worgen (Pumpkin Peasant, Swift Messenger, Spellshifter): at the start of each of its owner's turns in the hand it
-- becomes its other form (the paired id: wiki, "Transform in hand"), keeping its enchantments (before patch 12.0).
local function worgen(other)
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
cards.GIL_201 = worgen("GIL_201t")
cards.GIL_201t = worgen("GIL_201")
cards.GIL_528 = worgen("GIL_528t")
cards.GIL_528t = worgen("GIL_528")
cards.GIL_529 = worgen("GIL_529t")
cards.GIL_529t = worgen("GIL_529")

-- Swamp Dragon Egg: Deathrattle: a random Dragon (a collectible Dragon minion of any class) to your hand.
cards.GIL_816 = {
  deathrattle = function(g, me)
    local c = random_minion(g, function(i)
      return i.race == "DRAGON"
    end)
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Lost Spirit: Deathrattle: your minions +1 Attack (those on the board then).
cards.GIL_513 = {
  deathrattle = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.buff(m, 1, 0)
    end
  end,
}

-- Baleful Banker: choose another friendly minion, shuffle a copy of it into your deck (the plain card: a play→deck copy
-- kept no enchantments).
cards.GIL_815 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me
  end },
  battlecry = function(g, me, t)
    if t then
      g.add_to_deck(g.ctrl(me), g.card(t))
    end
  end,
}

-- Ravencaller: two random 1-Cost minions (collectible, any class) to your hand.
cards.GIL_212 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 2 do
      local c = random_minion(g, of_cost(1))
      if c then
        g.add_to_hand(p, c)
      end
    end
  end,
}

-- Tanglefur Mystic: a random 2-Cost minion to each player's hand (two picks; yours first).
cards.GIL_213 = {
  battlecry = function(g, me)
    for _, p in ipairs({ g.ctrl(me), g.enemy(me) }) do
      local c = random_minion(g, of_cost(2))
      if c then
        g.add_to_hand(p, c)
      end
    end
  end,
}

-- Hench-Clan Thug: after your hero attacks, +1/+1.
cards.GIL_534 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == g.hero(g.ctrl(me)) then
        g.buff(me, 1, 1)
      end
    end,
  },
}

-- Blackwald Pixie: refresh your Hero Power (used this turn: it can be used again; unused: nothing).
cards.GIL_561 = {
  battlecry = function(g, me)
    g.erase_tag(g.power(g.ctrl(me)), "USED")
  end,
}

-- Voodoo Doll: Battlecry: choose a minion (either side); Deathrattle: destroy it. The curse is an enchantment of the
-- minion that ran the Battlecry (GIL_614e2: Silence takes it; Shudderwock repeating it gets one), the chosen ones its
-- VOODOO_<n> tags (a doubled Battlecry chooses twice). A chosen minion that left play or became another (a new entity)
-- is not destroyed.
cards.GIL_614 = {
  target = { base = "minion", filter = function(g, me, t)
    return t ~= me
  end },
  battlecry = function(g, me, t)
    if not t then
      return
    end
    local n = g.tag(me, "VOODOO_N") + 1
    g.set_tag(me, "VOODOO_N", n)
    g.set_tag(me, "VOODOO_" .. n, t)
    if n == 1 then
      g.enchant(me, { hooks = "ench:gil_voodoo", player = g.ctrl(me) })
    end
  end,
}
cards["ench:gil_voodoo"] = {
  deathrattle = function(g, me)
    for i = 1, g.tag(me, "VOODOO_N") do
      local t = g.tag(me, "VOODOO_" .. i)
      if alive(g, t) then
        g.destroy(t)
      end
    end
  end,
}

-- Marsh Drake: a 2/1 Poisonous Drakeslayer for your opponent (none on a full board).
cards.GIL_683 = {
  battlecry = function(g, me)
    g.summon(g.enemy(me), "GIL_683t")
  end,
}

-- Witch's Cauldron: after a friendly minion dies, a random Shaman spell (collectible) to your hand.
cards.GIL_819 = on_mine("death", function(g, me, ev)
  if ev.minion and ev.entity ~= me then
    local c = random_card(g, function(i)
      return i.type == "SPELL" and of_class(i, "SHAMAN")
    end)
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end
end)

-- Mad Hatter: three hats, each +1/+1 to a random other minion (either side; one may get several: wiki).
cards.GIL_125 = {
  battlecry = function(g, me)
    local others = list.filter(g.all_minions(), function(m)
      return m ~= me
    end)
    for _ = 1, 3 do
      local m = g.random_alive(others)
      if m then
        g.buff(m, 1, 1)
      end
    end
  end,
}

-- Lifedrinker: 3 damage to the enemy hero (no Spell Damage), then restore 3 Health to yours.
cards.GIL_622 = {
  battlecry = function(g, me)
    g.damage(me, g.hero(g.enemy(me)), 3)
    g.heal(me, g.hero(g.ctrl(me)), 3)
  end,
}

-- Night Prowler: if it is the only minion on the battlefield (both sides) as the Battlecry resolves, +3/+3. No glow in
-- the hand on 2018-04-12 (patch 11.2.0 of 2018-06-06 added it).
cards.GIL_624 = {
  battlecry = function(g, me)
    local others = list.filter(g.all_minions(), function(m)
      return m ~= me and alive(g, m)
    end)
    if #others == 0 then
      g.buff(me, 3, 3)
    end
  end,
}

-- Sandbinder: draw a random Elemental from your deck (nothing if none; Nightmare Amalgam is one).
cards.GIL_581 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local e = random_from_deck(g, p, function(d)
      return g.type(d) == "MINION" and g.race(d) == "ELEMENTAL"
    end)
    if e then
      g.draw_entity(p, e)
    end
  end,
}

-- Witchwood Piper: draw the minion of your deck with the lowest Cost now (ties: a random one).
cards.GIL_584 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local best, low = {}, nil
    for _, e in ipairs(g.deck(p)) do
      if g.type(e) == "MINION" then
        local c = g.cost(e)
        if not low or c < low then
          best, low = { e }, c
        elseif c == low then
          best[#best + 1] = e
        end
      end
    end
    local e = g.pick(best)
    if e then
      g.draw_entity(p, e)
    end
  end,
}

-- Scaleworm: if you're holding a Dragon (Nightmare Amalgam too), +1 Attack and Rush (GIL_601e).
cards.GIL_601 = {
  glow = function(g, me)
    return holding(g, me, "DRAGON")
  end,
  battlecry = function(g, me)
    if holding(g, me, "DRAGON") then
      g.buff(me, 1, 0)
      g.give_tag(me, "RUSH")
    end
  end,
}

return cards
