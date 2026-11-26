-- The Taverns of Time class cards (TOT_*), Arena-only from 2018-06-11 to 07-02 (packs/eras/formats.json `extra` of
-- version 24769; ~/ClassicHS-local/prep/patches/modes.md §6). Texts of build 24769.
local cards = {}

local function info(g, e)
  return g.info(g.card(e))
end

local function alive(g, m)
  return g.zone(m) == "PLAY" and g.health(m) > 0 and not g.has(m, "TO_DESTROY")
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

-- The collectible cards whose data pass ok.
local function pool(g, ok)
  return list.filter(g.collectible(), function(c)
    return ok(g.info(c))
  end)
end

-- Up to n different items of a list, each as likely.
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

-- Three different cards of the list offered to me's player (Discover).
local function offer(g, me, ids)
  local p = g.ctrl(me)
  local opts = {}
  for _, c in ipairs(pick_n(g, ids, 3)) do
    opts[#opts + 1] = g.create(p, c)
  end
  if #opts > 0 then
    g.request_choice(me, opts)
  end
end

-- Discover a minion: the champion's class's and the neutral ones (a class card four times as likely, as Kobolds &
-- Catacombs' Discover weighs them).
local function discover_minion(g, me)
  local cls = g.class(g.hero(g.ctrl(me)))
  local ids = {}
  for _, c in ipairs(g.collectible()) do
    local i = g.info(c)
    if i.type == "MINION" then
      if of_class(i, cls) then
        for _ = 1, 4 do
          ids[#ids + 1] = c
        end
      elseif is_neutral(i) then
        ids[#ids + 1] = c
      end
    end
  end
  -- three different cards: pick among the distinct ids by weight
  local opts, seen = {}, {}
  for _ = 1, 50 do
    if #opts == 3 or #ids == 0 then
      break
    end
    local c = ids[g.random(1, #ids)]
    if not seen[c] then
      seen[c] = true
      opts[#opts + 1] = g.create(g.ctrl(me), c)
    end
  end
  if #opts > 0 then
    g.request_choice(me, opts)
  end
end

local function to_hand(g, me, option)
  return g.add_to_hand(g.ctrl(me), g.card(option))
end

-- The sets that were Wild in June 2018: "spells from the past" (Consider the Past).
local WILD = { NAXX = true, GVG = true, BRM = true, TGT = true, LOE = true, OG = true, KARA = true, GANGS = true }

-- --- Druid ---------------------------------------------------------------------------------------------------------------

-- Flash Forward: each player gains two Mana Crystals and draws two cards (you first).
cards.TOT_105 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, q in ipairs({ p, g.opponent(p) }) do
      g.gain_mana(q, 2)
    end
    for _, q in ipairs({ p, g.opponent(p) }) do
      g.draw(q, 2)
    end
  end,
}

-- Harbinger of Catastrophe: at the start of your turn, the highest-cost minion of each player's deck is summoned for
-- that player (yours first; a tie: a random one).
cards.TOT_320 = {
  on = {
    turn_start = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.player ~= p then
        return
      end
      for _, q in ipairs({ p, g.opponent(p) }) do
        local best, top = {}, -1
        for _, e in ipairs(g.deck(q)) do
          if g.type(e) == "MINION" then
            local c = g.cost(e)
            if c > top then
              best, top = { e }, c
            elseif c == top then
              best[#best + 1] = e
            end
          end
        end
        if #best > 0 and g.room(q) > 0 then
          g.summon_entity(g.pick(best))
        end
      end
    end,
  },
}

-- --- Hunter --------------------------------------------------------------------------------------------------------------

-- Infinite Wolf: Rush. After it attacks it is shuffled into your deck and your future Infinite Wolves have +2/+2 more
-- (a count of yours; DOUBT: an aura on the Wolves in play, so a second Wolf already in play grows too).
cards.TOT_117 = {
  aura = function(g, me)
    local n = g.count(g.ctrl(me), "TOT_WOLF")
    if n > 0 then
      g.aura_add(me, 2 * n, 2 * n)
    end
  end,
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker ~= me or not alive(g, me) then
        return
      end
      local p = g.ctrl(me)
      g.add_count(p, "TOT_WOLF")
      g.remove(me, "SETASIDE")
      g.add_to_deck(p, "TOT_117")
    end,
  },
}

-- Chronoshot: an enemy minion back to its owner's hand; it costs (2) more.
cards.TOT_340 = {
  target = "enemy_minion",
  spell = function(g, me, t)
    local c = g.return_to_hand(t)
    if c then
      g.enchant(c, { cost = 2 })
    end
  end,
}

-- --- Mage ----------------------------------------------------------------------------------------------------------------

-- Cavern Dreamer: at the end of your turn, a random spell that costs (2) or less to your hand.
cards.TOT_308 = {
  on = {
    turn_end = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.player == p then
        local c = g.pick(pool(g, function(i)
          return i.type == "SPELL" and i.cost <= 2
        end))
        if c then
          g.add_to_hand(p, c)
        end
      end
    end,
  },
}

-- Consider the Past: three random spells of the Wild sets of the time (DOUBT: of any class).
cards.TOT_341 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local ids = pool(g, function(i)
      return i.type == "SPELL" and WILD[i.set] == true
    end)
    for _ = 1, 3 do
      local c = g.pick(ids)
      if c then
        g.add_to_hand(p, c)
      end
    end
  end,
}

-- --- Paladin -------------------------------------------------------------------------------------------------------------

-- Blessing of Aeons: a minion gains +1/+1 at the end of its blesser's turns.
cards.TOT_069 = {
  target = "minion",
  spell = function(g, me, t)
    g.enchant(t, { hooks = "ench:tot_aeons", player = g.ctrl(me) })
  end,
}
cards["ench:tot_aeons"] = {
  on = {
    turn_end = function(g, me, ev)
      for _, p in ipairs(g.enchants(me, "ench:tot_aeons")) do
        if p == ev.player then
          g.buff(me, 1, 1)
        end
      end
    end,
  },
}

-- Bronze Broodmother: when you draw it, a 1/1 Wee Whelp is summoned.
cards.TOT_330 = {
  hand = {
    draw = function(g, me, ev)
      if ev.entity == me then
        g.summon(g.ctrl(me), "TOT_303t")
      end
    end,
  },
}

-- --- Priest --------------------------------------------------------------------------------------------------------------

-- Reminisce: two random cards your opponent played this game to your hand (the cards of theirs that were played: the
-- pack's PLAYED_COST mark, in their graveyard or in play; DOUBT: a card played for (0) has no mark).
cards.TOT_343 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local o = g.opponent(p)
    local ids = {}
    local function seen(e)
      if g.has(e, "PLAYED_COST") then
        ids[#ids + 1] = g.card(e)
      end
    end
    for _, e in ipairs(g.graveyard(o)) do
      seen(e)
    end
    for _, e in ipairs(g.minions(o)) do
      seen(e)
    end
    if g.weapon(o) then
      seen(g.weapon(o))
    end
    for _ = 1, 2 do
      local c = g.pick(ids)
      if c then
        g.add_to_hand(p, c)
      end
    end
  end,
}

-- Ripple in Time: Discover a minion; played this turn it has Echo (the ECHO tag for this turn; DOUBT: its Echo copy
-- has no Echo of its own).
cards.TOT_345 = {
  spell = function(g, me)
    discover_minion(g, me)
  end,
  on_choose = function(g, me, option)
    local c = to_hand(g, me, option)
    if c then
      g.give_tag(c, "ECHO", true)
    end
  end,
}

-- --- Rogue ---------------------------------------------------------------------------------------------------------------

-- Thief of Futures: a copy of the top card of your opponent's deck to your hand.
cards.TOT_107 = {
  battlecry = function(g, me)
    local d = g.deck(g.enemy(me))
    if #d > 0 then
      g.add_to_hand(g.ctrl(me), g.card(d[#d]))
    end
  end,
}

-- Déjà Vu: Discover a copy of a spell you played this game (the spells in your graveyard; three different ones).
cards.TOT_108 = {
  spell = function(g, me)
    local ids, seen = {}, {}
    for _, e in ipairs(g.graveyard(g.ctrl(me))) do
      local c = g.card(e)
      if e ~= me and g.type(e) == "SPELL" and not seen[c] then
        seen[c] = true
        ids[#ids + 1] = c
      end
    end
    offer(g, me, ids)
  end,
  on_choose = function(g, me, option)
    to_hand(g, me, option)
  end,
}

-- --- Shaman --------------------------------------------------------------------------------------------------------------

-- Stasis Elemental: a minion is Frozen until this leaves the battlefield (frozen again at the start of each turn
-- while this is in play).
cards.TOT_118 = {
  target = "minion",
  battlecry = function(g, me, t)
    if t then
      g.set_tag(t, "TOT_STASIS", me)
      g.enchant(t, { hooks = "ench:tot_stasis", player = g.ctrl(me) })
      g.freeze(t)
    end
  end,
}
cards["ench:tot_stasis"] = {
  on = {
    turn_start = function(g, me)
      local by = g.tag(me, "TOT_STASIS")
      if by > 0 and g.zone(by) == "PLAY" and not g.silenced(by) then
        g.freeze(me)
      else
        g.set_tag(me, "TOT_STASIS", nil)
        g.remove_enchant(me, "ench:tot_stasis")
      end
    end,
  },
}

-- Master of Realities: after you summon a minion, it becomes a random minion that costs (2) more (none of that
-- cost: it stays).
cards.TOT_313 = {
  on = {
    after_summon = function(g, me, ev)
      if ev.entity == me or not g.mine(me, ev) or not alive(g, ev.entity) then
        return
      end
      local cost = info(g, ev.entity).cost + 2
      local c = g.pick(pool(g, function(i)
        return i.type == "MINION" and i.cost == cost
      end))
      if c then
        g.transform(ev.entity, c)
      end
    end,
  },
}

-- --- Warlock -------------------------------------------------------------------------------------------------------------

-- Rift Warden: Battlecry: a random minion of your hand is discarded; Deathrattle: it is summoned.
cards.TOT_102 = {
  battlecry = function(g, me)
    local ms = list.filter(g.hand(g.ctrl(me)), function(e)
      return g.type(e) == "MINION"
    end)
    local e = g.pick(ms)
    if e then
      g.set_tag(me, "TOT_RIFT", e)
      g.discard(e)
    end
  end,
  deathrattle = function(g, me)
    local e = g.tag(me, "TOT_RIFT")
    if e > 0 then
      local pos = g.died_pos(me)
      g.summon(g.ctrl(me), g.card(e), pos >= 0 and pos or nil)
    end
  end,
}

-- Grasp the Future: two cards drawn; they cost (2) less.
cards.TOT_103 = {
  spell = function(g, me)
    for _, e in ipairs(g.draw(g.ctrl(me), 2)) do
      if g.zone(e) == "HAND" then
        g.enchant(e, { cost = -2 })
      end
    end
  end,
}

-- --- Warrior -------------------------------------------------------------------------------------------------------------

-- Draconic Herald: Discover a minion; it gets +3/+3 and goes on top of your deck.
cards.TOT_316 = {
  battlecry = function(g, me)
    discover_minion(g, me)
  end,
  on_choose = function(g, me, option)
    local p = g.ctrl(me)
    local e = g.to_deck(option, p, #g.deck(p))
    if e then
      g.buff(e, 3, 3)
    end
  end,
}

-- Fatecleaver: after it kills a minion, every copy of that minion's card is destroyed, both players' (in play, in the
-- hands and the decks).
cards.TOT_342 = {
  on = {
    after_attack = function(g, me, ev)
      local p = g.ctrl(me)
      local d = ev.defender
      if ev.attacker ~= g.hero(p) or g.weapon(p) ~= me or not d or d < 0 or not g.is_minion(d) then
        return
      end
      if g.health(d) > 0 and not g.has(d, "TO_DESTROY") then
        return
      end
      local c = g.card(d)
      for q = 0, 1 do
        for _, m in ipairs(g.minions(q)) do
          if g.card(m) == c then
            g.destroy(m)
          end
        end
        for _, zone in ipairs({ g.hand(q), g.deck(q) }) do
          for _, e in ipairs(zone) do
            if g.card(e) == c then
              g.remove(e, "GRAVEYARD")
            end
          end
        end
      end
    end,
  },
}

return cards
