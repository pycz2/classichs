-- Rise of Shadows (April 2019): the Rogue, Shaman, Warlock and Warrior cards, their tokens and the five Lackeys, as on
-- 2019-04-09 (build 30103; hearthstone.wiki.gg). The Schemes (DAL_007-DAL_010) and Swampqueen Hagatha's Horror are not
-- here yet.
local cards = {}

-- --- helpers (copied from boom_cards.lua) ---------------------------------------------------------------------------

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local COIN = "GAME_005"
local BOMB = "BOT_511t"

local function playable(class)
  return list.any(CLASSES, function(c)
    return c == class
  end)
end

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

local function pool(g, ok)
  return list.filter(g.collectible(), function(c)
    return ok(g.info(c))
  end)
end

local function info(g, e)
  return g.info(g.card(e))
end

local function alive(g, m)
  return g.zone(m) == "PLAY" and g.health(m) > 0 and not g.has(m, "TO_DESTROY")
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

local function to_hand(g, me, option)
  return g.add_to_hand(g.ctrl(me), g.card(option))
end

local function self_transform(g, me, card)
  local started = g.has(me, "STARTED_IN_DECK")
  local n = g.transform(me, card)
  if n and started then
    g.set_tag(n, "STARTED_IN_DECK", true)
  end
  return n
end

local function is_spell(i)
  return i.type == "SPELL"
end

-- --- Rise of Shadows' helpers ---------------------------------------------------------------------------------------

-- The five Lackeys (mechanics.md §2): "Generation of Lackeys is always random" (duplicates possible).
local LACKEYS = { "DAL_613", "DAL_614", "DAL_615", "DAL_739", "DAL_741" }

local function is_lackey(g, e)
  local c = g.card(e)
  return list.any(LACKEYS, function(x)
    return x == c
  end)
end

