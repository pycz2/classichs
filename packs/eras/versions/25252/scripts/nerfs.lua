-- Patch 11.1.1.24589 of 2018-05-22 on (packs/eras/versions/24589, 24769, 25252): the nerfed cards whose hooks changed
-- (as packs/boom/scripts/boom.lua has them); the costs are in patch.json.
local cards = {}

-- Dark Pact: destroy a friendly minion, restore 4 Health to your hero (8 until this patch).
cards.LOOT_017 = {
  target = "friendly_minion",
  spell = function(g, me, t)
    g.destroy(t)
    g.heal(me, g.hero(g.ctrl(me)), g.heal_amt(me, 4))
  end,
}

-- Crystal Core: "for the rest of the game, your minions are 4/4" (5/5 until this patch): the minions in play and in
-- the hand now, the later ones by the player hooks' core() (this version's gil.lua).
cards.UNG_067t1 = {
  spell = function(g, me)
    local p = g.ctrl(me)
    g.add_count(p, "CRYSTAL_CORE")
    for _, zone in ipairs({ g.minions(p), g.hand(p) }) do
      for _, e in ipairs(zone) do
        if g.is_minion(e) and not g.has(e, "CORED") then
          g.enchant(e, { set_atk = 4, set_hp = 4, base = true })
          g.set_tag(e, "CORED", true)
        end
      end
    end
  end,
}

return cards
