-- Whispers of the Old Gods (April 2016): the 134 cards and their tokens as at the release (patch 5.0.0.12574 of
-- 2016-04-24, two days before the release; hearthstone.wiki.gg and its card notes; docs/packs/api.md). The older
-- sets' cards are those packs' scripts, copied in by the recipe; the ones that changed by then are at the end.
local cards = {}

-- --- helpers -----------------------------------------------------------------------------------

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
-- each class's basic Hero Power (Renounce Darkness)
local POWERS = { DRUID = "VAN_HERO_06bp", HUNTER = "VAN_HERO_05bp", MAGE = "VAN_HERO_08bp", PALADIN = "VAN_HERO_04bp",
  PRIEST = "VAN_HERO_09bp", ROGUE = "VAN_HERO_03bp", SHAMAN = "VAN_HERO_02bp", WARLOCK = "VAN_HERO_07bp",
  WARRIOR = "VAN_HERO_01bp" }

local function playable(class)
  return list.any(CLASSES, function(c)
    return c == class
  end)
end

local function has_kw(info, kw)
  return list.any(info.keywords, function(k)
    return k == kw
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

local function random_enemy(g, me)
  return g.random_alive(g.chars(g.enemy(me)))
end

-- A death hook that summons card where me stood.
local function summon_here(g, me, card)
  local pos = g.died_pos(me)
  return g.summon(g.ctrl(me), card, pos >= 0 and pos or nil)
end

local function deathrattle_summon(card, n)
  return {
    deathrattle = function(g, me)
      for _ = 1, n or 1 do
        summon_here(g, me, card)
      end
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

local function at_start_of_my_turn(f)
  return on_mine("turn_start", f)
end

local function enrage(atk)
  return {
    aura = function(g, me)
      if g.dmg(me) > 0 then
        g.aura_add(me, atk, 0)
      end
    end,
  }
end

local function other_friendly(g, me, t)
  return t ~= me
end

local function spend_all_mana(g, p)
  local x = g.mana(p)
  g.set_mana(p, 0)
  return x
end

-- --- the game's counts (rules.json player_hooks) ----------------------------------------------
-- For each player: the spells they cast from the hand this game and were not countered (Yogg-Saron), the Totems they
-- summoned (Thing from Below), and the order friendly minions died in (N'Zoth).

cards["player:og"] = {
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
  },
}

-- --- C'Thun ------------------------------------------------------------------------------------
-- "Give your C'Thun +X/+X (wherever it is)": each player keeps a ritual total (the counts CTHUN_ATK, CTHUN_HP and
-- CTHUN_TAUNT); every C'Thun of theirs in the hand, the deck or on the board gets each ritual, a new one the whole total
-- (Doomcaller). Silence takes a C'Thun's rituals away and it gets no more (as in 2016).

local CTHUN = "OG_280"

local function cthuns(g, p)
  local out = {}
  for _, zone in ipairs({ g.hand(p), g.deck(p), g.minions(p) }) do
    for _, e in ipairs(zone) do
      if g.card(e) == CTHUN and not g.silenced(e) then
        out[#out + 1] = e
      end
    end
  end
  return out
end

-- C'Thun's Attack and Health with every ritual so far.
local function cthun_stats(g, p)
  return 6 + g.count(p, "CTHUN_ATK"), 6 + g.count(p, "CTHUN_HP")
end

local function ritual(g, me, atk, hp)
  local p = g.ctrl(me)
  g.add_count(p, "CTHUN_ATK", atk)
  g.add_count(p, "CTHUN_HP", hp)
  for _, c in ipairs(cthuns(g, p)) do
    g.buff(c, atk, hp)
  end
  local a, h = cthun_stats(g, p)
  g.log({ type = "cthun", player = p, atk = a, health = h }) -- both players see the new stats (the client's pop-up)
end

-- "If your C'Thun has at least 10 Attack": with every ritual, or a C'Thun in your hand or on your board now.
local function cthun10(g, me)
  local p = g.ctrl(me)
  if cthun_stats(g, p) >= 10 then
    return true
  end
  for _, zone in ipairs({ g.hand(p), g.minions(p) }) do
    for _, e in ipairs(zone) do
      if g.card(e) == CTHUN and g.atk(e) >= 10 then
        return true
      end
    end
  end
  return false
end

local function ritual_battlecry(atk, hp)
  return {
    battlecry = function(g, me)
      ritual(g, me, atk, hp)
    end,
  }
end

-- C'Thun: one damage at a time, as many as its Attack, each at a random enemy still alive (Stealth and Immune ones
-- too), each resolving before the next; the Battlecry goes on if C'Thun dies.
cards.OG_280 = {
  battlecry = function(g, me)
    for _ = 1, math.min(g.atk(me), 100) do
      local t = random_enemy(g, me)
      if not t then
        break
      end
      g.damage(me, t, 1)
      g.resolve()
    end
  end,
}

cards.OG_281 = ritual_battlecry(2, 2) -- Beckoner of Evil
cards.OG_283 = ritual_battlecry(2, 2) -- C'Thun's Chosen
cards.OG_339 = ritual_battlecry(2, 2) -- Skeram Cultist
cards.OG_293 = ritual_battlecry(3, 3) -- Dark Arakkoa

-- Twilight Geomancer: your C'Thun has Taunt.
cards.OG_284 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    g.add_count(p, "CTHUN_TAUNT")
    for _, c in ipairs(cthuns(g, p)) do
      g.give_tag(c, "TAUNT")
    end
  end,
}

-- Disciple of C'Thun: 2 damage (its triggers resolve), then C'Thun +2/+2.
cards.OG_162 = {
  target = "any",
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, 2)
      g.resolve()
    end
    ritual(g, me, 2, 2)
  end,
}

-- Twilight Elder: at the end of your turn, C'Thun +1/+1.
cards.OG_286 = on_mine("turn_end", function(g, me)
  ritual(g, me, 1, 1)
end)

-- Cult Sorcerer: Spell Damage +1; after you cast a spell, C'Thun +1/+1.
cards.OG_303 = on_mine("after_spell", function(g, me)
  ritual(g, me, 1, 1)
end)

-- Crazed Worshipper: whenever it takes damage, C'Thun +1/+1.
cards.OG_321 = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me then
        ritual(g, me, 1, 1)
      end
    end,
  },
}

