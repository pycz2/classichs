-- Neutral cards, their tokens and The Coin (was rust/engine/src/cards/neutral.rs).
local cards = {}

local function not_me(g, me, t)
  return t ~= me
end

local function murloc_other(g, me, m)
  return m ~= me and g.race(m) == "MURLOC"
end

-- Enrage: while damaged, the minion gets atk (and tags).
local function enrage(atk, tags)
  return {
    aura = function(g, me)
      if g.dmg(me) > 0 then
        g.aura_add(me, atk, 0, tags)
      end
    end,
  }
end

-- A battlecry on a target: f(g, t).
local function on_target(target, f)
  return {
    target = target,
    battlecry = function(g, me, t)
      f(g, t)
    end,
  }
end

-- An `on` hook for event `ty` that runs f(g, me, ev) on me's controller's events only.
local function on_mine(ty, f)
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

local function draw_one(g, me)
  g.draw(g.ctrl(me), 1)
end

local function buff_temp_2(g, t)
  g.buff(t, 2, 0, true)
end

local function silence(g, t)
  g.silence(t)
end

local function destroy(g, t)
  g.destroy(t)
end

local function return_other_friendly()
  return {
    target = { base = "friendly_minion", filter = not_me },
    battlecry = function(g, me, t)
      g.return_to_hand(t)
    end,
  }
end

-- The Coin: one mana crystal this turn.
cards.GAME_005 = {
  spell = function(g, me)
    g.add_mana(g.ctrl(me), 1)
  end,
}

-- --- Basic ---------------------------------------------------------------------------

cards.VAN_CS2_189 = lib.hit("any", 1) -- Elven Archer

-- Grimscale Oracle: ALL other Murlocs have +1 Attack.
cards.VAN_EX1_508 = {
  aura = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if m ~= me and g.race(m) == "MURLOC" then
        g.aura_add(m, 1, 0)
      end
    end
  end,
}

-- Voodoo Doctor
cards.VAN_EX1_011 = {
  target = "any",
  battlecry = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 2))
  end,
}

-- Acidic Swamp Ooze: destroy the opponent's weapon.
cards.VAN_EX1_066 = {
  battlecry = function(g, me)
    g.destroy(g.weapon(g.enemy(me)))
  end,
}

cards.VAN_EX1_506 = lib.summon_right("VAN_EX1_506a") -- Murloc Tidehunter
cards.VAN_EX1_015 = lib.draw_battlecry(1) -- Novice Engineer
cards.VAN_CS2_147 = lib.draw_battlecry(1) -- Gnomish Inventor
cards.VAN_CS2_141 = lib.hit("any", 1) -- Ironforge Rifleman
cards.VAN_CS2_122 = lib.others_aura(1, 0) -- Raid Leader
cards.VAN_CS2_196 = lib.summon_right("VAN_CS2_boar") -- Razorfen Hunter

-- Shattered Sun Cleric
cards.VAN_EX1_019 = {
  target = "friendly_minion",
  battlecry = function(g, me, t)
    g.buff(t, 1, 1)
  end,
}

cards.VAN_EX1_025 = lib.summon_right("EX1_025t") -- Dragonling Mechanic

-- Darkscale Healer: restore 2 Health to all friendly characters.
cards.VAN_DS1_055 = {
  battlecry = function(g, me)
    for _, c in ipairs(g.chars(g.ctrl(me))) do
      g.heal(me, c, g.heal_amt(me, 2))
    end
  end,
}

-- Frostwolf Warlord: +1/+1 for each other friendly minion.
cards.VAN_CS2_226 = {
  battlecry = function(g, me)
    local n = #g.others(me)
    g.buff(me, n, n)
  end,
}

-- Gurubashi Berserker: whenever this minion takes damage, gain +3 Attack.
cards.VAN_EX1_399 = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me then
        g.buff(me, 3, 0)
      end
    end,
  },
}

-- Nightblade: 3 damage to the enemy hero.
cards.VAN_EX1_593 = {
  battlecry = function(g, me)
    g.damage(me, g.hero(g.enemy(me)), 3)
  end,
}

cards.VAN_CS2_150 = lib.hit("any", 2) -- Stormpike Commando
cards.VAN_CS2_222 = lib.others_aura(1, 1) -- Stormwind Champion

-- --- Common ------------------------------------------------------------------------------

cards.VAN_CS2_188 = on_target("minion", buff_temp_2) -- Abusive Sergeant