local function add_lackeys(g, p, n)
  for _ = 1, n or 1 do
    g.add_to_hand(p, LACKEYS[g.random(1, #LACKEYS)])
  end
end

-- A random collectible minion that costs (printed) `cost` (Witchy Lackey, Mutate), or nil.
local function minion_of_cost(g, cost)
  return g.pick(pool(g, function(i)
    return i.type == "MINION" and i.cost == cost
  end))
end

-- Transforms minion t into a random one costing (1) more than t's card (none of that Cost: nothing).
local function cost_up(g, t)
  local c = minion_of_cost(g, info(g, t).cost + 1)
  if c then
    g.transform(t, c)
  end
end

-- "If you're holding a card from another class": a card in p's hand of a class (not neutral) that is not p's hero's.
local function holding_other_class(g, p, except)
  local mine = g.class(g.hero(p))
  return list.any(g.hand(p), function(e)
    if e == except then
      return false
    end
    local i = info(g, e)
    return not is_neutral(i) and not of_class(i, mine)
  end)
end

local function random_deck_minion(g, p, ok)
  return g.pick(list.filter(g.deck(p), function(e)
    return g.type(e) == "MINION" and (not ok or ok(e))
  end))
end

local function friendly_other(g, me, t)
  return t ~= me
end

-- --- Schemes (api.md "A counter that grows in the hand"): X = 1, +1 at the start of each of its owner's turns while in
-- the hand; a new copy starts again at 1.

local function scheme_x(g, me)
  return 1 + g.tag(me, "SCHEME")
end

local function scheme(h)
  h.hand = {
    turn_start = function(g, me, ev)
      if ev.player == g.ctrl(me) then
        g.add_tag(me, "SCHEME", 1)
      end
    end,
  }
  h.text = function(g, me)
    return tostring(scheme_x(g, me))
  end
  return h
end

-- Rafaam's Scheme: summon X 1/1 Imps (castable with a full board on 2019-04-09).
cards.DAL_007 = scheme({
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, scheme_x(g, me) do
      if not g.summon(p, "DAL_751t") then
        break
      end
    end
  end,
})

-- Dr. Boom's Scheme: gain X Armor.
cards.DAL_008 = scheme({
  spell = function(g, me)
    g.gain_armor(g.ctrl(me), scheme_x(g, me))
  end,
})

-- Hagatha's Scheme: X damage to all minions (spell damage applies).
cards.DAL_009 = scheme({
  spell = function(g, me)
    local n = g.spell_dmg(me, scheme_x(g, me))
    for _, m in ipairs(g.all_minions()) do
      g.damage(me, m, n)
    end
  end,
})

-- Togwaggle's Scheme: choose a minion (either side); shuffle X copies of it into your deck.
cards.DAL_010 = scheme({
  target = "minion",
  spell = function(g, me, t)
    local p = g.ctrl(me)
    for _ = 1, scheme_x(g, me) do
      g.add_to_deck(p, g.card(t))
    end
  end,
})

-- --- Lackeys ----------------------------------------------------------------------------------------------------------

-- Faceless Lackey: Battlecry: summon a random 2-Cost minion.
cards.DAL_613 = {
  battlecry = function(g, me)
    local c = minion_of_cost(g, 2)
    if c then
      g.summon_right(me, c)
    end
  end,
}

-- Kobold Lackey: Battlecry: deal 2 damage.
cards.DAL_614 = {
  target = "any",
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, 2)
    end
  end,
}

-- Witchy Lackey: Battlecry: transform a friendly minion into one that costs (1) more.
cards.DAL_615 = {
  target = { base = "friendly_minion", filter = friendly_other },
  battlecry = function(g, me, t)
    if t then
      cost_up(g, t)
    end
  end,
}

-- Goblin Lackey: Battlecry: a friendly minion +1 Attack and Rush.
cards.DAL_739 = {
  target = { base = "friendly_minion", filter = friendly_other },
  battlecry = function(g, me, t)
    if t then
      g.buff(t, 1, 0)
      g.give_tag(t, "RUSH")
    end
  end,
}

-- Ethereal Lackey: Battlecry: Discover a spell.
cards.DAL_741 = {
  battlecry = function(g, me)
    offer(g, me, discover_choices(g, discover_class(g, me), is_spell))
  end,
  on_choose = to_hand,
}

-- --- Rogue ------------------------------------------------------------------------------------------------------------

-- Daring Escape: return all friendly minions to your hand.
cards.DAL_728 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.return_to_hand(m)
    end
  end,
}

-- Underbelly Fence: Battlecry: if you're holding a card from another class, +1/+1 and Rush.
cards.DAL_714 = {
  glow = function(g, me)
    return holding_other_class(g, g.ctrl(me), me)
  end,
  battlecry = function(g, me)
    if holding_other_class(g, g.ctrl(me), me) then
      g.buff(me, 1, 1)
      g.give_tag(me, "RUSH")
    end
  end,
}

-- EVIL Miscreant: Combo: two random Lackeys.
cards.DAL_415 = {
  combo = function(g, me)
    add_lackeys(g, g.ctrl(me), 2)
  end,
}

-- Hench-Clan Burglar: Battlecry: Discover a spell from another class (each option may be of a different class).
cards.DAL_416 = {
  battlecry = function(g, me)
    local mine = g.class(g.hero(g.ctrl(me)))
    offer_cards(g, me, pool(g, function(i)
      return i.type == "SPELL" and not is_neutral(i) and not of_class(i, mine) and (i.classes or playable(i.class))
    end))
  end,
  on_choose = to_hand,
}

-- Vendetta: 4 damage to a minion; costs (0) while you hold a card from another class (whatever would raise it).
cards.DAL_716 = {
  target = "minion",
  cost_last = true,
  cost_mod = function(g, me)
    if g.zone(me) == "HAND" and holding_other_class(g, g.ctrl(me), me) then
      return -1000
    end
    return 0
  end,
  glow = function(g, me)
    return holding_other_class(g, g.ctrl(me), me)
  end,
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
  end,
}

-- Waggle Pick: Deathrattle: a random friendly minion back to your hand; it costs (2) less.
cards.DAL_720 = {
  deathrattle = function(g, me)
    local m = g.random_alive(g.minions(g.ctrl(me)))
    local c = m and g.return_to_hand(m)
    if c then
      g.enchant(c, { cost = -2 })
    end
  end,
}

-- Heistbaron Togwaggle: Battlecry: if you control a Lackey, choose one of three of the four K&C treasures.
local TREASURES = { "LOOT_998h", "LOOT_998j", "LOOT_998k", "LOOT_998l" }
local function lackey_on_board(g, me)
  return list.any(g.minions(g.ctrl(me)), function(m)
    return m ~= me and is_lackey(g, m)
  end)
end
cards.DAL_417 = {
  glow = lackey_on_board,
  battlecry = function(g, me)
    if lackey_on_board(g, me) then
      offer_cards(g, me, TREASURES)
    end
  end,
  on_choose = to_hand,
}

-- Unidentified Contract: put into the hand (drawn or given), it becomes one of its four contracts (as K&C's
-- Unidentified items; DOUBT: the opening hand keeps the plain card).
local CONTRACTS = { "DAL_366t1", "DAL_366t2", "DAL_366t3", "DAL_366t4" }
local function contract(f)
  return {
    target = "minion",
    spell = function(g, me, t)
      if f then
        f(g, me, t)
      end
      g.destroy(t)
    end,
  }
end
local function identify(g, me, ev)
  if ev.entity == me and g.zone(me) == "HAND" then
    self_transform(g, me, g.pick(CONTRACTS))
  end
end
cards.DAL_366 = contract()
cards.DAL_366.hand = { draw = identify, add_to_hand = identify }
-- Assassin's Contract: and a 1/1 Patient Assassin.
cards.DAL_366t1 = {
  target = "minion",
  spell = function(g, me, t)
    g.destroy(t)
    g.summon(g.ctrl(me), "VAN_EX1_522")
  end,
}
-- Recruitment Contract: and a copy of it to your hand.
cards.DAL_366t2 = contract(function(g, me, t)
  g.add_to_hand(g.ctrl(me), g.card(t))
end)
-- Lucrative Contract: and two Coins.
cards.DAL_366t3 = contract(function(g, me, t)
  g.add_to_hand(g.ctrl(me), COIN)
  g.add_to_hand(g.ctrl(me), COIN)
end)
-- Turncoat Contract: it deals its damage (its Attack) to the minions next to it, then dies.
cards.DAL_366t4 = contract(function(g, me, t)
  local n = g.atk(t)
  if n > 0 then
    for _, m in ipairs(g.adjacent(t)) do
      g.damage(t, m, n)
    end
  end
end)

-- Tak Nozwhisker: whenever you shuffle a card into your deck, a copy of it to your hand.
local function tak(g, me, ev)
  if ev.player == g.ctrl(me) then
    g.add_to_hand(ev.player, g.card(ev.entity))
  end
end
cards.DAL_719 = { on = { add_to_deck = tak, to_deck = tak } }

-- --- Shaman -----------------------------------------------------------------------------------------------------------

-- Mutate: transform a friendly minion into a random one that costs (1) more.
cards.DAL_071 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    cost_up(g, t)
  end,
}