-- Hooded Acolyte: whenever a character is healed (Health restored), C'Thun +1/+1.
cards.OG_334 = {
  on = {
    heal = function(g, me, ev)
      ritual(g, me, 1, 1)
    end,
  },
}

-- Usher of Souls: whenever a friendly minion dies, C'Thun +1/+1.
cards.OG_302 = {
  on = {
    death = function(g, me, ev)
      if ev.minion and g.mine(me, ev) and ev.entity ~= me then
        ritual(g, me, 1, 1)
      end
    end,
  },
}

-- A C'Thun of p's died on p's board this game.
local function cthun_died(g, p)
  return list.any(g.graveyard(p), function(e)
    return g.card(e) == CTHUN and g.died_pos(e) >= 0
  end)
end

-- Doomcaller: C'Thun +2/+2; if one of yours died, a new C'Thun (with every ritual) into your deck.
cards.OG_255 = {
  glow = function(g, me)
    return cthun_died(g, g.ctrl(me))
  end,
  battlecry = function(g, me)
    ritual(g, me, 2, 2)
    local p = g.ctrl(me)
    if cthun_died(g, p) then
      local c = g.add_to_deck(p, CTHUN)
      g.buff(c, g.count(p, "CTHUN_ATK"), g.count(p, "CTHUN_HP"))
      if g.count(p, "CTHUN_TAUNT") > 0 then
        g.give_tag(c, "TAUNT")
      end
    end
  end,
}

-- Blade of C'Thun: destroy a minion; its Attack and Health go to C'Thun.
cards.OG_282 = {
  target = "minion",
  battlecry = function(g, me, t)
    if t then
      local a, h = g.atk(t), g.health(t)
      g.destroy(t)
      ritual(g, me, a, h)
    end
  end,
}

local function cthun10_battlecry(f)
  return {
    glow = cthun10,
    battlecry = function(g, me)
      if cthun10(g, me) then
        f(g, me)
      end
    end,
  }
end

cards.OG_131 = cthun10_battlecry(function(g, me) -- Twin Emperor Vek'lor
  g.summon_right(me, "OG_319")
end)
cards.OG_188 = cthun10_battlecry(function(g, me) -- Klaxxi Amber-Weaver
  g.buff(me, 0, 5)
end)
cards.OG_301 = cthun10_battlecry(function(g, me) -- Ancient Shieldbearer
  g.gain_armor(g.ctrl(me), 10)
end)
cards.OG_096 = cthun10_battlecry(function(g, me) -- Twilight Darkmender
  g.heal(me, g.hero(g.ctrl(me)), 10)
end)

-- --- the other Old Gods --------------------------------------------------------------------------

-- N'Zoth, the Corruptor: a fresh copy of each friendly minion with a Deathrattle of its own (silenced or not; not one an
-- enchantment gave) that died this game, each death once, in the order they died, right of N'Zoth; with too little
-- room, a random few of them.
cards.OG_133 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local dead = list.filter(g.graveyard(p), function(e)
      return g.is_minion(e) and g.died_pos(e) >= 0 and has_kw(g.info(g.card(e)), "DEATHRATTLE")
    end)
    local room = g.room(p)
    if #dead > room then
      g.shuffle(dead)
      local keep = {}
      for i = 1, room do
        keep[i] = dead[i]
      end
      dead = keep
    end
    dead = list.sort_by(dead, function(e)
      return g.tag(e, "DIED_ORDER")
    end)
    local pos = (g.board_pos(me) or g.room(p)) + 1
    for _, e in ipairs(dead) do
      if g.summon(p, g.card(e), pos) then
        pos = pos + 1
      end
    end
  end,
}

-- A random spell for me's player, cast with random choices, then resolved.
local function cast_random_spell(g, me, spells)
  local s = g.pick(spells)
  if s then
    g.cast_random(me, s)
    g.resolve()
  end
end

local function all_spells(g)
  return pool(g, function(i)
    return i.type == "SPELL"
  end)
end

-- Yogg-Saron, Hope's End: a random spell for each spell you cast this game (at most 30), random targets and choices;
-- it goes on if Yogg-Saron dies (until patch 6.1.3), without Overload (until 6.2).
cards.OG_134 = {
  battlecry = function(g, me)
    local spells = all_spells(g)
    for _ = 1, math.min(g.count(g.ctrl(me), "SPELLS"), 30) do
      cast_random_spell(g, me, spells)
    end
  end,
}

-- Y'Shaarj, Rage Unbound: at the end of your turn, a random minion of your deck into play.
cards.OG_042 = on_mine("turn_end", function(g, me)
  local p = g.ctrl(me)
  local m = g.pick(list.filter(g.deck(p), function(e)
    return g.is_minion(e)
  end))
  if m and g.room(p) > 0 then
    g.summon_entity(m)
  end
end)

-- Deathwing, Dragonlord: Deathrattle: the Dragons of your hand into play.
cards.OG_317 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    for _, e in ipairs(g.hand(p)) do
      if g.is_minion(e) and g.race(e) == "DRAGON" and g.room(p) > 0 then
        g.summon_entity(e)
      end
    end
  end,
}

