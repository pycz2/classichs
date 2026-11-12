-- Kobolds & Catacombs (December 2017): the Shaman, Warlock and Warrior cards as at the release (build 22611 of patch
-- 10.0.0.22611; hearthstone.wiki.gg; docs/packs/api.md). Their Spellstones, the Unidentified Shield and Murmuring Elemental
-- are in loot.lua.
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

-- --- Shaman --------------------------------------------------------------------------------------------------------------

local BASIC_TOTEMS = { "VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009" }

-- Crushing Hand: 8 damage to a minion (its Overload (3) is data).
cards.LOOT_060 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 8))
  end,
}

-- Kobold Hermit: choose one of the four basic Totems (any of them, one you have too: the build's entourage), summoned right
-- of it (a full board: no choice).
cards.LOOT_062 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if g.room(p) <= 0 then
      return
    end
    local opts = {}
    for _, c in ipairs(BASIC_TOTEMS) do
      opts[#opts + 1] = g.create(p, c)
    end
    g.request_choice(me, opts)
  end,
  on_choose = function(g, me, option)
    if g.zone(me) == "PLAY" then
      g.summon_right(me, g.card(option))
    else
      g.summon(g.ctrl(me), g.card(option))
    end
  end,
}

-- Primal Talismans: your minions get "Deathrattle: Summon a random basic Totem" (where it died).
cards.LOOT_344 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, m in ipairs(g.minions(p)) do
      g.enchant(m, { hooks = "ench:loot_ssw_talisman", player = p })
    end
  end,
}
cards["ench:loot_ssw_talisman"] = {
  deathrattle = function(g, me)
    summon_here(g, me, g.pick(BASIC_TOTEMS))
  end,
}

-- Grumble, Worldshaker: your other minions go back to the hand (fresh cards; a full hand: they die) and cost (1) there.
cards.LOOT_358 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.others(me)) do
      local c = g.return_to_hand(m)
      if c then
        g.enchant(c, { cost_set = 1 })
      end
    end
  end,
}

-- Healing Rain: 12 heals of 1, each on a random damaged friendly character (none damaged: the rest is lost); no Spell
-- Damage (ImmuneToSpellpower); Prophet Velen doubles each heal; with Auchenai Soulpriest each is 1 damage to any friendly
-- character.
cards.LOOT_373 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local hurts = g.has(g.hero(p), "HEAL_IS_DAMAGE")
    for _ = 1, 12 do
      local c = g.pick(list.filter(g.chars(p), function(x)
        return alive(g, x) and (hurts or g.dmg(x) > 0)
      end))
      if not c then
        break
      end
      g.heal(me, c, g.heal_amt(me, 1))
    end
  end,
}

-- Unstable Evolution: a friendly minion becomes a random collectible minion costing (1) more than its card (none of that
-- Cost: it stays); then a copy (LOOT_504t, the same card) comes to the hand, removed at the end of the turn ("Repeatable
-- this turn"; like Echo later: removed, not discarded).
local UNSTABLE = "LOOT_504t"
local function unstable_evolution()
  return {
    target = "friendly_minion",
    spell = function(g, me, t)
      local cost = g.info(g.card(t)).cost + 1
      local c = random_card(g, minion_of(function(i)
        return i.cost == cost
      end))
      if c then
        g.transform(t, c)
      end
      g.add_to_hand(g.ctrl(me), UNSTABLE)
    end,
  }
end
cards.LOOT_504 = unstable_evolution()
cards.LOOT_504t = unstable_evolution()
cards.LOOT_504t.hand = {
  turn_end = function(g, me)
    local p = g.ctrl(me)
    g.remove(me, "SETASIDE")
    g.log({ type = "removed_from_hand", player = p, entity = me, card = g.card(me) })
  end,
}

-- The Runespear: after your hero attacks, Discover a spell (your class's and neutral) and cast it with random targets.
cards.LOOT_506 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == g.hero(g.ctrl(me)) then
        discover(g, me, function(i)
          return i.type == "SPELL"
        end)
      end
    end,
  },
  on_choose = function(g, me, option)
    g.cast_random(me, g.card(option))
  end,
}

-- Windshear Stormcaller: if you control the four basic Totems, Al'Akir the Windlord right of it.
local function all_basic_totems(g, me)
  local mine = g.minions(g.ctrl(me))
  return list.all(BASIC_TOTEMS, function(c)
    return list.any(mine, function(m)
      return g.card(m) == c
    end)
  end)
end
cards.LOOT_518 = {
  glow = all_basic_totems,
  battlecry = function(g, me)
    if all_basic_totems(g, me) then
      g.summon_right(me, "VAN_NEW1_010")
    end
  end,
}

-- --- Warlock -------------------------------------------------------------------------------------------------------------

local function hurt_own_hero(n)
  return function(g, me)
    g.damage(me, g.hero(g.ctrl(me)), n)
  end
end

-- Vulgar Homunculus: 2 damage to your hero.
cards.LOOT_013 = { battlecry = hurt_own_hero(2) }

-- Kobold Librarian: draw a card, then 2 damage to your hero (a drawn Amethyst Spellstone upgrades).
cards.LOOT_014 = {
  battlecry = function(g, me)
    g.draw(g.ctrl(me))
    g.damage(me, g.hero(g.ctrl(me)), 2)
  end,
}

-- Dark Pact: destroy a friendly minion, restore 8 Health to your hero.
cards.LOOT_017 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.destroy(t)
    g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 8))
  end,
}

