-- Rise of Shadows (April 2019): the older cards that changed between Rastakhan's Rumble and the release (patches
-- 13.0.3.28329 of 2018-12-19, 13.2.0.28855 of 2019-02-05 and 14.0.0.29933/30103 of April 2019; hearthstone.wiki.gg).
-- Their costs are in cards.patch.json, their texts in cards.texts.json; the class and neutral cards of the set are in
-- dal_*.lua.
local cards = {}

-- Saronite Chain Gang (13.0.3): Battlecry: summon another Saronite Chain Gang (a fresh 2/3, not a copy of this one).
cards.ICC_466 = {
  battlecry = function(g, me)
    g.summon_right(me, g.card(me))
  end,
}

-- Leeching Poison (13.0.3): 1 mana, your weapon has Lifesteal this turn.
cards.ICC_221 = {
  can_play = function(g, me)
    return g.weapon(g.ctrl(me)) ~= nil
  end,
  spell = function(g, me)
    g.give_tag(g.weapon(g.ctrl(me)), "LIFESTEAL", true)
  end,
}

return cards
