-- Ship's Cannon: the game deals its 2 damage after the Pirate is summoned (after its Battlecry), like Knife Juggler;
-- patch 4.1.0.10956 only changed its text to "After you summon a Pirate" (the gvg pack's hook ran on `summon`).
local cards = {}

cards.GVG_075 = {
  on = {
    after_summon = function(g, me, ev)
      if g.mine(me, ev) and ev.entity ~= me and g.race(ev.entity) == "PIRATE" then
        g.damage(me, g.random_alive(g.chars(g.enemy(me))), 2)
      end
    end,
  },
}

return cards