-- --- Discover (as The League of Explorers' in 2016: class cards four times as likely as neutral ones) --------------

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

local function discover(g, me, ok)
  local cls = g.class(g.hero(g.ctrl(me)))
  if not playable(cls) then
    cls = g.info(g.card(me)).class
  end
  if not playable(cls) then
    cls = CLASSES[g.random(1, #CLASSES)]
  end
  local choices = {}
  for _, c in ipairs(g.collectible()) do
    local i = g.info(c)
    if (i.class == cls or i.class == "NEUTRAL") and i.type ~= "CHAMPION" and i.type ~= "POWER" and ok(i) then
      choices[#choices + 1] = { c, i.class == cls and 4 or 1 }
    end
  end
  offer(g, me, choices)
end

-- --- Druid -------------------------------------------------------------------------------------

-- Forbidden Ancient: spend all your Mana, +1/+1 for each.
cards.OG_051 = {
  battlecry = function(g, me)
    local x = spend_all_mana(g, g.ctrl(me))
    g.buff(me, x, x)
  end,
}

-- Mark of Y'Shaarj: +2/+2; a Beast: draw a card.
cards.OG_048 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 2, 2)
    if g.race(t) == "BEAST" then
      g.draw(g.ctrl(me))
    end
  end,
}

-- Addled Grizzly: after you summon a minion, it gets +1/+1.
cards.OG_313 = on_mine("after_summon", function(g, me, ev)
  if ev.entity ~= me then
    g.buff(ev.entity, 1, 1)
  end
end)

-- Feral Rage: Choose One - your hero +4 Attack this turn; or 8 Armor.
cards.OG_047 = { choose_one = { "OG_047a", "OG_047b" } }
cards.OG_047a = {
  effect = function(g, me)
    g.buff(g.hero(g.ctrl(me)), 4, 0, true)
  end,
}
cards.OG_047b = {
  effect = function(g, me)
    g.gain_armor(g.ctrl(me), 8)
  end,
}

-- Fandral Staghelm: your Choose One cards have both effects (CHOOSE_BOTH on your hero).
cards.OG_044 = {
  aura = function(g, me)
    g.aura_add(g.hero(g.ctrl(me)), 0, 0, { CHOOSE_BOTH = true })
  end,
}

-- Mire Keeper: Choose One - a 2/2 Slime; or an empty Mana Crystal.
cards.OG_202 = { choose_one = { "OG_202a", "OG_202b" } }
cards.OG_202a = {
  effect = function(g, me)
    g.summon_right(me, "OG_202c")
  end,
}
cards.OG_202b = {
  effect = function(g, me)
    g.gain_mana(g.ctrl(me), 1, true)
  end,
}

-- Wisps of the Old Gods: Choose One - seven 1/1 Wisps; or your minions +2/+2.
cards.OG_195 = { choose_one = { "OG_195a", "OG_195b" } }
cards.OG_195a = {
  effect = function(g, me)
    for _ = 1, 7 do
      g.summon(g.ctrl(me), "OG_195c")
    end
  end,
}
cards.OG_195b = {
  effect = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.buff(m, 2, 2)
    end
  end,
}

-- --- Hunter ------------------------------------------------------------------------------------

-- On the Hunt: 1 damage, then a 1/1 Mastiff.
cards.OG_061 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 1))
    g.summon(g.ctrl(me), "OG_061t")
  end,
}

-- Fiery Bat: Deathrattle: 1 damage to a random enemy.
cards.OG_179 = {
  deathrattle = function(g, me)
    g.damage(me, random_enemy(g, me), 1)
  end,
}

-- Forlorn Stalker: the Deathrattle minions in your hand +1/+1.
cards.OG_292 = {
  battlecry = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      if g.is_minion(e) and has_kw(g.info(g.card(e)), "DEATHRATTLE") then
        g.buff(e, 1, 1)
      end
    end
  end,
}

-- Infest: your minions get "Deathrattle: add a random Beast to your hand".
cards.OG_045 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.enchant(m, { hooks = "ench:infest" })
    end
  end,
}
cards["ench:infest"] = {
  deathrattle = function(g, me)
    local b = g.pick(pool(g, function(i)
      return i.type == "MINION" and i.race == "BEAST"
    end))
    if b then
      g.add_to_hand(g.ctrl(me), b)
    end
  end,
}

cards.OG_216 = deathrattle_summon("OG_216a", 2) -- Infested Wolf: two 1/1 Spiders

-- Princess Huhuran: a friendly minion's Deathrattle runs (it stays alive).
cards.OG_309 = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t)
      return t ~= me and has_kw(g.info(g.card(t)), "DEATHRATTLE") and not g.silenced(t)
    end,
  },
  battlecry = function(g, me, t)
    if t then
      g.deathrattle(t)
    end
  end,
}

-- Call of the Wild: Huffer, Leokk and Misha.
cards.OG_211 = {
  spell = function(g, me)
    for _, c in ipairs({ "VAN_NEW1_034", "VAN_NEW1_033", "VAN_NEW1_032" }) do
      g.summon(g.ctrl(me), c)
    end
  end,
}

-- After me attacks and kills a minion (it is at 0 Health or to be destroyed).
local function kills(g, me, ev)
  local d = ev.defender
  return ev.attacker == me and d >= 0 and g.is_minion(d) and (g.health(d) <= 0 or g.has(d, "TO_DESTROY"))
end

-- Giant Sand Worm: when it attacks and kills a minion, it may attack again.
cards.OG_308 = {
  on = {
    after_attack = function(g, me, ev)
      if kills(g, me, ev) then
        g.add_tag(me, "ATTACKS", -1)
      end
    end,
  },
}

-- --- Mage --------------------------------------------------------------------------------------

-- Forbidden Flame: spend all your Mana; that much damage to a minion.
cards.OG_086 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, spend_all_mana(g, g.ctrl(me)))
  end,
}