-- Leper Gnome: Deathrattle: 2 damage to the enemy hero.
cards.VAN_EX1_029 = {
  deathrattle = function(g, me)
    g.damage(me, g.hero(g.enemy(me)), 2)
  end,
}

-- Southsea Deckhand: Charge while you have a weapon.
cards.VAN_CS2_146 = {
  aura = function(g, me)
    if g.weapon(g.ctrl(me)) then
      g.aura_add(me, 0, 0, { CHARGE = true })
    end
  end,
}

cards.VAN_EX1_393 = enrage(3) -- Amani Berserker

-- Bloodsail Raider: gain Attack equal to your weapon's.
cards.VAN_NEW1_018 = {
  battlecry = function(g, me)
    local w = g.weapon(g.ctrl(me))
    if w then
      g.buff(me, g.atk(w), 0)
    end
  end,
}

-- Dire Wolf Alpha: adjacent minions have +1 Attack.
cards.VAN_EX1_162 = {
  aura = function(g, me)
    for _, m in ipairs(g.adjacent(me)) do
      g.aura_add(m, 1, 0)
    end
  end,
}

cards.VAN_CS2_203 = on_target("minion", silence) -- Ironbeak Owl

-- Loot Hoarder: Deathrattle: draw a card.
cards.VAN_EX1_096 = { deathrattle = draw_one }

-- Mad Bomber: 3 damage randomly split between all other characters.
cards.VAN_EX1_082 = {
  battlecry = function(g, me)
    for _ = 1, 3 do
      local pool = {}
      for _, c in ipairs(g.all_chars()) do
        if c ~= me and g.health(c) > 0 then
          table.insert(pool, c)
        end
      end
      g.damage(me, g.pick(pool), 1)
    end
  end,
}

cards.VAN_EX1_049 = return_other_friendly() -- Youthful Brewmaster

-- Acolyte of Pain: whenever this minion takes damage, draw a card.
cards.VAN_EX1_007 = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me then
        draw_one(g, me)
      end
    end,
  },
}

-- Earthen Ring Farseer
cards.VAN_CS2_117 = {
  target = "any",
  battlecry = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 3))
  end,
}

-- Flesheating Ghoul: whenever a minion dies, gain +1 Attack.
cards.VAN_tt_004 = {
  on = {
    death = function(g, me, ev)
      if ev.minion then
        g.buff(me, 1, 0)
      end
    end,
  },
}

-- Harvest Golem: Deathrattle: summon a 2/1 Damaged Golem.
cards.VAN_EX1_556 = {
  deathrattle = function(g, me)
    g.summon(g.ctrl(me), "VAN_skele21", g.died_pos(me))
  end,
}

cards.VAN_EX1_412 = enrage(1, { WINDFURY = true }) -- Raging Worgen
cards.VAN_EX1_390 = enrage(3) -- Tauren Warrior
cards.VAN_EX1_057 = return_other_friendly() -- Ancient Brewmaster

-- Cult Master: whenever one of your other minions dies, draw a card (2014: not if it dies too).
cards.VAN_EX1_595 = on_mine("death", function(g, me, ev)
  if ev.minion then
    draw_one(g, me)
  end
end)

cards.VAN_EX1_046 = on_target("minion", buff_temp_2) -- Dark Iron Dwarf

-- Dread Corsair: costs (1) less per Attack of your weapon.
cards.VAN_NEW1_022 = {
  cost_mod = function(g, me)
    local w = g.weapon(g.ctrl(me))
    return w and -g.atk(w) or 0
  end,
}

cards.VAN_EX1_048 = on_target("minion", silence) -- Spellbreaker
cards.VAN_CS2_151 = lib.summon_right("VAN_CS2_152") -- Silver Hand Knight

-- Spiteful Smith: Enrage: your weapon has +2 Attack.
cards.VAN_CS2_221 = {
  aura = function(g, me)
    local w = g.weapon(g.ctrl(me))
    if w and g.dmg(me) > 0 then
      g.aura_add(w, 2, 0)
    end
  end,
}

-- Venture Co. Mercenary: your minions cost (3) more.
cards.VAN_CS2_227 = {
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.is_minion(card) and g.zone(card) == "HAND" then
      return cost + 3
    end
    return cost
  end,
}

-- Frost Elemental: freeze a character.
cards.VAN_EX1_283 = on_target("any", function(g, t)
  g.freeze(t)
end)