-- Sludge Slurper: Battlecry: a Lackey to your hand (its Overload is the card's).
cards.DAL_433 = {
  battlecry = function(g, me)
    add_lackeys(g, g.ctrl(me), 1)
  end,
}

-- Soul of the Murloc: your minions get "Deathrattle: summon a 1/1 Murloc" (Murloc Scout).
cards["ench:dal_soul_of_the_murloc"] = {
  deathrattle = function(g, me)
    local pos = g.died_pos(me)
    g.summon(g.ctrl(me), "VAN_EX1_506a", pos >= 0 and pos or nil)
  end,
}
cards.DAL_710 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, m in ipairs(g.minions(p)) do
      g.enchant(m, { hooks = "ench:dal_soul_of_the_murloc", player = p })
    end
  end,
}

-- Underbelly Angler: after you play a Murloc, a random Murloc to your hand.
cards.DAL_049 = {
  on = {
    after_summon = function(g, me, ev)
      if ev.played and ev.entity ~= me and g.mine(me, ev) and g.race(ev.entity) == "MURLOC" then
        g.add_to_hand(ev.player, g.pick(pool(g, function(i)
          return i.type == "MINION" and i.race == "MURLOC"
        end)))
      end
    end,
  },
}

-- Witch's Brew: restore 4 Health; a copy comes to the hand that goes away at the end of the turn (as Echo's: GHOSTLY).
cards.DAL_432 = {
  target = "any",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 4))
    local c = g.add_to_hand(g.ctrl(me), g.card(me))
    if c then
      g.set_tag(c, "GHOSTLY", true)
    end
  end,
}

