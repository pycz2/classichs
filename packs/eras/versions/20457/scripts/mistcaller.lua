-- The Mistcaller from patch 7.0.0.15590: the minions in your hand and your deck +1/+1, as its text says (until then the
-- minions in the hand and every minion drawn later that game; the deck was not touched).
local cards = {}

cards.AT_054 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _, zone in ipairs({ g.hand(p), g.deck(p) }) do
      for _, c in ipairs(zone) do
        if g.type(c) == "MINION" then
          g.buff(c, 1, 1)
        end
      end
    end
  end,
}

return cards
