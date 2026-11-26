-- Patch 14.2.0.30795 (2019-05-14) on Rise of Shadows' pack: Kalecgos and The Forest's Aid (hearthstone.wiki.gg,
-- Patch 14.2.0.30795). Each later version of the era keeps them (a copy of this file).
local cards = {}

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

-- Discover as packs/dal/scripts/dal_dhmpp.lua's (the class cards four times as likely as the neutral ones).
local function discover(g, me, ok)
  local p = g.ctrl(me)
  local cls = g.class(g.hero(p))
  if not playable(cls) then
    cls = g.info(g.card(me)).class
    if not playable(cls) then
      cls = CLASSES[g.random(1, #CLASSES)]
    end
  end
  local left = {}
  for _, c in ipairs(g.collectible()) do
    local i = g.info(c)
    if ok(i) then
      if of_class(i, cls) then
        left[#left + 1] = { c, 4 }
      elseif i.class == "NEUTRAL" and not i.classes then
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

-- Kalecgos: your first spell each of your turns costs (0); from this patch a countered spell uses the discount up too
-- ("Kalecgos no longer grants a discount to another spell if the first spell is countered"): no spell played yet this
-- turn (the player hooks' TURN_SPELLS, countered ones too) instead of the base's no spell resolved (RESOLVED).
cards.DAL_609 = {
  cost_aura = function(g, me, card, cost)
    local p = g.ctrl(me)
    if g.ctrl(card) == p and g.type(card) == "SPELL" and g.zone(card) == "HAND" and g.current() == p
        and g.count(p, "TURN_SPELLS") == 0 then
      return 0
    end
    return cost
  end,
  battlecry = function(g, me)
    discover(g, me, function(i)
      return i.type == "SPELL"
    end)
  end,
  on_choose = function(g, me, option)
    return g.add_to_hand(g.ctrl(me), g.card(option))
  end,
}

-- The Forest's Aid (Twinspell, its copy too): five 2/2 Treants; from this patch not with a full board
-- (REQ_NUM_MINION_SLOTS).
cards.DAL_256 = {
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 5 do
      if not g.summon(p, "DAL_256t2") then
        break
      end
    end
  end,
}

return cards
