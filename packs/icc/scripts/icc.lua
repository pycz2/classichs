-- Knights of the Frozen Throne (August 2017): the 135 cards and their tokens as at the release (patch 9.0.0.20457 of
-- 2017-08-08, two days before the release; hearthstone.wiki.gg and its card notes; docs/packs/api.md). The older sets'
-- cards are those packs' scripts, copied in by the recipe; the ones that changed by then are here and in cards.patch.json
-- (patch 8.4.0 of July 2017: The Caverns Below five minions, the Elemental tribe of Jade Spirit and others; patch 9.0:
-- Dreadsteed at the end of the turn, Mistress of Pain and Wickerflame's Lifesteal, Naga Sea Witch and Emerald Hive
-- Queen's cost change before the others, a new hero keeps its weapon swing; a random or Discovered card of a class may
-- be a hero card).
--
-- New here: hero cards (a CHAMPION played from the hand: the engine keeps the Health, adds the Armor and gives the new
-- Hero Power; the scripts are their Battlecries and powers), Lifesteal (LIFESTEAL: the engine), the Zombeast
-- (g.set_hooks: its first Beast's text), Drakkari Enchanter (EXTRA_END_TURN_EFFECT: the engine runs its owner's end of
-- turn hooks twice), Defile, Spreading Plague and Roll the Bones casting again, Fatespinner's secret choice (g.choice).
local cards = {}

-- --- helpers -----------------------------------------------------------------------------------

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local COIN = "GAME_005"
local GHOUL = "ICC_900t"
local SKELETON = "ICC_026t"
local DK_CARDS = { "ICC_314t1", "ICC_314t2", "ICC_314t3", "ICC_314t4", "ICC_314t5", "ICC_314t6", "ICC_314t7", "ICC_314t8" }

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

-- --- the older cards of patches 8.4 and 9.0 -------------------------------------------------------------------

-- Dreadsteed (patch 9.0.0.20457): "Deathrattle: At the end of the turn, summon a Dreadsteed." The dead one counts on
-- its player (DREADSTEEDS); the player hooks summon them at the turn's end (Drakkari Enchanter: its player's twice).
cards.AT_019 = {
  deathrattle = function(g, me)
    g.add_count(g.ctrl(me), "DREADSTEEDS")
  end,
}

-- The Caverns Below (patch 8.4.0.20022): play five minions with the same name.
local function quest_progress(g, me, n, reward)
  if n <= 0 or g.zone(me) ~= "SECRET" then
    return
  end
  local goal = g.tag(me, "QUEST_PROGRESS_TOTAL")
  local v = math.min(g.tag(me, "QUEST_PROGRESS") + n, goal)
  g.set_tag(me, "QUEST_PROGRESS", v)
  if v >= goal then
    local p = g.ctrl(me)
    g.remove(me, "GRAVEYARD")
    g.log({ type = "quest_done", player = p, entity = me, card = g.card(me) })
    g.add_to_hand(p, reward)
  end
end
cards.UNG_067 = {
  spell = function(g, me)
    g.set_tag(me, "QUEST_PROGRESS", 0)
    g.set_tag(me, "QUEST_PROGRESS_TOTAL", 5)
  end,
  on = {
    play = function(g, me, ev)
      if ev.kind == "minion" and g.mine(me, ev) then
        local key = "CAVERNS_" .. ev.card
        local n = g.tag(me, key) + 1
        g.set_tag(me, key, n)
        quest_progress(g, me, n - g.tag(me, "QUEST_PROGRESS"), "UNG_067t1")
      end
    end,
  },
}

-- Naga Sea Witch and Emerald Hive Queen (patch 9.0, undocumented: "applied before other mana cost modifiers"): the
-- group after Summoning Portal (cost_first 2; Corpse Widow too).
cards.LOE_038 = {
  cost_first = 2,
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.zone(card) == "HAND" then
      return 5
    end
    return cost
  end,
}
cards.UNG_085 = {
  cost_first = 2,
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.is_minion(card) and g.zone(card) == "HAND" then
      return cost + 2
    end
    return cost
  end,
}

-- A new champion keeps its weapon swing (patch 9.0: "Changing your Hero will no longer 'refresh' your weapon swing"):
-- Lord Jaraxxus and Majordomo Executus's Ragnaros keep the attacks made this turn.
local function keep_attacks(g, p, f)
  local n = g.tag(g.hero(p), "ATTACKS")
  f()
  g.set_tag(g.hero(p), "ATTACKS", n)
end
cards.VAN_EX1_323 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    g.remove(me, "SETASIDE")
    keep_attacks(g, p, function()
      g.replace_hero(p, "EX1_323h")
    end)
    g.equip(p, "EX1_323w")
    g.set_power(p, "VAN_EX1_tk33")
  end,
}
cards.BRM_027 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    keep_attacks(g, p, function()
      g.replace_hero(p, "BRM_027h")
    end)
    g.set_power(p, "BRM_027p")
  end,
}

-- Kalimos, Primal Lord (patch 9.0: "selecting the Invocation of Air ... while having Hallazeal the Ascended on your board
-- no longer heals your hero"): the Invocation is Kalimos's doing, not a spell's (its damage no spell damage).
local INVOCATION = {
  UNG_211a = function(g, me) -- Earth: fill your board with 1/1 Elementals
    local p = g.ctrl(me)
    while g.room(p) > 0 do
      if not g.summon(p, "UNG_211aa") then
        break
      end
    end
  end,
  UNG_211b = function(g, me) -- Water: 12 Health to your hero
    g.heal(me, g.hero(g.ctrl(me)), 12)
  end,
  UNG_211c = function(g, me) -- Fire: 6 damage to the enemy hero
    g.damage(me, g.hero(g.enemy(me)), 6)
  end,
  UNG_211d = function(g, me) -- Air: 3 damage to all enemy minions
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.damage(me, m, 3)
    end
  end,
}
cards.UNG_211 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if g.count(p, "ELEM_LAST") > 0 then
      local opts = {}
      for _, c in ipairs({ "UNG_211a", "UNG_211b", "UNG_211c", "UNG_211d" }) do
        opts[#opts + 1] = g.create(p, c)
      end
      g.request_choice(me, opts)
    end
  end,
  on_choose = function(g, me, option)
    INVOCATION[g.card(option)](g, me)
  end,
  glow = function(g, me)
    return g.count(g.ctrl(me), "ELEM_LAST") > 0
  end,
}

-- The older cards whose random or Discovered card of a class may now be a hero card (the older packs left the
-- champions out of their pools: none was collectible then).

-- Burgle: 2 random class cards of your opponent's class (against a hero without one: two Coins).
cards.AT_033 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local cls = g.class(g.hero(g.enemy(me)))
    for _ = 1, 2 do
      g.add_to_hand(p, (playable(cls) and random_class_card(g, cls)) or COIN)
    end
  end,
}

-- A random class card of the opponent's class (none if the opponent has no class).
local function enemy_class_card(g, me)
  local cls = g.class(g.hero(g.enemy(me)))
  local c = playable(cls) and random_class_card(g, cls)
  if c then
    g.add_to_hand(g.ctrl(me), c)
  end
end
cards.KAR_069 = { battlecry = enemy_class_card } -- Swashburglar
cards.OG_330 = { deathrattle = enemy_class_card } -- Undercity Huckster
cards.CFM_781 = { -- Shaku, the Collector: whenever it attacks
  on = {
    attack = function(g, me, ev)
      if ev.attacker == me then
        enemy_class_card(g, me)
      end
    end,
  },
}

-- Grand Crusader: a random Paladin card.
cards.AT_118 = {
  battlecry = function(g, me)
    local c = random_class_card(g, "PALADIN")
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Lock and Load: this turn, whenever you cast a spell, a random Hunter card.
cards.AT_061 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.enchant(g.hero(p), { hooks = "ench:lock_and_load_icc", player = p, eot = true })
  end,
}
cards["ench:lock_and_load_icc"] = {
  on = {
    play = function(g, me, ev)
      if ev.kind == "spell" and g.mine(me, ev) then
        local c = random_class_card(g, "HUNTER")
        if c then
          g.add_to_hand(g.ctrl(me), c)
        end
      end
    end,
  },
}

-- Renounce Darkness: your Hero Power and Warlock cards (tri-class ones of Warlock too) become another class's (its
-- cards cost (1) less).
local POWERS = { DRUID = "VAN_HERO_06bp", HUNTER = "VAN_HERO_05bp", MAGE = "VAN_HERO_08bp", PALADIN = "VAN_HERO_04bp",
  PRIEST = "VAN_HERO_09bp", ROGUE = "VAN_HERO_03bp", SHAMAN = "VAN_HERO_02bp", WARRIOR = "VAN_HERO_01bp" }
