-- The Grand Tournament (August 2015): the 132 cards and their 26 tokens as at the release (patch 3.0.0.9786 of
-- 2015-08-18, six days before the set; hearthstone.wiki.gg and its card notes; docs/packs/api.md). The Basic,
-- Classic, Naxxramas, Goblins vs Gnomes and Blackrock Mountain cards are those packs' scripts, copied in by the
-- recipe; the few of them that changed by then are at the end.
local cards = {}

-- --- helpers -----------------------------------------------------------------------------------

-- The items of a list that pass ok(e).
local function only(list_, ok)
  local out = {}
  for _, e in ipairs(list_) do
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

-- Inspire: after its controller uses the Hero Power (the `hero_power` event comes after the power's effect).
local function inspire(f)
  return on_mine("hero_power", f)
end

-- Collectible cards of the constructed sets whose data pass ok(info).
local function collectible(g, ok)
  return only(g.collectible(), function(c)
    return ok(g.info(c))
  end)
end

-- A random collectible card whose data pass ok, or nil.
local function random_card(g, ok)
  return g.pick(collectible(g, ok))
end

local function minion_of_race(race)
  return function(i)
    return i.type == "MINION" and i.race == race
  end
end

-- me's side has a minion other than me that passes ok.
local function have(g, me, ok)
  return list.any(g.minions(g.ctrl(me)), function(m)
    return m ~= me and ok(m)
  end)
end

local function race_is(g, race)
  return function(m)
    return g.race(m) == race
  end
end

-- "If you're holding a Dragon": another card in me's controller's hand is a Dragon.
local function holding_dragon(g, me)
  return list.any(g.hand(g.ctrl(me)), function(c)
    return c ~= me and g.race(c) == "DRAGON"
  end)
end

-- A minion for me's side right of me (where it stood if it already left the board).
local function summon_beside(g, me, card)
  if g.board_pos(me) then
    return g.summon_right(me, card)
  end
  local pos = g.died_pos(me)
  return g.summon(g.ctrl(me), card, pos >= 0 and pos or nil)
end

-- A random living enemy character of me, or nil.
local function random_enemy(g, me)
  return g.random_alive(g.chars(g.enemy(me)))
end

-- Joust: each player reveals a random minion of their deck; me's side wins if its minion's base cost is higher. No
-- minion in me's deck: lost, nothing revealed; none in the other deck: won. Both players see both cards (a `joust`
-- event, card ids only). Returns won and me's revealed minion.
-- ponytail: the revealed cards stay where they were instead of being shuffled back: their places were random already.
local function joust(g, me)
  local p = g.ctrl(me)
  local is_minion = function(e)
    return g.type(e) == "MINION"
  end
  local mine = g.pick(only(g.deck(p), is_minion))
  local theirs = mine and g.pick(only(g.deck(g.opponent(p)), is_minion))
  local won = mine ~= nil and (theirs == nil or g.info(g.card(mine)).cost > g.info(g.card(theirs)).cost)
  g.log({ type = "joust", player = p, card = mine and g.card(mine) or "", foe_card = theirs and g.card(theirs) or "",
    won = won })
  return won, mine
end

-- "Whenever you target this minion with a spell" (as the spell is cast, before it resolves; also when countered).
local function targeted_by_my_spell(f)
  return {
    on = {
      play = function(g, me, ev)
        if ev.kind == "spell" and ev.target == me and g.mine(me, ev) then
          f(g, me)
        end
      end,
    },
  }
end

-- Steamwheedle Sniper: your Hero Power can target minions.
local function sniper(g, me)
  return list.any(g.minions(g.ctrl(me)), function(m)
    return g.card(m) == "GVG_087" and not g.silenced(m)
  end)
end

-- The power can be used again (Coldarra Drake; Garrison Commander while it was used fewer than twice this turn).
local function refresh_power(g, me, limit)
  local hp = g.power(g.ctrl(me))
  if not limit or g.tag(hp, "POWER_USES") < limit then
    g.erase_tag(hp, "USED")
  end
end

local function refresher(limit)
  return {
    on = {
      hero_power = function(g, me, ev)
        if g.mine(me, ev) then
          refresh_power(g, me, limit)
        end
      end,
      summon = function(g, me, ev)
        if ev.entity == me then
          refresh_power(g, me, limit)
        end
      end,
    },
  }
end

-- --- the upgraded Hero Powers (Justicar Trueheart) ----------------------------------------------

-- Each basic Hero Power and its better one.
local UPGRADE = {
  VAN_HERO_01bp = "AT_132_WARRIOR", VAN_HERO_02bp = "AT_132_SHAMAN", VAN_HERO_03bp = "AT_132_ROGUE",
  VAN_HERO_04bp = "AT_132_PALADIN", VAN_HERO_05bp = "AT_132_HUNTER", VAN_HERO_06bp = "AT_132_DRUID",
  VAN_HERO_07bp = "AT_132_WARLOCK", VAN_HERO_08bp = "AT_132_MAGE", VAN_HERO_09bp = "AT_132_PRIEST",
}

-- Justicar Trueheart: a basic Hero Power (the one you have now, even a copied one) becomes its better one, unused.
cards.AT_132 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    local up = UPGRADE[g.card(g.power(p))]
    if up then
      g.set_power(p, up)
    end
  end,
}

-- Dire Shapeshift: +2 Attack this turn and 2 Armor.
cards.AT_132_DRUID = {
  hero_power = function(g, me)
    local p = g.ctrl(me)
    g.buff(g.hero(p), 2, 0, true)
    g.gain_armor(p, 2)
  end,
}

-- Ballista Shot: 3 damage to the enemy hero (with Steamwheedle Sniper: or a minion).
cards.AT_132_HUNTER = {
  target = { base = "any", when = sniper, filter = function(g, me, t)
    return g.is_minion(t) or t == g.hero(g.enemy(me))
  end },
  hero_power = function(g, me, t)
    g.damage(me, t or g.hero(g.enemy(me)), g.hp_dmg(me, 3))
  end,
}

