-- Goblins vs Gnomes (December 2014): the 123 cards, their tokens and the Spare Parts, as at the release
-- (patch 2.0.0.7234; docs/packs/api.md). The Basic, Classic and Naxxramas cards are those packs' scripts,
-- copied in by the recipe; the few of them this patch changed are at the end.
local cards = {}

-- --- helpers -----------------------------------------------------------------------------------

-- The items of a list that pass ok(e).
local function only(list, ok)
  local out = {}
  for _, e in ipairs(list) do
    if ok(e) then
      out[#out + 1] = e
    end
  end
  return out
end

-- An `on` hook that runs only on its controller's events (ev.player).
local function on_mine(event, f)
  return {
    on = {
      [event] = function(g, me, ev)
        if g.mine(me, ev) then
          f(g, me, ev)
        end
      end,
    },
  }
end

-- An `on` hook for the end of its controller's turn.
local function my_turn_end(f)
  return on_mine("turn_end", f)
end

local function is_mech(g, e)
  return g.race(e) == "MECHANICAL"
end

-- p's Mechs on the board (without `except`).
local function mechs(g, p, except)
  return only(g.minions(p), function(m)
    return m ~= except and is_mech(g, m)
  end)
end

-- "If you have a Mech": another one of me's side.
local function have_mech(g, me)
  return #mechs(g, g.ctrl(me), me) > 0
end

-- me's side has another minion of this race.
local function have_race(g, me, race)
  return #only(g.others(me), function(m)
    return g.race(m) == race
  end) > 0
end

-- Collectible cards of the constructed sets whose data pass ok(info) (Unstable Portal, Piloted Shredder…).
local function collectible(g, ok)
  return only(g.collectible(), function(c)
    return ok(g.info(c))
  end)
end

local function minions_where(g, ok)
  return collectible(g, function(i)
    return i.type == "MINION" and ok(i)
  end)
end

-- The living characters of a list (in play, Health above 0).
local function alive(g, list)
  return only(list, function(c)
    return g.zone(c) == "PLAY" and g.health(c) > 0
  end)
end

-- n hits of 1 damage, each on a random living character of the list list() gives (Goblin Blastmage, Madder
-- Bomber): a character killed by an earlier hit is not hit again.
local function split(g, me, n, list)
  for _ = 1, n do
    local t = g.pick(alive(g, list()))
    if not t then
      return
    end
    g.damage(me, t, 1)
  end
end

-- One of the seven Spare Parts into p's hand.
local PARTS = { "PART_001", "PART_002", "PART_003", "PART_004", "PART_005", "PART_006", "PART_007" }
local function spare_part(g, p)
  g.add_to_hand(p, g.pick(PARTS))
end

local function draw_until(g, p, n)
  local k = n - #g.hand(p)
  if k > 0 then
    g.draw(p, k)
  end
end

-- "50% chance to attack the wrong enemy": when there is another enemy character (Taunt, Stealth and Immune
-- ignored), the attack (an `attack` event) goes at a random one of them instead, half the time.
local function forget(g, ev)
  local wrong = only(g.chars(g.enemy(ev.attacker)), function(c)
    return c ~= ev.defender and g.health(c) > 0
  end)
  if #wrong > 0 and g.random(0, 1) == 1 then
    ev.defender = g.pick(wrong)
  end
end

-- A forgetful minion (Ogre Brute, Dunemaul Shaman, Ogre Ninja, Mogor).
local function forgetful()
  return {
    on = {
      attack = function(g, me, ev)
        if ev.attacker == me then
          forget(g, ev)
        end
      end,
    },
  }
end

-- A buff of a's side: +atk/+hp to a random other living friendly minion that passes ok (or any).
local function random_friend(g, me, ok)
  return g.pick(only(alive(g, g.others(me)), function(m)
    return not ok or ok(m)
  end))
end

-- --- Mage --------------------------------------------------------------------------------------

-- Flamecannon: 4 damage to a random enemy minion.
cards.GVG_001 = {
  can_play = function(g, me)
    return #g.minions(g.enemy(me)) > 0
  end,
  spell = function(g, me)
    g.damage(me, g.random_alive(g.minions(g.enemy(me))), g.spell_dmg(me, 4))
  end,
}

-- Snowchugger: Freeze any character damaged by this minion.
cards.GVG_002 = {
  on = {
    damage = function(g, me, ev)
      if ev.source == me then
        g.freeze(ev.target)
      end
    end,
  },
}

-- Unstable Portal: a random minion to your hand, costing (3) less.
cards.GVG_003 = {
  spell = function(g, me)
    local c = g.pick(minions_where(g, function()
      return true
    end))
    local e = c and g.add_to_hand(g.ctrl(me), c)
    if e then
      g.enchant(e, { cost = -3 })
    end
  end,
}

-- Goblin Blastmage: if you have a Mech, 4 damage randomly split among all enemies.
cards.GVG_004 = {
  glow = have_mech,
  battlecry = function(g, me)
    if have_mech(g, me) then
      split(g, me, 4, function()
        return g.chars(g.enemy(me))
      end)
    end
  end,
}

