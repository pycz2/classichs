-- Rastakhan's Rumble (December 2018): the neutral cards and their tokens as at the release (build 27845, patch
-- 13.0.0 of 2018-12-04). Release-day bugs fixed later are not copied (the intended behaviour).
local cards = {}

-- --- helpers (boom_cards.lua's) -------------------------------------------------------------------------------------

local COIN = "GAME_005"

local function info(g, e)
  return g.info(g.card(e))
end

local function has_kw(i, k)
  return list.any(i.keywords, function(x)
    return x == k
  end)
end

local function summon_here(g, me, card)
  local pos = g.died_pos(me)
  return g.summon(g.ctrl(me), card, pos >= 0 and pos or nil)
end

local function summon_right_n(g, me, card, n)
  for _ = 1, n do
    if not g.summon_right(me, card) then
      break
    end
  end
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

local function holding(g, me, race)
  return list.any(g.hand(g.ctrl(me)), function(e)
    return e ~= me and (g.race(e) == race or g.race(e) == "ALL")
  end)
end

local function draw_from_deck(g, p, ok)
  local e = g.pick(list.filter(g.deck(p), ok))
  if e then
    g.draw_entity(p, e)
  end
  return e
end

local function over(g)
  return g.health(g.hero(0)) <= 0 or g.health(g.hero(1)) <= 0
end

-- --- Discover (boom_cards.lua's: the class cards four times as likely as the neutral ones) ---------------------------

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }

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

local function discover_class(g, me)
  local c = g.class(g.hero(g.ctrl(me)))
  if playable(c) then
    return c
  end
  return CLASSES[g.random(1, #CLASSES)]
end

local function discover(g, me, ok)
  local cls = discover_class(g, me)
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
  return offer(g, me, choices)
end

local function to_hand(g, me, option)
  return g.add_to_hand(g.ctrl(me), g.card(option))
end

-- --- Overkill (mechanics.md 1): this card dealt more damage than its target had Health (the target's Health after the
-- hit is below 0; Armor first: a hero's Health + Armor), on its controller's turn; once per such target. The dead
-- attacker still triggers (it is in play until the death phase).

local function overkill(f)
  return {
    on = {
      damage = function(g, me, ev)
        if ev.source == me and ev.amount > 0 and g.current() == g.ctrl(me) and g.health(ev.target) < 0 then
          f(g, me, ev)
        end
      end,
    },
  }
end

-- "Has <x> while damaged".
local function while_damaged(atk, tags)
  return {
    aura = function(g, me)
      if g.dmg(me) > 0 then
        g.aura_add(me, atk, 0, tags)
      end
    end,
  }
end

-- --- cards ---------------------------------------------------------------------------------------------------------

-- Half-Time Scavenger: Stealth. Overkill: gain 3 Armor.
cards.TRL_010 = overkill(function(g, me)
  g.gain_armor(g.ctrl(me), 3)
end)

-- Ticket Scalper: Overkill: draw 2 cards.
cards.TRL_015 = overkill(function(g, me)
  g.draw(g.ctrl(me), 2)
end)

-- Sightless Ranger: Rush. Overkill: summon two 1/1 Bats (right of it).
cards.TRL_020 = overkill(function(g, me)
  summon_right_n(g, me, "TRL_020t", 2)
end)

-- Serpent Ward: at the end of your turn, 2 damage to the enemy hero.
cards.TRL_057 = on_mine("turn_end", function(g, me)
  g.damage(me, g.hero(g.enemy(me)), 2)
end)

-- Griftah: Discover two cards (two Discovers); one of them goes to your opponent's hand at random, the other to yours.
-- The first pick waits on Griftah (GRIFTAH_FIRST: the option entity).
cards.TRL_096 = {
  battlecry = function(g, me)
    discover(g, me, function()
      return true
    end)
  end,
  on_choose = function(g, me, option)
    local first = g.tag(me, "GRIFTAH_FIRST")
    if first == 0 then
      g.set_tag(me, "GRIFTAH_FIRST", option)
      if discover(g, me, function() return true end) == 0 then
        to_hand(g, me, option)
      end
      return
    end
    g.set_tag(me, "GRIFTAH_FIRST", nil)
    local mine, theirs = g.card(first), g.card(option)
    if g.random(0, 1) == 1 then
      mine, theirs = theirs, mine
    end
    g.add_to_hand(g.ctrl(me), mine)
    g.add_to_hand(g.enemy(me), theirs)
  end,
}

-- Former Champ: summon a 5/5 Hotshot.
cards.TRL_151 = {
  battlecry = function(g, me)
    g.summon_right(me, "TRL_151t")
  end,
}

-- Spellzerker: Spell Damage +2 while damaged.
cards.TRL_312 = while_damaged(0, { SPELLPOWER = 2 })

-- Ragnaros the Firelord (Jan'alai's): at the end of your turn, 8 damage to a random enemy.
cards.TRL_316t = on_mine("turn_end", function(g, me)
  g.damage(me, g.random_alive(g.chars(g.enemy(me))), 8)
end)

-- Saronite Taskmaster: Deathrattle: a 0/3 Taunt Free Agent for your opponent.
cards.TRL_363 = {
  deathrattle = function(g, me)
    g.summon(g.enemy(me), "TRL_363t")
  end,
}

-- Untamed Beastmaster: whenever you draw a Beast, give it +2/+2.
cards.TRL_405 = on_mine("draw", function(g, me, ev)
  local r = g.race(ev.entity)
  if g.zone(ev.entity) == "HAND" and (r == "BEAST" or r == "ALL") then
    g.buff(ev.entity, 2, 2)
  end
end)

-- Dozing Marksman: +4 Attack while damaged.
cards.TRL_406 = while_damaged(4)

-- Waterboy: your next Hero Power this turn costs (0).
cards.TRL_407 = {
  battlecry = function(g, me)
    g.add_cost_mod(g.ctrl(me), { kind = "power", set = 0, ["until"] = "use" })
  end,
}

-- Scarab Egg: Deathrattle: three 1/1 Scarabs.
cards.TRL_503 = {
  deathrattle = function(g, me)
    for _ = 1, 3 do
      summon_here(g, me, "TRL_503t")
    end
  end,
}

-- Booty Bay Bookie: your opponent gets a Coin.
cards.TRL_504 = {
  battlecry = function(g, me)
    g.add_to_hand(g.enemy(me), COIN)
  end,
}

-- Helpless Hatchling: Deathrattle: a random Beast in your hand costs (1) less (a 0-cost one too: 2018).
cards.TRL_505 = {
  deathrattle = function(g, me)
    local b = g.pick(list.filter(g.hand(g.ctrl(me)), function(e)
      return g.race(e) == "BEAST" or g.race(e) == "ALL"
    end))
    if b then
      g.enchant(b, { cost = -1 })
    end
  end,
}

-- Gurubashi Chicken: Overkill: +5 Attack.
cards.TRL_506 = overkill(function(g, me)
  g.buff(me, 5, 0)
end)

-- Sharkfin Fan: after your hero attacks, summon a 1/1 Swabbie.
cards.TRL_507 = on_mine("after_attack", function(g, me, ev)
  if ev.attacker == g.hero(g.ctrl(me)) then
    g.summon_right(me, "TRL_507t")
  end
end)

-- Regeneratin' Thug: at the start of your turn, restore 2 Health to it.
cards.TRL_508 = on_mine("turn_start", function(g, me)
  g.heal(me, me, g.heal_amt(me, 2))
end)

-- Banana Buffoon: two Bananas into your hand.
cards.TRL_509 = {
  battlecry = function(g, me)
    g.add_to_hand(g.ctrl(me), "TRL_509t")
    g.add_to_hand(g.ctrl(me), "TRL_509t")
  end,
}

-- Bananas: give a minion +1/+1.
cards.TRL_509t = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 1, 1)
  end,
}

-- Cheaty Anklebiter: Lifesteal. Battlecry: 1 damage.
cards.TRL_512 = {
  target = "any",
  battlecry = function(g, me, t)
    g.damage(me, t, 1)
  end,
}

-- Belligerent Gnome: Taunt. Battlecry: +1 Attack if your opponent has 2 or more minions.
cards.TRL_514 = {
  battlecry = function(g, me)
    if #g.minions(g.enemy(me)) >= 2 then
      g.buff(me, 1, 0)
    end
  end,
}

-- Rabble Bouncer: Taunt. Costs (1) less for each enemy minion.
cards.TRL_515 = {
  cost_mod = function(g, me)
    return -#g.minions(g.enemy(me))
  end,
}

-- Gurubashi Offering: at the start of your turn, destroy it and gain 8 Armor.
cards.TRL_516 = on_mine("turn_start", function(g, me)
  g.destroy(me)
  g.gain_armor(g.ctrl(me), 8)
end)

-- Arena Fanatic: every minion card in your hand +1/+1.
cards.TRL_517 = {
  battlecry = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      if g.type(e) == "MINION" then
        g.buff(e, 1, 1)
      end
    end
  end,
}

-- Murloc Tastyfin: Deathrattle: draw 2 Murlocs from your deck.
cards.TRL_520 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 2 do
      draw_from_deck(g, p, function(e)
        return g.race(e) == "MURLOC" or g.race(e) == "ALL"
      end)
    end
  end,
}

-- Arena Patron: Overkill: summon another Arena Patron.
cards.TRL_521 = overkill(function(g, me)
  g.summon_right(me, "TRL_521")
end)

-- Firetree Witchdoctor: if you're holding a Dragon, Discover a spell.
cards.TRL_523 = {
  glow = function(g, me)
    return holding(g, me, "DRAGON")
  end,
  battlecry = function(g, me)
    if holding(g, me, "DRAGON") then
      discover(g, me, function(i)
        return i.type == "SPELL"
      end)
    end
  end,
  on_choose = to_hand,
}

-- Shieldbreaker: Silence an enemy minion with Taunt.
cards.TRL_524 = {
  target = {
    base = "enemy_minion",
    filter = function(g, me, t)
      return g.has(t, "TAUNT")
    end,
  },
  battlecry = function(g, me, t)
    g.silence(t)
  end,
}

-- Arena Treasure Chest: Deathrattle: draw 2 cards.
cards.TRL_525 = {
  deathrattle = function(g, me)
    g.draw(g.ctrl(me), 2)
  end,
}

-- Dragonmaw Scorcher: 1 damage to all other minions.
cards.TRL_526 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if m ~= me then
        g.damage(me, m, 1)
      end
    end
  end,
}

