-- Swipe and Explosive Shot before patch 2.7.0.9166 (2015-06-15): the main target is hit, its on-damage triggers
-- run (and the dead die), then the others are hit, so a Grim Patron, Imp or Whelp those triggers summoned is hit
-- too. Since 2.7.0.9166 all their damage comes first (the Classic scripts).
local cards = {}

-- Swipe: 4 damage to an enemy, then 1 to every other enemy (as they are after the first hit's triggers).
cards.VAN_CS2_012 = {
  target = "enemy_char",
  spell = function(g, me, t)
    local p = g.ctrl(t)
    g.damage(me, t, g.spell_dmg(me, 4))
    g.resolve()
    for _, c in ipairs(g.chars(p)) do
      if c ~= t then
        g.damage(me, c, g.spell_dmg(me, 1))
      end
    end
  end,
}

-- Explosive Shot: 5 damage to a minion, then 2 to the minions next to it (next to where it stood if it died).
cards.VAN_EX1_537 = {
  target = "minion",
  spell = function(g, me, t)
    local p = g.ctrl(t)
    g.damage(me, t, g.spell_dmg(me, 5))
    g.resolve()
    local near = {}
    if g.board_pos(t) then
      near = g.adjacent(t)
    elseif g.died_pos(t) >= 0 then
      local b, at = g.minions(p), g.died_pos(t)
      near = { b[at], b[at + 1] }
      if not near[1] then
        near = { near[2] }
      end
    end
    for _, m in ipairs(near) do
      g.damage(me, m, g.spell_dmg(me, 2))
    end
  end,
}

return cards
