-- Kobolds & Catacombs (December 2017): the Druid, Hunter and Mage cards (the Spellstones are in loot.lua) as at the
-- release (patch 10.0.0.22611 of 2017-12-06; hearthstone.wiki.gg and its card notes; docs/packs/api.md).
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

-- --- this file's helpers -----------------------------------------------------------------------------------------------

local function no_minions_in_deck(g, p)
  return not list.any(g.deck(p), function(e)
    return g.type(e) == "MINION"
  end)
end

local function cost_4_or_less(g)
  return function(e)
    return g.cost(e) <= 4
  end
end

-- A card shown to both players (Seeping Oozeling's minion, Dragon's Fury's spell); it stays where it is.
local function reveal(g, p, e)
  g.log({ type = "reveal", player = p, card = g.card(e) }) -- (no entity: a card in a deck stays hidden by it)
end

-- --- Druid ---------------------------------------------------------------------------------------------------------------

-- Barkskin: a minion +3 Health; 3 Armor.
cards.LOOT_047 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 0, 3)
    g.gain_armor(g.ctrl(me), 3)
  end,
}

-- Ironwood Golem: Taunt; can only attack while its player has 3 Armor or more.
cards.LOOT_048 = {
  aura = function(g, me)
    if g.tag(g.hero(g.ctrl(me)), "ARMOR") < 3 then
      g.aura_add(me, 0, 0, { CANT_ATTACK = true })
    end
  end,
}

-- Branching Paths: Choose Twice (wiki: not Choose One, so not Fandral Staghelm; the same path may be taken twice): draw
-- a card; your minions +1 Attack; 6 Armor. The three paths are cards of their own too.
local PATHS = {
  LOOT_054d = function(g, p)
    g.draw(p)
  end,
  LOOT_054b = function(g, p)
    for _, m in ipairs(g.minions(p)) do
      g.buff(m, 1, 0)
    end
  end,
  LOOT_054c = function(g, p)
    g.gain_armor(p, 6)
  end,
}
local function path(id)
  return {
    spell = function(g, me)
      PATHS[id](g, g.ctrl(me))
    end,
  }
end
cards.LOOT_054 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 2 do
      g.request_choice(me, { g.create(p, "LOOT_054d"), g.create(p, "LOOT_054b"), g.create(p, "LOOT_054c") })
    end
  end,
  on_choose = function(g, me, option)
    PATHS[g.card(option)](g, g.ctrl(me))
  end,
}
cards.LOOT_054b = path("LOOT_054b")
cards.LOOT_054c = path("LOOT_054c")
cards.LOOT_054d = path("LOOT_054d")

-- Astral Tiger: Deathrattle: a copy of this minion (a new card) shuffled into your deck.
cards.LOOT_056 = {
  deathrattle = function(g, me)
    g.add_to_deck(g.ctrl(me), g.card(me))
  end,
}

-- Oaken Summons: 6 Armor; Recruit a minion that costs (4) or less.
cards.LOOT_309 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.gain_armor(p, 6)
    recruit(g, p, cost_4_or_less(g))
  end,
}

-- Grizzled Guardian: Taunt; Deathrattle: Recruit 2 minions that cost (4) or less (two pulls).
cards.LOOT_314 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 2 do
      recruit(g, p, cost_4_or_less(g))
    end
  end,
}

-- Ixlid, Fungal Lord: after you play a minion (from the hand), summon a copy of it (right of it; no Battlecry).
cards.LOOT_329 = on_mine("after_summon", function(g, me, ev)
  if ev.played and ev.entity ~= me and g.zone(ev.entity) == "PLAY" then
    summon_copies(g, ev.entity, 1)
  end
end)

-- Greedy Sprite: Deathrattle: an empty Mana Crystal.
cards.LOOT_351 = {
  deathrattle = function(g, me)
    g.gain_mana(g.ctrl(me), 1, true)
  end,
}

