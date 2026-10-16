-- Ghost (Iris Null): cards and the Siphon power.
local cards = {}

-- Siphon: 1 damage to a minion; if it dies, draw a card.
cards.siphon = {
  target = "minion",
  hero_power = function(g, me, t)
    g.damage(me, t, g.hp_dmg(me, 1))
    if g.health(t) <= 0 or g.has(t, "TO_DESTROY") then
      g.draw(g.ctrl(me), 1)
    end
  end,
}

-- Zero-Day: 1 damage and Jam; Chain: 3 damage and Jam.
local function zero_day(n)
  return function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, n))
    g.freeze(t)
  end
end
cards.zero_day = { target = "minion", spell = zero_day(1), combo = zero_day(3) }

-- Ghostwalk: a friendly minion +1/+1 and Cloak; Chain: also draw a card.
local function ghostwalk(g, me, t)
  g.buff(t, 1, 1)
  g.give_tag(t, "STEALTH")
end
cards.ghostwalk = {
  target = "friendly_minion",
  spell = ghostwalk,
  combo = function(g, me, t)
    ghostwalk(g, me, t)
    g.draw(g.ctrl(me), 1)
  end,
}

-- Cache Raid: draw a card; Chain: draw 2.
cards.cache_raid = {
  spell = function(g, me) g.draw(g.ctrl(me), 1) end,
  combo = function(g, me) g.draw(g.ctrl(me), 2) end,
}

-- Signal Leech: Bandwidth +1 (card field); after you cast a spell, 1 damage to the enemy champion.
cards.signal_leech = lib.on_mine("after_spell", function(g, me)
  g.damage(me, g.hero(g.enemy(me)), 1)
end)

-- Static Lock: Jam a minion and its neighbours; draw a card.
cards.static_lock = {
  target = "minion",
  spell = function(g, me, t)
    local adj = g.adjacent(t)
    g.freeze(t)
    for _, m in ipairs(adj) do
      g.freeze(m)
    end
    g.draw(g.ctrl(me), 1)
  end,
}

-- Lattice Diver: Cloak (keyword); Chain: return an enemy minion costing (3) or less to its owner's hand.
cards.lattice_diver = {
  combo_target = {
    base = "enemy_minion",
    filter = function(g, me, t) return g.info(g.card(t)).cost <= 3 end,
  },
  combo = function(g, me, t) g.return_to_hand(t) end,
}

-- Firmware Rot: Wipe a minion, then 2 damage to it.
cards.firmware_rot = {
  target = "minion",
  spell = function(g, me, t)
    g.silence(t)
    g.damage(me, t, g.spell_dmg(me, 2))
  end,
}

-- Corrupt: an enemy minion becomes a 0/3 Glitch with Firewall.
cards.corrupt = {
  target = "enemy_minion",
  spell = function(g, me, t) g.transform(t, "glitch") end,
}

-- Packet Storm: 2 damage to all enemy minions; Chain: 3.
local function storm(n)
  return function(g, me)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.damage(me, m, g.spell_dmg(me, n))
    end
  end
end
cards.packet_storm = { spell = storm(2), combo = storm(3) }

-- Recursive Hound: Flatline: add a Hound Shard to your hand.
cards.recursive_hound = {
  deathrattle = function(g, me) g.add_to_hand(g.ctrl(me), "hound_shard") end,
}

-- Root Access: take control of a random enemy minion; the opponent draws 2.
cards.root_access = {
  can_play = function(g, me) return #g.minions(g.enemy(me)) > 0 end,
  spell = function(g, me)
    local p = g.ctrl(me)
    g.take_control(lib.random_enemy_minion(g, me), p)
    g.draw(g.opponent(p), 2)
  end,
}

-- Compiler Wyrm: your spells cost (1) less.
cards.compiler_wyrm = {
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.is_spell(card) and g.zone(card) == "HAND" then
      return math.max(0, cost - 1)
    end
    return cost
  end,
}

-- SABLE: Boot: Wipe all enemy minions.
cards.sable = {
  battlecry = function(g, me)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.silence(m)
    end
  end,
}

return cards
