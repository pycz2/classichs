-- Neutral cards and Jumpstart (the second player's card). Tokens without text have no hooks.
local cards = {}

local function other_friendly(g, me)
  return g.random_alive(g.others(me))
end

-- Jumpstart: gain 1 Mana this turn only.
cards.jumpstart = {
  spell = function(g, me) g.add_mana(g.ctrl(me), 1) end,
}

-- Signal Jammer: Boot: Jam an enemy minion.
cards.signal_jammer = {
  target = "enemy_minion",
  battlecry = function(g, me, t) g.freeze(t) end,
}

-- Courier Drone: Flatline: add a Jumpstart to your hand.
cards.courier_drone = {
  deathrattle = function(g, me) g.add_to_hand(g.ctrl(me), "jumpstart") end,
}

-- Holo Busker: at the end of your turn, another random friendly minion +1 Attack.
cards.holo_busker = lib.on_mine("turn_end", function(g, me)
  local m = other_friendly(g, me)
  if m then
    g.buff(m, 1, 0)
  end
end)

-- Chrome Stray: Flatline: 2 damage to a random enemy minion.
cards.chrome_stray = {
  deathrattle = function(g, me)
    g.damage(me, lib.random_enemy_minion(g, me), 2)
  end,
}

-- Club Bouncer: Flatline: a random friendly minion gets Firewall.
cards.club_bouncer = {
  deathrattle = function(g, me)
    local m = g.random_alive(g.minions(g.ctrl(me)))
    if m then
      g.give_tag(m, "GUARD")
    end
  end,
}

-- Night Market Cook: Boot: restore 3 Health to all friendly characters.
cards.night_market_cook = {
  battlecry = function(g, me)
    for _, c in ipairs(g.chars(g.ctrl(me))) do
      g.heal(me, c, g.heal_amt(me, 3))
    end
  end,
}

-- Bit-Rot Daemon: at the start of your turn, 1 damage to a random enemy.
cards.bitrot_daemon = lib.on_mine("turn_start", function(g, me)
  g.damage(me, g.random_alive(g.chars(g.enemy(me))), 1)
end)

-- Black Market Broker: Boot: add a random class card (a collectible card of any champion's class) to your hand.
cards.black_market_broker = {
  battlecry = function(g, me)
    local pool = list.filter(g.collectible(), function(id) return g.info(id).class ~= "NEUTRAL" end)
    g.add_to_hand(g.ctrl(me), g.pick(pool))
  end,
}

-- Rooftop Sniper: Cloak; Boot: 2 damage to a minion. Cloak is lost by attacking (the engine also
-- drops it when a minion deals damage), so the shot keeps it.
cards.rooftop_sniper = {
  target = "minion",
  battlecry = function(g, me, t)
    local cloaked = g.has(me, "STEALTH")
    g.damage(me, t, 2)
    if cloaked then
      g.give_tag(me, "STEALTH")
    end
  end,
}

-- Lattice Phantom: Cloak; at the end of your turn, Jam a random enemy minion.
cards.lattice_phantom = lib.on_mine("turn_end", function(g, me)
  g.freeze(lib.random_enemy_minion(g, me))
end)

-- Swarm Wrangler: Boot: summon two 1/1 Scrap Drones.
cards.swarm_wrangler = {
  battlecry = function(g, me)
    for _ = 1, 2 do
      g.summon_right(me, "scrap_drone")
    end
  end,
}

-- Rapid-Response Medic: Hardlight; Boot: restore 4 Health.
cards.rapid_response_medic = {
  target = "any",
  battlecry = function(g, me, t) g.heal(me, t, g.heal_amt(me, 4)) end,
}

-- Repo Mech: Firewall; Boot: destroy your opponent's weapon.
cards.repo_mech = {
  battlecry = function(g, me) g.destroy(g.weapon(g.enemy(me))) end,
}

-- Billboard Leviathan: Firewall; at the end of your turn, 1 damage to all enemy minions.
cards.billboard_leviathan = lib.on_mine("turn_end", function(g, me)
  for _, m in ipairs(g.minions(g.enemy(me))) do
    g.damage(me, m, 1)
  end
end)

-- Dr. Lucent Varga: Boot: swap the Attack and Health of all other minions.
cards.varga = {
  battlecry = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if m ~= me then
        g.set_stats(m, g.health(m), g.atk(m))
      end
    end
  end,
}

-- Seawall Colossus: Firewall; Redline: Dual-Core.
cards.seawall_colossus = lib.redline({ DOUBLE_ATTACK = true })

-- The Last Free Mind: Encrypted; at the end of your turn, a random enemy minion becomes a Glitch.
cards.last_free_mind = lib.on_mine("turn_end", function(g, me)
  local m = lib.random_enemy_minion(g, me)
  if m then
    g.transform(m, "glitch")
  end
end)

return cards
