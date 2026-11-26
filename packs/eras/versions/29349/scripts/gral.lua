-- Gral, the Shark from patch 13.4.0.29349: "will now correctly gain the extra stats if the minion it eats was buffed in
-- the deck" (trl_b.lua's gains the printed stats). Deathrattle: the eaten cards to the hand.
local cards = {}

cards.TRL_409 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local e = g.pick(list.filter(g.deck(p), function(d)
      return g.type(d) == "MINION"
    end))
    if not e then
      return
    end
    local atk, hp = g.atk(e), g.health(e)
    g.remove(e, "GRAVEYARD")
    g.log({ type = "removed_from_deck", player = p, entity = e, card = g.card(e) })
    g.buff(me, atk, hp)
    -- (the eaten entities, kept as player counts: a dead minion's tags are gone by its Deathrattle)
    local key = "GRAL_" .. me
    local n = g.add_count(p, key)
    g.add_count(p, key .. "_" .. n, e)
  end,
  deathrattle = function(g, me)
    local p, key = g.ctrl(me), "GRAL_" .. me
    for k = 1, g.count(p, key) do
      g.add_to_hand(p, g.card(g.count(p, key .. "_" .. k)))
    end
  end,
}

return cards
