-- Version 9.4.0.22115 (2017-11-06): Marin the Fox, given to every player a month before Kobolds & Catacombs came out,
-- its Master Chest and the four treasures (packs/loot/scripts/loot_neutral.lua, with the helpers they need).
local cards = {}

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }

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

local function info(g, e)
  return g.info(g.card(e))
end

-- A random collectible card of the pack's constructed sets whose data pass ok.
local function random_card(g, ok)
  return g.pick(list.filter(g.collectible(), function(c)
    return ok(g.info(c))
  end))
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

-- --- the cards -----------------------------------------------------------------------------------------------------

-- Marin the Fox: a 0/8 Master Chest for your opponent; its Deathrattle gives the chest's opponent (Marin's player) one
-- of four treasures.
cards.LOOT_357 = {
  battlecry = function(g, me)
    g.summon(g.enemy(me), "LOOT_357l")
  end,
}
cards.LOOT_357l = {
  deathrattle = function(g, me)
    g.add_to_hand(g.enemy(me), g.pick({ "LOOT_998h", "LOOT_998j", "LOOT_998k", "LOOT_998l" }))
  end,
}

-- Tolin's Goblet: draw a card, fill your hand with plain copies of it.
-- The card p draws now as it is in the hand, or nil (burnt, fatigue).
local function draw_one(g, p)
  local n = #g.hand(p)
  g.draw(p)
  local h = g.hand(p)
  return #h > n and h[#h] or nil
end

cards.LOOT_998h = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local d = draw_one(g, p)
    if not d then
      return
    end
    local c = g.card(d)
    while #g.hand(p) < g.rule("hand") do
      if not g.add_to_hand(p, c) then
        break
      end
    end
  end,
}

-- Zarog's Crown: Discover a Legendary minion, summon two copies of it.
local function legendary_minion(i)
  return i.type == "MINION" and i.rarity == "LEGENDARY"
end
cards.LOOT_998j = {
  spell = function(g, me)
    discover(g, me, legendary_minion)
  end,
  on_choose = function(g, me, option)
    for _ = 1, 2 do
      g.summon(g.ctrl(me), g.card(option))
    end
  end,
}

-- Golden Kobold: every card of your hand becomes a random Legendary minion.
cards.LOOT_998k = {
  battlecry = function(g, me)
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      local c = random_card(g, legendary_minion)
      if c then
        g.transform(e, c)
      end
    end
  end,
}

-- Wondrous Wand: draw 3 cards, they cost (0).
cards.LOOT_998l = {
  spell = function(g, me)
    for _ = 1, 3 do
      local d = draw_one(g, g.ctrl(me))
      if d then
        g.enchant(d, { cost_set = 0 })
      end
    end
  end,
}

return cards