-- Echo of Medivh: a copy of each friendly minion into your hand.
cards.GVG_005 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, m in ipairs(g.minions(p)) do
      g.add_to_hand(p, g.card(m))
    end
  end,
}

-- Mechwarper: your Mechs cost (1) less.
cards.GVG_006 = {
  cost_aura = function(g, me, card, cost)
    if g.ctrl(card) == g.ctrl(me) and g.zone(card) == "HAND" and g.is_minion(card) and is_mech(g, card) then
      return cost - 1
    end
    return cost
  end,
}

-- Flame Leviathan: when you draw this, 2 damage to all characters.
cards.GVG_007 = {
  hand = {
    draw = function(g, me, ev)
      if ev.entity == me then
        for _, c in ipairs(g.all_chars()) do
          g.damage(me, c, 2)
        end
      end
    end,
  },
}

-- Wee Spellstopper: adjacent minions can't be targeted by spells or Hero Powers.
cards.GVG_122 = {
  aura = function(g, me)
    for _, m in ipairs(g.adjacent(me)) do
      g.aura_add(m, 0, 0, { ELUSIVE = true })
    end
  end,
}

-- --- Priest ------------------------------------------------------------------------------------

-- Lightbomb: each minion takes damage equal to its Attack (all measured first; spell damage adds).
cards.GVG_008 = {
  spell = function(g, me)
    local hits = {}
    for _, m in ipairs(g.all_minions()) do
      hits[#hits + 1] = { m, g.atk(m) }
    end
    for _, h in ipairs(hits) do
      if h[2] > 0 then
        g.damage(me, h[1], g.spell_dmg(me, h[2]))
      end
    end
  end,
}

-- Shadowbomber: 3 damage to each hero.
cards.GVG_009 = {
  battlecry = function(g, me)
    g.damage(me, g.hero(g.ctrl(me)), 3)
    g.damage(me, g.hero(g.enemy(me)), 3)
  end,
}

-- Velen's Chosen: +2/+4 and Spell Damage +1.
cards.GVG_010 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 2, 4)
    g.add_tag(t, "SPELLPOWER", 1)
  end,
}

-- Shrinkmeister: a minion gets -2 Attack this turn.
cards.GVG_011 = {
  target = "minion",
  battlecry = function(g, me, t)
    g.buff(t, -2, 0, true)
  end,
}

-- Light of the Naaru: restore 3 Health; if the target is still damaged, summon a Lightwarden.
cards.GVG_012 = {
  target = "any",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 3))
    if g.dmg(t) > 0 then
      g.summon(g.ctrl(me), "VAN_EX1_001")
    end
  end,
}

-- Vol'jin: swap Health with another minion.
cards.GVG_014 = {
  target = { base = "minion", filter = function(g, me, t)
    return t ~= me
  end },
  battlecry = function(g, me, t)
    local mine, theirs = g.health(me), g.health(t)
    g.set_stats(me, nil, theirs)
    g.set_stats(t, nil, mine)
  end,
}

-- Upgraded Repair Bot: a friendly Mech gets +4 Health.
cards.GVG_083 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me and is_mech(g, t)
  end },
  battlecry = function(g, me, t)
    g.buff(t, 0, 4)
  end,
}

-- Shadowboxer: whenever a character is healed, 1 damage to a random enemy.
cards.GVG_072 = {
  on = {
    heal = function(g, me)
      g.damage(me, g.random_alive(g.chars(g.enemy(me))), 1)
    end,
  },
}

-- --- Warlock -----------------------------------------------------------------------------------

-- Darkbomb: 3 damage.
cards.GVG_015 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 3))
  end,
}

-- Mistress of Pain: whenever this minion deals damage, restore that much Health to your hero.
cards.GVG_018 = {
  on = {
    damage = function(g, me, ev)
      if ev.source == me then
        g.heal(me, g.hero(g.ctrl(me)), ev.amount)
      end
    end,
  },
}

-- Demonheart: 5 damage to a minion; a friendly Demon gets +5/+5 instead.
cards.GVG_019 = {
  target = "minion",
  spell = function(g, me, t)
    if g.ctrl(t) == g.ctrl(me) and g.race(t) == "DEMON" then
      g.buff(t, 5, 5)
    else
      g.damage(me, t, g.spell_dmg(me, 5))
    end
  end,
}

-- Fel Cannon: at the end of your turn, 2 damage to a random non-Mech minion.
cards.GVG_020 = my_turn_end(function(g, me)
  g.damage(me, g.random_alive(only(g.all_minions(), function(m)
    return not is_mech(g, m)
  end)), 2)
end)

-- Mal'Ganis: your other Demons have +2/+2; your hero is Immune.
cards.GVG_021 = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.race(m) == "DEMON" then
        g.aura_add(m, 2, 2)
      end
    end
    g.aura_add(g.hero(g.ctrl(me)), 0, 0, { IMMUNE = true })
  end,
}