cards.OG_118 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local cls = g.pick(list.filter(CLASSES, function(c)
      return c ~= "WARLOCK"
    end))
    g.set_power(p, POWERS[cls])
    local cards_of = pool(g, function(i)
      return of_class(i, cls)
    end)
    for _, zone in ipairs({ g.hand(p), g.deck(p) }) do
      for _, e in ipairs(zone) do
        if of_class(g.info(g.card(e)), "WARLOCK") then
          local n = g.transform(e, g.pick(cards_of))
          if n then
            g.enchant(n, { cost = -1 })
          end
        end
      end
    end
  end,
}

-- Kabal Courier, Lotus Agents, Grimestreet Informant: Discover a card of one of three classes (one of each).
local function discover_three(classes)
  return {
    battlecry = function(g, me)
      local p = g.ctrl(me)
      local taken = {}
      local opts = {}
      for _, cls in ipairs(classes) do
        local c = g.pick(pool(g, function(i)
          return of_class(i, cls) and not taken[i.id]
        end))
        if c then
          taken[c] = true
          opts[#opts + 1] = g.create(p, c)
        end
      end
      if #opts > 0 then
        g.request_choice(me, opts)
      end
    end,
    on_choose = to_hand,
  }
end
cards.CFM_649 = discover_three({ "MAGE", "PRIEST", "WARLOCK" })
cards.CFM_852 = discover_three({ "DRUID", "ROGUE", "SHAMAN" })
cards.CFM_321 = discover_three({ "HUNTER", "PALADIN", "WARRIOR" })

-- Hallucination: Discover a card from your opponent's class.
cards.UNG_856 = {
  spell = function(g, me)
    local cls = g.class(g.hero(g.enemy(me)))
    if not playable(cls) then
      cls = "ROGUE"
    end
    local choices = {}
    for _, c in ipairs(g.collectible()) do
      local i = g.info(c)
      if of_class(i, cls) then
        choices[#choices + 1] = { c, 1 }
      end
    end
    offer(g, me, choices)
  end,
  on_choose = to_hand,
}

-- Choose Your Path (Explore Un'Goro's cards): Discover a card.
cards.UNG_922t1 = {
  spell = function(g, me)
    discover(g, me, function()
      return true
    end)
  end,
  on_choose = to_hand,
}

-- Curious Glimmerroot: look at 3 cards (one of the opponent's starting deck, two other cards of their class); guess the
-- one from their deck to get a copy of it. A played hero card (now their champion) started in the deck too.
local function started_in_deck(g, p)
  local out = {}
  local w = g.weapon(p)
  for _, zone in ipairs({ g.deck(p), g.hand(p), g.minions(p), g.traps(p), g.tasks(p), g.graveyard(p), { w },
    { g.hero(p) } }) do
    for _, e in ipairs(zone) do
      if g.has(e, "STARTED_IN_DECK") then
        out[#out + 1] = e
      end
    end
  end
  return out
end
cards.UNG_035 = {
  battlecry = function(g, me)
    local p, foe = g.ctrl(me), g.enemy(me)
    local start = {}
    local list_ = {}
    local cls = g.class(g.hero(foe))
    local started = started_in_deck(g, foe)
    local function kind(i)
      return of_class(i, cls)
    end
    if not list.any(started, function(e)
      return of_class(info(g, e), cls)
    end) then
      kind = is_neutral
    end
    for _, e in ipairs(started) do
      local c = g.card(e)
      start[c] = true
      if kind(info(g, e)) and g.info(c).collectible and not list.any(list_, function(x)
        return x == c
      end) then
        list_[#list_ + 1] = c
      end
    end
    local right = g.pick(list_)
    if not right then
      return
    end
    local wrong = pick_n(g, pool(g, function(i)
      return kind(i) and not start[i.id]
    end), 2)
    local opts = { right, wrong[1], wrong[2] }
    g.shuffle(opts)
    local ids = {}
    for _, c in ipairs(opts) do
      if c then
        local e = g.create(p, c)
        if c == right then
          g.set_tag(e, "GLIMMER_RIGHT", true)
        end
        ids[#ids + 1] = e
      end
    end
    g.request_choice(me, ids)
  end,
  on_choose = function(g, me, option)
    if g.has(option, "GLIMMER_RIGHT") then
      to_hand(g, me, option)
    end
  end,
}

-- --- Death Knight hero cards ----------------------------------------------------------------------------------------

-- Malfurion the Pestilent (Druid): Choose One - two 1/2 Poisonous Spiders; or two 1/5 Scarabs with Taunt (both with
-- Fandral Staghelm).
cards.ICC_832 = { choose_one = { "ICC_832b", "ICC_832a" } }
cards.ICC_832b = { -- Spider Plague
  effect = function(g, me)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), "ICC_832t3")
    end
  end,
}
cards.ICC_832a = { -- Scarab Plague
  effect = function(g, me)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), "ICC_832t4")
    end
  end,
}
-- Plague Lord: Choose One - +3 Attack this turn; or 3 Armor (both with Fandral Staghelm: "Choose One cards and
-- powers", patch 9.0). The options are offered as cards only its player sees.
local function plague(g, me, which)
  local p = g.ctrl(me)
  if which == "ICC_832pb" then
    g.buff(g.hero(p), 3, 0, true)
  else
    g.gain_armor(p, 3)
  end
end
cards.ICC_832p = {
  hero_power = function(g, me)
    local p = g.ctrl(me)
    if g.has(g.hero(p), "CHOOSE_BOTH") then
      plague(g, me, "ICC_832pb")
      plague(g, me, "ICC_832pa")
      return
    end
    g.request_choice(me, { g.create(p, "ICC_832pb"), g.create(p, "ICC_832pa") })
  end,
  on_choose = function(g, me, option)
    plague(g, me, g.card(option))
  end,
}
cards.ICC_832pa = { spell = function(g, me) plague(g, me, "ICC_832pa") end } -- Scarab Shell (only offered)
cards.ICC_832pb = { spell = function(g, me) plague(g, me, "ICC_832pb") end } -- Spider Fangs (only offered)

-- Deathstalker Rexxar (Hunter): Battlecry: 2 damage to every enemy minion (from no weapon: patch 10.0 fixed a weapon's
-- Poisonous and Lifesteal reaching it, a bug).
cards.ICC_828 = {
  battlecry = function(g, me)
    for _, m in ipairs(enemy_minions(g, me)) do
      g.damage(nil, m, 2)
    end
  end,
}

-- Build-A-Beast: two Discovers of Beasts of 5 Mana or less, the Hunter's and the neutral ones as likely (no class bonus):
-- first one with card text (ZOMBEAST_FIRST), then one with only keywords or no text (ZOMBEAST_SECOND; a Beast with
-- both is in neither); the Zombeast comes to the hand with both Beasts' Cost, Attack and Health summed (base stats:
-- Silence keeps them), the second's keywords and the first's text (g.set_hooks). Only its player sees it. The lists:
-- the collectible Hunter and neutral Beasts of the pack (tools/zombeast_pools.py writes them).
-- @@ZOMBEAST_POOLS@@
local ZOMBEAST_FIRST = { "AT_058", "AT_063t", "AT_090", "AT_108", "BRM_014", "CFM_095", "CFM_315", "CFM_316",
  "CFM_333", "CFM_335", "FP1_002", "FP1_011", "ICC_021", "ICC_243", "ICC_854", "KAR_005", "KAR_030a", "LOE_020",
  "LOE_029", "LOE_046", "LOE_047", "OG_034", "OG_179", "OG_216", "OG_309", "UNG_001", "UNG_009", "UNG_075", "UNG_082",
  "UNG_085", "UNG_087", "UNG_089", "UNG_801", "UNG_803", "UNG_807", "UNG_912", "UNG_914", "UNG_915", "VAN_CS2_203",
  "VAN_CS2_237", "VAN_DS1_175", "VAN_DS1_178", "VAN_EX1_009", "VAN_EX1_014", "VAN_EX1_162", "VAN_EX1_531",
  "VAN_NEW1_016", "VAN_NEW1_017", "VAN_NEW1_041" }
local ZOMBEAST_SECOND = { "GVG_071", "ICC_023", "ICC_419", "ICC_905", "OG_325", "OG_326", "UNG_808", "UNG_810",
  "UNG_814", "VAN_CS2_119", "VAN_CS2_120", "VAN_CS2_125", "VAN_CS2_127", "VAN_CS2_169", "VAN_CS2_171", "VAN_CS2_172",
  "VAN_EX1_017", "VAN_EX1_028", "VAN_EX1_170" }
-- @@END@@
local KEYWORD_TAGS = { "TAUNT", "CHARGE", "DIVINE_SHIELD", "WINDFURY", "STEALTH", "POISONOUS", "ELUSIVE", "LIFESTEAL" }

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
  g.set_tag(z, "ZOMBEAST_A", a) -- the two Beasts it is made of (its text: the offered cards' ids)
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
-- The Zombeast: its text is the two Beasts' texts ({0}, {1}: card ids the client words in the player's language).
cards.ICC_828t = {
  text = function(g, me)
    local a, b = g.tag(me, "ZOMBEAST_A"), g.tag(me, "ZOMBEAST_B")
    if a == 0 or b == 0 then
      return "", ""
    end
    return g.card(a), g.card(b)
  end,
}

-- Frost Lich Jaina (Mage): Battlecry: a 3/6 Water Elemental; your Elementals have Lifesteal this game (an aura of the
-- hero: Silence doesn't take it).
cards.ICC_833 = {
  battlecry = function(g, me)
    g.summon(g.ctrl(me), "ICC_833t")
  end,
  aura = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if g.race(m) == "ELEMENTAL" then
        g.aura_add(m, 0, 0, { LIFESTEAL = true })
      end
    end
  end,
}
-- Icy Touch: 1 damage; if it kills a minion, a Water Elemental.
cards.ICC_833h = {
  target = "any",
  hero_power = function(g, me, t)
    g.damage(me, t, g.hp_dmg(me, 1))
    if g.is_minion(t) and not alive(g, t) then
      g.summon(g.ctrl(me), "ICC_833t")
    end
  end,
}
-- Water Elemental (Jaina's): freeze any character it damages.
cards.ICC_833t = {
  on = {
    damage = function(g, me, ev)
      if ev.source == me then
        g.freeze(ev.target)
      end
    end,
  },
}

-- Uther of the Ebon Blade (Paladin): Battlecry: equip a 5/3 Lifesteal weapon.
cards.ICC_829 = {
  battlecry = function(g, me)
    g.equip(g.ctrl(me), "ICC_829t")
  end,
}
-- The Four Horsemen: a random Horseman you don't control; when you control all four, the enemy hero is destroyed (while
-- the power works: Mindbreaker's LOCKED stops it).
local HORSEMEN = { "ICC_829t2", "ICC_829t3", "ICC_829t4", "ICC_829t5" }
local function horsemen_win(g, me)
  if g.has(me, "LOCKED") or g.zone(me) ~= "PLAY" then
    return
  end
  local p = g.ctrl(me)
  for _, h in ipairs(HORSEMEN) do
    if not list.any(g.minions(p), function(m)
      return g.card(m) == h
    end) then
      return
    end
  end
  g.destroy(g.hero(g.enemy(me)))
end
cards.ICC_829p = {
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
  hero_power = function(g, me)
    local p = g.ctrl(me)
    local missing = list.filter(HORSEMEN, function(h)
      return not list.any(g.minions(p), function(m)
        return g.card(m) == h
      end)
    end)
    local h = g.pick(missing)
    if h then
      g.summon(p, h)
    end
    horsemen_win(g, me)
  end,
  on = {
    after_summon = function(g, me, ev)
      if g.mine(me, ev) then
        horsemen_win(g, me)
      end
    end,
  },
}

-- Shadowreaper Anduin (Priest): Battlecry: destroy all minions with 5 or more Attack.
cards.ICC_830 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if g.atk(m) >= 5 then
        g.destroy(m)
      end
    end
  end,
}
-- Voidform: 2 damage; after you play a card, it is ready again.
cards.ICC_830p = {
  target = "any",
  hero_power = function(g, me, t)
    g.damage(me, t, g.hp_dmg(me, 2))
  end,
  on = {
    play = function(g, me, ev)
      if g.mine(me, ev) then
        g.erase_tag(me, "USED")
      end
    end,
  },
}

-- Valeera the Hollow (Rogue): Battlecry: her hero has Stealth until your next turn.
cards.ICC_827 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local h = g.hero(p)
    g.give_tag(h, "STEALTH")
    g.enchant(h, { hooks = "ench:valeera_stealth", player = p })
    -- Death's Shadow gives its first Reflection at once (on the turn Valeera is played); not twice with Brann
    if g.card(g.power(p)) == "ICC_827p" and not g.has(g.power(p), "LOCKED") and not g.has(g.power(p), "REFLECTED") then
      g.set_tag(g.power(p), "REFLECTED", true)
      g.add_to_hand(p, "ICC_827t")
    end
  end,
}
cards["ench:valeera_stealth"] = {
  on = {
    turn_start = function(g, me, ev)
      local p = g.enchants(me, "ench:valeera_stealth")[1]
      if p ~= nil and ev.player == p then
        g.erase_tag(me, "STEALTH")
        g.remove_enchant(me, "ench:valeera_stealth")
      end
    end,
  },
}
-- Death's Shadow: passive; at the start of your turn (before the draw) a Shadow Reflection (not while Mindbreaker
-- disables Hero Powers).
cards.ICC_827p = {
  can_play = function()
    return false
  end,
  on = {
    turn_start = function(g, me, ev)
      if g.mine(me, ev) and not g.has(me, "LOCKED") then
        g.add_to_hand(g.ctrl(me), "ICC_827t")
      end
    end,
  },
}
-- Shadow Reflection: each time you play a card, it becomes a copy of it (the copy too: it goes on copying); it leaves
-- the hand at the end of your turn, and when Death's Shadow is no longer its player's power.
local function reflection_gone(g, me)
  g.remove(me, "SETASIDE")
end
local REFLECTION = {
  play = function(g, me, ev)
    local p = g.ctrl(me)
    if ev.player ~= p or ev.entity == me then
      return
    end
    if g.card(g.power(p)) ~= "ICC_827p" then
      reflection_gone(g, me)
      return
    end
    local n = g.transform(me, ev.card)
    if n then
      g.enchant(n, { hooks = "ench:reflection" })
    end
  end,
  turn_end = function(g, me, ev)
    if ev.player == g.ctrl(me) then
      reflection_gone(g, me)
    end
  end,
}
cards.ICC_827t = {
  hand = REFLECTION,
  can_play = function()
    return false -- only ever a copy of what you play
  end,
}
cards["ench:reflection"] = { hand = REFLECTION }

-- Bloodreaver Gul'dan (Warlock): Battlecry: summon all friendly Demons that died this game (in the order they died).
cards.ICC_831 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _, e in ipairs(dead_minions(g, p, function(e)
      return g.race(e) == "DEMON"
    end)) do
      if g.room(p) <= 0 then
        break
      end
      g.summon(p, g.card(e))
    end
  end,
}
-- Siphon Life: Lifesteal (its card's keyword); 3 damage.
cards.ICC_831p = {
  target = "any",
  hero_power = function(g, me, t)
    g.damage(me, t, g.hp_dmg(me, 3))
  end,
}

-- Thrall, Deathseer (Shaman): Battlecry: your minions become random ones that cost (2) more.
local function evolve(g, m, n)
  local c = random_card(g, minion_of(function(i)
    return i.cost == info(g, m).cost + n
  end))
  if c then
    g.transform(m, c)
  end
end
cards.ICC_481 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      evolve(g, m, 2)
    end
  end,
}
-- Transmute Spirit: a friendly minion becomes a random one that costs (1) more.
cards.ICC_481p = {
  target = "friendly_minion",
  hero_power = function(g, me, t)
    evolve(g, t, 1)
  end,
}

