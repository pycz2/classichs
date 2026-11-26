-- Patch 2.7.0.9166 (2015-06-15). Swipe and Explosive Shot deal all their damage before any on-damage trigger runs
-- (a Patron, Imp or Whelp they make is not hit); the triggers come in the order of the hits: the target's first,
-- then Explosive Shot's right neighbour before its left one, Swipe's other enemies newest first (the wiki).
local cards = {}

-- Swipe: 4 damage to an enemy and 1 to every other enemy.
cards.VAN_CS2_012 = {
  target = "enemy_char",
  spell = function(g, me, t)
    local others = {}
    for _, c in ipairs(g.all_chars()) do
      if c ~= t and g.ctrl(c) == g.ctrl(t) then
        table.insert(others, 1, c)
      end
    end
    g.damage(me, t, g.spell_dmg(me, 4))
    for _, c in ipairs(others) do
      g.damage(me, c, g.spell_dmg(me, 1))
    end
  end,
}

-- Explosive Shot: 5 damage to a minion and 2 to the minions next to it.
cards.VAN_EX1_537 = {
  target = "minion",
  spell = function(g, me, t)
    local near = g.adjacent(t)
    g.damage(me, t, g.spell_dmg(me, 5))
    for i = #near, 1, -1 do
      g.damage(me, near[i], g.spell_dmg(me, 2))
    end
  end,
}

-- Shadow of Nothing (Mindgames): no longer destroys itself at the end of the turn.
cards.VAN_EX1_345t = {}

return cards
