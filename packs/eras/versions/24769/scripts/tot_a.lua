-- Taverns of Time (the Arena event of 2018-06-11 to 07-02; packs/eras/formats.json `extra`): the neutral cards and
-- Chromie's Historical Epochs as build 24769 has them (HearthstoneJSON; hearthstone.wiki.gg). Arena-only, never
-- collectible. The class cards are in tot_b.lua.
local cards = {}

local function pool(g, ok)
  return list.filter(g.collectible(), function(c)
    return ok(g.info(c))
  end)
end

local function random_card(g, ok)
  return g.pick(pool(g, ok))
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

-- Discover: three different cards passing ok, the class's four times as likely as the neutral ones (gil.lua's).
local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
local function discover(g, me, ok)
  local p = g.ctrl(me)
  local cls = g.class(g.hero(p))
  if not list.any(CLASSES, function(c)
    return c == cls
  end) then
    cls = CLASSES[g.random(1, #CLASSES)]
  end
  local left = {}
  for _, c in ipairs(g.collectible()) do
    local i = g.info(c)
    if ok(i) and not i.classes then
      if i.class == cls then
        left[#left + 1] = { c, 4 }
      elseif i.class == "NEUTRAL" then
        left[#left + 1] = { c, 1 }
      end
    end
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

-- "Cast this when drawn" (TOPDECK; gil.lua's): drawn, it leaves the hand and casts itself; played, the same.
local function cast_when_drawn(f)
  return {
    spell = function(g, me)
      f(g, me)
    end,
    hand = {
      draw = function(g, me, ev)
        if ev.entity == me then
          g.remove(me, "GRAVEYARD")
          g.log({ type = "cast_when_drawn", player = g.ctrl(me), entity = me, card = g.card(me) })
          f(g, me)
        end
      end,
    },
  }
end

-- Chromie: Battlecry: shuffle the four Historical Epochs into your deck.
cards.TOT_030 = {
  battlecry = function(g, me)
    for i = 1, 4 do
      g.add_to_deck(g.ctrl(me), "TOT_030t" .. i)
    end
  end,
}

-- Opening the Dark Portal: two random Legendary minions to your hand; draw a card.
cards.TOT_030t1 = cast_when_drawn(function(g, me)
  local p = g.ctrl(me)
  for _ = 1, 2 do
    g.add_to_hand(p, random_card(g, function(i)
      return i.type == "MINION" and i.rarity == "LEGENDARY"
    end))
  end
  g.draw(p)
end)

-- Battle for Mount Hyjal: your minions +2/+2; draw a card.
cards.TOT_030t2 = cast_when_drawn(function(g, me)
  local p = g.ctrl(me)
  for _, m in ipairs(g.minions(p)) do
    g.buff(m, 2, 2)
  end
  g.draw(p)
end)

-- Escape from Durnholde: two random spells to your hand; draw a card.
cards.TOT_030t3 = cast_when_drawn(function(g, me)
  local p = g.ctrl(me)
  for _ = 1, 2 do
    g.add_to_hand(p, random_card(g, function(i)
      return i.type == "SPELL" and not i.task
    end))
  end
  g.draw(p)
end)

-- Culling of Stratholme: $2 damage to all enemies; draw a card.
cards.TOT_030t4 = cast_when_drawn(function(g, me)
  local p = g.ctrl(me)
  for _, c in ipairs(g.chars(g.opponent(p))) do
    g.damage(me, c, g.spell_dmg(me, 2))
  end
  g.draw(p)
end)

-- Wildlands Adventurer: Battlecry: a random card of the Hall of Fame (HearthstoneJSON 24769's HOF set).
local HALL_OF_FAME = { "VAN_CS2_031", "VAN_EX1_016", "VAN_EX1_050", "VAN_EX1_062", "VAN_EX1_112", "VAN_EX1_128",
  "VAN_EX1_284", "VAN_EX1_295", "VAN_EX1_298", "VAN_EX1_316", "VAN_EX1_620", "VAN_NEW1_016", "VAN_PRO_001" }
cards.TOT_056 = {
  battlecry = function(g, me)
    g.add_to_hand(g.ctrl(me), g.pick(HALL_OF_FAME))
  end,
}

-- Infinite Murloc: Battlecry: shuffle an Infinite Murloc into your deck; your future ones get +1/+1 (each one played
-- gets +1/+1 for every one its player played before it; the count INFINITE_MURLOCS).
-- ponytail: the bonus shows once it is played, not on the card in the hand or deck.
cards.TOT_067 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local n = g.count(p, "INFINITE_MURLOCS")
    if n > 0 then
      g.buff(me, n, n)
    end
    g.add_count(p, "INFINITE_MURLOCS")
    g.add_to_deck(p, "TOT_067")
  end,
}

-- Stasis Dragon: it enters Dormant (UNTOUCHABLE, as The Darkness) and awakens at the start of its player's second turn
-- after (STASIS: the turns left), with its Rush.
cards.TOT_109 = {
  on = {
    summon = function(g, me, ev)
      if ev.entity == me then
        g.give_tag(me, "UNTOUCHABLE")
        g.set_tag(me, "STASIS", 2)
      end
    end,
    turn_start = function(g, me, ev)
      if g.mine(me, ev) and g.has(me, "UNTOUCHABLE") and g.tag(me, "STASIS") > 0 then
        g.add_tag(me, "STASIS", -1)
        if g.tag(me, "STASIS") <= 0 then
          g.erase_tag(me, "UNTOUCHABLE")
          g.log({ type = "awaken", player = g.ctrl(me), entity = me, card = g.card(me) })
        end
      end
    end,
  },
}

-- Timebound Giant: costs (1) less for each card you've drawn (the starting hand too): the cards gone from the deck.
-- ponytail: the gil player hooks count no draws; a card shuffled into the deck (or one taken from it without a draw)
-- throws the count off.
cards.TOT_110 = {
  cost_mod = function(g, me)
    return -math.max(0, g.rule("deck_size") - #g.deck(g.ctrl(me)))
  end,
}

-- Timeline Witness: instead of drawing your normal card each turn, Discover a card from your deck: the first card its
-- player draws in a turn (once it is in play: WITNESS_TURN) goes back into the deck, and three different cards of the
-- deck are offered; the chosen one is drawn.
local function witness_offer(g, me, p)
  local seen, ids = {}, {}
  for _, e in ipairs(g.deck(p)) do
    if not seen[g.card(e)] then
      seen[g.card(e)] = true
      ids[#ids + 1] = e
    end
  end
  local opts = pick_n(g, ids, 3)
  if #opts > 0 then
    g.request_choice(me, opts)
  end
end
cards.TOT_111 = {
  on = {
    summon = function(g, me, ev)
      if ev.entity == me then
        g.set_tag(me, "WITNESS_TURN", g.turn())
      end
    end,
    draw = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.player ~= p or g.current() ~= p or g.tag(me, "WITNESS_TURN") == g.turn() then
        return
      end
      g.set_tag(me, "WITNESS_TURN", g.turn())
      if g.zone(ev.entity) == "HAND" then
        g.to_deck(ev.entity, p)
        witness_offer(g, me, p)
      end
    end,
  },
  on_choose = function(g, me, opt)
    local p = g.ctrl(opt)
    if g.zone(opt) == "DECK" then
      g.draw_entity(p, opt)
    end
  end,
}

-- Possibility Seeker: Battlecry: shuffle your hand into your deck; draw that many cards.
cards.TOT_112 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local hand = g.hand(p)
    for _, e in ipairs(hand) do
      g.to_deck(e, p)
    end
    if #hand > 0 then
      g.draw(p, #hand)
    end
  end,
}

-- Timeway Wanderer: Battlecry: Discover a spell; it costs (5) less and goes on top of your deck.
cards.TOT_116 = {
  battlecry = function(g, me)
    discover(g, me, function(i)
      return i.type == "SPELL" and not i.task
    end)
  end,
  on_choose = function(g, me, opt)
    local p = g.ctrl(me)
    local e = g.add_to_deck(p, g.card(opt))
    if e then
      g.enchant(e, { cost = -5 })
      g.to_deck(e, p, #g.deck(p))
    end
  end,
}

-- Murozond: Battlecry: from now on its player draws 2 extra cards each turn (an enchantment of the champion).
-- ponytail: the 15-second turns are left out (the engine times turns only by a minion in play, cards.md
-- `turn_seconds`); a new champion (a hero card) loses the extra draws.
cards.TOT_332 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    g.enchant(g.hero(p), { hooks = "ench:tot_murozond", player = p })
  end,
}
cards["ench:tot_murozond"] = {
  on = {
    turn_start = function(g, me, ev)
      if ev.player == g.ctrl(me) then
        g.draw(ev.player, 2)
      end
    end,
  },
}

-- Temporal Anomaly: when you draw this, a random spell of your class to your hand.
cards.TOT_334 = {
  hand = {
    draw = function(g, me, ev)
      if ev.entity == me then
        local p = g.ctrl(me)
        local cls = g.class(g.hero(p))
        local s = random_card(g, function(i)
          return i.type == "SPELL" and i.class == cls and not i.task
        end)
        if s then
          g.add_to_hand(p, s)
        end
      end
    end,
  },
}

return cards