-- Fireblast Rank 2 and Lightning Jolt (Charged Hammer): 2 damage.
local function zap(n)
  return {
    target = "any",
    hero_power = function(g, me, t)
      g.damage(me, t, g.hp_dmg(me, n))
    end,
  }
end
cards.AT_132_MAGE = zap(2)
cards.AT_050t = zap(2)

-- The Silver Hand: two 1/1 Silver Hand Recruits.
cards.AT_132_PALADIN = {
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
  hero_power = function(g, me)
    local p = g.ctrl(me)
    g.summon(p, "VAN_CS2_101t")
    g.summon(p, "VAN_CS2_101t")
  end,
}

-- Heal: restore 4 Health.
cards.AT_132_PRIEST = {
  target = "any",
  hero_power = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 4))
  end,
}

-- Poisoned Blade in your hands: your Hero Power does not replace it (its own trigger gives it +1 Attack).
local function poisoned_blade(g, me)
  local w = g.weapon(g.ctrl(me))
  return w and g.card(w) == "AT_034" and not g.silenced(w)
end

-- Poisoned Daggers: equip a 2/2 Poisoned Dagger.
cards.AT_132_ROGUE = {
  hero_power = function(g, me)
    if not poisoned_blade(g, me) then
      g.equip(g.ctrl(me), "AT_132_ROGUEt")
    end
  end,
}

-- Totemic Slam: the totem of your choice (any of the four, one you already have too).
local SLAM = { AT_132_SHAMANa = "VAN_NEW1_009", AT_132_SHAMANb = "VAN_CS2_050", AT_132_SHAMANc = "VAN_CS2_051",
  AT_132_SHAMANd = "VAN_CS2_052" }
cards.AT_132_SHAMAN = {
  can_play = function(g, me)
    return g.room(g.ctrl(me)) > 0
  end,
  hero_power = function(g, me)
    local p = g.ctrl(me)
    local opts = {}
    for _, c in ipairs({ "AT_132_SHAMANa", "AT_132_SHAMANb", "AT_132_SHAMANc", "AT_132_SHAMANd" }) do
      opts[#opts + 1] = g.create(p, c)
    end
    g.request_choice(me, opts)
  end,
  on_choose = function(g, me, option)
    g.summon(g.ctrl(me), SLAM[g.card(option)])
  end,
}

-- Soul Tap: draw a card.
cards.AT_132_WARLOCK = {
  hero_power = function(g, me)
    g.draw(g.ctrl(me))
  end,
}

-- Tank Up!: 4 Armor.
cards.AT_132_WARRIOR = {
  hero_power = function(g, me)
    g.gain_armor(g.ctrl(me), 4)
  end,
}

-- --- Druid -------------------------------------------------------------------------------------

-- Living Roots: Choose One - 2 damage; or two 1/1 Saplings.
cards.AT_037 = { choose_one = { "AT_037a", "AT_037b" } }
cards.AT_037a = {
  target = "any",
  effect = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 2))
  end,
}
cards.AT_037b = {
  effect = function(g, me)
    local p = g.ctrl(me)
    g.summon(p, "AT_037t")
    g.summon(p, "AT_037t")
  end,
}

-- Darnassus Aspirant: an empty Mana Crystal (none at 10, no Excess Mana); Deathrattle: one crystal less (an empty
-- one first).
cards.AT_038 = {
  battlecry = function(g, me)
    g.gain_mana(g.ctrl(me), 1, true)
  end,
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    local max = g.max_mana(p)
    if max > 0 then
      g.set_mana(p, math.min(g.mana(p), max - 1), max - 1)
    end
  end,
}

-- Savage Combatant: Inspire: your hero +2 Attack this turn.
cards.AT_039 = inspire(function(g, me)
  g.buff(g.hero(g.ctrl(me)), 2, 0, true)
end)

-- Wildwalker: a friendly Beast +3 Health.
cards.AT_040 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return g.race(t) == "BEAST"
  end },
  battlecry = function(g, me, t)
    g.buff(t, 0, 3)
  end,
}

-- Knight of the Wild: whenever you summon a Beast, it costs (1) less (in the hand). A Druid that turns into a Beast
-- as it is played counts too (Druid of the Claw, of the Flame, of the Saber; of the Fang with a Beast).
local TO_BEAST = { VAN_EX1_165 = true, BRM_010 = true, AT_042 = true }
cards.AT_041 = {
  hand = {
    summon = function(g, me, ev)
      if ev.player == g.ctrl(me) and g.race(ev.entity) == "BEAST" then
        g.enchant(me, { cost = -1 })
      end
    end,
    play = function(g, me, ev)
      if ev.player == g.ctrl(me) and ev.kind == "minion" and (TO_BEAST[ev.card]
          or (ev.card == "GVG_080" and have(g, ev.entity, race_is(g, "BEAST")))) then
        g.enchant(me, { cost = -1 })
      end
    end,
  },
}

-- Druid of the Saber: Choose One - a 2/1 with Charge; or a 3/2 with Stealth.
cards.AT_042 = { choose_one = { "AT_042a", "AT_042b" } }
cards.AT_042a = {
  effect = function(g, me)
    g.transform(me, "AT_042t")
  end,
}
cards.AT_042b = {
  effect = function(g, me)
    g.transform(me, "AT_042t2")
  end,
}

-- Astral Communion: discard your hand; then 10 full Mana Crystals, or Excess Mana if you have 10 already.
cards.AT_043 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _, c in ipairs(g.hand(p)) do
      g.discard(c)
    end
    g.resolve()
    local max = g.rule("max_mana")
    if g.max_mana(p) >= max then
      g.add_to_hand(p, "CS2_013t")
    else
      g.set_mana(p, max, max)
    end
  end,
}

