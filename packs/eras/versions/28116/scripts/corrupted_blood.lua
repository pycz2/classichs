-- Corrupted Blood before patch 13.2.0.28855 ("Corrupted Blood no longer benefits from Spell Damage"): its 3 damage
-- takes its player's Spell Damage. Otherwise trl_n.lua's TRL_541t: Casts When Drawn, the player draws on, every
-- Corrupted Blood drawn in a row casts too, then two copies per Blood of the row go into the deck.
local cards = {}

local BLOOD = "TRL_541t"

local function over(g)
  return g.health(g.hero(0)) <= 0 or g.health(g.hero(1)) <= 0
end

local function blood(g, me)
  local p = g.ctrl(me)
  local n = 1
  g.damage(me, g.hero(p), g.spell_dmg(me, 3))
  while not over(g) do
    local d = g.deck(p)
    local top = d[#d]
    if not top or g.card(top) ~= BLOOD then
      g.draw(p)
      break
    end
    g.remove(top, "GRAVEYARD")
    g.log({ type = "cast_when_drawn", player = p, entity = top, card = BLOOD })
    g.damage(top, g.hero(p), g.spell_dmg(top, 3))
    n = n + 1
  end
  for _ = 1, 2 * n do
    g.add_to_deck(p, BLOOD)
  end
end

cards.TRL_541t = {
  spell = blood,
  hand = {
    draw = function(g, me, ev)
      if ev.entity == me then
        local p = g.ctrl(me)
        g.remove(me, "GRAVEYARD")
        g.log({ type = "cast_when_drawn", player = p, entity = me, card = g.card(me) })
        blood(g, me)
      end
    end,
  },
}

return cards