-- Scourgelord Garrosh (Warrior): Battlecry: equip a 4/3 Shadowmourne.
cards.ICC_834 = {
  battlecry = function(g, me)
    g.equip(g.ctrl(me), "ICC_834w")
  end,
}
-- Bladestorm: 1 damage to all minions.
cards.ICC_834h = {
  hero_power = function(g, me)
    damage_all_minions(g, me, g.hp_dmg(me, 1))
  end,
}
-- Shadowmourne: also damages the minions next to whomever your hero attacks (as much as the hero hits for).
cards.ICC_834w = {
  on = {
    after_attack = function(g, me, ev)
      local h = g.hero(g.ctrl(me))
      if ev.attacker == h and g.is_minion(ev.defender) then
        local n = g.attack(h)
        for _, m in ipairs(g.adjacent(ev.defender)) do
          g.damage(h, m, n)
        end
      end
    end,
  },
}

-- --- Death Knight cards (The Lich King, Arfus) ------------------------------------------------------------------

-- Frostmourne: Deathrattle: summon every minion killed by this weapon (its hero's attacks; FROSTMOURNE_KILL marks
-- the minions its blow left at 0 Health, FROSTMOURNE_N counts them in order).
cards.ICC_314t1 = {
  on = {
    damage = function(g, me, ev)
      local h = g.hero(g.ctrl(me))
      if ev.source == h and g.weapon(g.ctrl(me)) == me and g.is_minion(ev.target) and g.health(ev.target) <= 0 then
        g.set_tag(ev.target, "FROSTMOURNE_KILL", me)
      end
    end,
    death = function(g, me, ev)
      if ev.minion and g.tag(ev.entity, "FROSTMOURNE_KILL") == me then
        g.add_tag(me, "FROSTMOURNE_N", 1)
        g.set_tag(ev.entity, "FROSTMOURNE_ORDER", g.tag(me, "FROSTMOURNE_N"))
      end
    end,
  },
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    local killed = {}
    for q = 0, 1 do
      for _, e in ipairs(g.graveyard(q)) do
        if g.tag(e, "FROSTMOURNE_KILL") == me and g.tag(e, "FROSTMOURNE_ORDER") > 0 then
          killed[#killed + 1] = e
        end
      end
    end
    for _, e in ipairs(list.sort_by(killed, function(e)
      return g.tag(e, "FROSTMOURNE_ORDER")
    end)) do
      g.summon(p, g.card(e))
    end
  end,
}
-- Army of the Dead: remove the top 5 cards of your deck; summon the minions among them.
cards.ICC_314t2 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, e in ipairs(remove_top(g, p, 5)) do
      if g.is_minion(e) then
        g.summon(p, g.card(e))
      end
    end
  end,
}
-- Doom Pact: destroy all minions; remove the top card of your deck for each.
cards.ICC_314t3 = {
  spell = function(g, me)
    local n = 0
    for _, m in ipairs(g.all_minions()) do
      if alive(g, m) then
        n = n + 1
      end
      g.destroy(m)
    end
    remove_top(g, g.ctrl(me), n)
  end,
}
-- Death Grip: steal a minion from your opponent's deck into your hand.
cards.ICC_314t4 = {
  spell = function(g, me)
    local e = random_from_deck(g, g.enemy(me), function(d)
      return g.is_minion(d)
    end)
    if e then
      g.remove(e, "SETASIDE")
      g.log({ type = "stolen", player = g.ctrl(me), entity = e, card = g.card(e) })
      g.add_to_hand(g.ctrl(me), g.card(e))
    end
  end,
}
-- Death Coil: 5 damage to an enemy, or 5 Health to a friendly character.
cards.ICC_314t5 = {
  target = "any",
  spell = function(g, me, t)
    if g.ctrl(t) == g.ctrl(me) then
      g.heal(me, t, g.heal_amt(me, 5))
    else
      g.damage(me, t, g.spell_dmg(me, 5))
    end
  end,
}
-- Obliterate: destroy a minion; your hero takes damage equal to its Health.
cards.ICC_314t6 = {
  target = "minion",
  spell = function(g, me, t)
    local n = g.health(t)
    g.destroy(t)
    g.damage(me, g.hero(g.ctrl(me)), n)
  end,
}
-- Anti-Magic Shell: your minions +2/+2 and "Can't be targeted by spells or Hero Powers".
cards.ICC_314t7 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.buff(m, 2, 2)
      g.give_tag(m, "ELUSIVE")
    end
  end,
}
-- Death and Decay: 3 damage to all enemies.
cards.ICC_314t8 = {
  spell = function(g, me)
    local n = g.spell_dmg(me, 3)
    for _, c in ipairs(g.chars(g.enemy(me))) do
      g.damage(me, c, n)
    end
  end,
}

