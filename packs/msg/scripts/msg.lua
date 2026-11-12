-- Mean Streets of Gadgetzan (December 2016): the 132 cards and their tokens as at the release (patch 7.0.0.15590 of
-- 2016-11-29, two days before the release; hearthstone.wiki.gg and its card notes; docs/packs/api.md). The older sets'
-- cards are those packs' scripts, copied in by the recipe; the ones that changed by then are here too (patches 6.1.3 and
-- 6.2 of October 2016: Charge, Tuskarr Totemic, Yogg-Saron, the four Murlocs that now help only their own side, Ethereal
-- Peddler; and the cards whose random or Discovered cards may now be a tri-class card).
local cards = {}

-- --- helpers -----------------------------------------------------------------------------------

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local BASIC_TOTEMS = { "VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009" }
local SHEEP = "VAN_CS2_tk1"
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

-- A neutral card: not of a class, nor of several.
local function is_neutral(i)
  return i.class == "NEUTRAL" and not i.classes
end

local function has_kw(i, k)
  return list.any(i.keywords, function(x)
    return x == k
  end)
end

-- The collectible cards (of the pack's constructed sets) whose data pass ok.
local function pool(g, ok)
  return list.filter(g.collectible(), function(c)
    return ok(g.info(c))
  end)
end

local function not_hero(i)
  return i.type ~= "CHAMPION" and i.type ~= "POWER"
end

-- A random collectible card of the class (a tri-class card of it too), or nil.
local function random_class_card(g, cls, ok)
  return g.pick(pool(g, function(i)
    return not_hero(i) and of_class(i, cls) and (not ok or ok(i))
  end))
end

local function random_minion(g, ok)
  return g.pick(pool(g, function(i)
    return i.type == "MINION" and ok(i)
  end))
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

-- "Whenever you cast a spell" (before it resolves).
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

-- "If your deck has no duplicates": no two cards of p's deck have the same id (an empty deck has none).
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

local function highlander(g, me)
  return no_duplicates(g, g.ctrl(me))
end

-- The minions of p's hand (passing ok, if given).
local function hand_minions(g, p, ok)
  return list.filter(g.hand(p), function(e)
    return g.is_minion(e) and (not ok or ok(e))
  end)
end

-- "Give a random minion in your hand +a/+h" (ok: only such minions); "Grimy Goons" style.
local function buff_random_in_hand(g, p, a, h, ok)
  local e = g.pick(hand_minions(g, p, ok))
  if e then
    g.buff(e, a, h)
  end
  return e
end

local function buff_all_in_hand(g, p, a, h)
  for _, e in ipairs(hand_minions(g, p)) do
    g.buff(e, a, h)
  end
end

-- A death hook that summons card where me stood.
local function summon_here(g, me, card)
  local pos = g.died_pos(me)
  return g.summon(g.ctrl(me), card, pos >= 0 and pos or nil)
end

-- The minions of me's side and the other side, alive (not dying).
local function alive(g, list_)
  return list.filter(list_, function(m)
    return g.health(m) > 0 and not g.has(m, "TO_DESTROY")
  end)
end

-- Up to n different random items of a list (each one a g.random_alive pick when alive_only).
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

-- --- Jade Golems ------------------------------------------------------------------------------------------------------
-- Each player's count of Jade Golems summoned (tried: one that finds the board full still counts), the next one N/N,
-- costing min(N, 10), at most 30/30 (CFM_712_t01 … t30).

local function next_jade(g, p)
  return math.min(g.count(p, "JADE") + 1, 30)
end

local function jade_card(n)
  return string.format(n < 10 and "CFM_712_t0%d" or "CFM_712_t%d", n)
end

-- Summons p's next Jade Golem at pos (nil: the right end); returns it (nil on a full board).
local function jade(g, p, pos)
  local n = next_jade(g, p)
  g.add_count(p, "JADE")
  return g.summon(p, jade_card(n), pos)
end

local function jade_right(g, me)
  local n = next_jade(g, g.ctrl(me))
  g.add_count(g.ctrl(me), "JADE")
  return g.summon_right(me, jade_card(n))
end

-- The card text's {0} (the next Golem, "4/4") and {1} (English: "n" for "an 8/8", "an 11/11", "an 18/18").
local function jade_text(g, me)
  local n = next_jade(g, g.ctrl(me))
  return string.format("%d/%d", n, n), (n == 8 or n == 11 or n == 18) and "n" or ""
end

-- --- Discover (2016: the class cards four times as likely as the neutral ones; a tri-class card is a class card) ---

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

-- Discover a card whose data pass ok: the class's cards (tri-class ones of it too) and the neutral ones.
local function discover(g, me, ok)
  local cls = discover_class(g, me)
  local choices = {}
  for _, c in ipairs(g.collectible()) do
    local i = g.info(c)
    if not_hero(i) and ok(i) then
      if of_class(i, cls) then
        choices[#choices + 1] = { c, 4 }
      elseif is_neutral(i) then
        choices[#choices + 1] = { c, 1 }
      end
    end
  end
  offer(g, me, choices)
end

local function to_hand(g, me, option)
  g.add_to_hand(g.ctrl(me), g.card(option))
end

local function discover_battlecry(ok)
  return {
    battlecry = function(g, me)
      discover(g, me, ok)
    end,
    on_choose = to_hand,
  }
end

-- The tri-class Discovers (Kabal Courier, Lotus Agents, Grimestreet Informant): one card of each of the three classes
-- (a card of that class or a tri-class card of it; no neutral one), whatever the player's class.
local function discover_three(classes)
  return {
    battlecry = function(g, me)
      local p = g.ctrl(me)
      local taken = {}
      local opts = {}
      for _, cls in ipairs(classes) do
        local c = g.pick(pool(g, function(i)
          return not_hero(i) and of_class(i, cls) and not taken[i.id]
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

-- --- the game's counts and its start (rules.json player_hooks) -------------------------------------
-- One Night in Karazhan's (spells cast, Totems summoned, the order friendly minions died in; Prince Malchezaar after
-- the mulligan), Secrets played from the hand (Kabal Crystal Runner), and Patches the Pirate, who waits in the deck.

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

cards["player:msg"] = {
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
    play = function(g, me, ev)
      if ev.kind == "spell" and ev.secret and g.mine(me, ev) then
        g.add_count(g.ctrl(me), "SECRETS")
      end
    end,
    -- Patches the Pirate: after you play a Pirate (after its Battlecry), it comes from your deck (room needed)
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
      malchezaar(g, g.ctrl(me))
    end,
  },
}

-- --- older cards that changed by December 2016 ---------------------------------------------------------------------

-- Charge (6.1.3): give a friendly minion Charge; it can't attack heroes this turn.
cards.VAN_CS2_103 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.give_tag(t, "CHARGE")
    g.give_tag(t, "CANNOT_ATTACK_HEROES", true)
  end,
}

-- Tuskarr Totemic (6.1.3): a random basic Totem (one you have may come again).
cards.AT_046 = {
  battlecry = function(g, me)
    g.summon_right(me, g.pick(BASIC_TOTEMS))
  end,
}

-- Yogg-Saron, Hope's End: a random spell for each spell you cast this game (at most 30), random targets and choices;
-- it stops once Yogg-Saron is destroyed, Silenced, transformed or returned to the hand (6.1.3), and the spells'
-- Overload is its controller's (6.2).
local function yogg_on(g, me)
  return g.zone(me) == "PLAY" and not g.silenced(me) and g.health(me) > 0 and not g.has(me, "TO_DESTROY")
end
cards.OG_134 = {
  battlecry = function(g, me)
    local spells = pool(g, function(i)
      return i.type == "SPELL"
    end)
    for _ = 1, math.min(g.count(g.ctrl(me), "SPELLS"), 30) do
      if not yogg_on(g, me) then
        break
      end
      local s = g.pick(spells)
      if s then
        g.cast_random(me, s, true)
        g.resolve()
      end
    end
  end,
}

-- Grimscale Oracle (6.2): your other Murlocs have +1 Attack.
cards.VAN_EX1_508 = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "MURLOC" then
        g.aura_add(m, 1, 0)
      end
    end
  end,
}

-- Murloc Warleader (6.2): your other Murlocs have +2/+1.
cards.VAN_EX1_507 = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "MURLOC" then
        g.aura_add(m, 2, 1)
      end
    end
  end,
}

-- Coldlight Seer (6.2): your other Murlocs +2 Health.
cards.VAN_EX1_103 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "MURLOC" then
        g.buff(m, 0, 2)
      end
    end
  end,
}

