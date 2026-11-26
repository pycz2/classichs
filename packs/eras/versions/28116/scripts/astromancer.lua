-- Astromancer before patch 13.4.0.29349 ("now correctly summons a minion immediately next to her instead of the far
-- right of the board"): a random minion whose Cost is your hand's size, at the right end of the board.
local cards = {}

cards.BOT_256 = {
  battlecry = function(g, me)
    local n = #g.hand(g.ctrl(me))
    local pool = list.filter(g.collectible(), function(c)
      local i = g.info(c)
      return i.type == "MINION" and i.cost == n
    end)
    local c = g.pick(pool)
    if c then
      g.summon(g.ctrl(me), c)
    end
  end,
}

return cards