local function death_knight_card(g, me)
  g.add_to_hand(g.ctrl(me), g.pick(DK_CARDS))
end

-- --- Neutral ---------------------------------------------------------------------------------------------------------

-- Phantom Freebooter: gain your weapon's Attack and Durability.
cards.ICC_018 = {
  battlecry = function(g, me)
    local w = g.weapon(g.ctrl(me))
    if w then
      g.buff(me, g.atk(w), g.tag(w, "DURABILITY"))
    end
  end,
}

-- Skelemancer, Vryghoul, Arrogant Crusader: Deathrattle: if it's your opponent's turn, summon one.
local function on_their_turn(card)
  return {
    deathrattle = function(g, me)
      if opponents_turn(g, me) then
        summon_here(g, me, card)
      end
    end,
  }
end
cards.ICC_019 = on_their_turn("ICC_019t")
cards.ICC_067 = on_their_turn(GHOUL)
cards.ICC_034 = on_their_turn(GHOUL)

-- Rattling Rascal: Battlecry: a 5/5 Skeleton. Deathrattle: one for your opponent.
cards.ICC_025 = {
  battlecry = function(g, me)
    g.summon_right(me, "ICC_025t")
  end,
  deathrattle = function(g, me)
    g.summon(g.enemy(me), "ICC_025t")
  end,
}

-- Grim Necromancer: two 1/1 Skeletons.
cards.ICC_026 = {
  battlecry = function(g, me)
    for _ = 1, 2 do
      g.summon_right(me, SKELETON)
    end
  end,
}

-- Bone Drake: Deathrattle: a random Dragon.
cards.ICC_027 = {
  deathrattle = function(g, me)
    local c = random_card(g, minion_of(function(i)
      return i.race == "DRAGON"
    end))
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Sunborne Val'kyr: adjacent minions +2 Health.
cards.ICC_028 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.adjacent(me)) do
      g.buff(m, 0, 2)
    end
  end,
}

-- At the end of your turn, another random friendly minion gets a buff (Cobalt Scalebane, Shadow Ascendant).
local function scale(atk, hp)
  return end_of_my_turn(function(g, me)
    local m = g.random_alive(g.others(me))
    if m then
      g.buff(m, atk, hp)
    end
  end)
end
cards.ICC_029 = scale(3, 0)
cards.ICC_210 = scale(1, 1)

-- Whenever this minion takes damage (Night Howler, Howlfiend).
local function when_damaged(f)
  return {
    on = {
      damage = function(g, me, ev)
        if ev.target == me then
          f(g, me, ev)
        end
      end,
    },
  }
end
cards.ICC_031 = when_damaged(function(g, me)
  g.buff(me, 2, 0)
end)
cards.ICC_218 = when_damaged(function(g, me)
  g.discard_random(g.ctrl(me))
end)