-- Mulch: destroy a minion; a random minion card into your opponent's hand.
cards.AT_044 = {
  target = "minion",
  spell = function(g, me, t)
    g.destroy(t)
    local c = random_card(g, function(i)
      return i.type == "MINION"
    end)
    if c then
      g.add_to_hand(g.enemy(me), c)
    end
  end,
}

-- Aviana: your minion cards cost (1) (0-Cost ones too).
cards.AT_045 = {
  cost_aura = function(g, me, card, cost)
    if g.type(card) == "MINION" and g.ctrl(card) == g.ctrl(me) and g.zone(card) == "HAND" then
      return 1
    end
    return cost
  end,
}

-- --- Hunter ------------------------------------------------------------------------------------

-- Ram Wrangler: if you have a Beast, a random Beast.
local function have_beast(g, me)
  return have(g, me, race_is(g, "BEAST"))
end
cards.AT_010 = {
  glow = have_beast,
  battlecry = function(g, me)
    if have_beast(g, me) then
      local c = random_card(g, minion_of_race("BEAST"))
      if c then
        g.summon_right(me, c)
      end
    end
  end,
}

-- Powershot: 2 damage to a minion and the minions next to it (the target, then left, then right).
cards.AT_056 = {
  target = "minion",
  spell = function(g, me, t)
    local near = g.adjacent(t)
    local n = g.spell_dmg(me, 2)
    g.damage(me, t, n)
    for _, m in ipairs(near) do
      g.damage(me, m, n)
    end
  end,
}

-- Stablemaster: a friendly Beast is Immune this turn.
cards.AT_057 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return g.race(t) == "BEAST"
  end },
  battlecry = function(g, me, t)
    g.give_tag(t, "IMMUNE", true)
  end,
}

-- King's Elekk: Joust: if yours costs more, draw it.
cards.AT_058 = {
  battlecry = function(g, me)
    local won, mine = joust(g, me)
    if won then
      g.draw_entity(g.ctrl(me), mine)
    end
  end,
}

-- Brave Archer: Inspire: if your hand is empty, 2 damage to the enemy hero.
cards.AT_059 = inspire(function(g, me)
  if #g.hand(g.ctrl(me)) == 0 then
    g.damage(me, g.hero(g.enemy(me)), 2)
  end
end)

-- Bear Trap: after your hero is attacked, an Ironfur Grizzly (3/3 Taunt; with a full board, none: the Secret is
-- spent anyway, as at the release until patch 4.0.0.10833).
cards.AT_060 = {
  secret = {
    event = "after_attack",
    cond = function(g, me, ev)
      return ev.defender == g.hero(g.ctrl(me))
    end,
    effect = function(g, me)
      g.summon(g.ctrl(me), "VAN_CS2_125")
    end,
  },
}

-- Lock and Load: each time you cast a spell this turn, a random Hunter card (not for itself; before the spell
-- resolves). The effect lives on your hero until the turn ends.
cards.AT_061 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.enchant(g.hero(p), { hooks = "ench:lock_and_load", player = p, eot = true })
  end,
}
cards["ench:lock_and_load"] = {
  on = {
    play = function(g, me, ev)
      if ev.kind == "spell" and g.mine(me, ev) then
        local c = random_card(g, function(i)
          return i.class == "HUNTER"
        end)
        if c then
          g.add_to_hand(g.ctrl(me), c)
        end
      end
    end,
  },
}

-- Ball of Spiders: three 1/1 Webspinners.
cards.AT_062 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 3 do
      g.summon(p, "FP1_011")
    end
  end,
}

-- Acidmaw: whenever another minion (either side) takes damage, destroy it.
cards.AT_063 = {
  on = {
    damage = function(g, me, ev)
      if ev.target ~= me and ev.amount > 0 and g.is_minion(ev.target) then
        g.destroy(ev.target)
      end
    end,
  },
}

-- Dreadscale: at the end of your turn, 1 damage to all other minions.
cards.AT_063t = on_mine("turn_end", function(g, me)
  for _, m in ipairs(g.all_minions()) do
    if m ~= me then
      g.damage(me, m, 1)
    end
  end
end)

-- --- Mage --------------------------------------------------------------------------------------

-- Flame Lance: 8 damage to a minion.
cards.AT_001 = {
  target = "minion",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 8))
  end,
}

-- Effigy: when a friendly minion dies, a random minion with the same (base) Cost.
cards.AT_002 = {
  secret = {
    event = "death",
    cond = function(g, me, ev)
      return ev.minion and ev.player == g.ctrl(me)
    end,
    effect = function(g, me, ev)
      local cost = g.info(ev.card).cost
      local c = random_card(g, function(i)
        return i.type == "MINION" and i.cost == cost
      end)
      if c then
        g.summon(g.ctrl(me), c)
      end
    end,
  },
}

-- Fallen Hero: your Hero Power deals 1 extra damage (before Prophet Velen doubles it).
cards.AT_003 = {
  aura = function(g, me)
    g.aura_add(g.hero(g.ctrl(me)), 0, 0, { POWER_DAMAGE = 1 })
  end,
}

-- Arcane Blast: 2 damage to a minion, Spell Damage counted twice (then Velen): 2 + 2 x Spell Damage.
cards.AT_004 = {
  target = "minion",
  spell = function(g, me, t)
    local sp = 0
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      sp = sp + g.tag(m, "SPELLPOWER")
    end
    g.damage(me, t, g.spell_dmg(me, 2 + sp))
  end,
}

-- Polymorph: Boar: a minion becomes a 4/2 Boar with Charge.
cards.AT_005 = {
  target = "minion",
  spell = function(g, me, t)
    g.transform(t, "AT_005t")
  end,
}

-- Dalaran Aspirant: Inspire: Spell Damage +1 (it stays and adds up).
cards.AT_006 = inspire(function(g, me)
  g.add_tag(me, "SPELLPOWER", 1)
end)

