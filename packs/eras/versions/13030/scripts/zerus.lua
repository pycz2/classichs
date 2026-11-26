-- Shifter Zerus (patch 5.0.0.13030, 2016-06-01): at the start of each of your turns while it is in your hand (not the
-- turn it came), it becomes a random minion that keeps shifting until it leaves the hand; no longer one with Choose One.
local cards = {}

local function shift(g, me, ev)
  if g.mine(me, ev) then
    local m = g.pick(list.filter(g.collectible(), function(c)
      local i = g.info(c)
      return i.type == "MINION" and not list.any(i.keywords, function(k)
        return k == "CHOOSE_ONE"
      end)
    end))
    local n = m and g.transform(me, m)
    if n then
      g.enchant(n, { hooks = "ench:zerus" })
    end
  end
end
cards.OG_123 = { hand = { turn_start = shift } }
cards["ench:zerus"] = { hand = { turn_start = shift } }

return cards