-- Drakkari Trickster: each player gets a copy of a random card of their opponent's deck (the printed card).
cards.TRL_527 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local a, b = g.pick(g.deck(g.opponent(p))), g.pick(g.deck(p))
    if a then
      g.add_to_hand(p, g.card(a))
    end
    if b then
      g.add_to_hand(g.opponent(p), g.card(b))
    end
  end,
}

-- Linecracker: Overkill: double its Attack.
cards.TRL_528 = overkill(function(g, me)
  g.buff(me, g.atk(me), 0)
end)

-- Masked Contender: if you control a Secret, put a random Secret of your deck that is not in play into play.
cards.TRL_530 = {
  glow = function(g, me)
    return #g.traps(g.ctrl(me)) > 0
  end,
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if #g.traps(p) == 0 then
      return
    end
    local e = g.pick(list.filter(g.deck(p), function(d)
      local c = g.card(d)
      return info(g, d).trap and not list.any(g.traps(p), function(s)
        return g.card(s) == c
      end)
    end))
    if e then
      g.put_trap(e)
    end
  end,
}

-- Rumbletusk Shaker: Deathrattle: a 3/2 Rumbletusk Breaker.
cards.TRL_531 = {
  deathrattle = function(g, me)
    summon_here(g, me, "TRL_531t")
  end,
}

