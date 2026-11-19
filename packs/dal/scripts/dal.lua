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

local CONTRACTS = { "DAL_366t1", "DAL_366t2", "DAL_366t3", "DAL_366t4" }

-- The player hooks of Rise of Shadows (rules.json `player_hooks`: after Rastakhan's Rumble's `player:trl`), `me` each
-- player's champion: the counts no card in play keeps.
-- RESTORED: the Health this player's cards restored this game (Crystal Stag). RESOLVED: the spells of this player that
-- resolved this turn (Kalecgos: before patch 14.2 a countered first spell left the next one free). CAST_TURN on a spell:
-- the turn it resolved (Archmage Vargoth recasts one of this turn's, cast before he came too; a countered one never).
cards["player:dal"] = {
  on = {
    -- a countered spell still has its after_spell event in this pack (behaviour.countered_no_after_spell false since
    -- Kobolds & Catacombs): its play event, heard after the Secrets, says it was countered
    play = function(g, me, ev)
      if ev.player == g.ctrl(me) and ev.kind == "spell" and ev.countered then
        g.set_tag(ev.entity, "COUNTERED", true)
      end
    end,
    after_spell = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.player == p and not g.has(ev.entity, "COUNTERED") then
        g.set_tag(ev.entity, "CAST_TURN", g.turn())
        g.add_count(p, "RESOLVED")
      end
    end,
    heal = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.amount > 0 and ev.source and ev.source > 0 and g.ctrl(ev.source) == p then
        g.add_count(p, "RESTORED", ev.amount)
      end
    end,
    turn_start = function(g, me, ev)
      local p = g.ctrl(me)
      if ev.player == p then
        g.add_count(p, "RESOLVED", -g.count(p, "RESOLVED"))
      end
    end,
    -- an Unidentified Contract in the opening hand is identified when the game starts (as K&C's Unidentified items)
    game_start = function(g, me)
      for _, e in ipairs(g.hand(g.ctrl(me))) do
        if g.card(e) == "DAL_366" then
          local n = g.transform(e, CONTRACTS[g.random(1, #CONTRACTS)])
          if n then
            g.set_tag(n, "STARTED_IN_DECK", true)
          end
        end
      end
    end,
  },
}

return cards