-- Scargil: your Murlocs cost (1).
cards.DAL_726 = {
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.type(card) == "MINION" and g.race(card) == "MURLOC" then
      return 1
    end
    return cost
  end,
}

-- Muckmorpher: Battlecry: transform into a 4/4 copy of a different minion in your deck (never a Muckmorpher).
cards.DAL_052 = {
  battlecry = function(g, me)
    local e = random_deck_minion(g, g.ctrl(me), function(d)
      return g.card(d) ~= g.card(me)
    end)
    if e then
      local n = g.transform(me, g.card(e))
      if n then
        g.set_stats(n, 4, 4)
      end
    end
  end,
}

-- --- Warlock ----------------------------------------------------------------------------------------------------------

-- EVIL Genius: Battlecry: destroy a friendly minion to add two random Lackeys.
cards.DAL_606 = {
  target = { base = "friendly_minion", filter = friendly_other },
  battlecry = function(g, me, t)
    if t then
      g.destroy(t)
      add_lackeys(g, g.ctrl(me), 2)
    end
  end,
}

-- Plot Twist: shuffle your hand into your deck, draw that many.
cards.DAL_602 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local hand = list.filter(g.hand(p), function(e)
      return e ~= me
    end)
    for _, e in ipairs(hand) do
      g.to_deck(e, p)
    end
    if #hand > 0 then
      g.draw(p, #hand)
    end
  end,
}

-- Impferno: your Demons +1 Attack, then 1 damage to all enemy minions.
cards.DAL_605 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, m in ipairs(g.minions(p)) do
      if g.race(m) == "DEMON" then
        g.buff(m, 1, 0)
      end
    end
    local n = g.spell_dmg(me, 1)
    for _, m in ipairs(g.minions(g.opponent(p))) do
      g.damage(me, m, n)
    end
  end,
}

-- Eager Underling: Deathrattle: two random friendly minions +2/+2.
cards.DAL_563 = {
  deathrattle = function(g, me)
    local live = list.filter(g.minions(g.ctrl(me)), function(m)
      return m ~= me and alive(g, m)
    end)
    for _, m in ipairs(pick_n(g, live, 2)) do
      g.buff(m, 2, 2)
    end
  end,
}

-- Aranasi Broodmother: Taunt; when you draw it (shown to both), restore 4 Health to your hero.
cards.DAL_185 = {
  hand = {
    draw = function(g, me, ev)
      if ev.entity == me then
        g.log({ type = "revealed", player = g.ctrl(me), entity = me, card = g.card(me) })
        g.heal(me, g.hero(g.ctrl(me)), 4)
      end
    end,
  },
}

-- Darkest Hour: destroy all friendly minions; for each, a random minion of your deck is summoned.
cards.DAL_173 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local mine = g.minions(p)
    for _, m in ipairs(mine) do
      g.destroy(m)
    end
    g.resolve()
    for _ = 1, #mine do
      local e = random_deck_minion(g, p)
      if not e or g.room(p) <= 0 then
        break
      end
      g.summon_entity(e)
    end
  end,
}

-- Arch-Villain Rafaam: Battlecry: every card in your hand and deck becomes a random Legendary minion.
cards.DAL_422 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local legends = pool(g, function(i)
      return i.type == "MINION" and i.rarity == "LEGENDARY"
    end)
    for _, zone in ipairs({ g.hand(p), g.deck(p) }) do
      for _, e in ipairs(zone) do
        g.transform(e, g.pick(legends))
      end
    end
  end,
}