-- Spellslinger: a random spell (any class) into each player's hand.
cards.AT_007 = {
  battlecry = function(g, me)
    local spell = function(i)
      return i.type == "SPELL"
    end
    local p = g.ctrl(me)
    for _, q in ipairs({ p, g.opponent(p) }) do
      local c = random_card(g, spell)
      if c then
        g.add_to_hand(q, c)
      end
    end
  end,
}

-- Coldarra Drake: you can use your Hero Power any number of times.
cards.AT_008 = refresher(nil)

-- Rhonin: Deathrattle: three Arcane Missiles into your hand.
cards.AT_009 = {
  deathrattle = function(g, me)
    for _ = 1, 3 do
      g.add_to_hand(g.ctrl(me), "VAN_EX1_277")
    end
  end,
}

-- --- Paladin -----------------------------------------------------------------------------------

-- Competitive Spirit: when your turn starts (with a minion), your minions +1/+1. The first Secret that goes off on
-- its owner's turn: an `on` hook, not a trap hook (those wait for the opponent's turn).
cards.AT_073 = {
  on = {
    turn_start = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.player == p and #g.minions(p) > 0 then
        g.reveal(me)
        for _, m in ipairs(g.minions(p)) do
          g.buff(m, 1, 1)
        end
      end
    end,
  },
}

-- Seal of Champions: a minion +3 Attack and Divine Shield.
cards.AT_074 = {
  target = "minion",
  spell = function(g, me, t)
    g.buff(t, 3, 0)
    g.give_tag(t, "DIVINE_SHIELD")
  end,
}

-- Warhorse Trainer: your Silver Hand Recruits have +1 Attack.
cards.AT_075 = {
  aura = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if g.card(m) == "VAN_CS2_101t" then
        g.aura_add(m, 1, 0)
      end
    end
  end,
}

-- Murloc Knight: Inspire: a random Murloc.
cards.AT_076 = inspire(function(g, me)
  local c = random_card(g, minion_of_race("MURLOC"))
  if c then
    g.summon(g.ctrl(me), c)
  end
end)

-- Argent Lance: Joust: if yours costs more, +1 Durability.
cards.AT_077 = {
  battlecry = function(g, me)
    if joust(g, me) then
      g.add_tag(me, "DURABILITY", 1)
    end
  end,
}

-- Enter the Coliseum: each side keeps only its highest-Attack minion (a tie: a random one of them).
cards.AT_078 = {
  spell = function(g, me)
    for p = 0, 1 do
      local ms = g.minions(p)
      local best = -1
      for _, m in ipairs(ms) do
        best = math.max(best, g.atk(m))
      end
      local keep = g.pick(only(ms, function(m)
        return g.atk(m) == best
      end))
      for _, m in ipairs(ms) do
        if m ~= keep then
          g.destroy(m)
        end
      end
    end
  end,
}

-- Mysterious Challenger: one of each Secret of your deck into play (as Mad Scientist: not one already in play, at
-- most `limits.secrets`).
cards.AT_079 = {
  battlecry = function(g, me)
    local seen = {}
    for _, e in ipairs(g.deck(g.ctrl(me))) do
      local c = g.card(e)
      if g.info(c).trap and not seen[c] then
        seen[c] = true
        g.put_trap(e)
      end
    end
  end,
}

-- Eadric the Pure: every enemy minion's Attack becomes 1.
cards.AT_081 = {
  battlecry = function(g, me)
    for _, m in ipairs(g.minions(g.enemy(me))) do
      g.set_stats(m, 1, nil)
    end
  end,
}

-- Tuskarr Jouster: Joust: if yours costs more, restore 7 Health to your hero.
cards.AT_104 = {
  battlecry = function(g, me)
    if joust(g, me) then
      g.heal(me, g.hero(g.ctrl(me)), 7)
    end
  end,
}

-- --- Priest ------------------------------------------------------------------------------------

-- Holy Champion: whenever a character is healed, +2 Attack.
cards.AT_011 = {
  on = {
    heal = function(g, me)
      g.buff(me, 2, 0)
    end,
  },
}

-- Spawn of Shadows: Inspire: 4 damage to each hero (yours first).
cards.AT_012 = inspire(function(g, me)
  g.damage(me, g.hero(g.ctrl(me)), 4)
  g.damage(me, g.hero(g.enemy(me)), 4)
end)

-- Power Word: Glory: whenever the minion attacks, restore 4 Health to its controller's hero (in 2015 the
-- enchantment followed the minion to a new controller).
cards.AT_013 = {
  target = "minion",
  spell = function(g, me, t)
    g.enchant(t, { hooks = "ench:power_word_glory", player = g.ctrl(me) })
  end,
}
cards["ench:power_word_glory"] = {
  on = {
    attack = function(g, me, ev)
      if ev.attacker == me then
        g.heal(me, g.hero(g.ctrl(me)), 4)
      end
    end,
  },
}

-- Shadowfiend: whenever you draw a card, it costs (1) less (before its own "when you draw this").
cards.AT_014 = on_mine("draw", function(g, me, ev)
  g.enchant(ev.entity, { cost = -1 })
end)

-- Convert: a copy of an enemy minion into your hand (the card, without its enchantments).
cards.AT_015 = {
  target = "enemy_minion",
  spell = function(g, me, t)
    g.add_to_hand(g.ctrl(me), g.card(t))
  end,
}

-- Confuse: swap the Attack and Health of all minions (a 0-Attack minion dies).
cards.AT_016 = {
  spell = function(g, me)
    local ms = g.all_minions()
    local was = {}
    for i, m in ipairs(ms) do
      was[i] = { g.atk(m), g.health(m) }
    end
    for i, m in ipairs(ms) do
      g.set_stats(m, was[i][2], was[i][1])
    end
  end,
}