-- Priestess of Elune: restore 4 Health to your hero.
cards.VAN_EX1_583 = {
  battlecry = function(g, me)
    g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 4))
  end,
}

-- --- Rare --------------------------------------------------------------------------------

cards.VAN_EX1_009 = enrage(5) -- Angry Chicken

-- Bloodsail Corsair: remove 1 Durability from the enemy weapon.
cards.VAN_NEW1_025 = {
  battlecry = function(g, me)
    g.add_tag(g.weapon(g.enemy(me)), "DURABILITY", -1)
  end,
}

-- Lightwarden: whenever a character is healed, gain +2 Attack.
cards.VAN_EX1_001 = {
  on = {
    heal = function(g, me)
      g.buff(me, 2, 0)
    end,
  },
}

-- Murloc Tidecaller: whenever a Murloc is summoned, gain +1 Attack.
cards.VAN_EX1_509 = {
  on = {
    summon = function(g, me, ev)
      if murloc_other(g, me, ev.entity) then
        g.buff(me, 1, 0)
      end
    end,
  },
}

-- Secretkeeper: whenever a Secret is played, gain +1/+1.
cards.VAN_EX1_080 = {
  on = {
    play = function(g, me, ev)
      if ev.secret then
        g.buff(me, 1, 1)
      end
    end,
  },
}

-- At the end of your turn, a random other friendly minion gets atk/hp.
local function end_turn_buff_other(atk, hp)
  return on_mine("turn_end", function(g, me)
    local t = g.random_alive(g.others(me))
    if t then
      g.buff(t, atk, hp)
    end
  end)
end

cards.VAN_EX1_004 = end_turn_buff_other(0, 1) -- Young Priestess

-- Crazed Alchemist: swap a minion's Attack and Health.
cards.VAN_EX1_059 = on_target("minion", function(g, t)
  g.set_stats(t, g.health(t), g.atk(t))
end)

-- Knife Juggler: after you summon a minion, 1 damage to a random enemy.
cards.VAN_NEW1_019 = on_mine("after_summon", function(g, me, ev)
  if ev.entity ~= me then
    g.damage(me, g.random_alive(g.chars(g.enemy(me))), 1)
  end
end)

-- Mana Addict: whenever you cast a spell, +2 Attack this turn.
cards.VAN_EX1_055 = {
  on = {
    play = function(g, me, ev)
      if lib.my_spell(g, me, ev) then
        g.buff(me, 2, 0, true)
      end
    end,
  },
}

-- Mana Wraith: ALL minions cost (1) more.
cards.VAN_EX1_616 = {
  cost_aura = function(g, me, card, cost)
    if g.is_minion(card) and g.zone(card) == "HAND" then
      return cost + 1
    end
    return cost
  end,
}

cards.VAN_NEW1_037 = end_turn_buff_other(1, 0) -- Master Swordsmith

-- Pint-Sized Summoner: the first minion you play each turn costs (1) less.
cards.VAN_EX1_076 = {
  cost_aura = function(g, me, card, cost)
    local p = g.ctrl(me)
    if g.minions_played(p) == 0 and g.ctrl(card) == p and g.is_minion(card) and g.zone(card) == "HAND" then
      return cost - 1
    end
    return cost
  end,
}

-- Sunfury Protector: give adjacent minions Taunt.
cards.VAN_EX1_058 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.adjacent(me)) do
      g.give_tag(m, "TAUNT")
    end
  end,
}

-- Wild Pyromancer: after you cast a spell, 1 damage to ALL minions.
cards.VAN_NEW1_020 = on_mine("after_spell", function(g, me)
  for _, m in ipairs(g.all_minions()) do
    g.damage(me, m, 1)
  end
end)

-- Alarm-o-Bot: at the start of your turn, swap this with a random minion in your hand.
cards.VAN_EX1_006 = on_mine("turn_start", function(g, me)
  local p = g.ctrl(me)
  local minions = {}
  for _, e in ipairs(g.hand(p)) do
    if g.is_minion(e) then
      table.insert(minions, e)
    end
  end
  local m = g.pick(minions)
  if not m then
    return
  end
  local pos = g.board_pos(me) or -1
  g.remove(m) -- out of the hand first: room for this one
  g.return_to_hand(me)
  g.summon_entity(m, pos)
end)

-- Arcane Golem: give your opponent a Mana Crystal.
cards.VAN_EX1_089 = {
  battlecry = function(g, me)
    g.gain_mana(g.enemy(me), 1)
  end,
}