-- Fel Lord Betrug: whenever you draw a minion, summon a copy of it with Rush that dies at the end of the turn.
cards["ench:dal_betrug_copy"] = {
  on = {
    turn_end = function(g, me)
      g.destroy(me)
    end,
  },
}
cards.DAL_607 = {
  on = {
    draw = function(g, me, ev)
      if g.mine(me, ev) and g.type(ev.entity) == "MINION" then
        local c = g.summon(ev.player, g.card(ev.entity))
        if c then
          g.give_tag(c, "RUSH")
          g.enchant(c, { hooks = "ench:dal_betrug_copy", player = ev.player })
        end
      end
    end,
  },
}

-- Jumbo Imp: costs (1) less whenever a friendly Demon dies while this is in your hand.
cards.DAL_561 = {
  hand = {
    death = function(g, me, ev)
      if ev.minion and g.mine(me, ev) and g.race(ev.entity) == "DEMON" then
        g.enchant(me, { cost = -1 })
      end
    end,
  },
}

-- --- Warrior ----------------------------------------------------------------------------------------------------------

-- Improve Morale: 1 damage to a minion; if it survives, a Lackey to your hand.
cards.DAL_769 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 1))
    if alive(g, t) then
      add_lackeys(g, g.ctrl(me), 1)
    end
  end,
}

-- Sweeping Strikes: a minion gets "Also damages minions next to whomever this attacks." (Foe Reaper 4000's).
cards["ench:dal_sweeping_strikes"] = {
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
cards.DAL_062 = {
  target = "minion",
  spell = function(g, me, t)
    g.enchant(t, { hooks = "ench:dal_sweeping_strikes", player = g.ctrl(me) })
  end,
}

-- Vicious Scraphound: whenever it deals damage, its player gains that much Armor.
cards.DAL_759 = {
  on = {
    damage = function(g, me, ev)
      if ev.source == me and ev.amount > 0 then
        g.gain_armor(g.ctrl(me), ev.amount)
      end
    end,
  },
}

-- Clockwork Goblin: Battlecry: a Bomb into the opponent's deck.
cards.DAL_060 = {
  battlecry = function(g, me)
    g.add_to_deck(g.enemy(me), BOMB)
  end,
}

-- Omega Devastator: Battlecry: with 10 Mana Crystals, 10 damage to a minion.
local function omega(g, me)
  return g.max_mana(g.ctrl(me)) >= 10
end
cards.DAL_770 = {
  target = { base = "minion", when = omega },
  glow = omega,
  battlecry = function(g, me, t)
    if t and omega(g, me) then
      g.damage(me, t, 10)
    end
  end,
}

-- Wrenchcalibur: after your hero attacks, a Bomb into the opponent's deck.
cards.DAL_063 = {
  on = {
    after_attack = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.attacker == g.hero(p) then
        g.add_to_deck(g.opponent(p), BOMB)
      end
    end,
  },
}

-- Blastmaster Boom: Battlecry: two 1/1 Boom Bots for each Bomb in the opponent's deck.
cards.DAL_064 = {
  battlecry = function(g, me)
    local n = list.count(g.deck(g.enemy(me)), function(e)
      return g.card(e) == BOMB
    end)
    for _ = 1, 2 * n do
      if not g.summon_right(me, "GVG_110t") then
        break
      end
    end
  end,
}

-- Dimensional Ripper: summon 2 copies of a random minion in your deck (it stays there).
cards.DAL_059 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local e = random_deck_minion(g, p)
    if e then
      g.summon(p, g.card(e))
      g.summon(p, g.card(e))
    end
  end,
}

-- The Boom Reaver: Battlecry: summon a copy of a random minion in your deck with Rush.
cards.DAL_070 = {
  battlecry = function(g, me)
    local e = random_deck_minion(g, g.ctrl(me))
    local c = e and g.summon_right(me, g.card(e))
    if c then
      g.give_tag(c, "RUSH")
    end
  end,
}

return cards