-- Twig of the World Tree: Deathrattle: "Gain 10 Mana Crystals": 10 full Mana Crystals (later worded "Refresh your Mana
-- Crystals").
cards.LOOT_392 = {
  deathrattle = function(g, me)
    local n = g.rule("max_mana")
    g.set_mana(g.ctrl(me), n, n)
  end,
}

-- --- Hunter --------------------------------------------------------------------------------------------------------------

-- Flanking Strike: 3 damage to a minion; a 3/3 Wolf (wiki: before the deaths, so none on a full board; no target: nothing).
cards.LOOT_077 = {
  target = "minion",
  spell = function(g, me, t)
    if t then
      g.damage(me, t, g.spell_dmg(me, 3))
      g.summon(g.ctrl(me), "LOOT_077t")
    end
  end,
}

-- Cave Hydra: also damages the minions next to whomever it attacks (as Foe Reaper 4000).
cards.LOOT_078 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == me and g.is_minion(ev.defender) then
        local n = g.atk(me)
        for _, m in ipairs(g.adjacent(ev.defender)) do
          g.damage(me, m, n)
        end
      end
    end,
  },
}

-- Wandering Monster: when an enemy attacks your hero, a random 3-Cost minion is summoned and attacked instead (as Noble
-- Sacrifice; not on a full board).
cards.LOOT_079 = {
  secret = {
    event = "attack",
    cond = function(g, me, ev)
      local p = g.ctrl(me)
      return not g.mine(me, ev) and ev.defender == g.hero(p) and g.room(p) > 0
    end,
    effect = function(g, me, ev)
      local c = random_card(g, minion_of(function(i)
        return i.cost == 3
      end))
      local n = c and g.summon(g.ctrl(me), c)
      if n then
        ev.defender = n
      end
    end,
  },
}

-- Rhok'delar: Battlecry: if your deck has no minions, fill your hand with random Hunter spells.
cards.LOOT_085 = {
  glow = function(g, me)
    return no_minions_in_deck(g, g.ctrl(me))
  end,
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if not no_minions_in_deck(g, p) then
      return
    end
    local spells = pool(g, function(i)
      return i.type == "SPELL" and of_class(i, "HUNTER")
    end)
    while #g.hand(p) < g.rule("hand") do
      local c = g.pick(spells)
      if not c or not g.add_to_hand(p, c) then
        break
      end
    end
  end,
}

-- To My Side!: an Animal Companion, or two different ones if your deck has no minions (needs room for one).
local COMPANIONS = { "VAN_NEW1_032", "VAN_NEW1_033", "VAN_NEW1_034" }
cards.LOOT_217 = {
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
  glow = function(g, me)
    return no_minions_in_deck(g, g.ctrl(me))
  end,
  glow = function(g, me)
    return no_minions_in_deck(g, g.ctrl(me))
  end,
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, c in ipairs(pick_n(g, COMPANIONS, no_minions_in_deck(g, p) and 2 or 1)) do
      g.summon(p, c)
    end
  end,
}

-- Candleshot: its hero is Immune while attacking.
cards.LOOT_222 = { immune_while_attacking = true }

-- Kathrena Winterwisp: Battlecry and Deathrattle: Recruit a Beast.
local function recruit_beast(g, me)
  recruit(g, g.ctrl(me), function(e)
    return g.race(e) == "BEAST"
  end)
end
cards.LOOT_511 = { battlecry = recruit_beast, deathrattle = recruit_beast }

-- Seeping Oozeling: Battlecry: the Deathrattle of a random minion of your deck (wiki: revealed to both players).
cards.LOOT_520 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local e = random_from_deck(g, p, function(d)
      return g.type(d) == "MINION" and has_kw(info(g, d), "DEATHRATTLE")
    end)
    if e then
      reveal(g, p, e)
      g.enchant(me, { deathrattle = g.card(e) })
    end
  end,
}