-- Imp-losion: 2-4 damage to a minion; a 1/1 Imp for each damage dealt.
cards.GVG_045 = {
  target = "minion",
  spell = function(g, me, t)
    local n = g.damage(me, t, g.spell_dmg(me, g.random(2, 4))) -- overkill counts, a Divine Shield gives none
    for _ = 1, n do
      g.summon(g.ctrl(me), "GVG_045t")
    end
  end,
}

-- Floating Watcher: whenever your hero takes damage on your turn, +2/+2.
cards.GVG_100 = {
  on = {
    damage = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.target == g.hero(p) and g.current() == p then
        g.buff(me, 2, 2)
      end
    end,
  },
}

-- Anima Golem: at the end of each turn, destroy this minion if it's your only one.
cards.GVG_077 = {
  on = {
    turn_end = function(g, me)
      if #g.minions(g.ctrl(me)) == 1 then
        g.destroy(me)
      end
    end,
  },
}

-- --- Rogue -------------------------------------------------------------------------------------

-- Tinker's Sharpsword Oil: your weapon +3 Attack; Combo: a random friendly minion +3 Attack.
local function oil(g, me)
  g.buff(g.weapon(g.ctrl(me)), 3, 0)
end
cards.GVG_022 = {
  spell = oil,
  combo = function(g, me)
    oil(g, me)
    g.buff(g.random_alive(g.minions(g.ctrl(me))), 3, 0)
  end,
}

-- Goblin Auto-Barber: your weapon +1 Attack.
cards.GVG_023 = {
  battlecry = function(g, me)
    g.buff(g.weapon(g.ctrl(me)), 1, 0)
  end,
}

-- Cogmaster's Wrench: +2 Attack while you have a Mech.
cards.GVG_024 = {
  aura = function(g, me)
    if #mechs(g, g.ctrl(me)) > 0 then
      g.aura_add(me, 2, 0)
    end
  end,
}

-- One-eyed Cheat: whenever you summon a Pirate, gain Stealth.
cards.GVG_025 = on_mine("summon", function(g, me, ev)
  if ev.entity ~= me and g.race(ev.entity) == "PIRATE" then
    g.give_tag(me, "STEALTH")
  end
end)

-- Iron Sensei: at the end of your turn, another friendly Mech gets +2/+2.
cards.GVG_027 = my_turn_end(function(g, me)
  g.buff(random_friend(g, me, function(m)
    return is_mech(g, m)
  end), 2, 2)
end)

-- Trade Prince Gallywix: whenever your opponent casts a spell, gain a copy of it and give them a Coin
-- (not for Gallywix's Coin).
cards.GVG_028 = {
  on = {
    play = function(g, me, ev)
      if ev.kind == "spell" and not g.mine(me, ev) and ev.card ~= "GVG_028t" and not ev.countered then
        g.add_to_hand(g.ctrl(me), ev.card)
        g.add_to_hand(ev.player, "GVG_028t")
      end
    end,
  },
}

-- Gallywix's Coin: one mana crystal this turn.
cards.GVG_028t = {
  spell = function(g, me)
    g.add_mana(g.ctrl(me), 1)
  end,
}

-- Sabotage: destroy a random enemy minion; Combo: and the opponent's weapon.
local function sabotage(g, me)
  g.destroy(g.random_alive(g.minions(g.enemy(me))))
end
cards.GVG_047 = {
  spell = sabotage,
  combo = function(g, me)
    sabotage(g, me)
    g.destroy(g.weapon(g.enemy(me)))
  end,
}

-- Ogre Ninja
cards.GVG_088 = forgetful()

-- --- Hunter ------------------------------------------------------------------------------------

-- Call Pet: draw a card; a Beast costs (4) less.
cards.GVG_017 = {
  spell = function(g, me)
    local e = g.draw(g.ctrl(me))[1]
    if e and g.is_minion(e) and g.race(e) == "BEAST" then
      g.enchant(e, { cost = -4 })
    end
  end,
}

-- Feign Death: the Deathrattles of your minions go off (twice with Baron Rivendare).
cards.GVG_026 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local times = g.has(g.hero(p), "DOUBLE_DEATHRATTLE") and 2 or 1
    for _, m in ipairs(g.minions(p)) do
      for _ = 1, times do
        g.deathrattle(m)
      end
    end
  end,
}

-- Glaivezooka: a random friendly minion +1 Attack.
cards.GVG_043 = {
  battlecry = function(g, me)
    g.buff(g.random_alive(g.minions(g.ctrl(me))), 1, 0)
  end,
}

-- King of Beasts: +1 Attack for each other Beast you have.
cards.GVG_046 = {
  battlecry = function(g, me)
    local n = #only(g.others(me), function(m)
      return g.race(m) == "BEAST"
    end)
    if n > 0 then
      g.buff(me, n, 0)
    end
  end,
}

