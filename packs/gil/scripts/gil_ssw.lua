-- The Witchwood (April 2018): the Shaman, Warlock and Warrior cards as at the release (build 23966 of patch 11.0.0.23966;
-- hearthstone.wiki.gg and its card notes; docs/packs/api.md). Echo, Rush and the counts (hurt this turn, the Battlecries
-- played) are gil.lua's player hooks.
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

-- --- this file's helpers ------------------------------------------------------------------------------------------------

-- The game is over (a champion died).
local function over(g)
  return g.health(g.hero(0)) <= 0 or g.health(g.hero(1)) <= 0
end

local function shaman_spell(g)
  return random_card(g, function(i)
    return i.type == "SPELL" and of_class(i, "SHAMAN")
  end)
end

local function hurt_glow(g, me)
  return hurt_this_turn(g, g.ctrl(me))
end

-- --- Shaman --------------------------------------------------------------------------------------------------------------

-- Zap!: 2 damage to a minion (its Overload (1) is data).
cards.GIL_600 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
  end,
}

-- Blazing Invocation: Discover a Battlecry minion.
cards.GIL_836 = {
  spell = function(g, me)
    discover(g, me, minion_of(function(i)
      return has_kw(i, "BATTLECRY")
    end))
  end,
  on_choose = to_hand,
}

-- Witch's Apprentice: Taunt (data); Battlecry: a random Shaman spell to your hand.
cards.GIL_531 = {
  battlecry = function(g, me)
    g.add_to_hand(g.ctrl(me), shaman_spell(g))
  end,
}

-- Earthen Might: +2/+2 to a minion; an Elemental (Nightmare Amalgam too) also gives a random Elemental to your hand.
cards.GIL_586 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 2, 2)
    if g.race(t) == "ELEMENTAL" then
      g.add_to_hand(g.ctrl(me), random_card(g, minion_of(function(i)
        return i.race == "ELEMENTAL"
      end)))
    end
  end,
}

-- Murkspark Eel: if your deck has only even-Cost cards, 2 damage (the target is asked only then).
local function even_deck(g, me)
  return deck_only(g, g.ctrl(me), false)
end
cards.GIL_530 = {
  glow = even_deck,
  target = { base = "any", when = even_deck },
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, 2)
    end
  end,
}

-- Totem Cruncher: Taunt (data); destroy your Totems (Nightmare Amalgam too), +2/+2 for each.
cards.GIL_583 = {
  battlecry = function(g, me)
    local n = 0
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "TOTEM" and alive(g, m) then
        g.destroy(m)
        n = n + 1
      end
    end
    if n > 0 then
      g.buff(me, 2 * n, 2 * n)
    end
  end,
}

-- Bogshaper: whenever you cast a spell (before it resolves), draw a random minion of your deck.
cards.GIL_807 = on_mine("play", function(g, me, ev)
  if ev.kind == "spell" then
    local p = g.ctrl(me)
    local m = random_from_deck(g, p, function(e)
      return g.type(e) == "MINION"
    end)
    if m then
      g.draw_entity(p, m)
    end
  end
end)

-- Hagatha the Witch: a hero card (5 Armor and Bewitch: data); Battlecry: 3 damage to all minions.
cards.GIL_504 = {
  battlecry = function(g, me)
    damage_all_minions(g, me, 3)
  end,
}

-- Bewitch: a passive Hero Power (it can't be used): after you play a minion, a random Shaman spell to your hand.
cards.GIL_504h = {
  can_play = function()
    return false
  end,
  on = {
    after_summon = function(g, me, ev)
      if ev.played and g.mine(me, ev) then
        g.add_to_hand(g.ctrl(me), shaman_spell(g))
      end
    end,
  },
}

-- Shudderwock (wiki notes): the Battlecries of the cards you played this game (not Shudderwocks: the player hooks'
-- BATTLECRIES list), in random order, each as its own with random targets and choices (never itself), its conditions
-- read now; a death phase after each; it stops when Shudderwock is no longer alive in play or the game is over; 30 at
-- most (DOUBT: patch 11.1 set 20, the June 2018 hotfix "reverted back" to 30: 30 at the release).
cards.GIL_820 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local ids = {}
    for i = 1, g.count(p, "BATTLECRIES") do
      local id = g.count(p, "BATTLECRIES_" .. i)
      if id > 0 then
        ids[#ids + 1] = id
      end
    end
    g.shuffle(ids)
    for i, id in ipairs(ids) do
      if i > 30 or not alive(g, me) or over(g) then
        break
      end
      g.battlecry(me, g.card(id))
      g.resolve()
    end
  end,
}

-- --- Warlock -------------------------------------------------------------------------------------------------------------

-- Dark Possession: 2 damage to a friendly character, then Discover a Demon.
cards.GIL_543 = {
  target = "friendly_char",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
    discover(g, me, minion_of(function(i)
      return i.race == "DEMON"
    end))
  end,
  on_choose = to_hand,
}

-- Witchwood Imp: Stealth (data); Deathrattle: +2 Health to a random friendly minion.
cards.GIL_608 = {
  deathrattle = function(g, me)
    local m = g.random_alive(g.minions(g.ctrl(me)))
    if m then
      g.buff(m, 0, 2)
    end
  end,
}

-- Curse of Weakness: Echo (the player hooks); the enemy minions in play get -2 Attack until the start of your next turn.
cards.GIL_665 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, m in ipairs(g.minions(g.opponent(p))) do
      g.enchant(m, { atk = -2, hooks = "ench:gil_ssw_weakness", player = p })
    end
  end,
}
cards["ench:gil_ssw_weakness"] = {
  on = {
    turn_start = function(g, me, ev)
      if list.any(g.enchants(me, "ench:gil_ssw_weakness"), function(p)
        return p == ev.player
      end) then
        g.remove_enchant(me, "ench:gil_ssw_weakness", ev.player)
      end
    end,
  },
}

