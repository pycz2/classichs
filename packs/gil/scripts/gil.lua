-- The Witchwood (April 2018): the cards as at the release (patch 11.0.0.23966 of 2018-04-10, two days before the release;
-- hearthstone.wiki.gg and its card notes; docs/packs/api.md). The older sets' cards are those packs' scripts, copied in by
-- the recipe; the ones that changed by then are here and in cards.patch.json (patch 10.2.0.23180 of 2018-02-06: Raza the
-- Chained's Hero Power costs (1); patch 11.0.0.23966: Deathstalker Rexxar's Beasts of the two newest sets).
--
-- This file: the helpers every gil file copies, Echo, Start of Game (Baku the Mooneater, Genn Greymane), the older cards
-- and the player hooks. The class and neutral cards are in gil_*.lua.
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

-- --- the older cards of patches 10.2 and 11.0 --------------------------------------------------------------------------

-- Raza the Chained (patch 10.2.0.23180 of 2018-02-06): "If your deck has no duplicates, your Hero Power costs (1) this
-- game" (a new one too).
local function no_duplicates(g, p)
  local seen = {}
  for _, e in ipairs(g.deck(p)) do
    local c = g.card(e)
    if seen[c] then
      return false
    end
    seen[c] = true
  end
  return true
end
cards.CFM_020 = {
  glow = function(g, me)
    return no_duplicates(g, g.ctrl(me))
  end,
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if no_duplicates(g, p) then
      g.add_cost_mod(p, { kind = "power", set = 1, lasting = true })
    end
  end,
}

-- Stand Against Darkness (patch 11.0.0.23966: "can no longer be cast with a full board"): five 1/1 Recruits.
cards.OG_273 = {
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
  spell = function(g, me)
    for _ = 1, 5 do
      g.summon(g.ctrl(me), "VAN_CS2_101t")
    end
  end,
}

-- Deathstalker Rexxar's Build-A-Beast (patch 11.0.0.23966): the Beasts of Kobolds & Catacombs and The Witchwood too
-- (tools/zombeast_pools.py packs/gil writes the lists); a Zombeast made of an Echo or a Rush Beast has it.
-- @@ZOMBEAST_POOLS@@
local ZOMBEAST_FIRST = { "AT_058", "AT_063t", "AT_090", "AT_108", "BRM_014", "CFM_095", "CFM_315", "CFM_316",
  "CFM_333", "CFM_335", "FP1_002", "FP1_011", "GIL_601", "GIL_622", "GIL_624", "ICC_021", "ICC_243", "ICC_854",
  "KAR_005", "KAR_030a", "LOE_020", "LOE_029", "LOE_046", "LOE_047", "LOOT_078", "LOOT_193", "LOOT_413", "OG_034",
  "OG_179", "OG_216", "OG_309", "UNG_001", "UNG_009", "UNG_075", "UNG_082", "UNG_085", "UNG_087", "UNG_089",
  "UNG_801", "UNG_803", "UNG_807", "UNG_912", "UNG_914", "UNG_915", "VAN_CS2_203", "VAN_CS2_237", "VAN_DS1_175",
  "VAN_DS1_178", "VAN_EX1_009", "VAN_EX1_014", "VAN_EX1_162", "VAN_EX1_531", "VAN_NEW1_016", "VAN_NEW1_017",
  "VAN_NEW1_041" }
local ZOMBEAST_SECOND = { "GIL_143", "GIL_558", "GIL_562", "GIL_607t", "GVG_071", "ICC_023", "ICC_419", "ICC_905",
  "LOOT_125", "LOOT_258", "OG_325", "OG_326", "UNG_808", "UNG_810", "UNG_814", "VAN_CS2_119", "VAN_CS2_120",
  "VAN_CS2_125", "VAN_CS2_127", "VAN_CS2_169", "VAN_CS2_171", "VAN_CS2_172", "VAN_EX1_017", "VAN_EX1_028",
  "VAN_EX1_170" }
-- @@END@@
local KEYWORD_TAGS = { "TAUNT", "CHARGE", "DIVINE_SHIELD", "WINDFURY", "STEALTH", "POISONOUS", "ELUSIVE", "LIFESTEAL", "RUSH",
  "ECHO" }

