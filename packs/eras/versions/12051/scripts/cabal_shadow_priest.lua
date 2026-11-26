-- Cabal Shadow Priest (patch 4.2.0.12051, 2016-03-14: the data lost REQ_MINION_CAP_IF_TARGET_AVAILABLE; the wiki
-- dates it 4.3.0.12266): playable with a full board; the minion is then destroyed (as packs/og/scripts/og.lua has it).
local cards = {}

cards.VAN_EX1_091 = {
  target = {
    base = "enemy_minion",
    filter = function(g, me, t)
      return g.atk(t) <= 2
    end,
  },
  battlecry = function(g, me, t)
    g.take_control(t, g.ctrl(me))
  end,
}

return cards