-- Crushing Walls: destroy the enemy's left- and right-most minions (wiki: a Permanent one is not counted).
cards.LOOT_522 = {
  spell = function(g, me)
    local ms = list.filter(enemy_minions(g, me), function(m)
      return not g.has(m, "UNTOUCHABLE")
    end)
    if #ms > 0 then
      g.destroy(ms[1])
      g.destroy(ms[#ms])
    end
  end,
}

-- --- Mage ----------------------------------------------------------------------------------------------------------------

-- Explosive Runes: after your opponent plays a minion, 6 damage to it (ImmuneToSpellpower: no Spell Damage) and the
-- excess over its Health to their hero (wiki: Divine Shield takes the whole hit, nothing goes over).
cards.LOOT_101 = {
  secret = {
    event = "after_summon",
    cond = function(g, me, ev)
      return ev.played and not g.mine(me, ev) and g.zone(ev.entity) == "PLAY"
    end,
    effect = function(g, me, ev)
      local m = ev.entity
      local hp = g.health(m)
      local shield = g.has(m, "DIVINE_SHIELD")
      g.damage(me, m, 6)
      if not shield and hp < 6 then
        g.damage(me, g.hero(g.ctrl(m)), 6 - hp)
      end
    end,
  },
}

-- Shifting Scroll: at the start of each of its player's turns in the hand (as Shifter Zerus), it becomes a random Mage
-- spell that keeps shifting; it can't be played as itself (nor cast at random). A card that transforms itself: Leyline
-- Manipulator still sees it as started in the deck.
local function shift_scroll(g, me, ev)
  if g.mine(me, ev) then
    local c = random_card(g, function(i)
      return i.type == "SPELL" and of_class(i, "MAGE")
    end)
    local n = c and self_transform(g, me, c)
    if n then
      g.enchant(n, { hooks = "ench:loot_dhm_scroll" })
    end
  end
end
cards.LOOT_104 = {
  can_play = function()
    return false
  end,
  hand = { turn_start = shift_scroll },
}
cards["ench:loot_dhm_scroll"] = { hand = { turn_start = shift_scroll } }

-- Deck of Wonders: 5 Scrolls of Wonder shuffled into your deck.
cards.LOOT_106 = {
  spell = function(g, me)
    for _ = 1, 5 do
      g.add_to_deck(g.ctrl(me), "LOOT_106t")
    end
  end,
}

-- Scroll of Wonder: cast a random spell (random targets); draw a card. Cast this when drawn.
cards.LOOT_106t = cast_when_drawn(function(g, me)
  local c = random_card(g, function(i)
    return i.type == "SPELL"
  end)
  if c then
    g.cast_random(me, c)
  end
  g.draw(g.ctrl(me))
end)

-- Aluneth: at the end of your turn, draw 3 cards.
cards.LOOT_108 = end_of_my_turn(function(g, me)
  g.draw(g.ctrl(me), 3)
end)

-- Raven Familiar: Battlecry: a Joust of spells (wiki): a random spell of each deck; yours wins if its base Cost is higher
-- (a tie loses; none in yours: lost, nothing shown; none in theirs: won); on a win you draw it.
cards.LOOT_170 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local function is_spell(e)
      return g.type(e) == "SPELL"
    end
    local mine = random_from_deck(g, p, is_spell)
    local theirs = mine and random_from_deck(g, g.opponent(p), is_spell)
    local won = mine ~= nil and (theirs == nil or info(g, mine).cost > info(g, theirs).cost)
    g.log({ type = "joust", player = p, card = mine and g.card(mine) or "", foe_card = theirs and g.card(theirs) or "",
      won = won })
    if won then
      g.draw_entity(p, mine)
    end
  end,
}

-- Dragon's Fury: a random spell of your deck is revealed (it stays there); damage equal to its Cost to all minions (the
-- build's text has no $: no Spell Damage; Shifting Scroll is 0).
cards.LOOT_172 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local s = random_from_deck(g, p, function(e)
      return g.type(e) == "SPELL"
    end)
    if s then
      reveal(g, p, s)
      local n = g.cost(s)
      if n > 0 then
        damage_all_minions(g, me, n)
      end
    end
  end,
}

-- Arcane Artificer: whenever you cast a spell, Armor equal to the Cost you paid for it.
cards.LOOT_231 = on_mine("play", function(g, me, ev)
  if ev.kind == "spell" then
    local n = g.tag(ev.entity, "PLAYED_COST")
    if n > 0 then
      g.gain_armor(g.ctrl(me), n)
    end
  end
end)

-- Dragoncaller Alanna: Battlecry: a 5/5 Fire Dragon for each spell of Cost 5 or more you cast this game (the Cost paid;
-- the player hooks' BIG_SPELLS).
cards.LOOT_535 = {
  battlecry = function(g, me)
    for _ = 1, g.count(g.ctrl(me), "BIG_SPELLS") do
      if not g.summon_right(me, "LOOT_535t") then
        break
      end
    end
  end,
}

-- Leyline Manipulator: Battlecry: the cards in your hand that didn't start in your deck cost (2) less.
local function not_from_deck(g, me)
  return list.filter(g.hand(g.ctrl(me)), function(e)
    return e ~= me and not g.has(e, "STARTED_IN_DECK")
  end)
end
cards.LOOT_537 = {
  glow = function(g, me)
    return #not_from_deck(g, me) > 0
  end,
  battlecry = function(g, me)
    for _, e in ipairs(not_from_deck(g, me)) do
      g.enchant(e, { cost = -2 })
    end
  end,
}

return cards