-- Confessor Paletress: Inspire: a random Legendary minion (any class).
cards.AT_018 = inspire(function(g, me)
  local c = random_card(g, function(i)
    return i.type == "MINION" and i.rarity == "LEGENDARY"
  end)
  if c then
    g.summon(g.ctrl(me), c)
  end
end)

-- Flash Heal: restore 5 Health.
cards.AT_055 = {
  target = "any",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, 5))
  end,
}

-- "If you're holding a Dragon, +1 Attack and Taunt" (Wyrmrest Agent, Twilight Guardian).
local dragon_guard = {
  glow = holding_dragon,
  battlecry = function(g, me)
    if holding_dragon(g, me) then
      g.buff(me, 1, 0)
      g.give_tag(me, "TAUNT")
    end
  end,
}
cards.AT_116 = dragon_guard
cards.AT_017 = dragon_guard

-- --- Rogue -------------------------------------------------------------------------------------

-- Shado-Pan Rider: Combo: +3 Attack.
cards.AT_028 = {
  combo = function(g, me)
    g.buff(me, 3, 0)
  end,
}

-- Buccaneer: whenever you equip a weapon (a Hero Power's dagger too), it gets +1 Attack.
cards.AT_029 = on_mine("equip", function(g, me, ev)
  g.buff(ev.entity, 1, 0)
end)

-- Undercity Valiant: Combo: 1 damage.
cards.AT_030 = {
  combo_target = "any",
  combo = function(g, me, t)
    g.damage(me, t, 1)
  end,
}

-- Cutpurse: whenever it attacks a hero (the one it really hit), The Coin into your hand.
cards.AT_031 = {
  on = {
    after_attack = function(g, me, ev)
      if ev.attacker == me and g.is_champion(ev.defender) then
        g.add_to_hand(g.ctrl(me), "GAME_005")
      end
    end,
  },
}

-- Shady Dealer: if you have a Pirate, +1/+1.
local function have_pirate(g, me)
  return have(g, me, race_is(g, "PIRATE"))
end
cards.AT_032 = {
  glow = have_pirate,
  battlecry = function(g, me)
    if have_pirate(g, me) then
      g.buff(me, 1, 1)
    end
  end,
}

-- Burgle: 2 random class cards of your opponent's class (against a hero without one: two Coins).
cards.AT_033 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    local class = g.class(g.hero(g.enemy(me)))
    local pool = collectible(g, function(i)
      return i.class == class
    end)
    for _ = 1, 2 do
      g.add_to_hand(p, (class ~= "" and class ~= "NEUTRAL" and g.pick(pool)) or "GAME_005")
    end
  end,
}

-- Poisoned Blade: your Hero Power gives it +1 Attack instead of replacing it (any power: in 2015 every use).
cards.AT_034 = inspire(function(g, me)
  g.buff(me, 1, 0)
end)

-- Beneath the Grounds: three Ambushes into your opponent's deck.
cards.AT_035 = {
  spell = function(g, me)
    for _ = 1, 3 do
      g.add_to_deck(g.enemy(me), "AT_035t")
    end
  end,
}

-- Ambush!: when drawn, a 4/4 Nerubian for its holder's opponent; its holder draws a card (burned: nothing).
cards.AT_035t = {
  hand = {
    draw = function(g, me, ev)
      if ev.entity == me then
        local p = g.ctrl(me)
        g.remove(me, "GRAVEYARD")
        g.summon(g.opponent(p), "AT_036t")
        g.draw(p)
      end
    end,
  },
}

-- Anub'arak: Deathrattle: it returns to your hand, then a 4/4 Nerubian where it stood.
cards.AT_036 = {
  deathrattle = function(g, me)
    local p = g.ctrl(me)
    g.add_to_hand(p, "AT_036")
    local pos = g.died_pos(me)
    g.summon(p, "AT_036t", pos >= 0 and pos or nil)
  end,
}

-- --- Shaman ------------------------------------------------------------------------------------

-- Tuskarr Totemic: ANY random Totem (2015: the collectible ones too, until patch 6.1.0 of 2016).
local BASIC_TOTEMS = { "VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009" }
cards.AT_046 = {
  battlecry = function(g, me)
    local pool = collectible(g, minion_of_race("TOTEM"))
    for _, t in ipairs(BASIC_TOTEMS) do
      pool[#pool + 1] = t
    end
    g.summon_right(me, g.pick(pool))
  end,
}

-- Draenei Totemcarver: +1/+1 for each friendly Totem.
cards.AT_047 = {
  battlecry = function(g, me)
    local n = list.count(g.others(me), race_is(g, "TOTEM"))
    g.buff(me, n, n)
  end,
}

-- Healing Wave: restore 7 Health; Joust: if yours costs more, 14 instead.
cards.AT_048 = {
  target = "any",
  spell = function(g, me, t)
    g.heal(me, t, g.heal_amt(me, joust(g, me) and 14 or 7))
  end,
}

-- Thunder Bluff Valiant: Inspire: your Totems +2 Attack.
cards.AT_049 = inspire(function(g, me)
  for _, m in ipairs(g.minions(g.ctrl(me))) do
    if g.race(m) == "TOTEM" then
      g.buff(m, 2, 0)
    end
  end
end)

-- Charged Hammer: Deathrattle: your Hero Power becomes Lightning Jolt (2 damage).
cards.AT_050 = {
  deathrattle = function(g, me)
    g.set_power(g.ctrl(me), "AT_050t")
  end,
}

-- Elemental Destruction: 4-5 damage to each minion, one after another in play order, each hit's triggers resolving
-- before the next (Overload: (5) is its data).
cards.AT_051 = {
  spell = function(g, me)
    for _, m in ipairs(g.all_minions()) do
      if g.zone(m) == "PLAY" then
        g.damage(me, m, g.spell_dmg(me, g.random(4, 5)))
        g.resolve()
      end
    end
  end,
}

-- Ancestral Knowledge: draw 2 cards (Overload: (2)).
cards.AT_053 = {
  spell = function(g, me)
    g.draw(g.ctrl(me), 2)
  end,
}

-- The Mistcaller: the minions in your hand +1/+1, and (as it worked until 2016, the text notwithstanding) every
-- minion you draw later this game too; the minions in the deck are not touched.
cards.AT_054 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _, c in ipairs(g.hand(p)) do
      if g.type(c) == "MINION" then
        g.buff(c, 1, 1)
      end
    end
    g.enchant(g.hero(p), { hooks = "ench:mistcaller", player = p })
  end,
}
cards["ench:mistcaller"] = on_mine("draw", function(g, me, ev)
  if g.type(ev.entity) == "MINION" then
    g.buff(ev.entity, 1, 1)
  end
end)