-- Coldlight Oracle: each player draws 2 cards.
cards.VAN_EX1_050 = {
  battlecry = function(g, me)
    g.draw(g.ctrl(me), 2)
    g.draw(g.enemy(me), 2)
  end,
}

-- Coldlight Seer: ALL other Murlocs get +2 Health.
cards.VAN_EX1_103 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if murloc_other(g, me, m) then
        g.buff(m, 0, 2)
      end
    end
  end,
}

-- Demolisher: at the start of your turn, 2 damage to a random enemy.
cards.VAN_EX1_102 = on_mine("turn_start", function(g, me)
  g.damage(me, g.random_alive(g.chars(g.enemy(me))), 2)
end)

-- Emperor Cobra: destroy any minion damaged by this minion.
cards.VAN_EX1_170 = {
  on = {
    damage = function(g, me, ev)
      if ev.source == me and g.is_minion(ev.target) then
        g.destroy(ev.target)
      end
    end,
  },
}

-- Imp Master: at the end of your turn, 1 damage to this minion and summon a 1/1 Imp.
cards.VAN_EX1_597 = on_mine("turn_end", function(g, me)
  g.damage(me, me, 1)
  g.summon_right(me, "VAN_EX1_598")
end)

-- Injured Blademaster: deal 4 damage to himself.
cards.VAN_CS2_181 = {
  battlecry = function(g, me)
    g.damage(me, me, 4)
  end,
}

-- Mind Control Tech: if your opponent has 4 or more minions, take control of one at random.
cards.VAN_EX1_085 = {
  battlecry = function(g, me)
    local enemy = g.minions(g.enemy(me))
    if #enemy >= 4 then
      g.take_control(g.pick(enemy), g.ctrl(me))
    end
  end,
}

-- Questing Adventurer: whenever you play a card, gain +1/+1.
cards.VAN_EX1_044 = on_mine("play", function(g, me, ev)
  if ev.entity ~= me then
    g.buff(me, 1, 1)
  end
end)

-- Ancient Mage: give adjacent minions Spell Damage +1.
cards.VAN_EX1_584 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.adjacent(me)) do
      g.add_tag(m, "SPELLPOWER", 1)
    end
  end,
}

-- Defender of Argus: adjacent minions get +1/+1 and Taunt.
cards.VAN_EX1_093 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.adjacent(me)) do
      g.buff(m, 1, 1)
      g.give_tag(m, "TAUNT")
    end
  end,
}

-- Twilight Drake: +1 Health for each card in your hand.
cards.VAN_EX1_043 = {
  battlecry = function(g, me)
    g.buff(me, 0, #g.hand(g.ctrl(me)))
  end,
}

-- Violet Teacher: whenever you cast a spell, summon a 1/1 Violet Apprentice.
cards.VAN_NEW1_026 = {
  on = {
    play = function(g, me, ev)
      if lib.my_spell(g, me, ev) then
        g.summon_right(me, "VAN_NEW1_026t")
      end
    end,
  },
}

-- Abomination: Deathrattle: 2 damage to ALL characters.
cards.VAN_EX1_097 = {
  deathrattle = function(g, me)
    for _, c in ipairs(g.all_chars()) do
      g.damage(me, c, 2)
    end
  end,
}

cards.VAN_EX1_284 = lib.draw_battlecry(1) -- Azure Drake

-- Gadgetzan Auctioneer: whenever you cast a spell, draw a card.
cards.VAN_EX1_095 = {
  on = {
    play = function(g, me, ev)
      if lib.my_spell(g, me, ev) then
        draw_one(g, me)
      end
    end,
  },
}

-- Stampeding Kodo: destroy a random enemy minion with 2 or less Attack.
cards.VAN_NEW1_041 = {
  battlecry = function(g, me)
    local small = {}
    for _, m in ipairs(g.minions(g.enemy(me))) do
      if g.atk(m) <= 2 then
        table.insert(small, m)
      end
    end
    g.destroy(g.random_alive(small))
  end,
}

-- --- Epic --------------------------------------------------------------------------------

-- Hungry Crab: destroy a Murloc and gain +2/+2.
cards.VAN_NEW1_017 = {
  target = {
    base = "minion",
    filter = function(g, me, t)
      return g.race(t) == "MURLOC"
    end,
  },
  battlecry = function(g, me, t)
    g.destroy(t)
    g.buff(me, 2, 2)
  end,
}

-- Captain's Parrot: put a random Pirate from your deck into your hand.
cards.VAN_NEW1_016 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local pirates = {}
    for _, e in ipairs(g.deck(p)) do
      if g.race(e) == "PIRATE" then
        table.insert(pirates, e)
      end
    end
    local e = g.pick(pirates)
    if e then
      g.draw_entity(p, e)
    end
  end,
}

