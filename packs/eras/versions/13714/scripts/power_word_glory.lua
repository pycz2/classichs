-- Power Word: Glory (patch 4.1.0.10956, 2015-12-04): a minion's enchantments keep their controller when the minion
-- changes sides, so the minion's attacks heal the hero of the player who cast it (and that player's Auchenai
-- Soulpriest turns it into damage), not its new controller's. One hook set per player: each enchantment's hook runs
-- once, and it must know whose it is.
local cards = {}

local function glory(p)
  return {
    on = {
      attack = function(g, me, ev)
        if ev.attacker == me then
          g.heal(g.hero(p), g.hero(p), 4)
        end
      end,
    },
  }
end
cards["ench:power_word_glory_0"] = glory(0)
cards["ench:power_word_glory_1"] = glory(1)

cards.AT_013 = {
  target = "minion",
  spell = function(g, me, t)
    local p = g.ctrl(me)
    g.enchant(t, { hooks = p == 0 and "ench:power_word_glory_0" or "ench:power_word_glory_1", player = p })
  end,
}

return cards