-- --- Warlock -----------------------------------------------------------------------------------

-- Dreadsteed: Deathrattle: a new Dreadsteed where it stood (at once, as in 2015).
cards.AT_019 = {
  deathrattle = function(g, me)
    local pos = g.died_pos(me)
    g.summon(g.ctrl(me), "AT_019", pos >= 0 and pos or nil)
  end,
}

-- Tiny Knight of Evil: whenever you discard a card, +1/+1.
cards.AT_021 = on_mine("discard", function(g, me)
  g.buff(me, 1, 1)
end)

-- Fist of Jaraxxus: played or discarded, 4 damage to a random enemy (Spell Damage counts both ways).
local function fist(g, me)
  g.damage(me, random_enemy(g, me), g.spell_dmg(me, 4))
end
cards.AT_022 = {
  spell = fist,
  hand = {
    discard = function(g, me, ev)
      if ev.entity == me then
        fist(g, me)
      end
    end,
  },
}

-- Void Crusher: Inspire: destroy a random minion of each player (it may be itself).
cards.AT_023 = inspire(function(g, me)
  local p = g.ctrl(me)
  for _, q in ipairs({ g.opponent(p), p }) do
    g.destroy(g.random_alive(g.minions(q)))
  end
end)

-- Demonfuse: a Demon +3/+3; your opponent gains a Mana Crystal.
cards.AT_024 = {
  target = { base = "minion", filter = function(g, me, t)
    return g.race(t) == "DEMON"
  end },
  spell = function(g, me, t)
    g.buff(t, 3, 3)
    g.gain_mana(g.enemy(me), 1)
  end,
}

-- Dark Bargain: only with 2 enemy minions (until 2019); destroy 2 random ones, then discard 2 random cards.
cards.AT_025 = {
  can_play = function(g, me)
    return #g.minions(g.enemy(me)) >= 2
  end,
  spell = function(g, me)
    local foes = g.minions(g.enemy(me))
    g.shuffle(foes)
    g.destroy(foes[1])
    g.destroy(foes[2])
    g.discard_random(g.ctrl(me), 2)
  end,
}

-- Wrathguard: whenever it takes damage, as much to your hero (even more than its Health).
cards.AT_026 = {
  on = {
    damage = function(g, me, ev)
      if ev.target == me and ev.amount > 0 then
        g.damage(me, g.hero(g.ctrl(me)), ev.amount)
      end
    end,
  },
}

-- Wilfred Fizzlebang: a card you draw from your Hero Power (its draw carries the power as `by_id`) costs (0).
cards.AT_027 = on_mine("draw", function(g, me, ev)
  if ev.by_id == g.power(g.ctrl(me)) and g.zone(ev.entity) == "HAND" then
    g.enchant(ev.entity, { cost = -g.cost(ev.entity) })
  end
end)

-- --- Warrior -----------------------------------------------------------------------------------

-- Bash: 3 damage, 3 Armor.
cards.AT_064 = {
  target = "any",
  spell = function(g, me, t)
    g.damage(me, t, g.spell_dmg(me, 3))
    g.gain_armor(g.ctrl(me), 3)
  end,
}

-- King's Defender: if you have a minion with Taunt, +1 Durability.
local function have_taunt(g, me)
  return have(g, me, function(m)
    return g.has(m, "TAUNT")
  end)
end
cards.AT_065 = {
  glow = have_taunt,
  battlecry = function(g, me)
    if have_taunt(g, me) then
      g.add_tag(me, "DURABILITY", 1)
    end
  end,
}

-- Orgrimmar Aspirant: Inspire: your weapon +1 Attack.
cards.AT_066 = inspire(function(g, me)
  g.buff(g.weapon(g.ctrl(me)), 1, 0)
end)