-- Shatter: destroy a Frozen minion.
cards.OG_081 = {
  target = {
    base = "minion",
    filter = function(g, me, t)
      return g.has(t, "FROZEN")
    end,
  },
  spell = function(g, me, t)
    g.destroy(t)
  end,
}

-- Twilight Flamecaller: 1 damage to each enemy minion.
cards.OG_083 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.damage(me, m, 1)
    end
  end,
}

-- Demented Frostcaller: after you cast a spell, Freeze a random enemy that is not Frozen.
cards.OG_085 = on_mine("after_spell", function(g, me)
  g.freeze(g.random_alive(list.filter(g.chars(g.enemy(me)), function(c)
    return not g.has(c, "FROZEN")
  end)))
end)

-- Servant of Yogg-Saron: a random spell of Cost (5) or less, random targets and choices.
cards.OG_087 = {
  battlecry = function(g, me)
    cast_random_spell(g, me, pool(g, function(i)
      return i.type == "SPELL" and i.cost <= 5
    end))
  end,
}

-- Cabalist's Tome: 3 random Mage spells into your hand.
cards.OG_090 = {
  spell = function(g, me)
    local spells = pool(g, function(i)
      return i.type == "SPELL" and i.class == "MAGE"
    end)
    for _ = 1, 3 do
      g.add_to_hand(g.ctrl(me), g.pick(spells))
    end
  end,
}

-- Faceless Summoner: a random 3-Cost minion.
cards.OG_207 = {
  battlecry = function(g, me)
    local m = g.pick(pool(g, minion_of_cost(3)))
    if m then
      g.summon_right(me, m)
    end
  end,
}

-- Anomalus: Deathrattle: 8 damage to all minions.
cards.OG_120 = {
  deathrattle = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      g.damage(me, m, 8)
    end
  end,
}

-- --- Paladin -----------------------------------------------------------------------------------

-- Forbidden Healing: spend all your Mana; restore twice that much.
cards.OG_198 = {
  target = "any",
  spell = function(g, me, t)
    local x = spend_all_mana(g, g.ctrl(me))
    g.heal(me, t, g.heal_amt(me, 2 * x))
  end,
}

-- Selfless Hero: Deathrattle: Divine Shield to a random friendly minion (one that has it already too, until 2020).
cards.OG_221 = {
  deathrattle = function(g, me)
    g.give_tag(g.random_alive(g.minions(g.ctrl(me))), "DIVINE_SHIELD")
  end,
}

-- Vilefin Inquisitor: your Hero Power becomes The Tidal Hand.
cards.OG_006 = {
  battlecry = function(g, me)
    g.set_power(g.ctrl(me), "OG_006b")
  end,
}
cards.OG_006b = {
  hero_power = function(g, me)
    g.summon(g.ctrl(me), "OG_006a")
  end,
}

-- Divine Strength: +1/+2.
cards.OG_223 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 1, 2)
  end,
}

-- A Light in the Darkness: Discover a minion (any class's: until 2017); it gets +1/+1.
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

-- Rallying Blade: your Divine Shield minions +1/+1.
cards.OG_222 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if g.has(m, "DIVINE_SHIELD") then
        g.buff(m, 1, 1)
      end
    end
  end,
}

-- Steward of Darkshire: whenever you summon a minion with 1 Health (its maximum), it gets Divine Shield.
cards.OG_310 = on_mine("summon", function(g, me, ev)
  if ev.entity ~= me and g.max_health(ev.entity) == 1 then
    g.give_tag(ev.entity, "DIVINE_SHIELD")
  end
end)

-- Stand Against Darkness: five 1/1 Silver Hand Recruits.
cards.OG_273 = {
  spell = function(g, me)
    for _ = 1, 5 do
      g.summon(g.ctrl(me), "VAN_CS2_101t")
    end
  end,
}

-- Ragnaros, Lightlord: at the end of your turn, 8 Health to a random damaged friendly character.
cards.OG_229 = on_mine("turn_end", function(g, me)
  local hurt = list.filter(g.chars(g.ctrl(me)), function(c)
    return g.dmg(c) > 0
  end)
  local t = g.pick(hurt)
  if t then
    g.heal(me, t, 8)
  end
end)

-- --- Priest ------------------------------------------------------------------------------------

-- Forbidden Shaping: spend all your Mana; a random minion of that Cost.
cards.OG_101 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local m = g.pick(pool(g, minion_of_cost(spend_all_mana(g, p))))
    if m then
      g.summon(p, m)
    end
  end,
}

-- Embrace the Shadow: this turn your healing deals damage instead.
cards.OG_104 = {
  spell = function(g, me)
    g.give_tag(g.hero(g.ctrl(me)), "HEAL_IS_DAMAGE", true)
  end,
}

-- Shifting Shade: Deathrattle: a copy of a random card of your opponent's deck into your hand.
cards.OG_335 = {
  deathrattle = function(g, me)
    local c = g.pick(g.deck(g.enemy(me)))
    if c then
      g.add_to_hand(g.ctrl(me), g.card(c))
    end
  end,
}

-- Shadow Word: Horror: destroy every minion with 2 or less Attack.
cards.OG_100 = {
  spell = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if g.atk(m) <= 2 then
        g.destroy(m)
      end
    end
  end,
}

-- Darkshire Alchemist: restore 5 Health.
cards.OG_234 = {
  target = "any",
  battlecry = function(g, me, t)
    if t then
      g.heal(me, t, 5)
    end
  end,
}

-- Power Word: Tentacles: +2/+6.
cards.OG_094 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 2, 6)
  end,
}

-- Herald Volazj: a 1/1 copy of each of your other minions (their enchantments too), right of it.
cards.OG_316 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local pos = g.board_pos(me) + 1
    for _, m in ipairs(g.others(me)) do
      local n = g.summon(p, g.card(m), pos)
      if n then
        n = g.copy_minion(n, m)
        g.set_stats(n, 1, 1)
        pos = pos + 1
      end
    end
  end,
}