-- Murloc Tidecaller (6.2): whenever you summon a Murloc, +1 Attack.
cards.VAN_EX1_509 = on_mine("summon", function(g, me, ev)
  if ev.entity ~= me and g.race(ev.entity) == "MURLOC" then
    g.buff(me, 1, 0)
  end
end)

-- Ethereal Peddler (6.2): the non-Rogue class cards in your hand cost (2) less (a tri-class card without Rogue too;
-- neutral cards, a made potion, not).
cards.KAR_070 = {
  battlecry = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      local i = g.info(g.card(e))
      if not is_neutral(i) and playable(i.classes and i.classes[1] or i.class) and not of_class(i, "ROGUE") then
        g.enchant(e, { cost = -2 })
      end
    end
  end,
}

-- The older cards whose random or Discovered cards may now be a tri-class card (a card of each of its classes).

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

-- Swashburglar: a random class card of your opponent's class (none if the opponent has no class).
cards.KAR_069 = {
  battlecry = function(g, me)
    local cls = g.class(g.hero(g.enemy(me)))
    local c = playable(cls) and random_class_card(g, cls)
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Undercity Huckster: Deathrattle: a random class card of your opponent's class.
cards.OG_330 = {
  deathrattle = function(g, me)
    local cls = g.class(g.hero(g.enemy(me)))
    local c = playable(cls) and random_class_card(g, cls)
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
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
    g.enchant(g.hero(p), { hooks = "ench:lock_and_load_msg", player = p, eot = true })
  end,
}
cards["ench:lock_and_load_msg"] = {
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
      return not_hero(i) and of_class(i, cls)
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

cards.LOE_006 = discover_battlecry(function(i) -- Museum Curator: a card with a Deathrattle
  return has_kw(i, "DEATHRATTLE")
end)
cards.LOE_029 = discover_battlecry(function(i) -- Jeweled Scarab: a 3-Cost card
  return i.cost == 3
end)
cards.LOE_115a = { -- Raven Idol: Discover a minion
  effect = function(g, me)
    discover(g, me, function(i)
      return i.type == "MINION"
    end)
  end,
}

-- A Light in the Darkness: Discover a minion; it gets +1/+1.
cards.OG_311 = {
  spell = function(g, me)
    discover(g, me, function(i)
      return i.type == "MINION"
    end)
  end,
  on_choose = function(g, me, option)
    local e = g.add_to_hand(g.ctrl(me), g.card(option))
    if e then
      g.buff(e, 1, 1)
    end
  end,
}

-- Journey Below: Discover a Deathrattle card.
cards.OG_072 = {
  spell = function(g, me)
    discover(g, me, function(i)
      return has_kw(i, "DEATHRATTLE")
    end)
  end,
  on_choose = to_hand,
}

-- --- Neutral ------------------------------------------------------------------------------------

-- Small-Time Buccaneer: +2 Attack while you have a weapon equipped.
cards.CFM_325 = {
  aura = function(g, me)
    if g.weapon(g.ctrl(me)) then
      g.aura_add(me, 2, 0)
    end
  end,
}

-- Weasel Tunneler: Deathrattle: shuffle this minion into your opponent's deck (a fresh one).
cards.CFM_095 = {
  deathrattle = function(g, me)
    g.add_to_deck(g.enemy(me), g.card(me))
  end,
}

-- Mistress of Mixtures: Deathrattle: restore 4 Health to both players.
cards.CFM_120 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    g.heal(me, g.hero(p), 4)
    g.heal(me, g.hero(g.opponent(p)), 4)
  end,
}

-- Blowgill Sniper: 1 damage.
cards.CFM_647 = {
  target = "any",
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, 1)
    end
  end,
}

-- Gadgetzan Socialite: restore 2 Health.
cards.CFM_659 = {
  target = "any",
  battlecry = function(g, me, t)
    if t then
      g.heal(me, t, 2)
    end
  end,
}

-- Kooky Chemist: swap a minion's Attack and Health.
cards.CFM_063 = {
  target = "minion",
  battlecry = function(g, me, t)
    if t then
      g.set_stats(t, g.health(t), g.atk(t))
    end
  end,
}

-- Hozen Healer: restore a minion to full Health (its maximum Health: as damage with Auchenai Soulpriest).
cards.CFM_067 = {
  target = "minion",
  battlecry = function(g, me, t)
    if t then
      g.heal(me, t, g.max_health(t))
    end
  end,
}

-- Red Mana Wyrm: whenever you cast a spell, +2 Attack.
cards.CFM_060 = on_my_spell(function(g, me)
  g.buff(me, 2, 0)
end)

-- Blubber Baron: while in your hand, whenever you summon a Battlecry minion (played or not), +1/+1.
cards.CFM_064 = {
  hand = {
    summon = function(g, me, ev)
      if g.mine(me, ev) and has_kw(g.info(g.card(ev.entity)), "BATTLECRY") then
        g.buff(me, 1, 1)
      end
    end,
  },
}

-- Fight Promoter: if you control a minion with 6 or more Health (itself too), draw two cards.
local function promoter(g, me)
  return list.any(g.minions(g.ctrl(me)), function(m)
    return g.health(m) >= 6
  end)
end
cards.CFM_328 = {
  glow = function(g, me)
    return promoter(g, me) or g.health(me) >= 6 -- (itself, made bigger in the hand)
  end,
  battlecry = function(g, me)
    if promoter(g, me) then
      g.draw(g.ctrl(me), 2)
    end
  end,
}

-- Sergeant Sally: Deathrattle: damage equal to her Attack to all enemy minions.
cards.CFM_341 = {
  deathrattle = function(g, me)
    local n = g.atk(me)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.damage(me, m, n)
    end
  end,
}