-- Metaltooth Leaper: your other Mechs +2 Attack.
cards.GVG_048 = {
  battlecry = function(g, me)
    for _, m in ipairs(mechs(g, g.ctrl(me), me)) do
      g.buff(m, 2, 0)
    end
  end,
}

-- Gahz'rilla: whenever this minion takes damage, double its Attack.
cards.GVG_049 = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me then
        g.buff(me, g.atk(me), 0)
      end
    end,
  },
}

-- Cobra Shot: 3 damage to a minion and the enemy hero.
cards.GVG_073 = {
  target = "minion",
  spell = function(g, me, t)
    local n = g.spell_dmg(me, 3)
    g.damage(me, t, n)
    g.damage(me, g.hero(g.enemy(me)), n)
  end,
}

-- Steamwheedle Sniper: your Hero Power can target minions (its mark for Steady Shot below).
local function sniper(g, me)
  return list.any(g.minions(g.ctrl(me)), function(m)
    return g.card(m) == "GVG_087" and not g.silenced(m)
  end)
end

-- --- Druid -------------------------------------------------------------------------------------

-- Anodized Robo Cub: Choose One - +1 Attack; or +1 Health.
cards.GVG_030 = { choose_one = { "GVG_030a", "GVG_030b" } }
cards.GVG_030a = {
  effect = function(g, me)
    g.buff(me, 1, 0)
  end,
}
cards.GVG_030b = {
  effect = function(g, me)
    g.buff(me, 0, 1)
  end,
}

-- Recycle: shuffle an enemy minion into your opponent's deck.
cards.GVG_031 = {
  target = "enemy_minion",
  spell = function(g, me, t)
    local c, p = g.card(t), g.ctrl(t)
    g.remove(t, "SETASIDE")
    g.add_to_deck(p, c)
  end,
}

-- Grove Tender: Choose One - each player gets a Mana Crystal; or each player draws a card.
cards.GVG_032 = { choose_one = { "GVG_032a", "GVG_032b" } }
cards.GVG_032a = {
  effect = function(g, me)
    g.gain_mana(g.ctrl(me), 1)
    g.gain_mana(g.enemy(me), 1)
  end,
}
cards.GVG_032b = {
  effect = function(g, me)
    g.draw(g.ctrl(me))
    g.draw(g.enemy(me))
  end,
}

-- Tree of Life: restore all characters to full Health (each by its maximum Health: with Auchenai Soulpriest,
-- that much damage).
cards.GVG_033 = {
  spell = function(g, me)
    for _, c in ipairs(g.all_chars()) do
      g.heal(me, c, g.max_health(c))
    end
  end,
}

-- Mech-Bear-Cat: whenever this minion takes damage, a Spare Part into your hand.
cards.GVG_034 = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me then
        spare_part(g, g.ctrl(me))
      end
    end,
  },
}

-- Malorne: Deathrattle: shuffle this minion into your deck.
cards.GVG_035 = {
  deathrattle = function(g, me)
    g.add_to_deck(g.ctrl(me), g.card(me))
  end,
}

-- Dark Wispers: Choose One - summon 5 Wisps; or a minion gets +5/+5 and Taunt.
cards.GVG_041 = { choose_one = { "GVG_041b", "GVG_041a" } }
cards.GVG_041a = {
  target = "minion",
  effect = function(g, me, t)
    g.buff(t, 5, 5)
    g.give_tag(t, "TAUNT")
  end,
}
cards.GVG_041b = {
  effect = function(g, me)
    for _ = 1, 5 do
      g.summon(g.ctrl(me), "VAN_CS2_231")
    end
  end,
}

-- Druid of the Fang: if you have a Beast, transform into a 7/7.
cards.GVG_080 = {
  glow = function(g, me)
    return have_race(g, me, "BEAST")
  end,
  battlecry = function(g, me)
    if have_race(g, me, "BEAST") then
      g.transform(me, "GVG_080t")
    end
  end,
}

-- --- Shaman ------------------------------------------------------------------------------------

-- Ancestor's Call: a random minion from each player's hand into the battlefield.
cards.GVG_029 = {
  spell = function(g, me)
    for _, p in ipairs({ g.ctrl(me), g.enemy(me) }) do
      local e = g.pick(only(g.hand(p), g.is_minion))
      if e then
        g.summon_entity(e)
      end
    end
  end,
}

-- Powermace: Deathrattle: a random friendly Mech +2/+2.
cards.GVG_036 = {
  deathrattle = function(g, me)
    g.buff(g.pick(only(alive(g, g.minions(g.ctrl(me))), function(m)
      return is_mech(g, m)
    end)), 2, 2)
  end,
}

-- Crackle: 3-6 damage.
cards.GVG_038 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, g.random(3, 6)))
  end,
}

-- Vitality Totem: at the end of your turn, restore 4 Health to your hero.
cards.GVG_039 = my_turn_end(function(g, me)
  g.heal(me, g.hero(g.ctrl(me)), 4)
end)