local function zombeast(g, me, a, b)
  local p = g.ctrl(me)
  local z = g.add_to_hand(p, "ICC_828t")
  if not z then
    return
  end
  local ia, ib = g.info(g.card(a)), g.info(g.card(b))
  g.enchant(z, { set_atk = ia.attack + ib.attack, set_hp = ia.health + ib.health, base = true })
  g.enchant(z, { cost = ia.cost + ib.cost })
  for _, i in ipairs({ ia, ib }) do
    for _, k in ipairs(KEYWORD_TAGS) do
      if has_kw(i, k) then
        g.give_tag(z, k)
      end
    end
  end
  g.set_hooks(z, ia.id)
  g.set_tag(z, "ZOMBEAST_A", a)
  g.set_tag(z, "ZOMBEAST_B", b)
end

cards.ICC_828p = {
  can_play = function(g, me)
    return #g.hand(g.ctrl(me)) < g.rule("hand")
  end,
  hero_power = function(g, me)
    g.set_tag(me, "ZOMBEAST_A", nil)
    offer_cards(g, me, ZOMBEAST_FIRST)
  end,
  on_choose = function(g, me, option)
    if g.tag(me, "ZOMBEAST_A") == 0 then
      g.set_tag(me, "ZOMBEAST_A", option)
      offer_cards(g, me, ZOMBEAST_SECOND)
      return
    end
    local a = g.tag(me, "ZOMBEAST_A")
    g.set_tag(me, "ZOMBEAST_A", nil)
    zombeast(g, me, a, option)
  end,
}

-- --- the game's counts and its start (rules.json player_hooks) -------------------------------------------------------
-- Kobolds & Catacombs' (and the packs' before it: loot.lua), and The Witchwood's: Echo (ECHOING, the copies, GHOSTLY),
-- the last turn p's champion took damage (HURT_TURN: Duskbat, Deathweb Spider), the Battlecries p played this game
-- (BATTLECRIES and BATTLECRIES_<n>: the entity played; Shudderwock), the cards of another class p played this game
-- (OTHER_CARDS and OTHER_CARDS_<n>: the entity played; Tess Greymane) and Start of Game.

local LANATHEL = "ICC_841"
local function lanathel(g, e)
  if g.card(e) ~= LANATHEL or g.silenced(e) then
    return
  end
  local n = g.count(g.ctrl(e), "DISCARDS") - g.tag(e, "LANATHEL")
  if n > 0 then
    g.buff(e, n, 0)
    g.add_tag(e, "LANATHEL", n)
  end
end

local MALCHEZAAR = "KAR_096"
local PATCHES = "CFM_637"
local SHUDDERWOCK = "GIL_820"

local function malchezaar(g, p)
  local hero_class = g.class(g.hero(p))
  local n = 0
  for _, zone in ipairs({ g.deck(p), g.hand(p) }) do
    n = n + #list.filter(zone, function(e)
      return g.card(e) == MALCHEZAAR
    end)
  end
  for _ = 1, 5 * n do
    local have = {}
    for _, zone in ipairs({ g.deck(p), g.hand(p) }) do
      for _, e in ipairs(zone) do
        have[g.card(e)] = true
      end
    end
    local c = g.pick(pool(g, function(i)
      return i.type == "MINION" and i.rarity == "LEGENDARY" and (of_class(i, hero_class) or is_neutral(i))
        and not have[i.id]
    end))
    if c then
      g.add_to_deck(p, c)
    end
  end
end

-- A card of a class other than its player's (a neutral card is of none; a tri-class card of its classes).
local function other_class(g, e, p)
  local i = info(g, e)
  if is_neutral(i) then
    return false
  end
  return not of_class(i, g.class(g.hero(p)))
end

local function core(g, m)
  if not g.has(m, "CORED") then
    g.enchant(m, { set_atk = 5, set_hp = 5, base = true })
    g.set_tag(m, "CORED", true)
  end
end

