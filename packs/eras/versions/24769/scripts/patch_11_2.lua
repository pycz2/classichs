-- Patch 11.2.0.24769 of 2018-06-06 on (packs/eras/versions/24769, 25252): the cards whose hooks changed (Tess Greymane
-- and Lynessa Sunsorrow as packs/boom/scripts/boom.lua has them; Rat Trap's fix). Shudderwock is gil's again: the
-- hotfix of 2018-06-11 took its cap back to 30.
local cards = {}

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

local function alive(g, m)
  return g.zone(m) == "PLAY" and g.health(m) > 0 and not g.has(m, "TO_DESTROY")
end

local function over(g)
  return g.health(g.hero(0)) <= 0 or g.health(g.hero(1)) <= 0
end

-- Tess Greymane: replays every card from another class you played this game, hero cards too, at most 30, in random
-- order with random targets and choices; she stops once she is silenced, dead, transformed or out of play, or a hero
-- has died. A hero card becomes your hero (its Armor, its power, its Battlecry with random choices). Until this patch:
-- no hero cards, no cap, on after she dies (packs/gil/scripts/gil_ppr.lua).
cards.GIL_598 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local cls = g.class(g.hero(p))
    local replay = {}
    for i = 1, g.count(p, "OTHER_CARDS") do
      local e = g.count(p, "OTHER_CARDS_" .. i)
      local inf = info(g, e)
      if e ~= me and not is_neutral(inf) and not of_class(inf, cls) then
        replay[#replay + 1] = inf.id
      end
    end
    for i, c in ipairs(g.shuffle(replay)) do
      if i > 30 or not alive(g, me) or g.silenced(me) or over(g) then
        break
      end
      local t = g.info(c).type
      if t == "SPELL" then
        g.cast_random(me, c, true)
      elseif t == "MINION" then
        g.summon(p, c)
      elseif t == "WEAPON" then
        g.equip(p, c)
      elseif t == "CHAMPION" then
        g.battlecry(g.replace_hero(p, c, true), c)
      end
      g.resolve()
    end
  end,
}

-- Lynessa Sunsorrow: every spell you cast on your minions this game (ON_OWN_MINION), Choose One spells too (as they
-- were cast), in random order, cast again on her; at most 30; it stops once she is gone. Until this patch: no cap, the
-- order they were played in, no Choose One spell (packs/loot/scripts/loot_ppr.lua).
cards.LOOT_216 = {
  battlecry = function(g, me)
    local spells = list.filter(g.graveyard(g.ctrl(me)), function(s)
      return g.is_spell(s) and g.has(s, "ON_OWN_MINION")
    end)
    for i, s in ipairs(g.shuffle(spells)) do
      if i > 30 or not alive(g, me) then
        break
      end
      g.cast(me, s, me)
      g.resolve()
    end
  end,
}

-- Rat Trap (packs/gil/scripts/gil_dhm.lua's): after your opponent plays a third card in a turn, a 6/6 Doom Rat; since
-- this patch it waits while your board is full (it went off for nothing before).
local function rat_trap(g, me)
  if g.room(g.ctrl(me)) > 0 then
    g.reveal(me)
    g.summon(g.ctrl(me), "GIL_577t")
  end
end
local function rat_after(g, me, ev)
  if g.trap_ready(me) and g.tag(me, "RAT_TRAP_CARD") == ev.entity then
    rat_trap(g, me)
  end
end
cards.GIL_577 = {
  on = {
    play = function(g, me, ev)
      local foe = g.enemy(me)
      if ev.player == foe and g.trap_ready(me) and g.cards_played(foe) >= 3 then
        if ev.kind == "champion" then
          rat_trap(g, me)
        else
          g.set_tag(me, "RAT_TRAP_CARD", ev.entity)
        end
      end
    end,
    after_summon = rat_after,
    after_spell = rat_after,
    equip = rat_after,
  },
}

return cards
