-- Helpers shared by the Classic card scripts. Every other script file sees
-- this table as the global `lib` (scripts/lib.lua is loaded first).
local lib = {}

-- The event is a spell the opponent of me's controller played.
function lib.enemy_spell(g, me, ev)
  return ev.kind == "spell" and not g.mine(me, ev)
end

-- The event is a spell me's controller played.
function lib.my_spell(g, me, ev)
  return ev.kind == "spell" and g.mine(me, ev)
end

-- An attack event against me's controller's champion.
function lib.attacks_my_hero(g, me, ev)
  return ev.defender == g.hero(g.ctrl(me))
end

-- me's side has room for one more minion.
function lib.room(g, me)
  return g.room(g.ctrl(me)) > 0
end

-- Deals n spell damage (spell power added) to every enemy minion; then calls after(m) if given.
function lib.each_enemy_minion(g, me, n, after)
  for _, m in ipairs(g.minions(g.enemy(me))) do
    if n then
      g.damage(me, m, g.spell_dmg(me, n))
    end
    if after then
      after(m)
    end
  end
end

-- A hook set: a battlecry or spell with a target that deals n damage (spell: with spell power).
function lib.hit(target, n, spell)
  local f = function(g, me, t)
    g.damage(me, t, spell and g.spell_dmg(me, n) or n)
  end
  if spell then
    return { target = target, spell = f }
  end
  return { target = target, battlecry = f }
end

-- A battlecry that draws n cards.
function lib.draw_battlecry(n)
  return {
    battlecry = function(g, me)
      g.draw(g.ctrl(me), n)
    end,
  }
end

-- An aura: me's other minions get atk/hp.
function lib.others_aura(atk, hp)
  return {
    aura = function(g, me)
      for _, m in ipairs(g.others(me)) do
        g.aura_add(m, atk, hp)
      end
    end,
  }
end

-- A battlecry that summons a token right of me.
function lib.summon_right(card)
  return {
    battlecry = function(g, me)
      g.summon_right(me, card)
    end,
  }
end

return lib