-- Whenever this minion survives damage (Rotface, Val'kyr Soulclaimer).
local function survives(f)
  return when_damaged(function(g, me, ev)
    if alive(g, me) then
      f(g, me, ev)
    end
  end)
end
cards.ICC_405 = survives(function(g, me)
  local c = random_card(g, minion_of(function(i)
    return i.rarity == "LEGENDARY"
  end))
  if c then
    g.summon_right(me, c)
  end
end)
cards.ICC_408 = survives(function(g, me)
  g.summon_right(me, GHOUL)
end)

-- A Battlecry on a friendly minion (Acherus Veteran, Tuskarr Fisherman, Fallen Sun Cleric, Deathspeaker, Bonemare).
local function on_friend(f)
  return {
    target = { base = "friendly_minion", filter = other_friendly },
    battlecry = function(g, me, t)
      if t then
        f(g, me, t)
      end
    end,
  }
end
cards.ICC_092 = on_friend(function(g, me, t)
  g.buff(t, 1, 0)
end)
cards.ICC_093 = on_friend(function(g, me, t)
  g.add_tag(t, "SPELLPOWER", 1)
end)
cards.ICC_094 = on_friend(function(g, me, t)
  g.buff(t, 1, 1)
end)
cards.ICC_467 = on_friend(function(g, me, t)
  g.give_tag(t, "IMMUNE", true)
end)
cards.ICC_705 = on_friend(function(g, me, t)
  g.buff(t, 4, 4)
  g.give_tag(t, "TAUNT")
end)

-- Furnacefire Colossus: discard the weapons in your hand, gain their stats.
cards.ICC_096 = {
  battlecry = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      if g.is_weapon(e) then
        local a, d = g.atk(e), g.tag(e, "DURABILITY")
        g.discard(e)
        g.buff(me, a, d)
      end
    end
  end,
}

-- Grave Shambler: whenever your weapon is destroyed (it dies; replaced too: behaviour.replaced_weapon_dies), +1/+1.
cards.ICC_097 = {
  on = {
    death = function(g, me, ev)
      if not ev.minion and g.mine(me, ev) and g.type(ev.entity) == "WEAPON" then
        g.buff(me, 1, 1)
      end
    end,
  },
}

-- Tomb Lurker: a random Deathrattle minion that died this game (either side's; each different one as likely).
cards.ICC_098 = {
  battlecry = function(g, me)
    local dead = {}
    for p = 0, 1 do
      for _, e in ipairs(dead_minions(g, p, function(e)
        return has_kw(info(g, e), "DEATHRATTLE") and info(g, e).collectible
      end)) do
        dead[#dead + 1] = e
      end
    end
    local c = g.pick(distinct_cards(g, dead))
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Ticking Abomination: Deathrattle: 5 damage to your minions.
cards.ICC_099 = {
  deathrattle = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.damage(me, m, 5)
    end
  end,
}

-- Corpse Raiser: a friendly minion gets "Deathrattle: Resummon this minion."
cards.ICC_257 = on_friend(function(g, me, t)
  g.enchant(t, { hooks = "ench:resummon" })
end)
cards["ench:resummon"] = {
  deathrattle = function(g, me)
    summon_here(g, me, g.card(me))
  end,
}

-- The Lich King: at the end of your turn, a random Death Knight card.
cards.ICC_314 = end_of_my_turn(death_knight_card)

-- Saronite Chain Gang: Battlecry: a copy of this minion (its stats and buffs; no Battlecry).
cards.ICC_466 = {
  battlecry = function(g, me)
    local s = g.summon_right(me, g.card(me))
    if s then
      g.copy_minion(s, me)
    end
  end,
}

-- Wretched Tiller: whenever it attacks, 2 damage to the enemy hero.
cards.ICC_468 = {
  on = {
    attack = function(g, me, ev)
      if ev.attacker == me then
        g.damage(me, g.hero(g.enemy(me)), 2)
      end
    end,
  },
}

-- Happy Ghoul: costs (0) if your hero was healed this turn (the player hooks: HEALED_TURN).
local function healed_this_turn(g, me)
  return g.count(g.ctrl(me), "HEALED_TURN") == g.turn()
end
cards.ICC_700 = {
  cost_mod = function(g, me)
    if g.zone(me) == "HAND" and healed_this_turn(g, me) then
      return -info(g, me).cost
    end
    return 0
  end,
  glow = healed_this_turn,
}

-- Skulking Geist: destroy the spells whose card costs 1 (their printed Cost: until patch 25.4 of 2023) in both hands and
-- decks.
cards.ICC_701 = {
  battlecry = function(g, me)
    for p = 0, 1 do
      for _, zone in ipairs({ g.hand(p), g.deck(p) }) do
        for _, e in ipairs(zone) do
          if g.is_spell(e) and info(g, e).cost == 1 then
            g.remove(e, "GRAVEYARD")
            g.log({ type = "destroy", target = e })
          end
        end
      end
    end
  end,
}

-- Shallow Gravedigger: Deathrattle: a random Deathrattle minion.
cards.ICC_702 = {
  deathrattle = function(g, me)
    local c = random_card(g, minion_of(function(i)
      return has_kw(i, "DEATHRATTLE")
    end))
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Nerubian Unraveler: spells cost (2) more (both players').
cards.ICC_706 = {
  cost_aura = function(g, me, card, cost)
    if g.is_spell(card) and g.zone(card) == "HAND" then
      return cost + 2
    end
    return cost
  end,
}

-- Deathaxe Punisher: a random Lifesteal minion in your hand +2/+2.
cards.ICC_810 = {
  battlecry = function(g, me)
    local m = g.pick(list.filter(g.hand(g.ctrl(me)), function(e)
      return g.is_minion(e) and g.has(e, "LIFESTEAL")
    end))
    if m then
      g.buff(m, 2, 2)
    end
  end,
  glow = function(g, me)
    return list.any(g.hand(g.ctrl(me)), function(e)
      return e ~= me and g.is_minion(e) and g.has(e, "LIFESTEAL")
    end)
  end,
}

-- Meat Wagon: Deathrattle: a minion from your deck with less Attack than this one had.
cards.ICC_812 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    local a = g.atk(me)
    local e = random_from_deck(g, p, function(d)
      return g.is_minion(d) and g.atk(d) < a
    end)
    if e then
      g.summon_entity(e)
    end
  end,
}

-- Prince Keleseth: if your deck has no 2-Cost cards, the minions in it +1/+1.
cards.ICC_851 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if no_cost_in_deck(g, p, 2) then
      for _, e in ipairs(g.deck(p)) do
        if g.is_minion(e) then
          g.buff(e, 1, 1)
        end
      end
    end
  end,
  glow = prince_glow(2),
}

-- Prince Taldaram: if your deck has no 3-Cost cards, it becomes a 3/3 copy of a minion (5/5 with Crystal Core: the
-- patch 9.2 fix).
cards.ICC_852 = {
  target = {
    base = "minion",
    filter = other_friendly,
    when = function(g, me)
      return no_cost_in_deck(g, g.ctrl(me), 3)
    end,
  },
  battlecry = function(g, me, t)
    if not t or not no_cost_in_deck(g, g.ctrl(me), 3) then
      return
    end
    local n = g.copy_minion(me, t)
    if n then
      g.set_stats(n, 3, 3)
      if g.count(g.ctrl(n), "CRYSTAL_CORE") > 0 then
        g.enchant(n, { set_atk = 5, set_hp = 5 })
      end
    end
  end,
  glow = prince_glow(3),
}

-- Prince Valanar: if your deck has no 4-Cost cards, Lifesteal and Taunt.
cards.ICC_853 = {
  battlecry = function(g, me)
    if no_cost_in_deck(g, g.ctrl(me), 4) then
      g.give_tag(me, "LIFESTEAL")
      g.give_tag(me, "TAUNT")
    end
  end,
  glow = prince_glow(4),
}

-- Arfus: Deathrattle: a random Death Knight card.
cards.ICC_854 = { deathrattle = death_knight_card }

-- Hyldnir Frostrider: freeze your other minions.
cards.ICC_855 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.others(me)) do
      g.freeze(m)
    end
  end,
}

-- Necrotic Geist: whenever one of your other minions dies, a 2/2 Ghoul.
cards.ICC_900 = {
  on = {
    death = function(g, me, ev)
      if ev.minion and ev.entity ~= me and g.mine(me, ev) then
        g.summon(g.ctrl(me), GHOUL)
      end
    end,
  },
}

-- Drakkari Enchanter: your end of turn effects trigger twice (two Enchanters: still twice).
cards.ICC_901 = {
  aura = function(g, me)
    local p = g.ctrl(me)
    local first = list.filter(g.minions(p), function(m)
      return g.card(m) == "ICC_901" and not g.silenced(m)
    end)[1]
    if first == me then
      g.aura_add(g.hero(p), 0, 0, { EXTRA_END_TURN_EFFECT = 1 })
    end
  end,
}

-- Mindbreaker: Hero Powers are disabled (both players').
cards.ICC_902 = {
  aura = function(g, me)
    for p = 0, 1 do
      g.aura_add(g.power(p), 0, 0, { LOCKED = true })
    end
  end,
}

-- Wicked Skeleton: +1/+1 for each minion that died this turn.
cards.ICC_904 = {
  battlecry = function(g, me)
    local n = 0
    for p = 0, 1 do
      n = n + #list.filter(g.graveyard(p), function(e)
        return g.type(e) == "MINION" and g.died_pos(e) >= 0 and g.tag(e, "DIED_TURN") == g.turn()
      end)
    end
    if n > 0 then
      g.buff(me, n, n)
    end
  end,
}

-- Keening Banshee: whenever you play a card, remove the top 3 cards of your deck.
cards.ICC_911 = on_mine("play", function(g, me, ev)
  if ev.entity ~= me then
    remove_top(g, g.ctrl(me), 3)
  end
end)

-- Corpsetaker: Taunt, Divine Shield, Lifesteal, Windfury for each your deck's minions have.
cards.ICC_912 = {
  battlecry = function(g, me)
    local deck = list.filter(g.deck(g.ctrl(me)), function(e)
      return g.is_minion(e)
    end)
    for _, k in ipairs({ "TAUNT", "DIVINE_SHIELD", "LIFESTEAL", "WINDFURY" }) do
      if list.any(deck, function(e)
        return has_kw(info(g, e), k)
      end) then
        g.give_tag(me, k)
      end
    end
  end,
}

-- --- Druid -------------------------------------------------------------------------------------------------------------

-- Fatespinner: Choose a Deathrattle (secretly) - +2/+2 to all minions (Growth, option 0) or 3 damage to them (Decay,
-- option 1). It becomes its in-play form (a transform: ICC_047t, the same card whichever was chosen, so its opponent
-- can't tell; the option stays the entity's: g.choice; its player's client shows the chosen one of the card's text
-- variants, "generic@Growth@Decay"). With Fandral Staghelm: ICC_047t2, +2/+2, then 3 damage.
local function fate_grow(g)
  for _, m in ipairs(g.all_minions()) do
    g.buff(m, 2, 2)
  end
end
local function fate_secretly(g, me)
  g.transform(me, "ICC_047t")
end
cards.ICC_047 = {
  choose_one = { "ICC_047a", "ICC_047b" },
  both = function(g, me)
    g.transform(me, "ICC_047t2")
  end,
}
cards.ICC_047b = { effect = fate_secretly } -- Decay
cards.ICC_047a = { effect = fate_secretly } -- Growth
cards.ICC_047t = {
  deathrattle = function(g, me)
    local c = g.choice(me)
    if c == 0 then
      fate_grow(g)
    elseif c == 1 then
      damage_all_minions(g, me, 3)
    end
  end,
}
cards.ICC_047t2 = {
  deathrattle = function(g, me)
    fate_grow(g)
    damage_all_minions(g, me, 3)
  end,
}

-- Webweave: two 1/2 Poisonous Spiders.
cards.ICC_050 = {
  spell = function(g, me)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), "ICC_832t3")
    end
  end,
}

