-- One Night in Karazhan (August 2016): the 45 cards and their 12 tokens as at the release (patch 6.0.0.13921 of
-- 2016-08-09, two days before the first wing; hearthstone.wiki.gg and its card notes; docs/packs/api.md). The older
-- sets' cards are those packs' scripts, copied in by the recipe; none of them changed its effect by then (only costs,
-- a tribe and texts: cards.patch.json, cards.texts.json).
local cards = {}

-- --- helpers -----------------------------------------------------------------------------------

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local BASIC_TOTEMS = { "VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009" }

local function playable(class)
  return list.any(CLASSES, function(c)
    return c == class
  end)
end

-- The collectible cards whose data pass ok.
local function pool(g, ok)
  return list.filter(g.collectible(), function(c)
    return ok(g.info(c))
  end)
end

local function minion_of_cost(n)
  return function(i)
    return i.type == "MINION" and i.cost == n
  end
end

-- A random collectible minion of that cost for me's side, at the right end (the portals, Atiesh: any class, every set
-- of the pack, as in Wild then); nil when there is none or no room.
local function summon_random_of_cost(g, me, n)
  local c = g.pick(pool(g, minion_of_cost(n)))
  if c then
    return g.summon(g.ctrl(me), c)
  end
end

-- A death hook that summons card where me stood.
local function summon_here(g, me, card)
  local pos = g.died_pos(me)
  return g.summon(g.ctrl(me), card, pos >= 0 and pos or nil)
end

local function deathrattle_summon(card)
  return {
    deathrattle = function(g, me)
      summon_here(g, me, card)
    end,
  }
end

local function battlecry_summon(card)
  return {
    battlecry = function(g, me)
      g.summon_right(me, card)
    end,
  }
end

-- An `on` hook for an event of me's controller.
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