-- Mosh'Ogg Announcer: an enemy attacking it has a 50% chance to attack another of its side's characters instead
-- (past Taunt; Ogre Brute's way).
cards.TRL_532 = {
  on = {
    attack = function(g, me, ev)
      if ev.defender ~= me or g.ctrl(ev.attacker) == g.ctrl(me) then
        return
      end
      local other = list.filter(g.chars(g.ctrl(me)), function(c)
        return c ~= me and g.health(c) > 0
      end)
      if #other > 0 and g.random(0, 1) == 1 then
        ev.defender = g.pick(other)
      end
    end,
  },
}

-- Ice Cream Peddler: if you control a Frozen minion, gain 8 Armor.
cards.TRL_533 = {
  glow = function(g, me)
    return list.any(g.minions(g.ctrl(me)), function(m)
      return g.has(m, "FROZEN")
    end)
  end,
  battlecry = function(g, me)
    if list.any(g.minions(g.ctrl(me)), function(m)
      return m ~= me and g.has(m, "FROZEN")
    end) then
      g.gain_armor(g.ctrl(me), 8)
    end
  end,
}

-- Snapjaw Shellfighter: damage to an adjacent minion is dealt to it instead (before modifiers; each Shellfighter once
-- per chain: SNAPJAW_BUSY).
cards.TRL_535 = {
  now = {
    predamage = function(g, me, ev)
      if ev.amount <= 0 or g.zone(me) ~= "PLAY" or g.has(me, "SNAPJAW_BUSY") then
        return
      end
      if not list.any(g.adjacent(me), function(m)
        return m == ev.target
      end) then
        return
      end
      local n = ev.amount
      ev.amount = 0
      g.set_tag(me, "SNAPJAW_BUSY", true)
      g.damage(ev.source, me, n)
      g.set_tag(me, "SNAPJAW_BUSY", nil)
    end,
  },
}

-- Da Undatakah: gains the Deathrattles of 3 random friendly minions that died this game (printed Deathrattles).
cards.TRL_537 = {
  battlecry = function(g, me)
    local dead = list.filter(g.graveyard(g.ctrl(me)), function(e)
      return g.type(e) == "MINION" and g.died_pos(e) >= 0 and has_kw(info(g, e), "DEATHRATTLE")
    end)
    for _, e in ipairs(pick_n(g, dead, 3)) do
      g.enchant(me, { deathrattle = g.card(e), from = e })
    end
  end,
}

-- Hakkar, the Soulflayer: Deathrattle: a Corrupted Blood into each player's deck.
cards.TRL_541 = {
  deathrattle = function(g, me)
    g.add_to_deck(g.ctrl(me), "TRL_541t")
    g.add_to_deck(g.enemy(me), "TRL_541t")
  end,
}

-- Corrupted Blood: Casts When Drawn. Take 3 damage (no Spell Damage: 13.2.0's fix). The player draws on; every
-- Corrupted Blood drawn in a row casts too; then two copies per Blood of the row go into the deck (wiki, Hakkar).
local BLOOD = "TRL_541t"

local function blood(g, me)
  local p = g.ctrl(me)
  local n = 1
  g.damage(me, g.hero(p), 3)
  while not over(g) do
    local d = g.deck(p)
    local top = d[#d]
    if not top or g.card(top) ~= BLOOD then
      g.draw(p)
      break
    end
    g.remove(top, "GRAVEYARD")
    g.log({ type = "cast_when_drawn", player = p, entity = top, card = BLOOD })
    g.damage(top, g.hero(p), 3)
    n = n + 1
  end
  for _ = 1, 2 * n do
    g.add_to_deck(p, BLOOD)
  end
end

cards.TRL_541t = {
  spell = blood,
  hand = {
    draw = function(g, me, ev)
      if ev.entity == me then
        local p = g.ctrl(me)
        g.remove(me, "GRAVEYARD")
        g.log({ type = "cast_when_drawn", player = p, entity = me, card = g.card(me) })
        blood(g, me)
      end
    end,
  },
}

-- Oondasta: Rush. Overkill: summon a random Beast from your hand (no Battlecry).
cards.TRL_542 = overkill(function(g, me)
  local p = g.ctrl(me)
  if g.room(p) <= 0 then
    return
  end
  local b = g.pick(list.filter(g.hand(p), function(e)
    return g.type(e) == "MINION" and (g.race(e) == "BEAST" or g.race(e) == "ALL")
  end))
  if b then
    local pos = g.board_pos(me)
    g.summon_entity(b, pos and pos + 1 or nil)
  end
end)

-- Ornery Tortoise: 5 damage to your hero.
cards.TRL_546 = {
  battlecry = function(g, me)
    g.damage(me, g.hero(g.ctrl(me)), 5)
  end,
}

-- Mojomaster Zihi: each player has 5 Mana Crystals (above: the spent ones go first; below: empty ones come).
cards.TRL_564 = {
  battlecry = function(g, me)
    for p = 0, 1 do
      local m = g.mana(p)
      if m > 5 then
        m = 5
      end
      g.set_mana(p, m, 5)
    end
  end,
}

-- Crowd Roaster: if you're holding a Dragon, 7 damage to an enemy minion.
cards.TRL_569 = {
  glow = function(g, me)
    return holding(g, me, "DRAGON")
  end,
  target = {
    base = "enemy_minion",
    when = function(g, me)
      return holding(g, me, "DRAGON")
    end,
  },
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, 7)
    end
  end,
}

-- Soup Vendor: whenever you restore 3 or more Health to your hero (actually restored), draw a card.
cards.TRL_570 = {
  on = {
    heal = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.target == g.hero(p) and ev.amount >= 3 then
        g.draw(p)
      end
    end,
  },
}

return cards