-- --- Rogue -------------------------------------------------------------------------------------

-- Journey Below: Discover a Deathrattle card.
cards.OG_072 = {
  spell = function(g, me)
    discover(g, me, function(i)
      return has_kw(i, "DEATHRATTLE")
    end)
  end,
  on_choose = function(g, me, option)
    g.add_to_hand(g.ctrl(me), g.card(option))
  end,
}

-- Bladed Cultist: Combo: +1/+1.
cards.OG_070 = {
  combo = function(g, me)
    g.buff(me, 1, 1)
  end,
}

-- Undercity Huckster: Deathrattle: a random class card of your opponent's class into your hand.
cards.OG_330 = {
  deathrattle = function(g, me)
    local cls = g.class(g.hero(g.enemy(me)))
    if playable(cls) then
      local c = g.pick(pool(g, function(i)
        return i.class == cls
      end))
      if c then
        g.add_to_hand(g.ctrl(me), c)
      end
    end
  end,
}

-- Shadow Strike: 5 damage to an undamaged character.
cards.OG_176 = {
  target = {
    base = "any",
    filter = function(g, me, t)
      return g.dmg(t) == 0
    end,
  },
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 5))
  end,
}

-- Xaril, Poisoned Mind: Battlecry and Deathrattle: a random Toxin into your hand.
local TOXINS = { "OG_080b", "OG_080c", "OG_080d", "OG_080e", "OG_080f" }
local function toxin(g, me)
  g.add_to_hand(g.ctrl(me), g.pick(TOXINS))
end
cards.OG_080 = { battlecry = toxin, deathrattle = toxin }

cards.OG_080b = { -- Kingsblood Toxin: draw a card
  spell = function(g, me)
    g.draw(g.ctrl(me))
  end,
}
cards.OG_080c = { -- Bloodthistle Toxin: a friendly minion back to your hand; it costs (2) less
  target = "friendly_minion",
  spell = function(g, me, t)
    local n = g.return_to_hand(t)
    if n then
      g.enchant(n, { cost = -2 })
    end
  end,
}
cards.OG_080d = { -- Briarthorn Toxin: +3 Attack
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 3, 0)
  end,
}

-- Stealth until the start of the next turn of the player who gave it (Fadeleaf Toxin; Master of Disguise since
-- patch 5.0.0.12574: also a minion that had Stealth already loses it then).
local function stealth_until_next_turn(g, me, t)
  g.give_tag(t, "STEALTH")
  g.enchant(t, { hooks = "ench:og_stealth", player = g.ctrl(me) })
end
cards["ench:og_stealth"] = {
  on = {
    turn_start = function(g, me, ev)
      for _, p in ipairs(g.enchants(me, "ench:og_stealth")) do
        if p == ev.player then
          g.erase_tag(me, "STEALTH")
          g.remove_enchant(me, "ench:og_stealth", p)
        end
      end
    end,
  },
}
cards.OG_080e = { -- Fadeleaf Toxin
  target = "friendly_minion",
  spell = stealth_until_next_turn,
}
cards.OG_080f = { -- Firebloom Toxin: 2 damage
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
  end,
}

-- Southsea Squidface: Deathrattle: your weapon +2 Attack.
cards.OG_267 = {
  deathrattle = function(g, me)
    g.buff(g.weapon(g.ctrl(me)), 2, 0)
  end,
}

-- Shadowcaster: a 1/1 copy of a friendly minion that costs (1) into your hand (a plain card).
cards.OG_291 = {
  target = { base = "friendly_minion", filter = other_friendly },
  battlecry = function(g, me, t)
    if t then
      local n = g.add_to_hand(g.ctrl(me), g.card(t))
      if n then
        g.set_stats(n, 1, 1)
        g.enchant(n, { cost = 1 - g.info(g.card(t)).cost })
      end
    end
  end,
}

-- Thistle Tea: draw a card; 2 more copies of it into your hand.
cards.OG_073 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local d = g.draw(p)[1]
    if d then
      g.add_to_hand(p, g.card(d))
      g.add_to_hand(p, g.card(d))
    end
  end,
}

-- --- Shaman ------------------------------------------------------------------------------------

-- A minion turns into a random collectible minion that costs (1) more than its card (none of that Cost: it stays).
local function evolve(g, m)
  local c = g.pick(pool(g, minion_of_cost(g.info(g.card(m)).cost + 1)))
  if c then
    g.transform(m, c)
  end
end

-- Evolve: every minion of yours.
cards.OG_027 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      evolve(g, m)
    end
  end,
}

-- Master of Evolution: a friendly minion.
cards.OG_328 = {
  target = { base = "friendly_minion", filter = other_friendly },
  battlecry = function(g, me, t)
    if t then
      evolve(g, t)
    end
  end,
}

-- Primal Fusion: +1/+1 for each of your Totems.
cards.OG_023 = {
  target = "minion",
  spell = function(g, me, t)
    local n = list.count(g.minions(g.ctrl(me)), function(m)
      return g.race(m) == "TOTEM"
    end)
    g.buff(t, n, n)
  end,
}

-- Eternal Sentinel: unlock your Overloaded Mana Crystals.
cards.OG_026 = {
  battlecry = function(g, me)
    g.unlock_mana(g.ctrl(me))
  end,
}

-- Stormcrack: 4 damage to a minion.
cards.OG_206 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
  end,
}

-- Hammer of Twilight: Deathrattle: a 4/2 Elemental.
cards.OG_031 = {
  deathrattle = function(g, me)
    g.summon(g.ctrl(me), "OG_031a")
  end,
}