-- "Whenever you cast a spell" (before it resolves; not a countered one's effect, as Violet Teacher).
local function on_my_spell(f)
  return {
    on = {
      play = function(g, me, ev)
        if lib.my_spell(g, me, ev) then
          f(g, me, ev)
        end
      end,
    },
  }
end

-- "If you're holding a Dragon": another card in me's controller's hand is a Dragon.
local function holding_dragon(g, me)
  return list.any(g.hand(g.ctrl(me)), function(e)
    return e ~= me and g.race(e) == "DRAGON"
  end)
end

-- "If you control a Secret".
local function control_secret(g, me)
  return #g.traps(g.ctrl(me)) > 0
end

-- --- Discover (as The League of Explorers': the class cards four times as likely, as in 2016) --------------------

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
end

local function discover_class(g, me)
  local c = g.class(g.hero(g.ctrl(me)))
  if playable(c) then
    return c
  end
  c = g.info(g.card(me)).class
  if playable(c) then
    return c
  end
  return CLASSES[g.random(1, #CLASSES)]
end

-- Discover a card whose data pass ok.
local function discover(g, me, ok)
  local cls = discover_class(g, me)
  local choices = {}
  for _, c in ipairs(g.collectible()) do
    local i = g.info(c)
    if (i.class == cls or i.class == "NEUTRAL") and i.type ~= "CHAMPION" and i.type ~= "POWER" and ok(i) then
      choices[#choices + 1] = { c, i.class == cls and 4 or 1 }
    end
  end
  offer(g, me, choices)
end

-- --- the game's counts and its start (rules.json player_hooks) -------------------------------------
-- Whispers of the Old Gods' counts (spells cast from the hand and not countered: Yogg-Saron, Arcane Giant; Totems
-- summoned; the order friendly minions died in), and "when the game starts" (Prince Malchezaar).

local MALCHEZAAR = "KAR_096"

-- Prince Malchezaar: after the mulligan, each one of the deck the player started with (in the deck or drawn into the
-- hand) shuffles in 5 random collectible Legendary minions of the player's class or neutral, none already in the deck
-- or the hand (one copy of each, as deckbuilding allows).
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
      return i.type == "MINION" and i.rarity == "LEGENDARY" and (i.class == hero_class or i.class == "NEUTRAL")
        and not have[i.id]
    end))
    if c then
      g.add_to_deck(p, c)
    end
  end
end

cards["player:kara"] = {
  on = {
    after_spell = function(g, me, ev)
      if g.mine(me, ev) then
        g.add_count(g.ctrl(me), "SPELLS")
      end
    end,
    summon = function(g, me, ev)
      if g.mine(me, ev) and g.race(ev.entity) == "TOTEM" then
        g.add_count(g.ctrl(me), "TOTEMS")
      end
    end,
    death = function(g, me, ev)
      if ev.minion and g.mine(me, ev) then
        g.set_tag(ev.entity, "DIED_ORDER", g.add_count(g.ctrl(me), "DEATHS"))
      end
    end,
    game_start = function(g, me)
      malchezaar(g, g.ctrl(me))
    end,
  },
}

-- --- Neutral ------------------------------------------------------------------------------------

-- Runic Egg: Deathrattle: draw a card.
cards.KAR_029 = {
  deathrattle = function(g, me)
    g.draw(g.ctrl(me))
  end,
}

-- Pantry Spider: summon a 1/3 Cellar Spider.
cards.KAR_030a = battlecry_summon("KAR_030")

-- Arcanosmith: summon a 0/5 Animated Shield with Taunt.
cards.KAR_710 = battlecry_summon("KAR_710m")

-- Arcane Anomaly: whenever you cast a spell, +1 Health.
cards.KAR_036 = on_my_spell(function(g, me)
  g.buff(me, 0, 1)
end)

-- Avian Watcher: if you control a Secret, +1/+1 and Taunt.
cards.KAR_037 = {
  glow = control_secret,
  battlecry = function(g, me)
    if control_secret(g, me) then
      g.buff(me, 1, 1)
      g.give_tag(me, "TAUNT")
    end
  end,
}

-- Book Wyrm: if you're holding a Dragon, destroy an enemy minion with 3 or less Attack (a target only then).
cards.KAR_033 = {
  glow = holding_dragon,
  target = {
    base = "enemy_minion",
    when = holding_dragon,
    filter = function(g, me, t)
      return g.atk(t) <= 3
    end,
  },
  battlecry = function(g, me, t)
    if t then
      g.destroy(t)
    end
  end,
}

-- Netherspite Historian: if you're holding a Dragon, Discover a Dragon.
cards.KAR_062 = {
  glow = holding_dragon,
  battlecry = function(g, me)
    if holding_dragon(g, me) then
      discover(g, me, function(i)
        return i.type == "MINION" and i.race == "DRAGON"
      end)
    end
  end,
  on_choose = function(g, me, option)
    g.add_to_hand(g.ctrl(me), g.card(option))
  end,
}

-- Moat Lurker: destroy a minion; Deathrattle: a fresh copy of it, at the right end of the side it was destroyed on.
-- The Lurker keeps which (a copy of the Lurker too: Faceless Manipulator); silenced, returned to the hand or summoned
-- fresh (Barnes, N'Zoth) it keeps none.
cards.KAR_041 = {
  target = "minion",
  battlecry = function(g, me, t)
    if t then
      g.set_tag(me, "LURKED", t) -- the destroyed minion (its entity stays, in the graveyard) and its side + 1
      g.set_tag(me, "LURKED_SIDE", g.ctrl(t) + 1)
      g.destroy(t)
    end
  end,
  deathrattle = function(g, me)
    local e = g.tag(me, "LURKED")
    if e > 0 then
      g.summon(g.tag(me, "LURKED_SIDE") - 1, g.card(e))
    end
  end,
}

-- Moroes: at the end of your turn, summon a 1/1 Steward.
cards.KAR_044 = on_mine("turn_end", function(g, me)
  g.summon_right(me, "KAR_044a")
end)

-- The Curator: draw a Beast, a Dragon and a Murloc from your deck (each a random one, in that order).
cards.KAR_061 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _, race in ipairs({ "BEAST", "DRAGON", "MURLOC" }) do
      local e = g.pick(list.filter(g.deck(p), function(d)
        return g.type(d) == "MINION" and g.race(d) == race
      end))
      if e then
        g.draw_entity(p, e)
      end
    end
  end,
}

-- Zoobot / Menagerie Magician: a random other friendly Beast, Dragon and Murloc +n/+n (each tribe picked on its own).
local function menagerie(n)
  return {
    battlecry = function(g, me)
      for _, race in ipairs({ "BEAST", "DRAGON", "MURLOC" }) do
        local m = g.pick(list.filter(g.others(me), function(x)
          return g.race(x) == race
        end))
        if m then
          g.buff(m, n, n)
        end
      end
    end,
  }
end
cards.KAR_095 = menagerie(1)
cards.KAR_702 = menagerie(2)

-- Violet Illusionist: during your turn, your hero is Immune.
cards.KAR_712 = {
  aura = function(g, me)
    local p = g.ctrl(me)
    if g.current() == p then
      g.aura_add(g.hero(p), 0, 0, { IMMUNE = true })
    end
  end,
}

-- Arcane Giant: costs (1) less for each spell you've cast this game (from the hand and not countered).
cards.KAR_711 = {
  cost_mod = function(g, me)
    return -g.count(g.ctrl(me), "SPELLS")
  end,
}

-- Barnes: a 1/1 copy of a random minion in your deck, right of Barnes (only its card: no Battlecry, no enchantments).
-- As in 2016 (until patch 7.1) the copy becomes 1/1 after "when you summon" effects (Sword of Justice: a 1/1).
cards.KAR_114 = {
  battlecry = function(g, me)
    local e = g.pick(list.filter(g.deck(g.ctrl(me)), function(d)
      return g.type(d) == "MINION"
    end))
    local m = e and g.summon_right(me, g.card(e))
    if m then
      g.resolve()
      if g.zone(m) == "PLAY" then
        g.set_stats(m, 1, 1)
      end
    end
  end,
}

-- Medivh, the Guardian: equip Atiesh.
cards.KAR_097 = {
  battlecry = function(g, me)
    g.equip(g.ctrl(me), "KAR_097t")
  end,
}

-- Atiesh: after you cast a spell, a random minion of the mana the spell cost (cost changes included) and 1 Durability.
-- A full board: nothing, no Durability; no minion of that cost: nothing, but the Durability goes.
cards.KAR_097t = on_mine("after_spell", function(g, me, ev)
  local p = g.ctrl(me)
  if g.zone(me) ~= "PLAY" or g.room(p) <= 0 then
    return
  end
  summon_random_of_cost(g, me, g.tag(ev.entity, "PLAYED_COST"))
  g.add_tag(me, "DURABILITY", -1)
end)

-- --- Druid --------------------------------------------------------------------------------------

-- Menagerie Warden: a copy of a friendly Beast (its stats, enchantments and damage), right of the Warden.
cards.KAR_065 = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t)
      return g.race(t) == "BEAST"
    end,
  },
  battlecry = function(g, me, t)
    if t then
      local c = g.summon_right(me, g.card(t))
      if c then
        g.copy_minion(c, t)
      end
    end
  end,
}

