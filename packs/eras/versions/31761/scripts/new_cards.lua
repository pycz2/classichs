-- Patch 14.6.0.31761 (2019-06-03): the cards that came after Rise of Shadows' release. SN1P-SN4P (from 14.4.0.31268),
-- the ten new Classic and Basic cards of 14.6 and Pilfer's rework (hearthstone.wiki.gg, each card's page).
local cards = {}

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }

local function playable(class)
  return list.any(CLASSES, function(c)
    return c == class
  end)
end

-- A random collectible card of the pack's constructed sets whose data (g.info) pass ok, or nil.
local function random_card(g, ok)
  return g.pick(list.filter(g.collectible(), function(c)
    return ok(g.info(c))
  end))
end

local function summon_here(g, me, card)
  local pos = g.died_pos(me)
  return g.summon(g.ctrl(me), card, pos >= 0 and pos or nil)
end

-- SN1P-SN4P: Magnetic, Echo (data); Deathrattle: two 1/1 Microbots.
cards.BOT_700 = {
  deathrattle = function(g, me)
    for _ = 1, 2 do
      summon_here(g, me, "BOT_312t")
    end
  end,
}

-- Pilfer (14.6): a random card of a class other than yours (no neutral card; DOUBT: a tri-class card is left out, as
-- Stolen Steel's "another class" does).
cards.EX1_182 = {
  spell = function(g, me)
    local mine = g.class(g.hero(g.ctrl(me)))
    local c = random_card(g, function(i)
      return playable(i.class) and i.class ~= mine
    end)
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Gift of the Wild: your minions +2/+2 and Taunt.
cards.EX1_183 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.buff(m, 2, 2)
      g.give_tag(m, "TAUNT")
    end
  end,
}

-- Righteousness: your minions get Divine Shield.
cards.EX1_184 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      g.give_tag(m, "DIVINE_SHIELD")
    end
  end,
}

-- Siegebreaker: Taunt (data); your other Demons have +1 Attack.
cards.EX1_185 = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "DEMON" then
        g.aura_add(m, 1, 0)
      end
    end
  end,
}

-- SI:7 Infiltrator: destroy a random enemy Secret (as Flare destroys them).
cards.EX1_186 = {
  battlecry = function(g, me)
    local s = g.pick(g.traps(g.enemy(me)))
    if s then
      g.remove(s, "GRAVEYARD")
      g.log({ type = "destroy", target = s })
    end
  end,
}

-- Arcane Devourer: whenever you cast a spell, +2/+2.
cards.EX1_187 = {
  on = {
    play = function(g, me, ev)
      if lib.my_spell(g, me, ev) then
        g.buff(me, 2, 2)
      end
    end,
  },
}

-- Barrens Stablehand: summon a random Beast.
cards.EX1_188 = {
  battlecry = function(g, me)
    local c = random_card(g, function(i)
      return i.type == "MINION" and i.race == "BEAST"
    end)
    if c then
      g.summon_right(me, c)
    end
  end,
}

-- Brightwing: a random Legendary minion to your hand.
cards.EX1_189 = {
  battlecry = function(g, me)
    local c = random_card(g, function(i)
      return i.type == "MINION" and i.rarity == "LEGENDARY"
    end)
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- High Inquisitor Whitemane: summon every friendly minion that died this turn, in the order they died (the player
-- hooks' DIED_ORDER), while there is room.
cards.EX1_190 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local dead = list.filter(g.graveyard(p), function(e)
      return g.type(e) == "MINION" and g.died_pos(e) >= 0 and g.tag(e, "DIED_TURN") == g.turn()
    end)
    for _, e in ipairs(list.sort_by(dead, function(e)
      return g.tag(e, "DIED_ORDER")
    end)) do
      if g.room(p) == 0 then
        break
      end
      g.summon(p, g.card(e))
    end
  end,
}

-- Plaguebringer: a friendly minion gets Poisonous.
cards.EX1_191 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me
  end },
  battlecry = function(g, me, t)
    if t then
      g.give_tag(t, "POISONOUS")
    end
  end,
}

-- Radiance: restore 5 Health to your hero.
cards.EX1_192 = {
  spell = function(g, me)
    g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 5))
  end,
}

return cards
