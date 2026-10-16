-- Executive (Director Vale): cards, the Deploy power and the Fork options.
local cards = {}

-- Deploy: summon a 0/2 Sentry Drone with Firewall.
cards.deploy = {
  can_play = lib.room,
  hero_power = function(g, me) g.summon(g.ctrl(me), "sentry_drone") end,
}

-- Field Auditor: Boot: a friendly Drone gets Hardlight.
cards.field_auditor = {
  target = {
    base = "friendly_minion",
    filter = function(g, me, t) return g.race(t) == "DRONE" end,
  },
  battlecry = function(g, me, t) g.give_tag(t, "BARRIER") end,
}

-- Patch Job: restore 3 Health to a minion and give it Firewall.
cards.patch_job = {
  target = "minion",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 3))
    g.give_tag(t, "GUARD")
  end,
}

-- Severance: destroy a friendly minion; its Health as damage to a random enemy minion.
cards.severance = {
  target = "friendly_minion",
  spell = function(g, me, t)
    local n = g.health(t)
    g.destroy(t)
    g.damage(me, lib.random_enemy_minion(g, me), g.spell_dmg(me, n))
  end,
}

-- Executive Decision: Fork: Hard Reset or Retention Bonus.
cards.executive_decision = { choose_one = { "hard_reset", "retention_bonus" } }

-- Hard Reset: Wipe a minion.
cards.hard_reset = {
  target = "minion",
  effect = function(g, me, t) g.silence(t) end,
}

-- Retention Bonus: a minion +2 Health and Firewall.
cards.retention_bonus = {
  target = "minion",
  effect = function(g, me, t)
    g.buff(t, 0, 2)
    g.give_tag(t, "GUARD")
  end,
}

-- Protocol: Golden Parachute: when a friendly minion dies, draw 2.
cards.golden_parachute = {
  secret = {
    event = "death",
    cond = function(g, me, ev) return ev.minion and g.mine(me, ev) end,
    effect = function(g, me) g.draw(g.ctrl(me), 2) end,
  },
}

-- Protocol: Lockout: when the opponent plays a minion, 1 damage to it and Jam it.
cards.lockout = {
  secret = {
    event = "after_summon",
    cond = function(g, me, ev) return ev.played == true and not g.mine(me, ev) end,
    effect = function(g, me, ev)
      g.damage(me, ev.entity, g.spell_dmg(me, 1))
      g.freeze(ev.entity)
    end,
  },
}

-- Protocol: Asset Seizure: when an enemy minion dies, add a copy of it to your hand.
cards.asset_seizure = {
  secret = {
    event = "death",
    cond = function(g, me, ev) return ev.minion and not g.mine(me, ev) end,
    effect = function(g, me, ev) g.add_to_hand(g.ctrl(me), ev.card) end,
  },
}

-- Medic Drone: at the end of your turn, restore 2 Health to a random damaged friendly character.
cards.medic_drone = lib.on_mine("turn_end", function(g, me)
  local hurt = list.filter(g.chars(g.ctrl(me)), function(c) return g.dmg(c) > 0 end)
  local t = g.pick(hurt)
  if t then
    g.heal(me, t, g.heal_amt(me, 2))
  end
end)

-- Grid Overseer: your Drones have +1 Attack.
cards.grid_overseer = {
  aura = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if g.race(m) == "DRONE" then
        g.aura_add(m, 1, 0)
      end
    end
  end,
}

-- Vat-Grown Clone: Boot: summon a copy of this minion.
cards.vat_clone = {
  battlecry = function(g, me)
    local c = g.summon_right(me, "vat_clone")
    if c then
      g.copy_minion(c, me)
    end
  end,
}

-- Enforcement Mech: Flatline: summon two Sentry Drones.
cards.enforcement_mech = {
  deathrattle = function(g, me)
    local p, pos = g.ctrl(me), g.died_pos(me)
    for _ = 1, 2 do
      g.summon(p, "sentry_drone", pos)
    end
  end,
}

-- ARCHON: at the end of your turn, summon a Sentry Drone and give your other Drones +1 Attack.
cards.archon = lib.on_mine("turn_end", function(g, me)
  g.summon_right(me, "sentry_drone")
  for _, m in ipairs(g.others(me)) do
    if g.race(m) == "DRONE" then
      g.buff(m, 1, 0)
    end
  end
end)

return cards