-- Moonglade Portal: restore 6 Health, then a random 6-Cost minion.
cards.KAR_075 = {
  target = "any",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 6))
    summon_random_of_cost(g, me, 6)
  end,
}

-- --- Hunter -------------------------------------------------------------------------------------

-- Cat Trick: after your opponent casts a spell, summon a 4/2 Panther with Stealth.
cards.KAR_004 = {
  secret = {
    event = "after_spell",
    cond = function(g, me, ev)
      return ev.player ~= g.ctrl(me) and g.room(g.ctrl(me)) > 0
    end,
    effect = function(g, me)
      g.summon(g.ctrl(me), "KAR_004a")
    end,
  },
}

-- Kindly Grandmother: Deathrattle: summon a 3/2 Big Bad Wolf.
cards.KAR_005 = deathrattle_summon("KAR_005a")

-- Cloaked Huntress: your Secrets cost (0).
cards.KAR_006 = {
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.zone(card) == "HAND" and g.info(g.card(card)).trap then
      return 0
    end
    return cost
  end,
}

-- --- Mage ---------------------------------------------------------------------------------------

-- Babbling Book: a random Mage spell into your hand.
cards.KAR_009 = {
  battlecry = function(g, me)
    local c = g.pick(pool(g, function(i)
      return i.class == "MAGE" and i.type == "SPELL"
    end))
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Firelands Portal: 5 damage, then a random 5-Cost minion.
cards.KAR_076 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 5))
    summon_random_of_cost(g, me, 5)
  end,
}

-- Medivh's Valet: if you control a Secret, 3 damage (a target only then).
cards.KAR_092 = {
  glow = control_secret,
  target = { base = "any", when = control_secret },
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, 3)
    end
  end,
}

-- --- Paladin ------------------------------------------------------------------------------------

-- Nightbane Templar: if you're holding a Dragon, two 1/1 Whelps (the right one first).
cards.KAR_010 = {
  glow = holding_dragon,
  battlecry = function(g, me)
    if holding_dragon(g, me) then
      g.summon_right(me, "KAR_010a")
      local pos = g.board_pos(me)
      if pos then
        g.summon(g.ctrl(me), "KAR_010a", pos)
      end
    end
  end,
}

