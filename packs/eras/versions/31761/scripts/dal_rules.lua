-- Patch 14.6.0.31761 (2019-07-01): Dark Bargain, Cleave, Multi-Shot and Forked Lightning need only one enemy minion
-- (REQ_MINIMUM_ENEMY_MINIONS 2 -> 1; g.cast_random no longer fizzles them with one); Rafaam's Scheme and Dreamway
-- Guardians need a free board slot, Duel! a free slot on either side.
local cards = {}

local function hit_two(g, me, n)
  local pool = g.shuffle(g.minions(g.enemy(me)))
  for i = 1, math.min(2, #pool) do
    g.damage(me, pool[i], g.spell_dmg(me, n))
  end
end

local function one_enemy(g, me)
  return #g.minions(g.enemy(me)) >= 1
end

local function my_room(g, me)
  return g.room(g.ctrl(me)) > 0
end

-- Cleave: 2 damage to two random enemy minions.
cards.VAN_CS2_114 = {
  can_play = one_enemy,
  spell = function(g, me)
    hit_two(g, me, 2)
  end,
}

-- Multi-Shot: 3 damage to two random enemy minions.
cards.VAN_DS1_183 = {
  can_play = one_enemy,
  spell = function(g, me)
    hit_two(g, me, 3)
  end,
}

-- Forked Lightning: 2 damage to two random enemy minions.
cards.VAN_EX1_251 = {
  can_play = one_enemy,
  spell = function(g, me)
    hit_two(g, me, 2)
  end,
}

-- Dark Bargain: destroy two random enemy minions (one if there is one), then discard two random cards.
cards.AT_025 = {
  can_play = one_enemy,
  spell = function(g, me)
    local foes = g.shuffle(g.minions(g.enemy(me)))
    for i = 1, math.min(2, #foes) do
      g.destroy(foes[i])
    end
    g.discard_random(g.ctrl(me), 2)
  end,
}

-- Rafaam's Scheme: summon X 1/1 Imps (X = 1, +1 each turn in the hand: packs/dal/scripts/dal_rsww.lua's scheme).
cards.DAL_007 = {
  hand = {
    turn_start = function(g, me, ev)
      if ev.player == g.ctrl(me) then
        g.add_tag(me, "SCHEME", 1)
      end
    end,
  },
  text = function(g, me)
    return tostring(1 + g.tag(me, "SCHEME"))
  end,
  can_play = my_room,
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 1 + g.tag(me, "SCHEME") do
      if not g.summon(p, "DAL_751t") then
        break
      end
    end
  end,
}

-- Dreamway Guardians: two 1/2 Lifesteal Dryads.
cards.DAL_733 = {
  can_play = my_room,
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 2 do
      if not g.summon(p, "DAL_733t") then
        break
      end
    end
  end,
}

-- Duel!: a random minion of each player's deck is summoned; yours attacks theirs (not one that Can't Attack).
cards.DAL_731 = {
  can_play = function(g, me)
    local p = g.ctrl(me)
    return g.room(p) > 0 or g.room(g.opponent(p)) > 0
  end,
  spell = function(g, me)
    local p = g.ctrl(me)
    local function pull(q)
      if g.room(q) <= 0 then
        return nil
      end
      local e = g.pick(list.filter(g.deck(q), function(d)
        return g.type(d) == "MINION"
      end))
      return e and g.summon_entity(e)
    end
    local function alive(m)
      return g.zone(m) == "PLAY" and g.health(m) > 0 and not g.has(m, "TO_DESTROY")
    end
    local mine = pull(p)
    local theirs = pull(g.opponent(p))
    g.resolve()
    if mine and theirs and alive(mine) and alive(theirs) and not g.has(mine, "CANT_ATTACK") then
      g.force_attack(mine, theirs)
    end
  end,
}

return cards