-- Siltfin Spiritwalker: whenever another friendly Murloc dies, draw a card.
cards.GVG_040 = on_mine("death", function(g, me, ev)
  if ev.minion and ev.entity ~= me and g.race(ev.entity) == "MURLOC" then
    g.draw(g.ctrl(me))
  end
end)

-- Neptulon: 4 random Murlocs into your hand.
cards.GVG_042 = {
  battlecry = function(g, me)
    local murlocs = minions_where(g, function(i)
      return i.race == "MURLOC"
    end)
    for _ = 1, 4 do
      g.add_to_hand(g.ctrl(me), g.pick(murlocs))
    end
  end,
}

-- Dunemaul Shaman
cards.GVG_066 = forgetful()

-- --- Paladin -----------------------------------------------------------------------------------

-- Seal of Light: restore 4 Health to your hero and +2 Attack this turn.
cards.GVG_057 = {
  spell = function(g, me)
    local h = g.hero(g.ctrl(me))
    g.heal(me, h, g.heal_amt(me, 4))
    g.buff(h, 2, 0, true)
  end,
}

-- Coghammer: a random friendly minion gets Divine Shield and Taunt.
cards.GVG_059 = {
  battlecry = function(g, me)
    local m = g.random_alive(g.minions(g.ctrl(me)))
    if m then
      g.give_tag(m, "DIVINE_SHIELD")
      g.give_tag(m, "TAUNT")
    end
  end,
}

-- Quartermaster: your Silver Hand Recruits +2/+2.
cards.GVG_060 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.others(me)) do
      if g.card(m) == "VAN_CS2_101t" then
        g.buff(m, 2, 2)
      end
    end
  end,
}

-- Muster for Battle: three 1/1 Silver Hand Recruits and a 1/4 weapon.
cards.GVG_061 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 3 do
      g.summon(p, "VAN_CS2_101t")
    end
    g.equip(p, "VAN_CS2_091")
  end,
}

-- Cobalt Guardian: whenever you summon a Mech, gain Divine Shield.
cards.GVG_062 = on_mine("summon", function(g, me, ev)
  if ev.entity ~= me and is_mech(g, ev.entity) then
    g.give_tag(me, "DIVINE_SHIELD")
  end
end)

-- Bolvar Fordragon: whenever a friendly minion dies while this is in your hand, +1 Attack.
cards.GVG_063 = {
  hand = {
    death = function(g, me, ev)
      if ev.minion and g.mine(me, ev) then
        g.buff(me, 1, 0)
      end
    end,
  },
}

-- Scarlet Purifier: 2 damage to all minions with Deathrattle.
cards.GVG_101 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if g.has(m, "DEATHRATTLE") then
        g.damage(me, m, 2)
      end
    end
  end,
}

-- --- Warrior -----------------------------------------------------------------------------------

-- Bouncing Blade: 1 damage to a random minion, again until a minion dies (at most 80 times).
cards.GVG_050 = {
  can_play = function(g, me)
    return #g.all_minions() > 0
  end,
  spell = function(g, me)
    for _ = 1, 80 do
      local t = g.pick(only(alive(g, g.all_minions()), function(m)
        return not g.has(m, "IMMUNE")
      end))
      if not t then
        return
      end
      g.damage(me, t, g.spell_dmg(me, 1))
      if g.health(t) <= 0 then
        return
      end
    end
  end,
}

-- Warbot: Enrage: +1 Attack.
cards.GVG_051 = {
  aura = function(g, me)
    if g.dmg(me) > 0 then
      g.aura_add(me, 1, 0)
    end
  end,
}

-- Crush: destroy a minion; costs (4) less if you have a damaged minion.
local function damaged_friend(g, me)
  return list.any(g.minions(g.ctrl(me)), function(m)
    return g.dmg(m) > 0
  end)
end
cards.GVG_052 = {
  target = "minion",
  cost_mod = function(g, me)
    return damaged_friend(g, me) and -4 or 0
  end,
  glow = damaged_friend,
  spell = function(g, me, t)
    g.destroy(t)
  end,
}

-- Shieldmaiden: gain 5 Armor.
cards.GVG_053 = {
  battlecry = function(g, me)
    g.gain_armor(g.ctrl(me), 5)
  end,
}

-- Ogre Warmaul: its hero's attacks may go at the wrong enemy.
cards.GVG_054 = {
  on = {
    attack = function(g, me, ev)
      if ev.attacker == g.hero(g.ctrl(me)) then
        forget(g, ev)
      end
    end,
  },
}

-- Screwjank Clunker: a friendly Mech +2/+2.
cards.GVG_055 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me and is_mech(g, t)
  end },
  battlecry = function(g, me, t)
    g.buff(t, 2, 2)
  end,
}

-- Iron Juggernaut: a Burrowing Mine into your opponent's deck.
cards.GVG_056 = {
  battlecry = function(g, me)
    g.add_to_deck(g.enemy(me), "GVG_056t")
  end,
}