-- Doomsayer: at the start of your turn, destroy ALL minions.
cards.VAN_NEW1_021 = on_mine("turn_start", function(g)
  for _, m in ipairs(g.all_minions()) do
    g.destroy(m)
  end
end)

-- Big Game Hunter: destroy a minion with 7 or more Attack.
cards.VAN_EX1_005 = on_target({
  base = "minion",
  filter = function(g, me, t)
    return g.atk(t) >= 7
  end,
}, destroy)

-- Blood Knight: all minions lose Divine Shield; +3/+3 for each one.
cards.VAN_EX1_590 = {
  battlecry = function(g, me)
    local n = 0
    for _, m in ipairs(g.all_minions()) do
      if g.has(m, "DIVINE_SHIELD") then
        g.erase_tag(m, "DIVINE_SHIELD")
        n = n + 1
      end
    end
    g.buff(me, 3 * n, 3 * n)
  end,
}

-- Murloc Warleader: ALL other Murlocs have +2/+1.
cards.VAN_EX1_507 = {
  aura = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if murloc_other(g, me, m) then
        g.aura_add(m, 2, 1)
      end
    end
  end,
}

-- Southsea Captain: your other Pirates have +1/+1.
cards.VAN_NEW1_027 = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "PIRATE" then
        g.aura_add(m, 1, 1)
      end
    end
  end,
}

-- Faceless Manipulator: become a copy of a minion.
cards.VAN_EX1_564 = {
  target = { base = "minion", filter = not_me },
  battlecry = function(g, me, t)
    g.copy_minion(me, t)
  end,
}

-- Sea Giant: costs (1) less for each minion on the battlefield.
cards.VAN_EX1_586 = {
  cost_mod = function(g)
    return -#g.all_minions()
  end,
}