-- Ivory Knight: Discover a spell; restore Health to your hero equal to its printed Cost (the hand full: still).
cards.KAR_057 = {
  battlecry = function(g, me)
    discover(g, me, function(i)
      return i.type == "SPELL"
    end)
  end,
  on_choose = function(g, me, option)
    local p = g.ctrl(me)
    local c = g.card(option)
    g.add_to_hand(p, c)
    g.heal(me, g.hero(p), g.info(c).cost)
  end,
}

-- Silvermoon Portal: a minion +2/+2, then a random 2-Cost minion.
cards.KAR_077 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 2, 2)
    summon_random_of_cost(g, me, 2)
  end,
}

-- --- Priest -------------------------------------------------------------------------------------

-- Purify: silence a friendly minion, draw a card.
cards.KAR_013 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.silence(t)
    g.draw(g.ctrl(me))
  end,
}

-- Priest of the Feast: whenever you cast a spell, restore 3 Health to your hero.
cards.KAR_035 = on_my_spell(function(g, me)
  g.heal(me, g.hero(g.ctrl(me)), 3)
end)

-- Onyx Bishop: a random friendly minion that died this game (each death one chance), fresh, at the right end.
cards.KAR_204 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local e = g.pick(list.filter(g.graveyard(p), function(d)
      return g.died_pos(d) >= 0 and g.type(d) == "MINION"
    end))
    if e then
      g.summon(p, g.card(e))
    end
  end,
}

-- --- Rogue --------------------------------------------------------------------------------------

-- Swashburglar: a random class card of your opponent's class into your hand (none if the opponent has no class).
cards.KAR_069 = {
  battlecry = function(g, me)
    local cls = g.class(g.hero(g.enemy(me)))
    if not playable(cls) then
      return
    end
    local c = g.pick(pool(g, function(i)
      return i.class == cls and i.type ~= "CHAMPION" and i.type ~= "POWER"
    end))
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Ethereal Peddler: the cards in your hand of another class (not neutral, not your hero's class) cost (2) less.
cards.KAR_070 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local mine = g.class(g.hero(p))
    for _, e in ipairs(g.hand(p)) do
      local c = g.class(e)
      if c ~= "NEUTRAL" and c ~= "" and c ~= mine then
        g.enchant(e, { cost = -2 })
      end
    end
  end,
}

-- Deadly Fork: Deathrattle: a 3/2 Sharp Fork into your hand.
cards.KAR_094 = {
  deathrattle = function(g, me)
    g.add_to_hand(g.ctrl(me), "KAR_094a")
  end,
}

-- --- Shaman -------------------------------------------------------------------------------------

-- Wicked Witchdoctor: whenever you cast a spell, a random basic Totem (the same one may come again).
cards.KAR_021 = on_my_spell(function(g, me)
  g.summon_right(me, g.pick(BASIC_TOTEMS))
end)

-- Spirit Claws: +2 Attack while you have Spell Damage.
cards.KAR_063 = {
  aura = function(g, me)
    if g.spell_dmg(me, 0) > 0 then
      g.aura_add(me, 2, 0)
    end
  end,
}

-- Maelstrom Portal: 1 damage to all enemy minions, then a random 1-Cost minion.
cards.KAR_073 = {
  spell = function(g, me)
    local n = g.spell_dmg(me, 1)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.damage(me, m, n)
    end
    summon_random_of_cost(g, me, 1)
  end,
}

-- --- Warlock ------------------------------------------------------------------------------------

-- Malchezaar's Imp: whenever you discard a card, draw a card.
cards.KAR_089 = on_mine("discard", function(g, me)
  g.draw(g.ctrl(me))
end)

-- Silverware Golem: if you discard it, summon it (a fresh 3/3; a full board: nothing).
cards.KAR_205 = {
  hand = {
    discard = function(g, me, ev)
      if ev.entity == me then
        g.summon(g.ctrl(me), "KAR_205")
      end
    end,
  },
}

-- Kara Kazham!: a 1/1 Candle, a 2/2 Broom and a 3/3 Teapot.
cards.KAR_025 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, c in ipairs({ "KAR_025a", "KAR_025b", "KAR_025c" }) do
      g.summon(p, c)
    end
  end,
}

-- --- Warrior ------------------------------------------------------------------------------------

-- Protect the King!: a 1/1 Pawn with Taunt for each enemy minion.
cards.KAR_026 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, #g.minions(g.enemy(me)) do
      g.summon(p, "KAR_026t")
    end
  end,
}

-- Ironforge Portal: 4 Armor, then a random 4-Cost minion.
cards.KAR_091 = {
  spell = function(g, me)
    g.gain_armor(g.ctrl(me), 4)
    summon_random_of_cost(g, me, 4)
  end,
}

return cards