-- Burrowing Mine: when drawn it explodes: 10 damage to its holder, who draws a card.
cards.GVG_056t = {
  hand = {
    draw = function(g, me, ev)
      if ev.entity == me then
        local p = g.ctrl(me)
        g.remove(me, "GRAVEYARD")
        g.damage(me, g.hero(p), 10)
        g.draw(p)
      end
    end,
  },
}

-- Siege Engine: whenever you gain Armor, +1 Attack.
cards.GVG_086 = on_mine("armor", function(g, me)
  g.buff(me, 1, 0)
end)

-- --- Neutral -----------------------------------------------------------------------------------

-- Cogmaster: +2 Attack while you have a Mech.
cards.GVG_013 = {
  aura = function(g, me)
    if have_mech(g, me) then
      g.aura_add(me, 2, 0)
    end
  end,
}

-- Fel Reaver: whenever your opponent plays a card, the top 3 cards of your deck are discarded.
cards.GVG_016 = {
  on = {
    play = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.player ~= p then
        for _ = 1, 3 do
          local d = g.deck(p)
          local top = d[#d]
          if not top then
            return
          end
          g.remove(top, "GRAVEYARD")
          g.log({ type = "burn", player = p, entity = top, card = g.card(top) })
        end
      end
    end,
  },
}

-- Ogre Brute
cards.GVG_065 = forgetful()

-- Stonesplinter Trogg, Burly Rockjaw Trogg: whenever your opponent casts a spell, +1 / +2 Attack.
local function grows_on_enemy_spells(n)
  return {
    on = {
      play = function(g, me, ev)
        if ev.kind == "spell" and not g.mine(me, ev) then
          g.buff(me, n, 0)
        end
      end,
    },
  }
end
cards.GVG_067 = grows_on_enemy_spells(1)
cards.GVG_068 = grows_on_enemy_spells(2)

-- Antique Healbot: restore 8 Health to your hero.
cards.GVG_069 = {
  battlecry = function(g, me)
    g.heal(me, g.hero(g.ctrl(me)), 8)
  end,
}

-- Kezan Mystic: take control of a random enemy Secret (one you don't have; if you have them all, a random one
-- is destroyed: g.take_control of a Secret you have).
cards.GVG_074 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local have = {}
    for _, s in ipairs(g.traps(p)) do
      have[g.card(s)] = true
    end
    local theirs = g.traps(g.enemy(me))
    local new = only(theirs, function(s)
      return not have[g.card(s)]
    end)
    g.take_control(g.pick(#new > 0 and new or theirs), p)
  end,
}

-- Ship's Cannon: whenever you summon a Pirate, 2 damage to a random enemy.
cards.GVG_075 = on_mine("summon", function(g, me, ev)
  if ev.entity ~= me and g.race(ev.entity) == "PIRATE" then
    g.damage(me, g.random_alive(g.chars(g.enemy(me))), 2)
  end
end)

-- Explosive Sheep: Deathrattle: 2 damage to all minions.
cards.GVG_076 = {
  deathrattle = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      g.damage(me, m, 2)
    end
  end,
}

-- Mechanical Yeti: Deathrattle: each player gets a Spare Part.
cards.GVG_078 = {
  deathrattle = function(g, me)
    spare_part(g, g.ctrl(me))
    spare_part(g, g.enemy(me))
  end,
}

-- Clockwork Gnome: Deathrattle: a Spare Part.
cards.GVG_082 = {
  deathrattle = function(g, me)
    spare_part(g, g.ctrl(me))
  end,
}

-- Illuminator: if you control a Secret at the end of your turn, restore 4 Health to your hero.
cards.GVG_089 = my_turn_end(function(g, me)
  if #g.traps(g.ctrl(me)) > 0 then
    g.heal(me, g.hero(g.ctrl(me)), 4)
  end
end)

-- Madder Bomber: 6 damage randomly split between all other characters.
cards.GVG_090 = {
  battlecry = function(g, me)
    split(g, me, 6, function()
      return only(g.all_chars(), function(c)
        return c ~= me
      end)
    end)
  end,
}

-- Gnomish Experimenter: draw a card; a minion becomes a Chicken.
cards.GVG_092 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local e = g.draw(p)[1]
    g.resolve() -- what it does when drawn goes first (Flame Leviathan)
    if e and g.zone(e) == "HAND" and g.is_minion(e) then
      g.remove(e, "SETASIDE")
      g.add_to_hand(p, "GVG_092t")
    end
  end,
}

-- Jeeves: at the end of each player's turn, that player draws until they have 3 cards.
cards.GVG_094 = {
  on = {
    turn_end = function(g, me, ev)
      draw_until(g, ev.player, 3)
    end,
  },
}

-- Goblin Sapper: +4 Attack while your opponent has 6 or more cards in hand.
cards.GVG_095 = {
  aura = function(g, me)
    if #g.hand(g.enemy(me)) >= 6 then
      g.aura_add(me, 4, 0)
    end
  end,
}

-- A deathrattle that summons a random minion whose data pass ok, where it died.
local function piloted(ok)
  return {
    deathrattle = function(g, me)
      local c = g.pick(minions_where(g, ok))
      if c then
        g.summon(g.ctrl(me), c, g.died_pos(me))
      end
    end,
  }
end

cards.GVG_096 = piloted(function(i)
  return i.cost == 2
end) -- Piloted Shredder: a random 2-Cost minion
cards.GVG_105 = piloted(function(i)
  return i.cost == 4
end) -- Piloted Sky Golem: a random 4-Cost minion
cards.GVG_114 = piloted(function(i)
  return i.rarity == "LEGENDARY"
end) -- Sneed's Old Shredder: a random legendary minion

-- Lil' Exorcist: +1/+1 for each enemy minion with Deathrattle.
cards.GVG_097 = {
  battlecry = function(g, me)
    local n = #only(g.minions(g.enemy(me)), function(m)
      return g.has(m, "DEATHRATTLE")
    end)
    if n > 0 then
      g.buff(me, n, n)
    end
  end,
}