-- Mountain Giant: costs (1) less for each other card in your hand.
cards.VAN_EX1_105 = {
  cost_mod = function(g, me)
    return -(#g.hand(g.ctrl(me)) - 1)
  end,
}

-- Molten Giant: costs (1) less for each damage your hero has taken.
cards.VAN_EX1_620 = {
  cost_mod = function(g, me)
    return -g.dmg(g.hero(g.ctrl(me)))
  end,
}

-- --- Legendary ---------------------------------------------------------------------------

cards.VAN_EX1_012 = { deathrattle = draw_one } -- Bloodmage Thalnos

-- Lorewalker Cho: whenever a player casts a spell, put a copy into the other player's hand.
cards.VAN_EX1_100 = {
  on = {
    play = function(g, me, ev)
      if ev.kind == "spell" then
        g.add_to_hand(g.opponent(ev.player), ev.card)
      end
    end,
  },
}

-- Millhouse Manastorm: enemy spells cost (0) next turn.
cards.VAN_NEW1_029 = {
  battlecry = function(g, me)
    g.add_cost_mod(g.enemy(me), { kind = "spell", set = 0, ["until"] = "turn_end", turn = g.turn() + 1 })
  end,
}

-- Nat Pagle: at the start of your turn, a 50% chance to draw a card.
cards.VAN_EX1_557 = on_mine("turn_start", function(g, me)
  if g.random(0, 1) == 1 then
    draw_one(g, me)
  end
end)

-- King Mukla: give your opponent 2 Bananas.
cards.VAN_EX1_014 = {
  battlecry = function(g, me)
    for _ = 1, 2 do
      g.add_to_hand(g.enemy(me), "EX1_014t")
    end
  end,
}

-- Tinkmaster Overspark: transform another random minion into a 5/5 Devilsaur or a 1/1 Squirrel.
cards.VAN_EX1_083 = {
  battlecry = function(g, me)
    local pool = {}
    for _, m in ipairs(g.all_minions()) do
      if m ~= me then
        table.insert(pool, m)
      end
    end
    local t = g.random_alive(pool)
    if t then
      g.transform(t, g.pick({ "VAN_EX1_tk29", "VAN_EX1_tk28" }))
    end
  end,
}

-- Leeroy Jenkins: summon two 1/1 Whelps for your opponent.
cards.VAN_EX1_116 = {
  battlecry = function(g, me)
    for _ = 1, 2 do
      g.summon(g.enemy(me), "EX1_116t")
    end
  end,
}

-- Old Murk-Eye: +1 Attack for each other Murloc on the battlefield.
cards.VAN_EX1_062 = {
  aura = function(g, me)
    local n = 0
    for _, m in ipairs(g.all_minions()) do
      if murloc_other(g, me, m) then
        n = n + 1
      end
    end
    g.aura_add(me, n, 0)
  end,
}

-- Captain Greenskin: give your weapon +1/+1.
cards.VAN_NEW1_024 = {
  battlecry = function(g, me)
    local w = g.weapon(g.ctrl(me))
    if w then
      g.buff(w, 1, 0)
      g.add_tag(w, "DURABILITY", 1)
    end
  end,
}

-- Elite Tauren Chieftain: give both players a Power Chord.
cards.VAN_PRO_001 = {
  battlecry = function(g, me)
    for _, p in ipairs({ g.ctrl(me), g.enemy(me) }) do
      g.add_to_hand(p, g.pick({ "PRO_001a", "PRO_001b", "VAN_PRO_001c" }))
    end
  end,
}

-- Harrison Jones: destroy the enemy weapon and draw cards equal to its Durability.
cards.VAN_EX1_558 = {
  battlecry = function(g, me)
    local w = g.weapon(g.enemy(me))
    if w then
      local n = g.tag(w, "DURABILITY")
      g.destroy(w)
      g.draw(g.ctrl(me), n)
    end
  end,
}

-- Cairne Bloodhoof: Deathrattle: summon a 4/5 Baine Bloodhoof.
cards.VAN_EX1_110 = {
  deathrattle = function(g, me)
    g.summon(g.ctrl(me), "VAN_EX1_110t", g.died_pos(me))
  end,
}

-- Gelbin Mekkatorque: summon an AWESOME invention.
cards.VAN_EX1_112 = {
  battlecry = function(g, me)
    g.summon_right(me, g.pick({ "Mekka1", "Mekka2", "Mekka3", "Mekka4" }))
  end,
}

-- Hogger: at the end of your turn, summon a 2/2 Gnoll with Taunt.
cards.VAN_NEW1_040 = on_mine("turn_end", function(g, me)
  g.summon_right(me, "NEW1_040t")
end)

-- Illidan Stormrage: whenever you play a card, summon a 2/1 Flame (2014: The Coin too).
cards.VAN_EX1_614 = on_mine("play", function(g, me, ev)
  if ev.entity ~= me then
    g.summon_right(me, "VAN_TU4e_002t")
  end
end)

-- Sylvanas Windrunner: Deathrattle: take control of a random enemy minion.
cards.VAN_EX1_016 = {
  deathrattle = function(g, me)
    local t = g.random_alive(g.minions(g.enemy(me)))
    if t then
      g.take_control(t, g.ctrl(me))
    end
  end,
}

-- The Beast: Deathrattle: summon a 3/3 Finkle Einhorn for your opponent.
cards.VAN_EX1_577 = {
  deathrattle = function(g, me)
    g.summon(g.enemy(me), "VAN_EX1_finkle")
  end,
}

-- The Black Knight: destroy an enemy minion with Taunt.
cards.VAN_EX1_002 = on_target({
  base = "enemy_minion",
  filter = function(g, me, t)
    return g.has(t, "TAUNT")
  end,
}, destroy)

-- Baron Geddon: at the end of your turn, 2 damage to ALL other characters.
cards.VAN_EX1_249 = on_mine("turn_end", function(g, me)
  for _, c in ipairs(g.all_chars()) do
    if c ~= me then
      g.damage(me, c, 2)
    end
  end
end)

-- Gruul: at the end of each turn, gain +1/+1.
cards.VAN_NEW1_038 = {
  on = {
    turn_end = function(g, me)
      g.buff(me, 1, 1)
    end,
  },
}

-- Ragnaros the Firelord: at the end of your turn, 8 damage to a random enemy.
cards.VAN_EX1_298 = on_mine("turn_end", function(g, me)
  g.damage(me, g.random_alive(g.chars(g.enemy(me))), 8)
end)

-- Alexstrasza: set a hero's remaining Health to 15.
cards.VAN_EX1_561 = {
  target = {
    base = "any",
    filter = function(g, me, t)
      return g.is_champion(t)
    end,
  },
  battlecry = function(g, me, t)
    g.set_damage(t, g.max_health(t) - 15)
    g.log({ type = "set_health", target = t, health = g.health(t) })
  end,
}

-- Onyxia: summon 1/1 Whelps until your side of the battlefield is full (right, left, ...).
cards.VAN_EX1_562 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local right = true
    while g.room(p) > 0 do
      local i = g.board_pos(me) or -1
      g.summon(p, "ds1_whelptoken", right and i + 1 or i)
      right = not right
    end
  end,
}

