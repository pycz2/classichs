-- Patch 8.4.0.20022 (2017-07-10) over Journey to Un'Goro: The Caverns Below needs five minions with the same name
-- (as packs/icc/scripts/icc.lua has it).
local cards = {}

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

cards.UNG_067 = {
  spell = function(g, me)
    g.set_tag(me, "QUEST_PROGRESS", 0)
    g.set_tag(me, "QUEST_PROGRESS_TOTAL", 5)
  end,
  on = {
    play = function(g, me, ev)
      if ev.kind == "minion" and g.mine(me, ev) then
        local key = "CAVERNS_" .. ev.card
        local n = g.tag(me, key) + 1
        g.set_tag(me, key, n)
        quest_progress(g, me, n - g.tag(me, "QUEST_PROGRESS"), "UNG_067t1")
      end
    end,
  },
}

return cards