-- Bomb Lobber: 4 damage to a random enemy minion.
cards.GVG_099 = {
  battlecry = function(g, me)
    g.damage(me, g.random_alive(g.minions(g.enemy(me))), 4)
  end,
}

-- Tinkertown Technician: if you have a Mech, +1/+1 and a Spare Part.
cards.GVG_102 = {
  glow = have_mech,
  battlecry = function(g, me)
    if have_mech(g, me) then
      g.buff(me, 1, 1)
      spare_part(g, g.ctrl(me))
    end
  end,
}

-- Micro Machine: at the start of each turn, +1 Attack.
cards.GVG_103 = {
  on = {
    turn_start = function(g, me)
      g.buff(me, 1, 0)
    end,
  },
}

-- Hobgoblin: whenever you play a 1-Attack minion, it gets +2/+2.
cards.GVG_104 = on_mine("play", function(g, me, ev)
  if ev.kind == "minion" and ev.entity ~= me and g.info(ev.card).attack == 1 then
    g.buff(ev.entity, 2, 2)
  end
end)

-- Junkbot: whenever a friendly Mech dies, +2/+2.
cards.GVG_106 = on_mine("death", function(g, me, ev)
  if ev.minion and ev.entity ~= me and is_mech(g, ev.entity) then
    g.buff(me, 2, 2)
  end
end)

-- Enhance-o Mechano: each of your other minions gets Windfury, Taunt or Divine Shield (at random).
local GIFTS = { "WINDFURY", "TAUNT", "DIVINE_SHIELD" }
cards.GVG_107 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.others(me)) do
      g.give_tag(m, g.pick(GIFTS))
    end
  end,
}

-- Recombobulator: a friendly minion becomes a random minion with the same Cost.
cards.GVG_108 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return t ~= me
  end },
  battlecry = function(g, me, t)
    local cost = g.info(g.card(t)).cost
    local c = g.pick(minions_where(g, function(i)
      return i.cost == cost
    end))
    if c then
      g.transform(t, c)
    end
  end,
}

-- Dr. Boom: two 1/1 Boom Bots, one on each side.
cards.GVG_110 = {
  battlecry = function(g, me)
    g.summon_right(me, "GVG_110t")
    g.summon(g.ctrl(me), "GVG_110t", g.board_pos(me))
  end,
}

-- Boom Bot: Deathrattle: 1-4 damage to a random enemy.
cards.GVG_110t = {
  deathrattle = function(g, me)
    local t = g.random_alive(g.chars(g.enemy(me)))
    if t then
      g.damage(me, t, g.random(1, 4))
    end
  end,
}

-- Mimiron's Head: at the start of your turn, with at least 3 Mechs (itself too), destroy them all and form
-- V-07-TR-0N.
cards.GVG_111 = on_mine("turn_start", function(g, me)
  local p = g.ctrl(me)
  local all = mechs(g, p)
  if #all >= 3 then
    for _, m in ipairs(all) do
      g.destroy(m)
    end
    -- ponytail: the Mechs' Deathrattles go before V-07-TR-0N comes (in Hearthstone after); an engine "remove
    -- the dead now, Deathrattles later" step would fix the order
    g.resolve()
    g.summon(p, "GVG_111t")
  end
end)

-- V-07-TR-0N: Mega-Windfury: four attacks a turn (after each of the first three it may attack again).
cards.GVG_111t = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == me then
        local n = g.tag(me, "MEGA_ATTACKS") + 1
        g.set_tag(me, "MEGA_ATTACKS", n)
        if n < 4 then
          g.set_tag(me, "ATTACKS", 0)
        end
      end
    end,
    turn_start = function(g, me)
      g.set_tag(me, "MEGA_ATTACKS", nil)
    end,
  },
}

-- Mogor the Ogre: all minions (both sides, itself too) have a 50% chance to attack the wrong enemy; each
-- such effect rolls for itself, one after another (an Ogre Brute with Mogor rolls twice).
cards.GVG_112 = {
  on = {
    attack = function(g, me, ev)
      if g.is_minion(ev.attacker) then
        forget(g, ev)
      end
    end,
  },
}