-- Druid of the Swarm: Choose One - a 1/2 Poisonous; or a 1/5 Taunt (both: a 1/5 Taunt Poisonous).
cards.ICC_051 = {
  choose_one = { "ICC_051a", "ICC_051b" },
  both = function(g, me)
    g.transform(me, "ICC_051t3")
  end,
}
cards.ICC_051a = {
  effect = function(g, me)
    g.transform(me, "ICC_051t")
  end,
}
cards.ICC_051b = {
  effect = function(g, me)
    g.transform(me, "ICC_051t2")
  end,
}

-- Spreading Plague: a 1/5 Taunt Scarab; while your opponent has more minions, again (each after the last one's
-- triggers; not "cast" by you; a full board stops it).
cards.ICC_054 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    repeat
      if not g.summon(p, "ICC_832t4") then
        break
      end
      g.resolve()
    until #g.minions(g.enemy(me)) <= #g.minions(p)
  end,
}

-- Gnash: +3 Attack this turn and 3 Armor.
cards.ICC_079 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.buff(g.hero(p), 3, 0, true)
    g.gain_armor(p, 3)
  end,
}

-- Ultimate Infestation: 5 damage, draw 5, 5 Armor, a 5/5 Ghoul.
cards.ICC_085 = {
  target = "any",
  spell = function(g, me, t)
    local p = g.ctrl(me)
    g.damage(me, t, g.spell_dmg(me, 5))
    g.draw(p, 5)
    g.gain_armor(p, 5)
    g.summon(p, "ICC_085t")
  end,
}

-- Strongshell Scavenger: your Taunt minions +2/+2.
cards.ICC_807 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.has(m, "TAUNT") then
        g.buff(m, 2, 2)
      end
    end
  end,
}

-- Crypt Lord: after you summon a minion, +1 Health.
cards.ICC_808 = {
  on = {
    after_summon = function(g, me, ev)
      if g.mine(me, ev) and ev.entity ~= me and alive(g, me) then
        g.buff(me, 0, 1)
      end
    end,
  },
}

-- Hadronox: Deathrattle: summon your Taunt minions that died this game (the cards with Taunt: a minion that only got
-- Taunt doesn't count), in the order they died.
cards.ICC_835 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    for _, e in ipairs(dead_minions(g, p, function(e)
      return has_kw(info(g, e), "TAUNT")
    end)) do
      if g.room(p) <= 0 then
        break
      end
      g.summon(p, g.card(e))
    end
  end,
}

-- --- Hunter ------------------------------------------------------------------------------------------------------------

-- Exploding Bloatbat: Deathrattle: 2 damage to all enemy minions.
cards.ICC_021 = {
  deathrattle = function(g, me)
    for _, m in ipairs(enemy_minions(g, me)) do
      g.damage(me, m, 2)
    end
  end,
}

-- Toxic Arrow: 2 damage to a minion; if it survives, Poisonous.
cards.ICC_049 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
    if alive(g, t) then
      g.give_tag(t, "POISONOUS")
    end
  end,
}

-- Play Dead: trigger a friendly minion's Deathrattle.
cards.ICC_052 = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t)
      return has_kw(info(g, t), "DEATHRATTLE") or #g.enchants(t, "ench:resummon") > 0 or #g.enchants(t, "ench:desperate") > 0
    end,
  },
  spell = function(g, me, t)
    g.deathrattle(t)
  end,
}

-- Venomstrike Trap: when one of your minions is attacked, a 2/3 Poisonous Emperor Cobra.
cards.ICC_200 = {
  secret = {
    event = "attack",
    cond = function(g, me, ev)
      local d = ev.defender
      return g.is_minion(d) and g.ctrl(d) == g.ctrl(me) and g.room(g.ctrl(me)) > 0
    end,
    effect = function(g, me)
      g.summon(g.ctrl(me), "VAN_EX1_170")
    end,
  },
}

-- Professor Putricide: after you play a Secret, a random Hunter Secret (not one you have) into the battlefield.
cards.ICC_204 = {
  on = {
    after_spell = function(g, me, ev)
      if not g.mine(me, ev) or not g.info(ev.card).trap then
        return
      end
      local p = g.ctrl(me)
      local have = {}
      for _, s in ipairs(g.traps(p)) do
        have[g.card(s)] = true
      end
      local c = random_card(g, function(i)
        return i.trap and i.class == "HUNTER" and not have[i.id]
      end)
      if c then
        g.put_trap(g.create(p, c))
      end
    end,
  },
}

-- Corpse Widow: your Deathrattle cards cost (2) less (applied before the other cost changes but Summoning Portal: patch
-- 9.0).
cards.ICC_243 = {
  cost_first = 2,
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.zone(card) == "HAND" and has_kw(info(g, card), "DEATHRATTLE") then
      return cost - 2
    end
    return cost
  end,
}

-- Stitched Tracker: Discover a copy of a minion in your deck (a plain copy: patch 12.0 kept the buffs).
cards.ICC_415 = {
  battlecry = function(g, me)
    offer_cards(g, me, distinct_cards(g, list.filter(g.deck(g.ctrl(me)), function(e)
      return g.is_minion(e)
    end)))
  end,
  on_choose = to_hand,
}

-- Abominable Bowman: Deathrattle: a random friendly Beast that died this game.
cards.ICC_825 = {
  deathrattle = function(g, me)
    local e = g.pick(dead_minions(g, g.ctrl(me), function(e)
      return g.race(e) == "BEAST"
    end))
    if e then
      summon_here(g, me, g.card(e))
    end
  end,
}

-- --- Mage --------------------------------------------------------------------------------------------------------------

-- Ice Walker: your Hero Power also freezes its target.
cards.ICC_068 = {
  on = {
    hero_power = function(g, me, ev)
      if g.mine(me, ev) and ev.target and ev.target > 0 then
        g.freeze(ev.target)
      end
    end,
  },
}

-- Ghastly Conjurer: a Mirror Image.
cards.ICC_069 = {
  battlecry = function(g, me)
    g.add_to_hand(g.ctrl(me), "VAN_CS2_027")
  end,
}

-- Frozen Clone: after your opponent plays a minion, two copies of it into your hand.
cards.ICC_082 = {
  secret = {
    event = "after_summon",
    cond = function(g, me, ev)
      return ev.played and not g.mine(me, ev)
    end,
    effect = function(g, me, ev)
      for _ = 1, 2 do
        g.add_to_hand(g.ctrl(me), ev.card)
      end
    end,
  },
}

-- Doomed Apprentice: your opponent's spells cost (1) more.
cards.ICC_083 = {
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) ~= g.ctrl(me) and g.is_spell(card) and g.zone(card) == "HAND" then
      return cost + 1
    end
    return cost
  end,
}

-- Glacial Mysteries: one of each Secret in your deck into the battlefield (top first; one you have stays).
cards.ICC_086 = {
  spell = function(g, me)
    local d = g.deck(g.ctrl(me))
    for i = #d, 1, -1 do
      if g.info(g.card(d[i])).trap then
        g.put_trap(d[i])
      end
    end
  end,
}

-- Coldwraith: if an enemy is Frozen, draw a card.
cards.ICC_252 = {
  battlecry = function(g, me)
    if frozen_enemy(g, me) then
      g.draw(g.ctrl(me))
    end
  end,
  glow = frozen_enemy,
}

-- Simulacrum: a copy of the lowest Cost minion in your hand (ties: at random; a plain copy).
cards.ICC_823 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local ms = list.filter(g.hand(p), function(e)
      return g.is_minion(e)
    end)
    local low
    for _, m in ipairs(ms) do
      if not low or g.cost(m) < low then
        low = g.cost(m)
      end
    end
    local m = g.pick(list.filter(ms, function(e)
      return g.cost(e) == low
    end))
    if m then
      g.add_to_hand(p, g.card(m))
    end
  end,
}

-- Breath of Sindragosa: 2 damage to a random enemy minion and freeze it.
cards.ICC_836 = {
  spell = function(g, me)
    local m = g.random_alive(enemy_minions(g, me))
    if m then
      g.damage(me, m, g.spell_dmg(me, 2))
      g.freeze(m)
    end
  end,
}