-- Finja, the Flying Star: whenever she attacks and kills a minion, 2 random Murlocs of your deck into play.
local function killed(g, d)
  return g.is_minion(d) and (g.zone(d) ~= "PLAY" or g.health(d) <= 0 or g.has(d, "TO_DESTROY"))
end
cards.CFM_344 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == me and killed(g, ev.defender) then
        local p = g.ctrl(me)
        for _ = 1, 2 do
          local e = g.pick(list.filter(g.deck(p), function(d)
            return g.is_minion(d) and g.race(d) == "MURLOC"
          end))
          if e and g.room(p) > 0 then
            g.summon_entity(e)
          end
        end
      end
    end,
  },
}

-- Fel Orc Soulfiend: at the start of your turn, 2 damage to itself.
cards.CFM_609 = on_mine("turn_start", function(g, me)
  g.damage(me, me, 2)
end)

-- Backstreet Leper: Deathrattle: 2 damage to the enemy hero.
cards.CFM_646 = {
  deathrattle = function(g, me)
    g.damage(me, g.hero(g.enemy(me)), 2)
  end,
}

-- Big-Time Racketeer: summon a 6/6 Ogre.
cards.CFM_648 = lib.summon_right("CFM_648t")

-- Naga Corsair: your weapon +1 Attack.
cards.CFM_651 = {
  battlecry = function(g, me)
    local w = g.weapon(g.ctrl(me))
    if w then
      g.buff(w, 1, 0)
    end
  end,
}

-- Second-Rate Bruiser: costs (2) less while your opponent has at least three minions.
cards.CFM_652 = {
  cost_mod = function(g, me)
    return #g.minions(g.enemy(me)) >= 3 and -2 or 0
  end,
}

-- Friendly Bartender: at the end of your turn, restore 1 Health to your hero.
cards.CFM_654 = on_mine("turn_end", function(g, me)
  g.heal(me, g.hero(g.ctrl(me)), 1)
end)

-- Toxic Sewer Ooze: your opponent's weapon loses 1 Durability.
cards.CFM_655 = {
  battlecry = function(g, me)
    local w = g.weapon(g.enemy(me))
    if w then
      g.add_tag(w, "DURABILITY", -1)
    end
  end,
}

-- Streetwise Investigator: enemy minions lose Stealth.
cards.CFM_656 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.erase_tag(m, "STEALTH")
    end
  end,
}

-- Backroom Bouncer: whenever a friendly minion dies, +1 Attack.
cards.CFM_658 = {
  on = {
    death = function(g, me, ev)
      if ev.minion and ev.entity ~= me and g.mine(me, ev) then
        g.buff(me, 1, 0)
      end
    end,
  },
}

-- Bomb Squad: 5 damage to an enemy minion; Deathrattle: 5 damage to your hero.
cards.CFM_667 = {
  target = "enemy_minion",
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, 5)
    end
  end,
  deathrattle = function(g, me)
    g.damage(me, g.hero(g.ctrl(me)), 5)
  end,
}

-- Doppelgangster: summon its two other versions, left and right of it, as copies of it (its stats and enchantments).
local GANGSTERS = { "CFM_668", "CFM_668t", "CFM_668t2" }
cards.CFM_668 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local others = list.filter(GANGSTERS, function(c)
      return c ~= g.card(me)
    end)
    local pos = g.board_pos(me)
    if not pos then
      return
    end
    local left = g.summon(p, others[1], pos)
    if left and g.zone(me) == "PLAY" then
      g.copy_minion(left, me)
    end
    pos = g.board_pos(me)
    local right = pos and g.summon(p, others[2], pos + 1)
    if right and g.zone(me) == "PLAY" then
      g.copy_minion(right, me)
    end
  end,
}
cards.CFM_668t = cards.CFM_668
cards.CFM_668t2 = cards.CFM_668

-- Burgly Bully: whenever your opponent casts a spell, a Coin into your hand.
cards.CFM_669 = {
  on = {
    play = function(g, me, ev)
      if lib.enemy_spell(g, me, ev) then
        g.add_to_hand(g.ctrl(me), COIN)
      end
    end,
  },
}

-- Mayor Noggenfogger: all targets are chosen randomly (both players' plays, powers and attacks: RANDOM_TARGETS).
cards.CFM_670 = {
  aura = function(g, me)
    for p = 0, 1 do
      g.aura_add(g.hero(p), 0, 0, { RANDOM_TARGETS = true })
    end
  end,
}

-- Madam Goya: a friendly minion goes into your deck, a random other minion of your deck takes its place (no Battlecry).
cards.CFM_672 = {
  target = "friendly_minion",
  battlecry = function(g, me, t)
    if not t then
      return
    end
    local p = g.ctrl(me)
    local e = g.pick(list.filter(g.deck(p), function(d)
      return g.is_minion(d)
    end))
    if not e then
      return
    end
    local pos = g.board_pos(t)
    local card = g.card(t)
    g.remove(t, "SETASIDE")
    g.add_to_deck(p, card)
    g.summon_entity(e, pos)
  end,
}

-- Spiked Hogrider: if an enemy minion has Taunt, Charge.
local function enemy_taunt(g, me)
  return list.any(g.minions(g.enemy(me)), function(m)
    return g.has(m, "TAUNT")
  end)
end
cards.CFM_688 = {
  glow = enemy_taunt,
  battlecry = function(g, me)
    if enemy_taunt(g, me) then
      g.give_tag(me, "CHARGE")
    end
  end,
}

-- Dirty Rat: your opponent summons a random minion from their hand (no Battlecry).
cards.CFM_790 = {
  battlecry = function(g, me)
    local foe = g.enemy(me)
    local e = g.pick(hand_minions(g, foe))
    if e and g.room(foe) > 0 then
      g.summon_entity(e)
    end
  end,
}

-- Wrathion: draw until you draw a card that isn't a Dragon (a burned card or an empty deck ends it too).
cards.CFM_806 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 60 do
      local d = g.draw(p)
      if #d == 0 or g.race(d[1]) ~= "DRAGON" then
        break
      end
    end
  end,
}

-- Auctionmaster Beardo: after you cast a spell, your Hero Power can be used again.
cards.CFM_807 = on_mine("after_spell", function(g, me)
  g.erase_tag(g.power(g.ctrl(me)), "USED")
end)

-- Genzo, the Shark: whenever it attacks, both players draw until they have 3 cards.
cards.CFM_808 = {
  on = {
    attack = function(g, me, ev)
      if ev.attacker == me then
        local p = g.ctrl(me)
        for _, q in ipairs({ p, g.opponent(p) }) do
          local n = 3 - #g.hand(q)
          if n > 0 then
            g.draw(q, n)
          end
        end
      end
    end,
  },
}

-- Tanaris Hogchopper: if your opponent's hand is empty, Charge.
local function foe_hand_empty(g, me)
  return #g.hand(g.enemy(me)) == 0
end
cards.CFM_809 = {
  glow = foe_hand_empty,
  battlecry = function(g, me)
    if foe_hand_empty(g, me) then
      g.give_tag(me, "CHARGE")
    end
  end,
}

-- Leatherclad Hogleader: if your opponent has 6 or more cards in hand, Charge.
local function foe_hand_six(g, me)
  return #g.hand(g.enemy(me)) >= 6