-- Hallazeal the Ascended: whenever your spells deal damage, that much Health to your hero.
cards.OG_209 = {
  on = {
    damage = function(g, me, ev)
      local s = ev.source
      if s and s > 0 and g.is_spell(s) and g.ctrl(s) == g.ctrl(me) then
        g.heal(me, g.hero(g.ctrl(me)), ev.amount)
      end
    end,
  },
}

-- Thing from Below: (1) less for each Totem you summoned this game, while in your hand.
cards.OG_028 = {
  cost_mod = function(g, me)
    if g.zone(me) ~= "HAND" then
      return 0
    end
    return -g.count(g.ctrl(me), "TOTEMS")
  end,
}

-- --- Warlock -----------------------------------------------------------------------------------

-- Forbidden Ritual: spend all your Mana; that many 1/1 Tentacles.
cards.OG_114 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, spend_all_mana(g, p) do
      g.summon(p, "OG_114a")
    end
  end,
}

cards.OG_241 = deathrattle_summon("OG_241a") -- Possessed Villager: a 1/1 Shadowbeast

-- Renounce Darkness: a random other class's basic Hero Power; every Warlock card in your hand and deck becomes a random
-- card of that class, costing (1) less.
cards.OG_118 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local cls = g.pick(list.filter(CLASSES, function(c)
      return c ~= "WARLOCK"
    end))
    g.set_power(p, POWERS[cls])
    local cards_of = pool(g, function(i)
      return i.class == cls
    end)
    for _, zone in ipairs({ g.hand(p), g.deck(p) }) do
      for _, e in ipairs(zone) do
        if g.class(e) == "WARLOCK" then
          local n = g.transform(e, g.pick(cards_of))
          if n then
            g.enchant(n, { cost = -1 })
          end
        end
      end
    end
  end,
}

-- Darkshire Librarian: Battlecry: discard a random card. Deathrattle: draw a card.
cards.OG_109 = {
  battlecry = function(g, me)
    g.discard_random(g.ctrl(me))
  end,
  deathrattle = function(g, me)
    g.draw(g.ctrl(me))
  end,
}

-- Darkshire Councilman: after you summon a minion, +1 Attack.
cards.OG_113 = on_mine("after_summon", function(g, me, ev)
  if ev.entity ~= me then
    g.buff(me, 1, 0)
  end
end)

-- Spreading Madness: 9 damage one at a time among all characters (Spell Damage adds more).
cards.OG_116 = {
  spell = function(g, me)
    for _ = 1, g.spell_dmg(me, 9) do
      g.damage(me, g.random_alive(g.all_chars()), 1)
    end
  end,
}

-- Cho'gall: the next spell you cast this turn costs Health instead of Mana.
cards.OG_121 = {
  battlecry = function(g, me)
    g.add_cost_mod(g.ctrl(me), { kind = "spell", health = true, ["until"] = "use" })
  end,
}

-- DOOM!: destroy all minions; draw a card for each.
cards.OG_239 = {
  spell = function(g, me)
    local all = g.all_minions()
    for _, m in ipairs(all) do
      g.destroy(m)
    end
    g.draw(g.ctrl(me), #all)
  end,
}

-- --- Warrior -----------------------------------------------------------------------------------

-- N'Zoth's First Mate: equip a 1/3 Rusty Hook.
cards.OG_312 = {
  battlecry = function(g, me)
    g.equip(g.ctrl(me), "OG_058")
  end,
}

-- Blood To Ichor: 1 damage to a minion; if it survives, a 2/2 Slime.
cards.OG_314 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 1))
    g.resolve()
    if g.zone(t) == "PLAY" and g.health(t) > 0 and not g.has(t, "TO_DESTROY") then
      g.summon(g.ctrl(me), "OG_314b")
    end
  end,
}

-- Ravaging Ghoul: 1 damage to all other minions.
cards.OG_149 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if m ~= me then
        g.damage(me, m, 1)
      end
    end
  end,
}

-- Bloodsail Cultist: if you control another Pirate, your weapon +1/+1.
local function other_pirate(g, me)
  return list.any(g.minions(g.ctrl(me)), function(m)
    return m ~= me and g.race(m) == "PIRATE"
  end)
end
cards.OG_315 = {
  glow = other_pirate,
  battlecry = function(g, me)
    local w = g.weapon(g.ctrl(me))
    if w and other_pirate(g, me) then
      g.buff(w, 1, 0)
      g.add_tag(w, "DURABILITY", 1)
    end
  end,
}

-- Blood Warriors: a copy of each damaged friendly minion into your hand (plain cards).
cards.OG_276 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, m in ipairs(g.minions(p)) do
      if g.dmg(m) > 0 then
        g.add_to_hand(p, g.card(m))
      end
    end
  end,
}

cards.OG_218 = enrage(3) -- Bloodhoof Brave

-- Tentacles for Arms: Deathrattle: back into your hand (a fresh card).
cards.OG_033 = {
  deathrattle = function(g, me)
    g.add_to_hand(g.ctrl(me), "OG_033")
  end,
}