-- Ysera: at the end of your turn, add a Dream Card to your hand.
cards.VAN_EX1_572 = on_mine("turn_end", function(g, me)
  local dreams = { "VAN_DREAM_01", "VAN_DREAM_02", "VAN_DREAM_03", "VAN_DREAM_04", "VAN_DREAM_05" }
  g.add_to_hand(g.ctrl(me), g.pick(dreams))
end)

-- Deathwing: destroy all other minions and discard your hand.
cards.VAN_NEW1_030 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if m ~= me then
        g.destroy(m)
      end
    end
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      g.discard(e)
    end
  end,
}

-- --- Legendary tokens --------------------------------------------------------------------

-- Bananas: +1/+1.
cards.EX1_014t = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 1, 1)
  end,
}

-- I Am Murloc: summon three, four or five 1/1 Murlocs.
cards.PRO_001a = {
  spell = function(g, me)
    for _ = 1, g.random(3, 5) do
      g.summon(g.ctrl(me), "PRO_001at")
    end
  end,
}

-- Rogues Do It...: 4 damage, draw a card.
cards.PRO_001b = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 4))
    draw_one(g, me)
  end,
}

-- Power of the Horde: summon a random Horde Warrior.
cards.VAN_PRO_001c = {
  spell = function(g, me)
    local horde = { "VAN_CS2_121", "VAN_CS2_179", "VAN_EX1_023", "VAN_EX1_390", "VAN_EX1_021", "VAN_EX1_110" }
    g.summon(g.ctrl(me), g.pick(horde))
  end,
}

-- Homing Chicken: at the start of your turn, destroy this minion and draw 3 cards.
cards.Mekka1 = on_mine("turn_start", function(g, me)
  g.destroy(me)
  g.draw(g.ctrl(me), 3)
end)

-- Repair Bot: at the end of your turn, restore 6 Health to a damaged character.
cards.Mekka2 = on_mine("turn_end", function(g, me)
  local hurt = {}
  for _, c in ipairs(g.all_chars()) do
    if g.dmg(c) > 0 and g.health(c) > 0 then
      table.insert(hurt, c)
    end
  end
  local t = g.pick(hurt)
  if t then
    g.heal(me, t, g.heal_amt(me, 6))
  end
end)

-- Emboldener 3000: at the end of your turn, a random minion gets +1/+1.
cards.Mekka3 = on_mine("turn_end", function(g, me)
  local t = g.random_alive(g.all_minions())
  if t then
    g.buff(t, 1, 1)
  end
end)

-- Poultryizer: at the start of your turn, transform a random minion into a 1/1 Chicken.
cards.Mekka4 = on_mine("turn_start", function(g, me)
  local t = g.random_alive(g.all_minions())
  if t then
    g.transform(t, "Mekka4t")
  end
end)

-- Ysera Awakens: 5 damage to all characters except Ysera.
cards.VAN_DREAM_02 = {
  spell = function(g, me)
    for _, c in ipairs(g.all_chars()) do
      if g.card(c) ~= "VAN_EX1_572" then
        g.damage(me, c, g.spell_dmg(me, 5))
      end
    end
  end,
}

-- Dream: return a minion to its owner's hand.
cards.VAN_DREAM_04 = {
  target = "minion",
  spell = function(g, me, t)
    g.return_to_hand(t)
  end,
}

-- Nightmare: +5/+5; at the start of your next turn, destroy it.
cards.VAN_DREAM_05 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 5, 5)
    g.enchant(t, { hooks = "ench:nightmare", player = g.ctrl(me) })
  end,
}

cards["ench:nightmare"] = {
  on = {
    turn_start = function(g, me, ev)
      for _, p in ipairs(g.enchants(me, "ench:nightmare")) do
        if ev.player == p then
          g.destroy(me)
        end
      end
    end,
  },
}

return cards