end
cards.CFM_810 = {
  glow = foe_hand_six,
  battlecry = function(g, me)
    if foe_hand_six(g, me) then
      g.give_tag(me, "CHARGE")
    end
  end,
}

-- Daring Reporter: whenever your opponent draws a card, +1/+1.
cards.CFM_851 = {
  on = {
    draw = function(g, me, ev)
      if not g.mine(me, ev) then
        g.buff(me, 1, 1)
      end
    end,
  },
}

-- Defias Cleaner: Silence a minion with Deathrattle.
cards.CFM_855 = {
  target = {
    base = "minion",
    filter = function(g, me, t)
      return not g.silenced(t) and has_kw(g.info(g.card(t)), "DEATHRATTLE")
    end,
  },
  battlecry = function(g, me, t)
    if t then
      g.silence(t)
    end
  end,
}

-- Wind-up Burglebot: whenever it attacks a minion and survives, draw a card.
cards.CFM_025 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == me and g.is_minion(ev.defender) and g.health(me) > 0 and not g.has(me, "TO_DESTROY") then
        g.draw(g.ctrl(me))
      end
    end,
  },
}

-- --- the tri-class cards ---------------------------------------------------------------------------------------------

cards.CFM_649 = discover_three({ "MAGE", "PRIEST", "WARLOCK" }) -- Kabal Courier
cards.CFM_852 = discover_three({ "DRUID", "ROGUE", "SHAMAN" }) -- Lotus Agents
cards.CFM_321 = discover_three({ "HUNTER", "PALADIN", "WARRIOR" }) -- Grimestreet Informant

-- Kabal Chemist: a random Potion (the ten Potions of the three Kabal classes).
local POTIONS = { "CFM_021", "CFM_065", "CFM_620", "CFM_603", "CFM_604", "CFM_661", "CFM_662", "CFM_094", "CFM_608",
  "CFM_611" }
cards.CFM_619 = {
  battlecry = function(g, me)
    g.add_to_hand(g.ctrl(me), g.pick(POTIONS))
  end,
}

-- Grimestreet Smuggler: a random minion in your hand +1/+1.
cards.CFM_853 = {
  battlecry = function(g, me)
    buff_random_in_hand(g, g.ctrl(me), 1, 1)
  end,
}

-- Don Han'Cho: a random minion in your hand +5/+5.
cards.CFM_685 = {
  battlecry = function(g, me)
    buff_random_in_hand(g, g.ctrl(me), 5, 5)
  end,
}

-- Jade Spirit: a Jade Golem.
cards.CFM_715 = {
  text = jade_text,
  battlecry = function(g, me)
    jade_right(g, me)
  end,
}

-- Aya Blackpaw: Battlecry and Deathrattle: a Jade Golem.
cards.CFM_902 = {
  text = jade_text,
  battlecry = function(g, me)
    jade_right(g, me)
  end,
  deathrattle = function(g, me)
    local pos = g.died_pos(me)
    jade(g, g.ctrl(me), pos >= 0 and pos or nil)
  end,
}

-- Kazakus: if your deck has no duplicates, make a custom spell: a cost (1, 5 or 10), then two of three effects of that
-- cost, the second from the rest (the first one taken out). Only its player sees the choices (g.create).
-- The effects: what each does, in the order a potion does them (Heart of Fire first, then Felbloom and Mystic Wool,
-- the summons, Goldthorn last), by effect id.
local function damage_all(g, me, n)
  local d = g.spell_dmg(me, n)
  for _, m in ipairs(g.all_minions()) do
    g.damage(me, m, d)
  end
end
local function freeze_random(g, me, k)
  local left = alive(g, g.minions(g.enemy(me)))
  for _, m in ipairs(pick_n(g, left, k)) do
    g.freeze(m)
  end
end
local function add_demons(g, me, k)
  local demons = pool(g, function(i)
    return i.type == "MINION" and i.race == "DEMON"
  end)
  for _ = 1, k do
    g.add_to_hand(g.ctrl(me), g.pick(demons))
  end
end
local function ichor(g, me, k)
  local p = g.ctrl(me)
  local dead = list.filter(g.graveyard(p), function(e)
    return g.died_pos(e) >= 0 and g.type(e) == "MINION"
  end)
  for _, e in ipairs(pick_n(g, dead, k)) do
    g.summon(p, g.card(e))
  end
end
local function goldthorn(g, me, n)
  for _, m in ipairs(g.minions(g.ctrl(me))) do
    g.buff(m, 0, n)
  end
end
local EFFECTS = {
  -- { id, order, needs a target, what it does }
  { "CFM_621t2", 1, true, function(g, me, t) g.damage(me, t, g.spell_dmg(me, 3)) end },
  { "CFM_621t16", 1, true, function(g, me, t) g.damage(me, t, g.spell_dmg(me, 5)) end },
  { "CFM_621t25", 1, true, function(g, me, t) g.damage(me, t, g.spell_dmg(me, 8)) end },
  { "CFM_621t4", 2, false, function(g, me) damage_all(g, me, 2) end },
  { "CFM_621t18", 2, false, function(g, me) damage_all(g, me, 4) end },
  { "CFM_621t33", 2, false, function(g, me) damage_all(g, me, 6) end },
  { "CFM_621t21", 3, false, function(g, me)
    local m = g.random_alive(g.minions(g.enemy(me)))
    if m then
      g.transform(m, "CFM_621_m5")
    end
  end },
  { "CFM_621t29", 3, false, function(g, me)
    for _, m in ipairs(g.all_minions()) do
      g.transform(m, "CFM_621_m5")
    end
  end },
  { "CFM_621t5", 4, false, function(g, me) freeze_random(g, me, 1) end },
  { "CFM_621t19", 4, false, function(g, me) freeze_random(g, me, 2) end },
  { "CFM_621t27", 4, false, function(g, me) freeze_random(g, me, 3) end },
  { "CFM_621t3", 5, false, function(g, me) g.gain_armor(g.ctrl(me), 4) end },
  { "CFM_621t17", 5, false, function(g, me) g.gain_armor(g.ctrl(me), 7) end },
  { "CFM_621t26", 5, false, function(g, me) g.gain_armor(g.ctrl(me), 10) end },
  { "CFM_621t8", 6, false, function(g, me) g.draw(g.ctrl(me), 1) end },
  { "CFM_621t22", 6, false, function(g, me) g.draw(g.ctrl(me), 2) end },
  { "CFM_621t30", 6, false, function(g, me) g.draw(g.ctrl(me), 3) end },
  { "CFM_621t9", 7, false, function(g, me) add_demons(g, me, 1) end },
  { "CFM_621t23", 7, false, function(g, me) add_demons(g, me, 2) end },
  { "CFM_621t31", 7, false, function(g, me) add_demons(g, me, 3) end },
  { "CFM_621t10", 8, false, function(g, me) g.summon(g.ctrl(me), "CFM_621_m4") end },
  { "CFM_621t20", 8, false, function(g, me) g.summon(g.ctrl(me), "CFM_621_m2") end },
  { "CFM_621t28", 8, false, function(g, me) g.summon(g.ctrl(me), "CFM_621_m3") end },
  { "CFM_621t37", 9, false, function(g, me) ichor(g, me, 1) end },
  { "CFM_621t38", 9, false, function(g, me) ichor(g, me, 2) end },
  { "CFM_621t39", 9, false, function(g, me) ichor(g, me, 3) end },
  { "CFM_621t6", 10, false, function(g, me) goldthorn(g, me, 2) end },
  { "CFM_621t24", 10, false, function(g, me) goldthorn(g, me, 4) end },
  { "CFM_621t32", 10, false, function(g, me) goldthorn(g, me, 6) end },
}
-- The effects of each cost (1: no Mystic Wool), and the potion it makes.
local KAZ_COSTS = {
  CFM_621t11 = { cost = 1, potion = "CFM_621t", effects = { "CFM_621t2", "CFM_621t3", "CFM_621t4", "CFM_621t5",
    "CFM_621t6", "CFM_621t8", "CFM_621t9", "CFM_621t10", "CFM_621t37" } },
  CFM_621t12 = { cost = 5, potion = "CFM_621t14", effects = { "CFM_621t16", "CFM_621t17", "CFM_621t18", "CFM_621t19",
    "CFM_621t20", "CFM_621t21", "CFM_621t22", "CFM_621t23", "CFM_621t24", "CFM_621t38" } },
  CFM_621t13 = { cost = 10, potion = "CFM_621t15", effects = { "CFM_621t25", "CFM_621t26", "CFM_621t27", "CFM_621t28",
    "CFM_621t29", "CFM_621t30", "CFM_621t31", "CFM_621t32", "CFM_621t33", "CFM_621t39" } },
}
local function effect_index(id)
  for i, x in ipairs(EFFECTS) do
    if x[1] == id then
      return i
    end
  end
  return 0