-- Sindragosa: two 0/1 Frozen Champions.
cards.ICC_838 = {
  battlecry = function(g, me)
    for _ = 1, 2 do
      g.summon_right(me, "ICC_838t")
    end
  end,
}
-- Frozen Champion: Deathrattle: a random Legendary minion.
cards.ICC_838t = {
  deathrattle = function(g, me)
    local c = random_card(g, minion_of(function(i)
      return i.rarity == "LEGENDARY"
    end))
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- --- Paladin -----------------------------------------------------------------------------------------------------------

-- Dark Conviction: a minion's Attack and Health become 3.
cards.ICC_039 = {
  target = "minion",
  spell = function(g, me, t)
    g.set_stats(t, 3, 3)
  end,
}

-- Light's Sorrow: after a friendly minion loses Divine Shield, +1 Attack.
cards.ICC_071 = {
  on = {
    divine_shield_lost = function(g, me, ev)
      if g.is_minion(ev.target) and g.ctrl(ev.target) == g.ctrl(me) then
        g.buff(me, 1, 0)
      end
    end,
  },
}

-- Desperate Stand: a minion gets "Deathrattle: Return this to life with 1 Health."
cards.ICC_244 = {
  target = "minion",
  spell = function(g, me, t)
    g.enchant(t, { hooks = "ench:desperate" })
  end,
}
cards["ench:desperate"] = {
  deathrattle = function(g, me)
    local n = summon_here(g, me, g.card(me))
    if n then
      g.set_damage(n, g.max_health(n) - 1)
    end
  end,
}

-- Blackguard: whenever your hero is healed, that much damage to a random enemy minion.
cards.ICC_245 = {
  on = {
    heal = function(g, me, ev)
      if ev.target == g.hero(g.ctrl(me)) and ev.amount > 0 then
        local m = g.random_alive(enemy_minions(g, me))
        if m then
          g.damage(me, m, ev.amount)
        end
      end
    end,
  },
}

-- Howling Commander: draw a Divine Shield minion from your deck.
cards.ICC_801 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local e = random_from_deck(g, p, function(d)
      return g.is_minion(d) and has_kw(info(g, d), "DIVINE_SHIELD")
    end)
    if e then
      g.draw_entity(p, e)
    end
  end,
}

-- Bolvar, Fireblood: after a friendly minion (himself too) loses Divine Shield, +2 Attack.
cards.ICC_858 = {
  on = {
    divine_shield_lost = function(g, me, ev)
      if g.is_minion(ev.target) and g.ctrl(ev.target) == g.ctrl(me) then
        g.buff(me, 2, 0)
      end
    end,
  },
}

-- --- Priest ------------------------------------------------------------------------------------------------------------

-- Devour Mind: copies of 3 cards of your opponent's deck (plain copies).
cards.ICC_207 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, e in ipairs(pick_n(g, g.deck(g.enemy(me)), 3)) do
      g.add_to_hand(p, g.card(e))
    end
  end,
}

-- Eternal Servitude: Discover a friendly minion that died this game; summon it.
cards.ICC_213 = {
  spell = function(g, me)
    offer_cards(g, me, distinct_cards(g, dead_minions(g, g.ctrl(me))))
  end,
  on_choose = function(g, me, option)
    g.summon(g.ctrl(me), g.card(option))
  end,
}

-- Obsidian Statue: Deathrattle: destroy a random enemy minion.
cards.ICC_214 = {
  deathrattle = function(g, me)
    g.destroy(g.random_alive(enemy_minions(g, me)))
  end,
}

-- Archbishop Benedictus: shuffle a copy of your opponent's deck into your deck.
cards.ICC_215 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _, e in ipairs(g.deck(g.enemy(me))) do
      g.add_to_deck(p, g.card(e))
    end
  end,
}

-- Shadow Essence: a 5/5 copy of a random minion in your deck.
cards.ICC_235 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local e = random_from_deck(g, p, function(d)
      return g.is_minion(d)
    end)
    if e then
      local m = g.summon(p, g.card(e))
      if m then
        g.set_stats(m, 5, 5)
      end
    end
  end,
}

-- Spirit Lash: Lifesteal (the card's keyword); 1 damage to all minions.
cards.ICC_802 = {
  spell = function(g, me)
    damage_all_minions(g, me, g.spell_dmg(me, 1))
  end,
}

-- Embrace Darkness: choose an enemy minion; at the start of your turn, take it.
cards.ICC_849 = {
  target = "enemy_minion",
  spell = function(g, me, t)
    g.enchant(t, { hooks = "ench:embrace", player = g.ctrl(me) })
  end,
}
cards["ench:embrace"] = {
  on = {
    turn_start = function(g, me, ev)
      local p = g.enchants(me, "ench:embrace")[1]
      if p ~= nil and ev.player == p then
        g.remove_enchant(me, "ench:embrace")
        if g.ctrl(me) ~= p then
          g.take_control(me, p)
        end
      end
    end,
  },
}

-- --- Rogue -------------------------------------------------------------------------------------------------------------

-- Bone Baron: Deathrattle: two 1/1 Skeletons into your hand.
cards.ICC_065 = {
  deathrattle = function(g, me)
    for _ = 1, 2 do
      g.add_to_hand(g.ctrl(me), SKELETON)
    end
  end,
}

-- Roll the Bones: draw a card; if it has Deathrattle, again (a full hand stops it; not "cast" by you).
cards.ICC_201 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    while true do
      local d = g.draw(p)[1]
      if not d or not has_kw(info(g, d), "DEATHRATTLE") then
        break
      end
    end
  end,
}

-- Leeching Poison: your weapon gets Lifesteal (for good: until patch 13.0).
cards.ICC_221 = {
  can_play = has_weapon,
  spell = function(g, me)
    g.give_tag(g.weapon(g.ctrl(me)), "LIFESTEAL")
  end,
}

-- Doomerang: throw your weapon at a minion: it deals its damage (its Poisonous and Lifesteal too, no Spell Damage),
-- then returns to your hand as a fresh card (not destroyed: no Deathrattle).
cards.ICC_233 = {
  target = "minion",
  can_play = has_weapon,
  spell = function(g, me, t)
    local p = g.ctrl(me)
    local w = g.weapon(p)
    if not w then
      return
    end
    g.damage(w, t, g.atk(w))
    if g.weapon(p) == w then
      g.remove(w, "SETASIDE")
      g.log({ type = "return_to_hand", entity = w })
      g.add_to_hand(p, g.card(w))
    end
  end,
}

-- Runeforge Haunter: during your turn, your weapon doesn't lose Durability (from attacks, Sword of Justice or Atiesh:
-- what it had before an attack, a summon or a spell comes back after it).
local function keep_durability(g, me, ev, before)
  local p = g.ctrl(me)
  local w = g.weapon(p)
  if g.current() ~= p or not w then
    return
  end
  if before then
    g.set_tag(w, "KEEP_DURABILITY", g.tag(w, "DURABILITY"))
  elseif g.tag(w, "DURABILITY") < g.tag(w, "KEEP_DURABILITY") then
    g.set_tag(w, "DURABILITY", g.tag(w, "KEEP_DURABILITY"))
  end
end
cards.ICC_240 = {
  on = {
    attack = function(g, me, ev)
      keep_durability(g, me, ev, true)
    end,
    after_attack = function(g, me, ev)
      keep_durability(g, me, ev, false)
    end,
    summon = function(g, me, ev)
      keep_durability(g, me, ev, true)
    end,
    after_summon = function(g, me, ev)
      keep_durability(g, me, ev, false)
    end,
    play = function(g, me, ev)
      keep_durability(g, me, ev, true)
    end,
    after_spell = function(g, me, ev)
      keep_durability(g, me, ev, false)
    end,
  },
}

-- Plague Scientist: Combo: a friendly minion gets Poisonous.
cards.ICC_809 = {
  combo_target = { base = "friendly_minion", filter = other_friendly },
  combo = function(g, me, t)
    if t then
      g.give_tag(t, "POISONOUS")
    end
  end,
}

-- Lilian Voss: the spells in your hand become random spells of your opponent's class (none without a class).
cards.ICC_811 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local cls = g.class(g.hero(g.enemy(me)))
    if not playable(cls) then
      return
    end
    local spells = pool(g, function(i)
      return i.type == "SPELL" and of_class(i, cls)
    end)
    for _, e in ipairs(g.hand(p)) do
      if g.is_spell(e) then
        g.transform(e, g.pick(spells))
      end
    end
  end,
}

-- Shadowblade: Battlecry: your hero is Immune this turn.
cards.ICC_850 = {
  battlecry = function(g, me)
    g.give_tag(g.hero(g.ctrl(me)), "IMMUNE", true)
  end,
}

