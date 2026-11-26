-- Jungle Giants from patch 12.2.0.26996 (2018-10-02): "The Darkness no longer advances Jungle Giants when summoned".
-- Journey to Un'Goro's quest (packs/ungoro/scripts/ungoro.lua) with The Darkness left out.
local cards = {}

local DARKNESS = "LOOT_526"

local function quest_progress(g, me, n, reward)
  if n <= 0 or g.zone(me) ~= "SECRET" then
    return
  end
  local goal = g.tag(me, "QUEST_PROGRESS_TOTAL")
  local v = math.min(g.tag(me, "QUEST_PROGRESS") + n, goal)
  g.set_tag(me, "QUEST_PROGRESS", v)
  if v >= goal then
    local p = g.ctrl(me)
    g.remove(me, "GRAVEYARD")
    g.log({ type = "quest_done", player = p, entity = me, card = g.card(me) })
    g.add_to_hand(p, reward)
  end
end

-- Jungle Giants (Druid): summon 5 minions with 5 or more Attack (not The Darkness): as each enters play, before its
-- Battlecry, auras counted.
cards.UNG_116 = {
  spell = function(g, me)
    g.set_tag(me, "QUEST_PROGRESS", 0)
    g.set_tag(me, "QUEST_PROGRESS_TOTAL", 5)
  end,
  on = {
    summon = function(g, me, ev)
      local m = ev.entity
      if g.mine(me, ev) and g.is_minion(m) and g.card(m) ~= DARKNESS then
        g.update_auras()
        if g.atk(m) >= 5 then
          quest_progress(g, me, 1, "UNG_116t")
        end
      end
    end,
  },
}

return cards