-- Malkorok: equip a random weapon (any class's).
cards.OG_220 = {
  battlecry = function(g, me)
    local w = g.pick(pool(g, function(i)
      return i.type == "WEAPON"
    end))
    if w then
      g.equip(g.ctrl(me), w)
    end
  end,
}

-- --- Neutral -----------------------------------------------------------------------------------

-- Shifter Zerus: at the start of each of your turns while it is in your hand (not the turn it came), it becomes a
-- random minion that keeps shifting until it leaves the hand.
local function shift(g, me, ev)
  if g.mine(me, ev) then
    local m = g.pick(pool(g, function(i)
      return i.type == "MINION"
    end))
    local n = m and g.transform(me, m)
    if n then
      g.enchant(n, { hooks = "ench:zerus" })
    end
  end
end
cards.OG_123 = { hand = { turn_start = shift } }
cards["ench:zerus"] = { hand = { turn_start = shift } }

-- Tentacle of N'Zoth: Deathrattle: 1 damage to all minions.
cards.OG_151 = {
  deathrattle = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      g.damage(me, m, 1)
    end
  end,
}

-- Zealous Initiate: Deathrattle: a random friendly minion +1/+1.
cards.OG_158 = {
  deathrattle = function(g, me)
    g.buff(g.random_alive(g.minions(g.ctrl(me))), 1, 1)
  end,
}

cards.OG_156 = battlecry_summon("OG_156a") -- Bilefin Tidehunter: a 1/1 Ooze with Taunt

-- Nat, the Darkfisher: at the start of your opponent's turn, a 50% chance they draw a card more.
cards.OG_338 = {
  on = {
    turn_start = function(g, me, ev)
      if not g.mine(me, ev) and g.random(1, 2) == 1 then
        g.draw(ev.player)
      end
    end,
  },
}

-- Silithid Swarmer: can attack only if your hero attacked this turn.
cards.OG_034 = {
  aura = function(g, me)
    if g.tag(g.hero(g.ctrl(me)), "ATTACKS") == 0 then
      g.aura_add(me, 0, 0, { CANT_ATTACK = true })
    end
  end,
}

-- Spawn of N'Zoth: Deathrattle: your minions +1/+1.
cards.OG_256 = {
  deathrattle = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.buff(m, 1, 1)
    end
  end,
}

-- Blackwater Pirate: your weapons cost (2) less.
cards.OG_322 = {
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.zone(card) == "HAND" and g.is_weapon(card) then
      return cost - 2
    end
    return cost
  end,
}

cards.OG_249 = deathrattle_summon("OG_249a") -- Infested Tauren: a 2/2 Slime

-- Midnight Drake: +1 Attack for each other card in your hand.
cards.OG_320 = {
  battlecry = function(g, me)
    g.buff(me, #g.hand(g.ctrl(me)), 0)
  end,
}

cards.OG_272 = deathrattle_summon("OG_272t") -- Twilight Summoner: a 5/5 Faceless Destroyer

-- Eater of Secrets: destroy every enemy Secret; +1/+1 for each.
cards.OG_254 = {
  battlecry = function(g, me)
    local s = g.traps(g.enemy(me))
    for _, t in ipairs(s) do
      g.remove(t, "GRAVEYARD")
      g.log({ type = "destroy", target = t })
    end
    if #s > 0 then
      g.buff(me, #s, #s)
    end
  end,
}

-- Faceless Shambler: its Attack and Health become a friendly minion's.
cards.OG_174 = {
  target = { base = "friendly_minion", filter = other_friendly },
  battlecry = function(g, me, t)
    if t then
      g.set_stats(me, g.atk(t), g.health(t))
    end
  end,
}

-- Polluted Hoarder: Deathrattle: draw a card.
cards.OG_323 = {
  deathrattle = function(g, me)
    g.draw(g.ctrl(me))
  end,
}

cards.OG_150 = enrage(2) -- Aberrant Berserker

-- Cyclopian Horror: +1 Health for each enemy minion.
cards.OG_337 = {
  battlecry = function(g, me)
    g.buff(me, 0, #g.minions(g.enemy(me)))
  end,
}

-- Darkspeaker: swap stats with a friendly minion.
cards.OG_102 = {
  target = { base = "friendly_minion", filter = other_friendly },
  battlecry = function(g, me, t)
    if t then
      local a, h = g.atk(me), g.health(me)
      g.set_stats(me, g.atk(t), g.health(t))
      g.set_stats(t, a, h)
    end
  end,
}

-- Cult Apothecary: 2 Health to your hero for each enemy minion.
cards.OG_295 = {
  battlecry = function(g, me)
    local n = #g.minions(g.enemy(me))
    if n > 0 then
      g.heal(me, g.hero(g.ctrl(me)), 2 * n)
    end
  end,
}

-- Corrupted Healbot: Deathrattle: 8 Health to the enemy hero.
cards.OG_147 = {
  deathrattle = function(g, me)
    g.heal(me, g.hero(g.enemy(me)), 8)
  end,
}

-- Validated Doomsayer: at the start of your turn, its Attack becomes 7.
cards.OG_200 = at_start_of_my_turn(function(g, me)
  g.set_stats(me, 7, nil)
end)

-- Mukla, Tyrant of the Vale: 2 Bananas into your hand.
cards.OG_122 = {
  battlecry = function(g, me)
    g.add_to_hand(g.ctrl(me), "EX1_014t")
    g.add_to_hand(g.ctrl(me), "EX1_014t")
  end,
}

-- Corrupted Seer: 2 damage to every minion that is not a Murloc.
cards.OG_161 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if g.race(m) ~= "MURLOC" then
        g.damage(me, m, 2)
      end
    end
  end,
}

-- Scaled Nightmare: at the start of your turn, its Attack doubles.
cards.OG_271 = at_start_of_my_turn(function(g, me)
  g.buff(me, g.atk(me), 0)
end)

-- Ancient Harbinger: at the start of your turn, a 10-Cost minion of your deck into your hand (not a draw).
cards.OG_290 = at_start_of_my_turn(function(g, me)
  local p = g.ctrl(me)
  local m = g.pick(list.filter(g.deck(p), function(e)
    return g.is_minion(e) and g.info(g.card(e)).cost == 10
  end))
  if m then
    g.draw_entity(p, m, true)
  end
end)

-- Nerubian Prophet: at the start of your turn, in your hand, it costs (1) less.
cards.OG_138 = {
  hand = {
    turn_start = function(g, me, ev)
      if g.mine(me, ev) then
        g.enchant(me, { cost = -1 })
      end
    end,
  },
}

-- Hogger, Doom of Elwynn: whenever it takes damage, a 2/2 Gnoll with Taunt.
cards.OG_318 = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me then
        g.summon_right(me, "OG_318t")
      end
    end,
  },
}

-- The Boogeymonster: when it attacks and kills a minion, +2/+2.
cards.OG_300 = {
  on = {
    after_attack = function(g, me, ev)
      if kills(g, me, ev) then
        g.buff(me, 2, 2)
      end
    end,
  },
}

-- Blood of The Ancient One: at the end of your turn, two of them merge into The Ancient One.
local function blood(g, m)
  return g.card(m) == "OG_173" and g.zone(m) == "PLAY" and not g.has(m, "TO_DESTROY")
end
cards.OG_173 = on_mine("turn_end", function(g, me)
  if not blood(g, me) then
    return
  end
  local other = list.filter(g.others(me), function(m)
    return blood(g, m)
  end)[1]
  if other then
    local p, pos = g.ctrl(me), g.board_pos(me)
    g.destroy(me)
    g.destroy(other)
    g.resolve()
    g.summon(p, "OG_173a", pos)
  end
end)

-- --- older cards as on 2016-04-26 --------------------------------------------------------------

-- Force of Nature (patch 5.0.0.12574): three 2/2 Treants.
cards.VAN_EX1_571 = {
  spell = function(g, me)
    for _ = 1, 3 do
      g.summon(g.ctrl(me), "VAN_EX1_tk9")
    end
  end,
}

-- Ancient Teachings, Ancient of Lore's option (patch 5.0.0.12574): draw a card.
cards.VAN_NEW1_008a = {
  effect = function(g, me)
    g.draw(g.ctrl(me))
  end,
}

-- Arcane Golem (patch 5.0.0.12574: a 4/4 without Charge): the opponent gets a Mana Crystal.
cards.VAN_EX1_089 = {
  battlecry = function(g, me)
    g.gain_mana(g.enemy(me), 1)
  end,
}

-- Molten Giant (patch 5.0.0.12574: 25 Mana): (1) less for each damage your hero has taken.
cards.VAN_EX1_620 = {
  cost_mod = function(g, me)
    return -g.dmg(g.hero(g.ctrl(me)))
  end,
}

-- Blade Flurry (patch 5.0.0.12574): destroy your weapon; its damage to every enemy minion.
cards.VAN_CS2_233 = {
  can_play = function(g, me)
    return g.weapon(g.ctrl(me)) ~= nil
  end,
  spell = function(g, me)
    local w = g.weapon(g.ctrl(me))
    local n = g.spell_dmg(me, g.atk(w))
    g.destroy(w)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.damage(me, m, n)
    end
  end,
}

-- Master of Disguise (patch 5.0.0.12574): Stealth until your next turn.
cards.VAN_NEW1_014 = {
  target = { base = "friendly_minion", filter = other_friendly },
  battlecry = function(g, me, t)
    if t then
      stealth_until_next_turn(g, me, t)
    end
  end,
}

-- Cabal Shadow Priest (patch 4.3.0.12266): playable with a full board; the minion is then destroyed.
cards.VAN_EX1_091 = {
  target = {
    base = "enemy_minion",
    filter = function(g, me, t)
      return g.atk(t) <= 2
    end,
  },
  battlecry = function(g, me, t)
    g.take_control(t, g.ctrl(me))
  end,
}

-- Dark Iron Skulker (patch 5.0.0.12574): 2 damage to every undamaged enemy minion at once.
cards.BRM_008 = {
  battlecry = function(g, me)
    local hit = list.filter(g.minions(g.enemy(me)), function(m)
      return g.dmg(m) == 0
    end)
    for _, m in ipairs(hit) do
      g.damage(me, m, 2)
    end
  end,
}

-- Stampeding Kodo (patch 5.0.0.12574): not the minion its first Battlecry destroyed (Brann Bronzebeard).
cards.VAN_NEW1_041 = {
  battlecry = function(g, me)
    g.destroy(g.random_alive(list.filter(g.minions(g.enemy(me)), function(m)
      return g.atk(m) <= 2 and not g.has(m, "TO_DESTROY")
    end)))
  end,
}

-- Choose One minions with Fandral Staghelm (both options): the combined forms, and Keeper of the Grove silences first.
cards.VAN_EX1_165 = { -- Druid of the Claw: a 4/6 with Charge and Taunt
  choose_one = { "VAN_EX1_165a", "VAN_EX1_165b" },
  both = function(g, me)
    g.transform(me, "OG_044a")
  end,
}
cards.BRM_010 = { -- Druid of the Flame: a 5/5
  choose_one = { "BRM_010a", "BRM_010b" },
  both = function(g, me)
    g.transform(me, "OG_044b")
  end,
}
cards.AT_042 = { -- Druid of the Saber: a 3/2 with Charge and Stealth
  choose_one = { "AT_042a", "AT_042b" },
  both = function(g, me)
    g.transform(me, "OG_044c")
  end,
}
cards.VAN_EX1_166 = { -- Keeper of the Grove: Silence a minion, then 2 damage (a hero: the damage only)
  choose_one = { "VAN_EX1_166a", "VAN_EX1_166b" },
  both = function(g, me, t)
    if t then
      if g.is_minion(t) then
        g.silence(t)
      end
      g.damage(me, t, 2)
    end
  end,
}
cards.GVG_041 = { -- Dark Wispers: +5/+5 and Taunt first, then the Wisps
  choose_one = { "GVG_041b", "GVG_041a" },
  both = function(g, me, t)
    if t then
      g.buff(t, 5, 5)
      g.give_tag(t, "TAUNT")
    end
    for _ = 1, 5 do
      g.summon(g.ctrl(me), "VAN_CS2_231")
    end
  end,
}

return cards