-- Spectral Pillager: Combo: damage equal to the number of other cards you've played this turn (any character).
cards.ICC_910 = {
  combo_target = "any",
  combo = function(g, me, t)
    local n = g.cards_played(g.ctrl(me)) - 1
    if t and n > 0 then
      g.damage(me, t, n)
    end
  end,
}

-- --- Shaman ------------------------------------------------------------------------------------------------------------

-- Cryostasis: a minion +3/+3 and Frozen.
cards.ICC_056 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 3, 3)
    g.freeze(t)
  end,
}

-- Brrrloc: freeze an enemy.
cards.ICC_058 = {
  target = "enemy_char",
  battlecry = function(g, me, t)
    if t then
      g.freeze(t)
    end
  end,
}

-- Avalanche: freeze a minion, 3 damage to the ones next to it.
cards.ICC_078 = {
  target = "minion",
  spell = function(g, me, t)
    local adj = g.adjacent(t)
    g.freeze(t)
    local n = g.spell_dmg(me, 3)
    for _, m in ipairs(adj) do
      g.damage(me, m, n)
    end
  end,
}

-- Voodoo Hexxer: freeze any character it damages.
cards.ICC_088 = cards.ICC_833t

-- Ice Fishing: draw 2 Murlocs from your deck.
cards.ICC_089 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 2 do
      local e = random_from_deck(g, p, function(d)
        return g.race(d) == "MURLOC"
      end)
      if not e then
        break
      end
      g.draw_entity(p, e)
    end
  end,
}

-- Snowfury Giant: (1) less for each Mana Crystal you've Overloaded this game (the player hooks: OVERLOADED).
cards.ICC_090 = {
  cost_mod = function(g, me)
    return -g.count(g.ctrl(me), "OVERLOADED")
  end,
}

-- Ice Breaker: destroy any Frozen minion it damages (its hero's attacks).
cards.ICC_236 = {
  on = {
    damage = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.source == g.hero(p) and g.weapon(p) == me and g.is_minion(ev.target) and g.has(ev.target, "FROZEN") then
        g.destroy(ev.target)
      end
    end,
  },
}

-- Moorabi: whenever another minion is Frozen (again too), a copy of it into your hand.
cards.ICC_289 = {
  on = {
    freeze = function(g, me, ev)
      if ev.target ~= me and g.is_minion(ev.target) then
        g.add_to_hand(g.ctrl(me), g.card(ev.target))
      end
    end,
  },
}

-- --- Warlock -----------------------------------------------------------------------------------------------------------

-- Defile: 1 damage to all minions; if any die, again (their Deathrattles first; Spell Damage counted each time; 14 casts
-- at most; not "cast" by you).
local function deaths(g)
  return g.count(0, "DEATHS") + g.count(1, "DEATHS")
end
cards.ICC_041 = {
  spell = function(g, me)
    for _ = 1, 14 do
      local before = deaths(g)
      damage_all_minions(g, me, g.spell_dmg(me, 1))
      g.resolve()
      if deaths(g) == before then
        break
      end
    end
  end,
}

-- Drain Soul: Lifesteal (the card's keyword); 2 damage to a minion.
cards.ICC_055 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
  end,
}

-- Despicable Dreadlord: at the end of your turn, 1 damage to all enemy minions.
cards.ICC_075 = end_of_my_turn(function(g, me)
  for _, m in ipairs(enemy_minions(g, me)) do
    g.damage(me, m, 1)
  end
end)

-- Treachery: a friendly minion goes to your opponent.
cards.ICC_206 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.take_control(t, g.enemy(me))
  end,
}

-- Gnomeferatu: remove the top card of your opponent's deck.
cards.ICC_407 = {
  battlecry = function(g, me)
    remove_top(g, g.enemy(me), 1)
  end,
}

-- Unwilling Sacrifice: destroy a friendly minion and a random enemy minion.
cards.ICC_469 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    local e = g.random_alive(enemy_minions(g, me))
    g.destroy(t)
    g.destroy(e)
  end,
}

-- Blood-Queen Lana'thel: +1 Attack for each card you've discarded this game, wherever she is (in the hand and the deck
-- too, as the card shows it; one discarded before she came, Cruel Dinomancer's copy: all of them). The player hooks give
-- each of her +1 at each discard (LANATHEL: how many she has), and one who comes later what she lacks; Silence takes it.
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

-- Sanguine Reveler: destroy a friendly minion, +2/+2.
cards.ICC_903 = on_friend(function(g, me, t)
  g.destroy(t)
  g.buff(me, 2, 2)
end)

-- --- Warrior -----------------------------------------------------------------------------------------------------------

-- Mountainfire Armor: Deathrattle: if it's your opponent's turn, 6 Armor.
cards.ICC_062 = {
  deathrattle = function(g, me)
    if opponents_turn(g, me) then
      g.gain_armor(g.ctrl(me), 6)
    end
  end,
}

-- Blood Razor: Battlecry and Deathrattle: 1 damage to all minions.
cards.ICC_064 = {
  battlecry = function(g, me)
    damage_all_minions(g, me, 1)
  end,
  deathrattle = function(g, me)
    damage_all_minions(g, me, 1)
  end,
}

-- Dead Man's Hand: shuffle a copy of your hand into your deck.
cards.ICC_091 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, e in ipairs(g.hand(p)) do
      g.add_to_deck(p, g.card(e))
    end
  end,
}

-- Animated Berserker: after you play a minion, 1 damage to it.
cards.ICC_238 = {
  on = {
    after_summon = function(g, me, ev)
      if ev.played and g.mine(me, ev) and ev.entity ~= me then
        g.damage(me, ev.entity, 1)
      end
    end,
  },
}

-- Forge of Souls: draw 2 weapons from your deck.
cards.ICC_281 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 2 do
      local e = random_from_deck(g, p, function(d)
        return g.is_weapon(d)
      end)
      if not e then
        break
      end
      g.draw_entity(p, e)
    end
  end,
}

-- Death Revenant: +1/+1 for each damaged minion.
cards.ICC_450 = {
  battlecry = function(g, me)
    local n = #list.filter(g.all_minions(), function(m)
      return m ~= me and g.dmg(m) > 0
    end)
    if n > 0 then
      g.buff(me, n, n)
    end
  end,
}

-- Bring It On!: 10 Armor; the minions in your opponent's hand cost (2) less.
cards.ICC_837 = {
  spell = function(g, me)
    g.gain_armor(g.ctrl(me), 10)
    for _, e in ipairs(g.hand(g.enemy(me))) do
      if g.is_minion(e) then
        g.enchant(e, { cost = -2 })
      end
    end
  end,
}

-- --- the game's counts and its start (rules.json player_hooks) -------------------------------------
-- Journey to Un'Goro's (spells cast, Totems summoned, the order friendly minions died in, Secrets played from the hand,
-- Patches the Pirate from the deck, Prince Malchezaar after the mulligan, Elementals played this turn and the last, the
-- cards that started in the deck, the cards played from another class, the discarded cards, Crystal Core), and Knights of
-- the Frozen Throne's: the turn a player's hero was last healed (HEALED_TURN: Happy Ghoul), the Mana Crystals they
-- Overloaded (OVERLOADED: Snowfury Giant), the cards they discarded (DISCARDS: Blood-Queen Lana'thel), every minion
-- death (DEATHS on both sides: Defile) and Dreadsteeds owed at the end of the turn.

local MALCHEZAAR = "KAR_096"
local PATCHES = "CFM_637"

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

cards["player:icc"] = {
  on = {
    after_spell = function(g, me, ev)
      if g.mine(me, ev) then
        g.add_count(g.ctrl(me), "SPELLS")
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
    end,
    play = function(g, me, ev)
      if not g.mine(me, ev) then
        return
      end
      local p = g.ctrl(me)
      if ev.kind == "spell" and ev.secret then
        g.add_count(p, "SECRETS")
      end
      if ev.kind == "minion" and g.race(ev.entity) == "ELEMENTAL" then
        g.add_count(p, "ELEM_NOW")
      end
      if other_class(g, ev.entity, p) then
        g.add_count(p, "OTHER_CLASS")
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
        lanathel(g, ev.entity) -- (one shuffled in later: Dead Man's Hand, Archbishop Benedictus)
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
      end
    end,
    -- Dreadsteeds owed (patch 9.0): at the end of the turn (either player's), each comes back for its player; twice
    -- with Drakkari Enchanter (its player's end of turn effects; only the player hooks of that player see it twice)
    turn_end = function(g, me, ev)
      local p = g.ctrl(me)
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
    after_summon = function(g, me, ev)
      local p = g.ctrl(me)
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
      malchezaar(g, p)
    end,
  },
}

return cards
