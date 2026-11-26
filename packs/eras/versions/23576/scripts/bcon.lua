-- The BlizzCon 2017 Arena cards (BCON_*, 10.4.0.23576): drafted in the Arena from 2018-03-11 to 04-09 only
-- (formats.json `extra`). Not collectible; their data is in patch.json `add`.
local cards = {}

local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }

-- Discover (2017): three different cards, the class's four times as likely as the neutral ones (packs/loot's).
local function discover_minion(g, me)
  local p = g.ctrl(me)
  local cls = g.class(g.hero(p))
  if not list.any(CLASSES, function(c)
    return c == cls
  end) then
    cls = CLASSES[g.random(1, #CLASSES)]
  end
  local left = {}
  for _, c in ipairs(g.collectible()) do
    local i = g.info(c)
    if i.type == "MINION" then
      if i.class == cls or (i.classes and list.any(i.classes, function(x)
        return x == cls
      end)) then
        left[#left + 1] = { c, 4 }
      elseif i.class == "NEUTRAL" and not i.classes then
        left[#left + 1] = { c, 1 }
      end
    end
  end
  local opts = {}
  for _ = 1, 3 do
    local total = list.sum(left, function(x)
      return x[2]
    end)
    if total <= 0 then
      break
    end
    local r = g.random(1, total)
    for i, x in ipairs(left) do
      r = r - x[2]
      if r <= 0 then
        opts[#opts + 1] = g.create(p, x[1])
        table.remove(left, i)
        break
      end
    end
  end
  if #opts > 0 then
    g.request_choice(me, opts)
  end
end

-- Steamwheedle Sniper on the board, or Deadeye cast this game: the Hunter's power may target minions.
local function deadeye(g, me)
  local p = g.ctrl(me)
  return g.count(p, "DEADEYE") > 0 or list.any(g.minions(p), function(m)
    return g.card(m) == "GVG_087" and not g.silenced(m)
  end)
end

local function shot(n)
  return {
    target = { base = "any", when = deadeye, filter = function(g, me, t)
      return g.is_minion(t) or t == g.hero(g.enemy(me))
    end },
    hero_power = function(g, me, t)
      g.damage(me, t or g.hero(g.enemy(me)), g.hp_dmg(me, n))
    end,
  }
end

-- Steady Shot and Ballista Shot (packs/gvg's, packs/tgt's) with Deadeye's mark too.
cards.VAN_HERO_05bp = shot(2)
cards.AT_132_HUNTER = shot(3)

-- Deadeye: for the rest of the game, your Hero Power can target minions (a count, kept by a new champion).
cards.BCON_001 = {
  spell = function(g, me)
    g.add_count(g.ctrl(me), "DEADEYE")
  end,
}

-- Polymorph: ???: choose a minion; Discover a new minion to transform it into.
cards.BCON_004 = {
  target = "minion",
  spell = function(g, me, t)
    g.set_tag(me, "POLY_TARGET", t)
    discover_minion(g, me)
  end,
  on_choose = function(g, me, option)
    local t = g.tag(me, "POLY_TARGET")
    if g.zone(t) == "PLAY" then
      g.transform(t, g.card(option))
    end
  end,
}

-- Nature's Champion: return a friendly minion to your hand and give it +5/+5.
cards.BCON_008 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    local c = g.return_to_hand(t)
    if c then
      g.buff(c, 5, 5)
    end
  end,
}

-- Hand of Salvation: Secret: when your second minion dies in a turn, return it to life.
cards.BCON_012 = {
  secret = {
    event = "death",
    cond = function(g, me, ev)
      if not (ev.minion and g.mine(me, ev)) then
        return false
      end
      local n = 0
      for _, e in ipairs(g.graveyard(g.ctrl(me))) do
        if g.is_minion(e) and g.died_pos(e) >= 0 and g.tag(e, "DIED_TURN") == g.turn() then
          n = n + 1
          if e == ev.entity then
            return n == 2
          end
        end
      end
      return false
    end,
    effect = function(g, me, ev)
      g.summon(g.ctrl(me), ev.card, g.died_pos(ev.entity))
    end,
  },
}

-- Generous Spirit: give a friendly minion to your opponent and draw 3 cards.
cards.BCON_015 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    local p = g.ctrl(me)
    g.take_control(t, g.opponent(p))
    g.draw(p, 3)
  end,
}

-- Smoke Bomb: give a minion Stealth until your next turn (Conceal's hooks take it away); draw a card.
cards.BCON_016 = {
  target = "minion",
  spell = function(g, me, t)
    local p = g.ctrl(me)
    if not g.has(t, "STEALTH") then
      g.give_tag(t, "STEALTH")
      g.enchant(t, { hooks = "ench:conceal", player = p })
    end
    g.draw(p)
  end,
}

-- Crackling Doom: 12 damage to all minions (Overload: (10) is data).
cards.BCON_021 = {
  spell = function(g, me)
    local n = g.spell_dmg(me, 12)
    for _, m in ipairs(g.all_minions()) do
      g.damage(me, m, n)
    end
  end,
}

-- Bottled Madness: replace your hand with random Demons.
cards.BCON_024 = {
  spell = function(g, me)
    local demons = {}
    for _, c in ipairs(g.collectible()) do
      local i = g.info(c)
      if i.type == "MINION" and i.race == "DEMON" then
        demons[#demons + 1] = c
      end
    end
    for _, e in ipairs(g.hand(g.ctrl(me))) do
      g.transform(e, g.pick(demons))
    end
  end,
}

-- Blazing Longsword: also damages the minions next to whomever your hero attacks (as the attack begins).
cards.BCON_026 = {
  on = {
    attack = function(g, me, ev)
      local hero = g.hero(g.ctrl(me))
      if ev.attacker == hero and g.is_minion(ev.defender) then
        local n = g.attack(hero)
        for _, m in ipairs(g.adjacent(ev.defender)) do
          g.damage(hero, m, n)
        end
      end
    end,
  },
}

return cards