end

-- Offers three effects of the cost (the option card `kind`: Lesser, Greater, Superior Potion) without `first` (an
-- EFFECTS index, 0: none chosen yet); each option keeps which (KAZ_KIND: 1–3, KAZ_FIRST).
local KINDS = { "CFM_621t11", "CFM_621t12", "CFM_621t13" }
local function offer_effects(g, me, kind, first)
  local p = g.ctrl(me)
  local left = list.filter(KAZ_COSTS[KINDS[kind]].effects, function(id)
    return effect_index(id) ~= first
  end)
  local opts = {}
  for _, id in ipairs(pick_n(g, left, 3)) do
    local o = g.create(p, id)
    g.set_tag(o, "KAZ_KIND", kind)
    g.set_tag(o, "KAZ_FIRST", first)
    opts[#opts + 1] = o
  end
  g.request_choice(me, opts)
end

cards.CFM_621 = {
  glow = highlander,
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if no_duplicates(g, p) then
      local opts = {}
      for _, c in ipairs(KINDS) do
        opts[#opts + 1] = g.create(p, c)
      end
      g.request_choice(me, opts)
    end
  end,
  on_choose = function(g, me, option)
    local c = g.card(option)
    for kind, k in ipairs(KINDS) do
      if c == k then
        offer_effects(g, me, kind, 0)
        return
      end
    end
    local kind, first, now = g.tag(option, "KAZ_KIND"), g.tag(option, "KAZ_FIRST"), effect_index(c)
    if kind < 1 or now == 0 then
      return
    end
    if first == 0 then
      offer_effects(g, me, kind, now)
      return
    end
    local potion = g.add_to_hand(g.ctrl(me), KAZ_COSTS[KINDS[kind]].potion)
    if potion then
      local a, b = first, now
      if EFFECTS[b][2] < EFFECTS[a][2] then
        a, b = b, a
      end
      g.set_tag(potion, "POTION_A", a)
      g.set_tag(potion, "POTION_B", b)
    end
  end,
}

-- A Kazakus Potion (1, 5 or 10 mana): its two effects in order; a target when one of them deals damage to one.
local function potion_effects(g, me)
  local out = {}
  for _, k in ipairs({ "POTION_A", "POTION_B" }) do
    local i = g.tag(me, k)
    if EFFECTS[i] then
      out[#out + 1] = EFFECTS[i]
    end
  end
  return out
end
cards.CFM_621t = {
  target = {
    base = "any",
    when = function(g, me)
      return list.any(potion_effects(g, me), function(x)
        return x[3]
      end)
    end,
  },
  text = function(g, me)
    local e = potion_effects(g, me)
    return e[1] and e[1][1] or "", e[2] and e[2][1] or ""
  end,
  spell = function(g, me, t)
    for _, x in ipairs(potion_effects(g, me)) do
      x[4](g, me, t)
    end
  end,
}

-- --- Druid --------------------------------------------------------------------------------------

-- Kun the Forgotten King: Choose One - 10 Armor; or refresh your Mana Crystals (the Overloaded ones stay locked).
cards.CFM_308 = { choose_one = { "CFM_308a", "CFM_308b" } }
cards.CFM_308a = {
  effect = function(g, me)
    g.gain_armor(g.ctrl(me), 10)
  end,
}
cards.CFM_308b = {
  effect = function(g, me)
    local p = g.ctrl(me)
    g.set_mana(p, math.max(g.mana(p), g.max_mana(p) - g.locked(p)))
  end,
}

-- Jade Behemoth: a Jade Golem.
cards.CFM_343 = {
  text = jade_text,
  battlecry = function(g, me)
    jade_right(g, me)
  end,
}

-- Jade Idol: Choose One - a Jade Golem; or shuffle 3 copies of this card into your deck.
cards.CFM_602 = { choose_one = { "CFM_602a", "CFM_602b" }, text = jade_text }
cards.CFM_602a = {
  text = jade_text,
  effect = function(g, me)
    jade(g, g.ctrl(me))
  end,
}
cards.CFM_602b = {
  effect = function(g, me)
    for _ = 1, 3 do
      g.add_to_deck(g.ctrl(me), "CFM_602")
    end
  end,
}

-- Jade Blossom: a Jade Golem, then an empty Mana Crystal.
cards.CFM_713 = {
  text = jade_text,
  spell = function(g, me)
    local p = g.ctrl(me)
    jade(g, p)
    g.gain_mana(p, 1, true)
  end,
}

-- Mark of the Lotus: your minions +1/+1.
cards.CFM_614 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.buff(m, 1, 1)
    end
  end,
}

-- Pilfered Power: an empty Mana Crystal for each friendly minion (at full crystals: Excess Mana, as Wild Growth).
cards.CFM_616 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local n = #g.minions(p)
    if g.max_mana(p) >= g.rule("max_mana") then
      g.add_to_hand(p, "CS2_013t")
    elseif n > 0 then
      g.gain_mana(p, n, true)
    end
  end,
}

-- Celestial Dreamer: if a friendly minion (itself too) has 5 or more Attack, +2/+2.
local function strong_friend(g, me)
  return list.any(g.minions(g.ctrl(me)), function(m)
    return g.atk(m) >= 5
  end)
end
cards.CFM_617 = {
  glow = function(g, me)
    return strong_friend(g, me) or g.atk(me) >= 5 -- (itself, made bigger in the hand)
  end,
  battlecry = function(g, me)
    if strong_friend(g, me) then
      g.buff(me, 2, 2)
    end
  end,
}

-- Lunar Visions: draw 2 cards; the minions drawn cost (2) less.
cards.CFM_811 = {
  spell = function(g, me)
    for _, e in ipairs(g.draw(g.ctrl(me), 2)) do
      if g.is_minion(e) and g.zone(e) == "HAND" then
        g.enchant(e, { cost = -2 })
      end
    end
  end,
}

-- Virmen Sensei: a friendly Beast +2/+2.
cards.CFM_816 = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t)
      return g.race(t) == "BEAST"
    end,
  },
  battlecry = function(g, me, t)
    if t then
      g.buff(t, 2, 2)
    end
  end,
}

