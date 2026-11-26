-- Power Word: Glory before patch 4.1.0.10956: the minion's attacks heal the hero of the player who cast it ("your
-- hero": also when cast on an enemy minion), but when the minion changes sides the enchantment goes over to its new
-- controller. One hook set per caster and per side the minion was on when cast: each enchantment's hook runs once,
-- and it must know whose it is.
local cards = {}

local function glory(caster, side)
  return {
    on = {
      attack = function(g, me, ev)
        if ev.attacker == me then
          local p = g.ctrl(me) ~= side and g.ctrl(me) or caster
          g.heal(g.hero(p), g.hero(p), 4)
        end
      end,
    },
  }
end
cards["ench:power_word_glory_00"] = glory(0, 0)
cards["ench:power_word_glory_01"] = glory(0, 1)
cards["ench:power_word_glory_10"] = glory(1, 0)
cards["ench:power_word_glory_11"] = glory(1, 1)

cards.AT_013 = {
  target = "minion",
  spell = function(g, me, t)
    local p, s = g.ctrl(me), g.ctrl(t)
    local name = p == 0 and (s == 0 and "ench:power_word_glory_00" or "ench:power_word_glory_01")
      or (s == 0 and "ench:power_word_glory_10" or "ench:power_word_glory_11")
    g.enchant(t, { hooks = name, player = p })
  end,
}

return cards