-- Foe Reaper 4000: also damages the minions next to whomever it attacks.
cards.GVG_113 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == me and g.is_minion(ev.defender) then
        local n = g.atk(me)
        for _, m in ipairs(g.adjacent(ev.defender)) do
          g.damage(me, m, n)
        end
      end
    end,
  },
}

-- Toshley: Battlecry and Deathrattle: a Spare Part.
cards.GVG_115 = {
  battlecry = function(g, me)
    spare_part(g, g.ctrl(me))
  end,
  deathrattle = function(g, me)
    spare_part(g, g.ctrl(me))
  end,
}

-- Mekgineer Thermaplugg: whenever an enemy minion dies, summon a Leper Gnome.
cards.GVG_116 = {
  on = {
    death = function(g, me, ev)
      if ev.minion and not g.mine(me, ev) then
        g.summon(g.ctrl(me), "VAN_EX1_029")
      end
    end,
  },
}

-- Gazlowe: whenever you cast a 1-mana spell, a random Mech into your hand.
-- ponytail: the card's cost, not what was paid (Preparation, Loatheb); the play event would need the paid cost.
cards.GVG_117 = on_mine("play", function(g, me, ev)
  if ev.kind == "spell" and g.info(ev.card).cost == 1 then
    g.add_to_hand(g.ctrl(me), g.pick(minions_where(g, function(i)
      return i.race == "MECHANICAL"
    end)))
  end
end)

-- Troggzor the Earthinator: whenever your opponent casts a spell, summon a Burly Rockjaw Trogg.
cards.GVG_118 = {
  on = {
    play = function(g, me, ev)
      if ev.kind == "spell" and not g.mine(me, ev) then
        g.summon(g.ctrl(me), "GVG_068")
      end
    end,
  },
}

-- Blingtron 3000: each player equips a random weapon.
cards.GVG_119 = {
  battlecry = function(g, me)
    local weapons = collectible(g, function(i)
      return i.type == "WEAPON"
    end)
    g.equip(g.ctrl(me), g.pick(weapons))
    g.equip(g.enemy(me), g.pick(weapons))
  end,
}

-- Hemet Nesingwary: destroy a Beast.
cards.GVG_120 = {
  target = { base = "minion", filter = function(g, me, t)
    return g.race(t) == "BEAST"
  end },
  battlecry = function(g, me, t)
    g.destroy(t)
  end,
}

-- Clockwork Giant: costs (1) less for each card in your opponent's hand.
cards.GVG_121 = {
  cost_mod = function(g, me)
    return -#g.hand(g.enemy(me))
  end,
}

-- --- Spare Parts -------------------------------------------------------------------------------

cards.PART_001 = { target = "minion", spell = function(g, me, t) g.buff(t, 0, 1) end } -- Armor Plating
cards.PART_002 = { target = "friendly_minion", spell = function(g, me, t) g.return_to_hand(t) end } -- Time Rewinder
cards.PART_003 = { target = "minion", spell = function(g, me, t) g.give_tag(t, "TAUNT") end } -- Rusty Horn
cards.PART_005 = { target = "minion", spell = function(g, me, t) g.freeze(t) end } -- Emergency Coolant
cards.PART_007 = { target = "minion", spell = function(g, me, t) g.buff(t, 1, 0) end } -- Whirling Blades

-- Finicky Cloakfield: a friendly minion has Stealth until your next turn.
cards.PART_004 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.give_tag(t, "STEALTH")
    g.enchant(t, { hooks = "ench:cloakfield", player = g.ctrl(me) })
  end,
}
cards["ench:cloakfield"] = {
  on = {
    turn_start = function(g, me, ev)
      for _, p in ipairs(g.enchants(me, "ench:cloakfield")) do
        if p == ev.player then
          g.remove_enchant(me, "ench:cloakfield", p)
          g.erase_tag(me, "STEALTH")
        end
      end
    end,
  },
}

-- Reversing Switch: swap a minion's Attack and Health.
cards.PART_006 = {
  target = "minion",
  spell = function(g, me, t)
    g.set_stats(t, g.health(t), g.atk(t))
  end,
}

-- --- Basic and Classic cards this patch changed ------------------------------------------------

-- Bestial Wrath (patch 2.0.0.7234): only a friendly Beast.
cards.VAN_EX1_549 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return g.race(t) == "BEAST"
  end },
  spell = function(g, me, t)
    g.buff(t, 2, 0, true)
    g.give_tag(t, "IMMUNE", true)
  end,
}

-- Steady Shot: 2 damage to the enemy hero; with Steamwheedle Sniper it targets the enemy hero or a minion.
cards.VAN_HERO_05bp = {
  target = { base = "any", when = sniper, filter = function(g, me, t)
    return g.is_minion(t) or t == g.hero(g.enemy(me))
  end },
  hero_power = function(g, me, t)
    g.damage(me, t or g.hero(g.enemy(me)), g.hp_dmg(me, 2))
  end,
}

return cards
