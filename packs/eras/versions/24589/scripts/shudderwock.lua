-- Patch 11.1.0.24377 of 2018-05-08 to the hotfix of 2018-06-11 (packs/eras/versions/24377 and 24589): Shudderwock
-- replays at most 20 Battlecries.
local cards = {}

local function alive(g, m)
  return g.zone(m) == "PLAY" and g.health(m) > 0 and not g.has(m, "TO_DESTROY")
end

local function over(g)
  return g.health(g.hero(0)) <= 0 or g.health(g.hero(1)) <= 0
end

-- Shudderwock (packs/gil/scripts/gil_ssw.lua's, 30 there): the Battlecries of the cards you played this game (not
-- Shudderwocks: the player hooks' BATTLECRIES list), in random order, each as its own with random targets and choices
-- (never itself), its conditions read now; a death phase after each; it stops when Shudderwock is no longer alive in
-- play or the game is over; 20 at most.
cards.GIL_820 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local ids = {}
    for i = 1, g.count(p, "BATTLECRIES") do
      local id = g.count(p, "BATTLECRIES_" .. i)
      if id > 0 then
        ids[#ids + 1] = id
      end
    end
    g.shuffle(ids)
    for i, id in ipairs(ids) do
      if i > 20 or not alive(g, me) or over(g) then
        break
      end
      g.battlecry(me, g.card(id))
      g.resolve()
    end
  end,
}

return cards
