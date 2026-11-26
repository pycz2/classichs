-- Patch 10.2.0.23180 of 2018-02-06 (packs/eras/versions/23180): the cards whose hooks changed; the data changes are in
-- patch.json. The same in 23576.
local cards = {}

local function no_duplicates(g, p)
  local seen = {}
  for _, e in ipairs(g.deck(p)) do
    local c = g.card(e)
    if seen[c] then
      return false
    end
    seen[c] = true
  end
  return true
end

-- Raza the Chained (packs/gil/scripts/gil.lua's): "If your deck has no duplicates, your Hero Power costs (1) this game"
-- (a new one too); (0) until this patch.
cards.CFM_020 = {
  glow = function(g, me)
    return no_duplicates(g, g.ctrl(me))
  end,
  battlecry = function(g, me)
    local p = g.ctrl(me)
    if no_duplicates(g, p) then
      g.add_cost_mod(p, { kind = "power", set = 1, lasting = true })
    end
  end,
}

return cards