-- --- Hunter -------------------------------------------------------------------------------------

-- Hidden Cache: after your opponent plays a minion, a random minion in your hand +2/+2 (none there: it waits).
cards.CFM_026 = {
  secret = {
    event = "after_summon",
    cond = function(g, me, ev)
      return ev.played and ev.player ~= g.ctrl(me) and #hand_minions(g, g.ctrl(me)) > 0
    end,
    effect = function(g, me)
      buff_random_in_hand(g, g.ctrl(me), 2, 2)
    end,
  },
}

-- Alleycat: summon a 1/1 Cat.
cards.CFM_315 = lib.summon_right("CFM_315t")

-- Rat Pack: Deathrattle: a 1/1 Rat for each point of its Attack.
cards.CFM_316 = {
  deathrattle = function(g, me)
    for _ = 1, g.atk(me) do
      if not summon_here(g, me, "CFM_316t") then
        break
      end
    end
  end,
}

-- Knuckles: after it attacks a minion, it also hits the enemy hero.
cards.CFM_333 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == me and g.is_minion(ev.defender) then
        g.damage(me, g.hero(g.enemy(me)), g.atk(me))
      end
    end,
  },
}

-- Smuggler's Crate: a random Beast in your hand +2/+2.
cards.CFM_334 = {
  spell = function(g, me)
    buff_random_in_hand(g, g.ctrl(me), 2, 2, function(e)
      return g.race(e) == "BEAST"
    end)
  end,
}

-- Dispatch Kodo: damage equal to its Attack.
cards.CFM_335 = {
  target = "any",
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, g.atk(me))
    end
  end,
}

-- Shaky Zipgunner: Deathrattle: a random minion in your hand +2/+2.
cards.CFM_336 = {
  deathrattle = function(g, me)
    buff_random_in_hand(g, g.ctrl(me), 2, 2)
  end,
}

-- Piranha Launcher: after your hero attacks, a 1/1 Piranha.
cards.CFM_337 = {
  on = {
    after_attack = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.attacker == g.hero(p) then
        g.summon(p, "CFM_337t")
      end
    end,
  },
}

-- Trogg Beastrager: a random Beast in your hand +1/+1.
cards.CFM_338 = {
  battlecry = function(g, me)
    buff_random_in_hand(g, g.ctrl(me), 1, 1, function(e)
      return g.race(e) == "BEAST"
    end)
  end,
}

-- --- Mage ---------------------------------------------------------------------------------------

-- Freezing Potion: Freeze an enemy.
cards.CFM_021 = {
  target = "enemy_char",
  spell = function(g, me, t)
    g.freeze(t)
  end,
}

-- Volcanic Potion: 2 damage to all minions.
cards.CFM_065 = {
  spell = function(g, me)
    damage_all(g, me, 2)
  end,
}

-- Kabal Lackey: the next Secret you play this turn costs (0).
cards.CFM_066 = {
  battlecry = function(g, me)
    g.add_cost_mod(g.ctrl(me), { kind = "secret", set = 0, ["until"] = "use" })
  end,
}

-- Potion of Polymorph: after your opponent plays a minion (its Battlecry done), it becomes a 1/1 Sheep.
cards.CFM_620 = {
  secret = {
    event = "after_summon",
    cond = function(g, me, ev)
      return ev.played and ev.player ~= g.ctrl(me) and g.zone(ev.entity) == "PLAY" and g.health(ev.entity) > 0
        and not g.has(ev.entity, "TO_DESTROY")
    end,
    effect = function(g, me, ev)
      g.transform(ev.entity, SHEEP)
    end,
  },
}

-- Greater Arcane Missiles: three missiles of 3 damage at random enemies (each one at a living one).
cards.CFM_623 = {
  spell = function(g, me)
    local n = g.spell_dmg(me, 3)
    for _ = 1, 3 do
      local t = g.random_alive(g.chars(g.enemy(me)))
      if t then
        g.damage(me, t, n)
      end
    end
  end,
}

-- Manic Soulcaster: a copy of a friendly minion (its card) shuffled into your deck.
cards.CFM_660 = {
  target = "friendly_minion",
  battlecry = function(g, me, t)
    if t then
      g.add_to_deck(g.ctrl(me), g.card(t))
    end
  end,
}

-- Cryomancer: +2/+2 if an enemy is Frozen.
local function enemy_frozen(g, me)
  return list.any(g.chars(g.enemy(me)), function(c)
    return g.has(c, "FROZEN")
  end)
end
cards.CFM_671 = {
  glow = enemy_frozen,
  battlecry = function(g, me)
    if enemy_frozen(g, me) then
      g.buff(me, 2, 2)
    end
  end,
}

-- Inkmaster Solia: if your deck has no duplicates, the next spell you cast this turn costs (0).
cards.CFM_687 = {
  glow = highlander,
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if no_duplicates(g, p) then
      g.add_cost_mod(p, { kind = "spell", set = 0, ["until"] = "use" })
    end
  end,
}

-- Kabal Crystal Runner: costs (2) less for each Secret you've played this game.
cards.CFM_760 = {
  cost_mod = function(g, me)
    return -2 * g.count(g.ctrl(me), "SECRETS")
  end,
}

-- --- Paladin ------------------------------------------------------------------------------------

-- Grimestreet Protector: give adjacent minions Divine Shield.
cards.CFM_062 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.adjacent(me)) do
      g.give_tag(m, "DIVINE_SHIELD")
    end
  end,
}

-- Smuggler's Run: all minions in your hand +1/+1.
cards.CFM_305 = {
  spell = function(g, me)
    buff_all_in_hand(g, g.ctrl(me), 1, 1)
  end,
}

-- Grimestreet Enforcer: at the end of your turn, all minions in your hand +1/+1.
cards.CFM_639 = on_mine("turn_end", function(g, me)
  buff_all_in_hand(g, g.ctrl(me), 1, 1)
end)

-- Grimscale Chum: a random Murloc in your hand +1/+1.
cards.CFM_650 = {
  battlecry = function(g, me)
    buff_random_in_hand(g, g.ctrl(me), 1, 1, function(e)
      return g.race(e) == "MURLOC"
    end)
  end,
}

-- Grimestreet Outfitter: all minions in your hand +1/+1.
cards.CFM_753 = {
  battlecry = function(g, me)
    buff_all_in_hand(g, g.ctrl(me), 1, 1)
  end,
}

-- Meanstreet Marshal: Deathrattle: if it has 2 or more Attack, draw a card.
cards.CFM_759 = {
  deathrattle = function(g, me)
    if g.atk(me) >= 2 then
      g.draw(g.ctrl(me))
    end
  end,
}

