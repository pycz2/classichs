-- Helpers shared by the Neonfall card scripts (the global `lib` in every other file).
local lib = {}

-- An `on` hook set for event `ty` that runs f(g, me, ev) on me's controller's events only.
function lib.on_mine(ty, f)
  return {
    on = {
      [ty] = function(g, me, ev)
        if g.mine(me, ev) then
          f(g, me, ev)
        end
      end,
    },
  }
end

-- A random living enemy minion of me's controller, or nil.
function lib.random_enemy_minion(g, me)
  return g.random_alive(g.minions(g.enemy(me)))
end

-- Redline: while damaged, the minion has these tags (an aura on itself).
function lib.redline(tags)
  return {
    aura = function(g, me)
      if g.dmg(me) > 0 then
        g.aura_add(me, 0, 0, tags)
      end
    end,
  }
end

-- me's side has room for one more minion.
function lib.room(g, me)
  return g.room(g.ctrl(me)) > 0
end

return lib