-- Duskbat: if your hero took damage this turn (Armor that took it all: no), two 1/1 Bats right of it.
cards.GIL_508 = {
  glow = hurt_glow,
  battlecry = function(g, me)
    if hurt_this_turn(g, g.ctrl(me)) then
      g.summon_right(me, "GIL_508t")
      g.summon_right(me, "GIL_508t")
    end
  end,
}

-- Ratcatcher: Rush (data); destroy another friendly minion and gain its Attack and Health (as they are now).
cards.GIL_515 = {
  target = { base = "friendly_minion", filter = other_friendly },
  battlecry = function(g, me, t)
    if t then
      local a, h = g.atk(t), g.health(t)
      g.destroy(t)
      g.buff(me, a, h)
    end
  end,
}

-- Blood Witch: at the start of your turn, 1 damage to your hero.
cards.GIL_693 = on_mine("turn_start", function(g, me)
  g.damage(me, g.hero(g.ctrl(me)), 1)
end)

-- Fiendish Circle: four 1/1 Imps.
cards.GIL_191 = {
  spell = function(g, me)
    for _ = 1, 4 do
      g.summon(g.ctrl(me), "GIL_191t")
    end
  end,
}

-- Deathweb Spider: if your hero took damage this turn, it gains Lifesteal.
cards.GIL_565 = {
  glow = hurt_glow,
  battlecry = function(g, me)
    if hurt_this_turn(g, g.ctrl(me)) then
      g.give_tag(me, "LIFESTEAL")
    end
  end,
}

-- Glinda Crowskin: the minions in your hand have Echo (the player hooks read her; this shows it on the cards).
cards.GIL_618 = {
  aura = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      if g.type(e) == "MINION" then
        g.aura_add(e, 0, 0, { ECHO = true })
      end
    end
  end,
}

-- Lord Godfrey (wiki notes): 2 damage to all other minions; while a round kills one, again (on even if he died), 14
-- rounds at most.
cards.GIL_825 = {
  battlecry = function(g, me)
    for _ = 1, 14 do
      local hit = list.filter(g.all_minions(), function(m)
        return m ~= me and alive(g, m)
      end)
      if #hit == 0 then
        break
      end
      for _, m in ipairs(hit) do
        g.damage(me, m, 2)
      end
      g.resolve()
      local died = list.any(hit, function(m)
        return not alive(g, m)
      end)
      if not died or over(g) then
        break
      end
    end
  end,
}

-- --- Warrior -------------------------------------------------------------------------------------------------------------

-- Town Crier: draw a random Rush minion of your deck.
cards.GIL_580 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local m = random_from_deck(g, p, function(e)
      return g.type(e) == "MINION" and g.has(e, "RUSH")
    end)
    if m then
      g.draw_entity(p, m)
    end
  end,
}

-- Redband Wasp: Rush (data); +3 Attack while damaged.
cards.GIL_155 = {
  aura = function(g, me)
    if g.dmg(me) > 0 then
      g.aura_add(me, 3, 0)
    end
  end,
}

-- Warpath: Echo (the player hooks); 1 damage to all minions.
cards.GIL_654 = {
  spell = function(g, me)
    damage_all_minions(g, me, g.spell_dmg(me, 1))
  end,
}

-- Woodcutter's Axe (the release text): Deathrattle: +2/+1 to a random friendly minion with Rush (none: nothing).
cards.GIL_653 = {
  deathrattle = function(g, me)
    local m = g.random_alive(list.filter(g.minions(g.ctrl(me)), function(x)
      return g.has(x, "RUSH")
    end))
    if m then
      g.buff(m, 2, 1)
    end
  end,
}

-- Militia Commander: Rush (data); +3 Attack this turn.
cards.GIL_803 = {
  battlecry = function(g, me)
    g.buff(me, 3, 0, true)
  end,
}

-- Darius Crowley (4/4 at the release): after it attacks and kills a minion (and lives), +2/+2.
cards.GIL_547 = {
  on = {
    after_attack = function(g, me, ev)
      local d = ev.defender
      if ev.attacker == me and d and d > 0 and g.is_minion(d) and not alive(g, d) and alive(g, me) then
        g.buff(me, 2, 2)
      end
    end,
  },
}

-- Festeroot Hulk: after a friendly minion attacks (itself too), +1 Attack.
cards.GIL_655 = {
  on = {
    after_attack = function(g, me, ev)
      local a = ev.attacker
      if a and a > 0 and g.is_minion(a) and g.ctrl(a) == g.ctrl(me) and alive(g, me) then
        g.buff(me, 1, 0)
      end
    end,
  },
}

-- Deadly Arsenal: a random weapon of your deck is revealed (it stays there); its Attack as damage to all minions (Spell
-- Damage counts: AFFECTED_BY_SPELL_POWER). No weapon: nothing.
cards.GIL_537 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local w = random_from_deck(g, p, function(e)
      return g.type(e) == "WEAPON"
    end)
    if w then
      g.log({ type = "reveal", player = p, card = g.card(w) }) -- (no entity: a deck card's would be hidden)
      damage_all_minions(g, me, g.spell_dmg(me, g.atk(w)))
    end
  end,
}

-- Blackhowl Gunspire: Can't attack (data); whenever it takes damage (each time, also the hit that kills it), 3 damage to
-- a random enemy.
cards.GIL_152 = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me and ev.amount > 0 then
        local t = g.random_alive(g.chars(g.enemy(me)))
        if t then
          g.damage(me, t, 3)
        end
      end
    end,
  },
}

return cards