-- Wickerflame Burnbristle: damage it deals also heals your hero (as much; not while your hero is dead).
cards.CFM_815 = {
  on = {
    damage = function(g, me, ev)
      local h = g.hero(g.ctrl(me))
      if ev.source == me and ev.amount > 0 and g.health(h) > 0 then
        g.heal(me, h, ev.amount)
      end
    end,
  },
}

-- Getaway Kodo: when a friendly minion dies, it returns to your hand (a fresh card).
cards.CFM_800 = {
  secret = {
    event = "death",
    cond = function(g, me, ev)
      return ev.minion and ev.player == g.ctrl(me)
    end,
    effect = function(g, me, ev)
      g.add_to_hand(g.ctrl(me), ev.card)
    end,
  },
}

-- Small-Time Recruits: draw three 1-Cost minions (printed Cost) from your deck.
cards.CFM_905 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 3 do
      local e = g.pick(list.filter(g.deck(p), function(d)
        return g.is_minion(d) and g.info(g.card(d)).cost == 1
      end))
      if e then
        g.draw_entity(p, e)
      end
    end
  end,
}

-- --- Priest -------------------------------------------------------------------------------------

-- Raza the Chained: if your deck has no duplicates, your Hero Power costs (0) this game (a new one too).
cards.CFM_020 = {
  glow = highlander,
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if no_duplicates(g, p) then
      g.add_cost_mod(p, { kind = "power", set = 0, lasting = true })
    end
  end,
}

-- Potion of Madness: control an enemy minion with 2 or less Attack until the end of the turn (it may attack).
cards.CFM_603 = {
  target = {
    base = "enemy_minion",
    filter = function(g, me, t)
      return g.atk(t) <= 2
    end,
  },
  can_play = lib.room,
  spell = function(g, me, t)
    local owner = g.ctrl(t)
    g.take_control(t, g.ctrl(me))
    g.erase_tag(t, "EXHAUSTED")
    g.enchant(t, { hooks = "ench:shadow_madness", player = owner })
  end,
}

-- Greater Healing Potion: restore 12 Health to a friendly character.
cards.CFM_604 = {
  target = "friendly_char",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 12))
  end,
}

-- Drakonid Operative: if you're holding a Dragon, Discover a copy of a card of your opponent's deck (three different
-- cards; only you see them).
cards.CFM_605 = {
  glow = holding_dragon,
  battlecry = function(g, me)
    if not holding_dragon(g, me) then
      return
    end
    local p = g.ctrl(me)
    local seen, ids = {}, {}
    for _, e in ipairs(g.deck(g.enemy(me))) do
      local c = g.card(e)
      if not seen[c] then
        seen[c] = true
        ids[#ids + 1] = c
      end
    end
    local opts = {}
    for _, c in ipairs(pick_n(g, ids, 3)) do
      opts[#opts + 1] = g.create(p, c)
    end
    if #opts > 0 then
      g.request_choice(me, opts)
    end
  end,
  on_choose = to_hand,
}

-- Mana Geode: whenever it is healed, a 2/2 Crystal.
cards.CFM_606 = {
  on = {
    heal = function(g, me, ev)
      if ev.target == me and ev.amount > 0 then
        g.summon_right(me, "CFM_606t")
      end
    end,
  },
}

-- Kabal Talonpriest: a friendly minion +3 Health.
cards.CFM_626 = {
  target = "friendly_minion",
  battlecry = function(g, me, t)
    if t then
      g.buff(t, 0, 3)
    end
  end,
}

-- Kabal Songstealer: Silence a minion.
cards.CFM_657 = {
  target = "minion",
  battlecry = function(g, me, t)
    if t then
      g.silence(t)
    end
  end,
}

-- Pint-Size Potion: enemy minions -3 Attack this turn.
cards.CFM_661 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.buff(m, -3, 0, true)
    end
  end,
}

-- Dragonfire Potion: 5 damage to all minions except Dragons.
cards.CFM_662 = {
  spell = function(g, me)
    local d = g.spell_dmg(me, 5)
    for _, m in ipairs(g.all_minions()) do
      if g.race(m) ~= "DRAGON" then
        g.damage(me, m, d)
      end
    end
  end,
}

-- --- Rogue --------------------------------------------------------------------------------------

-- Luckydo Buccaneer: if your weapon has at least 3 Attack, +4/+4.
local function big_weapon(g, me)
  local w = g.weapon(g.ctrl(me))
  return w ~= nil and g.atk(w) >= 3
end
cards.CFM_342 = {
  glow = big_weapon,
  battlecry = function(g, me)
    if big_weapon(g, me) then
      g.buff(me, 4, 4)
    end
  end,
}

-- Counterfeit Coin: 1 Mana Crystal this turn only.
cards.CFM_630 = {
  spell = function(g, me)
    g.add_mana(g.ctrl(me), 1)
  end,
}

-- Lotus Assassin: whenever it attacks and kills a minion, it gains Stealth.
cards.CFM_634 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == me and killed(g, ev.defender) and g.zone(me) == "PLAY" then
        g.give_tag(me, "STEALTH")
      end
    end,
  },
}

-- Shaku, the Collector: whenever it attacks, a random card of your opponent's class into your hand.
cards.CFM_781 = {
  on = {
    attack = function(g, me, ev)
      if ev.attacker == me then
        local cls = g.class(g.hero(g.enemy(me)))
        local c = playable(cls) and random_class_card(g, cls)
        if c then
          g.add_to_hand(g.ctrl(me), c)
        end
      end
    end,
  },
}

-- Jade Shuriken: 2 damage; Combo: a Jade Golem too.
cards.CFM_690 = {
  text = jade_text,
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
  end,
  combo = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
    jade(g, g.ctrl(me))
  end,
}

-- Jade Swarmer: Deathrattle: a Jade Golem.
cards.CFM_691 = {
  text = jade_text,
  deathrattle = function(g, me)
    local pos = g.died_pos(me)
    jade(g, g.ctrl(me), pos >= 0 and pos or nil)
  end,
}

-- Gadgetzan Ferryman: Combo: return a friendly minion to your hand.
cards.CFM_693 = {
  combo_target = "friendly_minion",
  combo = function(g, me, t)
    if t then
      g.return_to_hand(t)
    end
  end,
}

-- Shadow Sensei: a Stealthed minion +2/+2.
cards.CFM_694 = {
  target = {
    base = "minion",
    filter = function(g, me, t)
      return g.has(t, "STEALTH")
    end,
  },
  battlecry = function(g, me, t)
    if t then
      g.buff(t, 2, 2)
    end
  end,
}

-- --- Shaman -------------------------------------------------------------------------------------

-- Jinyu Waterspeaker: restore 6 Health.
cards.CFM_061 = {
  target = "any",
  battlecry = function(g, me, t)
    if t then
      g.heal(me, t, 6)
    end
  end,
}

-- Call in the Finishers: four 1/1 Murlocs.
cards.CFM_310 = {
  spell = function(g, me)
    for _ = 1, 4 do
      g.summon(g.ctrl(me), "CFM_310t")
    end
  end,
}