-- Magnataur Alpha: also damages the minions next to whomever he attacks (after the combat, left to right).
cards.AT_067 = {
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

-- Bolster: your Taunt minions +2/+2.
cards.AT_068 = {
  spell = function(g, me)
    for _, m in ipairs(g.minions(g.ctrl(me))) do
      if g.has(m, "TAUNT") then
        g.buff(m, 2, 2)
      end
    end
  end,
}

-- Sparring Partner: a minion gets Taunt.
cards.AT_069 = {
  target = "minion",
  battlecry = function(g, me, t)
    g.give_tag(t, "TAUNT")
  end,
}

-- Alexstrasza's Champion: if you're holding a Dragon, +1 Attack and Charge.
cards.AT_071 = {
  glow = holding_dragon,
  battlecry = function(g, me)
    if holding_dragon(g, me) then
      g.buff(me, 1, 0)
      g.give_tag(me, "CHARGE")
    end
  end,
}

-- Varian Wrynn: three times, the top card of your deck: a minion goes onto the battlefield (no draw), anything
-- else (or a minion with a full board) is drawn.
cards.AT_072 = {
  battlecry = function(g, me)
    local p = g.ctrl(me)
    for _ = 1, 3 do
      local d = g.deck(p)
      local top = d[#d]
      if top and g.type(top) == "MINION" and g.room(p) > 0 then
        g.summon_entity(top)
      else
        g.draw(p)
      end
    end
  end,
}

-- Sea Reaver: when you draw it, 1 damage to your minions.
cards.AT_130 = {
  hand = {
    draw = function(g, me, ev)
      if ev.entity == me then
        for _, m in ipairs(g.minions(g.ctrl(me))) do
          g.damage(me, m, 1)
        end
      end
    end,
  },
}

-- --- Neutral -----------------------------------------------------------------------------------

-- Skycap'n Kragg: costs (1) less for each friendly Pirate in play.
cards.AT_070 = {
  cost_mod = function(g, me)
    return -list.count(g.minions(g.ctrl(me)), race_is(g, "PIRATE"))
  end,
}

-- Garrison Commander: you can use your Hero Power twice a turn (copies do not add up).
cards.AT_080 = refresher(2)

-- Lowly Squire: Inspire: +1 Attack.
cards.AT_082 = inspire(function(g, me)
  g.buff(me, 1, 0)
end)

-- Dragonhawk Rider: Inspire: Windfury this turn (a Windfury it has already stays).
cards.AT_083 = inspire(function(g, me)
  if not g.has(me, "WINDFURY") then
    g.give_tag(me, "WINDFURY", true)
  end
end)

-- Lance Carrier: a friendly minion +2 Attack.
cards.AT_084 = {
  target = "friendly_minion",
  battlecry = function(g, me, t)
    g.buff(t, 2, 0)
  end,
}

-- Maiden of the Lake: your Hero Power costs (1).
cards.AT_085 = {
  cost_aura = function(g, me, card, cost)
    if g.type(card) == "POWER" and g.ctrl(card) == g.ctrl(me) then
      return 1
    end
    return cost
  end,
}

-- Saboteur: your opponent's Hero Power costs (5) more next turn.
cards.AT_086 = {
  battlecry = function(g, me)
    g.add_cost_mod(g.enemy(me), { kind = "power", delta = 5, ["until"] = "turn_end", turn = g.turn() + 1 })
  end,
}

-- Mogor's Champion: 50% chance to attack the wrong enemy (another enemy character, Taunt and Stealth ignored).
cards.AT_088 = {
  on = {
    attack = function(g, me, ev)
      if ev.attacker == me then
        local wrong = only(g.chars(g.enemy(me)), function(c)
          return c ~= ev.defender and g.health(c) > 0
        end)
        if #wrong > 0 and g.random(0, 1) == 1 then
          ev.defender = g.pick(wrong)
        end
      end
    end,
  },
}

-- Boneguard Lieutenant: Inspire: +1 Health.
cards.AT_089 = inspire(function(g, me)
  g.buff(me, 0, 1)
end)

-- Mukla's Champion: Inspire: your other minions +1/+1.
cards.AT_090 = inspire(function(g, me)
  for _, m in ipairs(g.others(me)) do
    g.buff(m, 1, 1)
  end
end)

-- Tournament Medic: Inspire: restore 2 Health to your hero.
cards.AT_091 = inspire(function(g, me)
  g.heal(me, g.hero(g.ctrl(me)), 2)
end)

-- Flame Juggler: 1 damage to a random enemy.
cards.AT_094 = {
  battlecry = function(g, me)
    g.damage(me, random_enemy(g, me), 1)
  end,
}

-- Clockwork Knight: a friendly Mech +1/+1.
cards.AT_096 = {
  target = { base = "friendly_minion", filter = function(g, me, t)
    return g.race(t) == "MECHANICAL"
  end },
  battlecry = function(g, me, t)
    g.buff(t, 1, 1)
  end,
}

-- Sideshow Spelleater: your Hero Power becomes a copy of your opponent's (any power, unused).
cards.AT_098 = {
  battlecry = function(g, me)
    g.set_power(g.ctrl(me), g.card(g.power(g.enemy(me))))
  end,
}

-- Kodorider: Inspire: a 3/5 War Kodo.
cards.AT_099 = inspire(function(g, me)
  g.summon(g.ctrl(me), "AT_099t")
end)

-- Silver Hand Regent: Inspire: a 1/1 Silver Hand Recruit.
cards.AT_100 = inspire(function(g, me)
  g.summon(g.ctrl(me), "VAN_CS2_101t")
end)

-- North Sea Kraken: 4 damage.
cards.AT_103 = {
  target = "any",
  battlecry = function(g, me, t)
    g.damage(me, t, 4)
  end,
}

-- Injured Kvaldir: 3 damage to itself.
cards.AT_105 = {
  battlecry = function(g, me)
    g.damage(me, me, 3)
  end,
}

-- Light's Champion: Silence a Demon.
cards.AT_106 = {
  target = { base = "minion", filter = function(g, me, t)
    return g.race(t) == "DEMON"
  end },
  battlecry = function(g, me, t)
    g.silence(t)
  end,
}

-- Armored Warhorse: Joust: if yours costs more, Charge.
cards.AT_108 = {
  battlecry = function(g, me)
    if joust(g, me) then
      g.give_tag(me, "CHARGE")
    end
  end,
}

-- Argent Watchman: can't attack; Inspire: it can attack as normal this turn.
cards.AT_109 = {
  on = {
    hero_power = function(g, me, ev)
      if g.mine(me, ev) then
        g.erase_tag(me, "CANT_ATTACK")
      end
    end,
    turn_end = function(g, me, ev)
      if g.mine(me, ev) then
        g.give_tag(me, "CANT_ATTACK")
      end
    end,
  },
}

-- Coliseum Manager: Inspire: it returns to your hand.
cards.AT_110 = inspire(function(g, me)
  g.return_to_hand(me)
end)

-- Refreshment Vendor: restore 4 Health to each hero (yours first).
cards.AT_111 = {
  battlecry = function(g, me)
    g.heal(me, g.hero(g.ctrl(me)), 4)
    g.heal(me, g.hero(g.enemy(me)), 4)
  end,
}

-- Master Jouster: Joust: if yours costs more, Taunt and Divine Shield.
cards.AT_112 = {
  battlecry = function(g, me)
    if joust(g, me) then
      g.give_tag(me, "TAUNT")
      g.give_tag(me, "DIVINE_SHIELD")
    end
  end,
}

-- Recruiter: Inspire: a 2/2 Squire into your hand.
cards.AT_113 = inspire(function(g, me)
  g.add_to_hand(g.ctrl(me), "VAN_CS2_152")
end)

-- Fencing Coach: the next time you use your Hero Power, it costs (2) less (on any later turn too).
cards.AT_115 = {
  battlecry = function(g, me)
    g.add_cost_mod(g.ctrl(me), { kind = "power", delta = -2, ["until"] = "use", lasting = true })
  end,
}

-- Master of Ceremonies: if you have a minion with Spell Damage, +2/+2 (once).
local function have_spell_damage(g, me)
  return have(g, me, function(m)
    return g.tag(m, "SPELLPOWER") > 0
  end)
end
cards.AT_117 = {
  glow = have_spell_damage,
  battlecry = function(g, me)
    if have_spell_damage(g, me) then
      g.buff(me, 2, 2)
    end
  end,
}

-- Grand Crusader: a random Paladin card into your hand.
cards.AT_118 = {
  battlecry = function(g, me)
    local c = random_card(g, function(i)
      return i.class == "PALADIN"
    end)
    if c then
      g.add_to_hand(g.ctrl(me), c)
    end
  end,
}

-- Kvaldir Raider: Inspire: +2/+2.
cards.AT_119 = inspire(function(g, me)
  g.buff(me, 2, 2)
end)

-- Frost Giant: costs (1) less for each time you used your Hero Power this game (POWERS_USED, any power).
cards.AT_120 = {
  cost_mod = function(g, me)
    return -g.tag(g.hero(g.ctrl(me)), "POWERS_USED")
  end,
}

-- Crowd Favorite: whenever you play a card with Battlecry, +1/+1 (before the Battlecry).
cards.AT_121 = on_mine("play", function(g, me, ev)
  if ev.entity ~= me and list.any(g.info(ev.card).keywords, function(k)
    return k == "BATTLECRY"
  end) then
    g.buff(me, 1, 1)
  end
end)

-- Gormok the Impaler: if you have at least 4 other minions, 4 damage (a target only then).
local function gormok_ready(g, me)
  return list.count(g.minions(g.ctrl(me)), function(m)
    return m ~= me
  end) >= 4
end
cards.AT_122 = {
  glow = gormok_ready,
  target = { base = "any", when = gormok_ready },
  battlecry = function(g, me, t)
    if t then
      g.damage(me, t, 4)
    end
  end,
}

-- Chillmaw: Taunt; Deathrattle: if you're holding a Dragon, 3 damage to all minions (it glows in the hand then).
cards.AT_123 = {
  glow = holding_dragon,
  deathrattle = function(g, me)
    if holding_dragon(g, me) then
      for _, m in ipairs(g.all_minions()) do
        g.damage(me, m, 3)
      end
    end
  end,
}

-- Bolf Ramshield: whenever your hero would take damage, he takes it instead (all of it, before Armor; even at 0
-- Health until the deaths are checked).
cards.AT_124 = {
  now = {
    predamage = function(g, me, ev)
      if ev.target == g.hero(g.ctrl(me)) and ev.amount > 0 and g.zone(me) == "PLAY" then
        local n = ev.amount
        ev.amount = 0
        g.damage(ev.source, me, n)
      end
    end,
  },
}

-- Nexus-Champion Saraad: Inspire: a random spell (any class) into your hand.
cards.AT_127 = inspire(function(g, me)
  local c = random_card(g, function(i)
    return i.type == "SPELL"
  end)
  if c then
    g.add_to_hand(g.ctrl(me), c)
  end
end)

-- The Skeleton Knight: Deathrattle: Joust: if yours costs more, it returns to your hand.
cards.AT_128 = {
  deathrattle = function(g, me)
    if joust(g, me) then
      g.add_to_hand(g.ctrl(me), "AT_128")
    end
  end,
}

-- Fjola Lightbane: whenever you target her with a spell, Divine Shield.
cards.AT_129 = targeted_by_my_spell(function(g, me)
  g.give_tag(me, "DIVINE_SHIELD")
end)

-- Eydis Darkbane: whenever you target her with a spell, 3 damage to a random enemy.
cards.AT_131 = targeted_by_my_spell(function(g, me)
  g.damage(me, random_enemy(g, me), 3)
end)

-- Gadgetzan Jouster: Joust: if yours costs more, +1/+1.
cards.AT_133 = {
  battlecry = function(g, me)
    if joust(g, me) then
      g.buff(me, 1, 1)
    end
  end,
}

-- --- Older cards as on 2015-08-24 --------------------------------------------------------------

-- Resurrect (patch 3.0.0.9786): only once a friendly minion died this game; a random one of them (each death one
-- chance).
local function friendly_dead(g, me)
  return only(g.graveyard(g.ctrl(me)), function(e)
    return g.died_pos(e) >= 0 and g.type(e) == "MINION"
  end)
end
cards.BRM_017 = {
  can_play = function(g, me)
    return #friendly_dead(g, me) > 0
  end,
  spell = function(g, me)
    local e = g.pick(friendly_dead(g, me))
    if e then
      g.summon(g.ctrl(me), g.card(e))
    end
  end,
}

-- Dagger Mastery: equip a 1/2 Dagger, unless Poisoned Blade is in your hands (it stays).
cards.VAN_HERO_03bp = {
  hero_power = function(g, me)
    if not poisoned_blade(g, me) then
      g.equip(g.ctrl(me), "VAN_CS2_082")
    end
  end,
}

return cards
