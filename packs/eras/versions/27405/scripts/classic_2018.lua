-- The four Classic cards of patch 12.4.0.27405 (2018-11-05): Icicle, Tome of Intellect, Call of the Void and Pilfer,
-- copied from Rastakhan's Rumble's scripts (packs/trl/scripts/trl_a.lua, trl_b.lua) with the helpers they use.
local cards = {}

-- A card (its g.info) of the class: a tri-class card is one of each of its classes (cards.md `classes`).
local function of_class(i, cls)
  if i.classes then
    return list.any(i.classes, function(c)
      return c == cls
    end)
  end
  return i.class == cls
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

local function mage_spell(i)
  return i.type == "SPELL" and of_class(i, "MAGE")
end

-- Icicle: 2 damage to a minion; if it's Frozen, draw a card.
cards.EX1_179 = {
  target = "minion",
  spell = function(g, me, t)
    local frozen = g.has(t, "FROZEN")
    g.damage(me, t, g.spell_dmg(me, 2))
    if frozen or g.has(t, "FROZEN") then
      g.draw(g.ctrl(me))
    end
  end,
}

-- Tome of Intellect: a random Mage spell.
cards.EX1_180 = {
  spell = function(g, me)
    g.add_to_hand(g.ctrl(me), random_card(g, mage_spell))
  end,
}

-- Call of the Void: a random Demon.
cards.EX1_181 = {
  spell = function(g, me)
    local c = random_card(g, minion_of(function(i)
      return i.race == "DEMON"
    end))
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Pilfer: a random card of the opponent's class.
cards.EX1_182 = {
  spell = function(g, me)
    local c = random_class_card(g, g.class(g.hero(g.enemy(me))))
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

return cards