-- Jade Chieftain: a Jade Golem with Taunt.
cards.CFM_312 = {
  text = jade_text,
  battlecry = function(g, me)
    local m = jade_right(g, me)
    if m then
      g.give_tag(m, "TAUNT")
    end
  end,
}

-- Finders Keepers: Discover a card with Overload.
cards.CFM_313 = {
  spell = function(g, me)
    discover(g, me, function(i)
      return has_kw(i, "OVERLOAD")
    end)
  end,
  on_choose = to_hand,
}

-- White Eyes: Deathrattle: 'The Storm Guardian' shuffled into your deck.
cards.CFM_324 = {
  deathrattle = function(g, me)
    g.add_to_deck(g.ctrl(me), "CFM_324t")
  end,
}

-- Devolve: each enemy minion becomes a random minion costing (1) less than its printed Cost (the nearest cost that has
-- one; a 0-Cost one: another 0-Cost one).
local function minion_near_cost(g, n)
  for d = 0, 30 do
    for _, c in ipairs({ n - d, n + d }) do
      if c >= 0 then
        local m = random_minion(g, function(i)
          return i.cost == c
        end)
        if m then
          return m
        end
      end
    end
  end
end
cards.CFM_696 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      local want = math.max(g.info(g.card(m)).cost - 1, 0)
      local c = minion_near_cost(g, want)
      if c then
        g.transform(m, c)
      end
    end
  end,
}

-- Lotus Illusionist: after it attacks a hero, it becomes a random 6-Cost minion.
cards.CFM_697 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == me and g.is_champion(ev.defender) and g.zone(me) == "PLAY" and g.health(me) > 0 then
        local c = random_minion(g, function(i)
          return i.cost == 6
        end)
        if c then
          g.transform(me, c)
        end
      end
    end,
  },
}

-- Jade Lightning: 4 damage, then a Jade Golem.
cards.CFM_707 = {
  text = jade_text,
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
    jade(g, g.ctrl(me))
  end,
}

-- Jade Claws: a Jade Golem.
cards.CFM_717 = {
  text = jade_text,
  battlecry = function(g, me)
    jade(g, g.ctrl(me))
  end,
}

-- --- Warlock ------------------------------------------------------------------------------------

-- Felfire Potion: 5 damage to all characters.
cards.CFM_094 = {
  spell = function(g, me)
    local d = g.spell_dmg(me, 5)
    for _, c in ipairs(g.all_chars()) do
      g.damage(me, c, d)
    end
  end,
}

-- Blastcrystal Potion: destroy a minion and one of your Mana Crystals (an empty one first).
cards.CFM_608 = {
  target = "minion",
  spell = function(g, me, t)
    g.destroy(t)
    local p = g.ctrl(me)
    local max = g.max_mana(p)
    if max > 0 then
      g.set_mana(p, math.min(g.mana(p), max - 1), max - 1)
    end
  end,
}

-- Crystalweaver: your Demons +1/+1.
cards.CFM_610 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "DEMON" then
        g.buff(m, 1, 1)
      end
    end
  end,
}

-- Bloodfury Potion: a minion +3 Attack; a Demon +3 Health too.
cards.CFM_611 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 3, g.race(t) == "DEMON" and 3 or 0)
  end,
}

-- Kabal Trafficker: at the end of your turn, a random Demon into your hand.
cards.CFM_663 = on_mine("turn_end", function(g, me)
  add_demons(g, me, 1)
end)

-- Seadevil Stinger: the next Murloc you play this turn costs Health instead of Mana.
cards.CFM_699 = {
  battlecry = function(g, me)
    g.add_cost_mod(g.ctrl(me), { kind = "minion", race = "MURLOC", health = true, ["until"] = "use" })
  end,
}

-- Krul the Unshackled: if your deck has no duplicates, summon all Demons from your hand (left to right, while there is
-- room).
cards.CFM_750 = {
  glow = highlander,
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if not no_duplicates(g, p) then
      return
    end
    for _, e in ipairs(hand_minions(g, p, function(e)
      return g.race(e) == "DEMON"
    end)) do
      if g.room(p) <= 0 then
        break
      end
      g.summon_entity(e)
    end
  end,
}

-- Abyssal Enforcer: 3 damage to all other characters.
cards.CFM_751 = {
  battlecry = function(g, me)
    for _, c in ipairs(g.all_chars()) do
      if c ~= me then
        g.damage(me, c, 3)
      end
    end
  end,
}

-- Unlicensed Apothecary: whenever you summon a minion, 5 damage to your hero.
cards.CFM_900 = on_mine("summon", function(g, me, ev)
  if ev.entity ~= me then
    g.damage(me, g.hero(g.ctrl(me)), 5)
  end
end)

-- --- Warrior ------------------------------------------------------------------------------------

-- Hobart Grapplehammer: the weapons in your hand and deck +1 Attack.
cards.CFM_643 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _, zone in ipairs({ g.hand(p), g.deck(p) }) do
      for _, e in ipairs(zone) do
        if g.is_weapon(e) then
          g.buff(e, 1, 0)
        end
      end
    end
  end,
}

-- Brass Knuckles: after your hero attacks, a random minion in your hand +1/+1.
cards.CFM_631 = {
  on = {
    after_attack = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.attacker == g.hero(p) then
        buff_random_in_hand(g, p, 1, 1)
      end
    end,
  },
}

-- Sleep with the Fishes: 3 damage to all damaged minions (damaged as it is cast).
cards.CFM_716 = {
  spell = function(g, me)
    local d = g.spell_dmg(me, 3)
    local hurt = list.filter(g.all_minions(), function(m)
      return g.dmg(m) > 0
    end)
    for _, m in ipairs(hurt) do
      g.damage(me, m, d)
    end
  end,
}

-- Stolen Goods: a random Taunt minion in your hand +3/+3.
cards.CFM_752 = {
  spell = function(g, me)
    buff_random_in_hand(g, g.ctrl(me), 3, 3, function(e)
      return g.has(e, "TAUNT")
    end)
  end,
}

-- Grimy Gadgeteer: at the end of your turn, a random minion in your hand +2/+2.
cards.CFM_754 = on_mine("turn_end", function(g, me)
  buff_random_in_hand(g, g.ctrl(me), 2, 2)
end)

-- Grimestreet Pawnbroker: a random weapon in your hand +1/+1.
cards.CFM_755 = {
  battlecry = function(g, me)
    local w = g.pick(list.filter(g.hand(g.ctrl(me)), function(e)
      return g.is_weapon(e)
    end))
    if w then
      g.buff(w, 1, 0)
      g.add_tag(w, "DURABILITY", 1)
    end
  end,
}

-- Alley Armorsmith: whenever it deals damage, gain that much Armor.
cards.CFM_756 = {
  on = {
    damage = function(g, me, ev)
      if ev.source == me and ev.amount > 0 then
        g.gain_armor(g.ctrl(me), ev.amount)
      end
    end,
  },
}

-- I Know a Guy: Discover a Taunt minion.
cards.CFM_940 = {
  spell = function(g, me)
    discover(g, me, function(i)
      return i.type == "MINION" and has_kw(i, "TAUNT")
    end)
  end,
  on_choose = to_hand,
}

return cards