-- Hooked Reaver: with 15 Health or less, +3/+3 and Taunt.
cards.LOOT_018 = {
  glow = function(g, me)
    return g.health(g.hero(g.ctrl(me))) <= 15
  end,
  battlecry = function(g, me)
    if g.health(g.hero(g.ctrl(me))) <= 15 then
      g.buff(me, 3, 3)
      g.give_tag(me, "TAUNT")
    end
  end,
}

-- Possessed Lackey: Deathrattle: Recruit a Demon.
cards.LOOT_306 = {
  deathrattle = function(g, me)
    recruit(g, g.ctrl(me), function(e)
      return g.race(e) == "DEMON"
    end)
  end,
}

-- Voidlord: Deathrattle: three 1/3 Voidwalkers (Taunt) where it died.
cards.LOOT_368 = {
  deathrattle = function(g, me)
    for _ = 1, 3 do
      summon_here(g, me, "VAN_CS2_065")
    end
  end,
}

-- Rin, the First Disciple: Deathrattle: The First Seal to the hand. Each Seal summons its Felhunter and gives the next one;
-- The Final Seal gives Azari, the Devourer.
cards.LOOT_415 = {
  deathrattle = function(g, me)
    g.add_to_hand(g.ctrl(me), "LOOT_415t1")
  end,
}
local function seal(n, next)
  return {
    spell = function(g, me)
      local p = g.ctrl(me)
      g.summon(p, "LOOT_415t" .. n .. "t")
      g.add_to_hand(p, next)
    end,
  }
end
cards.LOOT_415t1 = seal(1, "LOOT_415t2")
cards.LOOT_415t2 = seal(2, "LOOT_415t3")
cards.LOOT_415t3 = seal(3, "LOOT_415t4")
cards.LOOT_415t4 = seal(4, "LOOT_415t5")
cards.LOOT_415t5 = seal(5, "LOOT_415t6")

-- Azari, the Devourer: destroy your opponent's deck (every card leaves it, none is drawn).
cards.LOOT_415t6 = {
  battlecry = function(g, me)
    local p = g.enemy(me)
    remove_top(g, p, #g.deck(p))
  end,
}

-- Cataclysm: destroy all minions, discard your hand (the Deathrattles come after the discard: the death phase follows).
cards.LOOT_417 = {
  spell = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      g.destroy(m)
    end
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      g.discard(e)
    end
  end,
}

-- Skull of the Man'ari: at the start of your turn (before the draw), a random Demon of your hand is summoned (no
-- Battlecry).
cards.LOOT_420 = on_mine("turn_start", function(g, me)
  local p = g.ctrl(me)
  if g.room(p) <= 0 then
    return
  end
  local d = g.pick(list.filter(g.hand(p), function(e)
    return g.type(e) == "MINION" and g.race(e) == "DEMON"
  end))
  if d then
    g.summon_entity(d)
  end
end)

-- --- Warrior -------------------------------------------------------------------------------------------------------------

local function armor(g, p)
  return g.tag(g.hero(p), "ARMOR")
end

-- Kobold Barbarian: at the start of your turn it attacks a random enemy (2017: that is its attack of the turn; patch 23.0
-- changed it).
cards.LOOT_041 = on_mine("turn_start", function(g, me)
  if g.atk(me) <= 0 then
    return
  end
  local t = g.random_alive(g.chars(g.enemy(me)))
  if t then
    g.force_attack(me, t)
    g.add_tag(me, "ATTACKS", 1)
  end
end)

-- Bladed Gauntlet: its Attack is always your Armor (after every other change: Deadly Poison does nothing); can't attack
-- heroes (CANNOT_ATTACK_HEROES, data).
cards.LOOT_044 = {
  aura_final = function(g, me)
    g.aura_add(me, armor(g, g.ctrl(me)) - g.atk(me), 0)
  end,
}

-- Reckless Flurry: all your Armor is spent, that much damage to every minion (no Spell Damage: not in its text).
cards.LOOT_364 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local n = armor(g, p)
    g.set_tag(g.hero(p), "ARMOR", 0)
    if n > 0 then
      damage_all_minions(g, me, n)
    end
  end,
}

-- Gemstudded Golem: can attack only with 5 Armor or more.
cards.LOOT_365 = {
  aura = function(g, me)
    if armor(g, g.ctrl(me)) < 5 then
      g.aura_add(me, 0, 0, { CANT_ATTACK = true })
    end
  end,
}

-- Drywhisker Armorer: 2 Armor for each enemy minion.
cards.LOOT_367 = {
  battlecry = function(g, me)
    local n = #g.minions(g.enemy(me))
    if n > 0 then
      g.gain_armor(g.ctrl(me), 2 * n)
    end
  end,
}

-- Gather Your Party: Recruit a minion.
cards.LOOT_370 = {
  spell = function(g, me)
    recruit(g, g.ctrl(me))
  end,
}

-- Woecleaver: after your hero attacks, Recruit a minion.
cards.LOOT_380 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == g.hero(g.ctrl(me)) then
        recruit(g, g.ctrl(me))
      end
    end,
  },
}

-- Geosculptor Yip: at the end of your turn, a random collectible minion of Cost = your Armor (10 at most; 0 Armor: a 0-Cost
-- one), right of it.
cards.LOOT_519 = end_of_my_turn(function(g, me)
  local cost = math.min(armor(g, g.ctrl(me)), 10)
  local c = random_card(g, minion_of(function(i)
    return i.cost == cost
  end))
  if c then
    g.summon_right(me, c)
  end
end)

return cards