-- Unidentified items of the opening hand (loot.lua's): identified after the mulligan.
local UNIDENTIFIED = {
  LOOT_278 = { "LOOT_278t1", "LOOT_278t2", "LOOT_278t3", "LOOT_278t4" },
  LOOT_286 = { "LOOT_286t1", "LOOT_286t2", "LOOT_286t3", "LOOT_286t4" },
  LOOT_285 = { "LOOT_285t", "LOOT_285t2", "LOOT_285t3", "LOOT_285t4" },
}
local function identify(g, e)
  local v = UNIDENTIFIED[g.card(e)]
  if v and g.zone(e) == "HAND" then
    self_transform(g, e, g.pick(v))
  end
end

local function murmur_used(g, p, e)
  local h = g.hero(p)
  if g.tag(h, "MURMUR") > 0 and g.tag(h, "MURMUR") ~= e and has_kw(info(g, e), "BATTLECRY") then
    g.erase_tag(h, "DOUBLE_BATTLECRY")
    g.set_tag(h, "MURMUR", nil)
  end
end

-- Remembers the entity e as the next of p's list `name` (NAME, NAME_<n>).
local function remember(g, p, name, e)
  local n = g.add_count(p, name)
  g.add_count(p, name .. "_" .. n, e)
end

cards["player:gil"] = {
  on = {
    after_spell = function(g, me, ev)
      if g.mine(me, ev) then
        g.add_count(g.ctrl(me), "SPELLS")
        echo_copy(g, g.ctrl(me), ev.entity)
      end
    end,
    summon = function(g, me, ev)
      if g.mine(me, ev) then
        local p = g.ctrl(me)
        lanathel(g, ev.entity)
        if g.race(ev.entity) == "TOTEM" then
          g.add_count(p, "TOTEMS")
        end
        if g.count(p, "CRYSTAL_CORE") > 0 and g.is_minion(ev.entity) then
          core(g, ev.entity)
        end
      end
    end,
    death = function(g, me, ev)
      if ev.minion and g.mine(me, ev) then
        g.set_tag(ev.entity, "DIED_ORDER", g.add_count(g.ctrl(me), "DEATHS"))
      end
      if not ev.minion and g.mine(me, ev) and g.is_weapon(ev.entity) then
        g.set_tag(ev.entity, "WEAPON_DESTROYED", true)
      end
    end,
    damage = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.target == g.hero(p) and ev.amount > 0 then
        g.add_count(p, "HURT_TURN", g.turn() - g.count(p, "HURT_TURN"))
      end
    end,
    play = function(g, me, ev)
      if not g.mine(me, ev) then
        return
      end
      local p = g.ctrl(me)
      if echo_card(g, ev.entity, p) then
        g.set_tag(ev.entity, "ECHOING", true)
      end
      if (ev.kind == "minion" or ev.kind == "champion") and has_kw(info(g, ev.entity), "BATTLECRY")
          and ev.card ~= SHUDDERWOCK then
        remember(g, p, "BATTLECRIES", ev.entity)
      end
      if ev.kind == "spell" and ev.secret then
        g.add_count(p, "SECRETS")
      end
      if ev.kind == "spell" then
        g.add_count(p, "TURN_SPELLS")
        if g.tag(ev.entity, "PLAYED_COST") >= 5 then
          g.add_count(p, "BIG_SPELLS")
          g.add_count(p, "BIG_SPELL_TURN", g.turn() - g.count(p, "BIG_SPELL_TURN"))
        end
        if ev.target and ev.target > 0 and g.is_minion(ev.target) and g.ctrl(ev.target) == p then
          g.set_tag(ev.entity, "ON_OWN_MINION", true)
        end
      end
      if ev.kind == "minion" and g.race(ev.entity) == "ELEMENTAL" then
        g.add_count(p, "ELEM_NOW")
      end
      if other_class(g, ev.entity, p) then
        g.add_count(p, "OTHER_CLASS")
        remember(g, p, "OTHER_CARDS", ev.entity)
      end
      local lock = g.info(ev.card).mana_lock
      if lock > 0 then
        g.add_count(p, "OVERLOADED", lock)
      end
    end,
    discard = function(g, me, ev)
      if g.mine(me, ev) then
        local p = g.ctrl(me)
        g.set_tag(ev.entity, "DISCARDED", true)
        g.add_count(p, "DISCARDS")
        for _, zone in ipairs({ g.hand(p), g.deck(p), g.minions(p) }) do
          for _, e in ipairs(zone) do
            lanathel(g, e)
          end
        end
      end
    end,
    heal = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.target == g.hero(p) and ev.amount > 0 then
        g.add_count(p, "HEALED_TURN", g.turn() - g.count(p, "HEALED_TURN"))
      end
    end,
    draw = function(g, me, ev)
      if g.mine(me, ev) then
        lanathel(g, ev.entity)
      end
      if g.mine(me, ev) and g.count(g.ctrl(me), "CRYSTAL_CORE") > 0 and g.is_minion(ev.entity) then
        core(g, ev.entity)
      end
    end,
    add_to_hand = function(g, me, ev)
      if g.mine(me, ev) then
        lanathel(g, ev.entity)
      end
      if g.mine(me, ev) and g.count(g.ctrl(me), "CRYSTAL_CORE") > 0 and g.is_minion(ev.entity) then
        core(g, ev.entity)
      end
    end,
    transform = function(g, me, ev)
      local e = ev.to or ev.entity
      local p = g.ctrl(me)
      if e and e > 0 and g.ctrl(e) == p then
        lanathel(g, e)
      end
      if e and e > 0 and g.ctrl(e) == p and g.count(p, "CRYSTAL_CORE") > 0 and g.is_minion(e) and g.zone(e) ~= "DECK" then
        core(g, e)
      end
    end,
    take_control = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.player == p and g.count(p, "CRYSTAL_CORE") > 0 and g.is_minion(ev.target) and g.zone(ev.target) == "PLAY" then
        core(g, ev.target)
      end
    end,
    turn_start = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.player == p then
        g.add_count(p, "ELEM_LAST", g.count(p, "ELEM_NOW") - g.count(p, "ELEM_LAST"))
        g.add_count(p, "ELEM_NOW", -g.count(p, "ELEM_NOW"))
        g.add_count(p, "TURN_SPELLS", -g.count(p, "TURN_SPELLS"))
      end
      -- Temporus (loot_ppr.lua): the extra turns its player owes, one at a turn start after the other player's turn
      if g.count(p, "TEMPORUS") > 0 then
        local last = g.count(p, "TEMPORUS_LAST") - 1
        g.add_count(p, "TEMPORUS_LAST", ev.player - last)
        if last ~= ev.player then
          g.extra_turn(ev.player)
          g.add_count(p, "TEMPORUS", -1)
        end
      end
    end,
    turn_end = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.player == p then
        echo_fade(g, p) -- the Echo copies left in the hand go
      end
      g.set_tag(g.hero(p), "MURMUR", nil) -- (DOUBLE_BATTLECRY was given for this turn only)
      local n = g.count(p, "DREADSTEEDS")
      if n <= 0 then
        return
      end
      g.add_count(p, "DREADSTEEDS", -n)
      local times = g.tag(g.hero(p), "EXTRA_END_TURN_EFFECT") > 0 and 2 or 1
      for _ = 1, n * times do
        g.summon(p, "AT_019")
      end
    end,
    equip = function(g, me, ev)
      if g.mine(me, ev) then
        murmur_used(g, g.ctrl(me), ev.entity)
      end
    end,
    after_summon = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.played and g.mine(me, ev) then
        murmur_used(g, p, ev.entity)
        echo_copy(g, p, ev.entity)
      end
      if ev.played and g.mine(me, ev) and g.race(ev.entity) == "PIRATE" and g.room(p) > 0 then
        local e = list.filter(g.deck(p), function(d)
          return g.card(d) == PATCHES
        end)[1]
        if e then
          g.summon_entity(e)
        end
      end
    end,
    game_start = function(g, me)
      local p = g.ctrl(me)
      for _, zone in ipairs({ g.deck(p), g.hand(p) }) do
        for _, e in ipairs(zone) do
          g.set_tag(e, "STARTED_IN_DECK", true)
        end
      end
      start_of_game(g, p)
      malchezaar(g, p)
      for _, e in ipairs(g.hand(p)) do
        identify(g, e)
      end
    end,
  },
}

return cards
