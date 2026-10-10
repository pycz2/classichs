extends RefCounted
## Hero powers and The Coin. Upgraded powers (*bp2, VAN_CS2_102_H3, VAN_HERO_02bp2)
## and Demon Hunter powers (VAN_HERO_10*) are unreachable in Classic: no hooks.

const BASIC_TOTEMS := ["VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009"]


static func _board_has_room(g, me) -> bool:
	return g.players[me.controller].board.size() < GameState.MAX_BOARD


static func _missing_totems(g, me) -> Array:
	var present: Array = g.players[me.controller].board.map(func(m): return m.card_id)
	return BASIC_TOTEMS.filter(func(id): return not present.has(id))


static func register(r: Dictionary) -> void:
	r["GAME_005"] = {  # The Coin
		"spell": func(g, me, _t):
			var p: Player = g.players[me.controller]
			p.mana = mini(GameState.MAX_MANA, p.mana + 1),
	}
	r["VAN_HERO_01bp"] = {  # Armor Up!
		"hero_power": func(g, me, _t): g.gain_armor(me.controller, 2),
	}
	r["VAN_HERO_02bp"] = {  # Totemic Call
		"can_play": func(g, me): return _board_has_room(g, me) and not _missing_totems(g, me).is_empty(),
		"hero_power": func(g, me, _t): g.summon(me.controller, g.random_choice(_missing_totems(g, me))),
	}
	r["VAN_NEW1_009"] = {  # Healing Totem (from Totemic Call)
		"on": {"turn_end": func(g, me, ev):
			if ev.player == me.controller:
				for m in g.minions(me.controller):
					g.heal(me, m, g.heal_amt(me, 1))},
	}
	r["VAN_HERO_03bp"] = {  # Dagger Mastery
		"hero_power": func(g, me, _t): g.equip(me.controller, "VAN_CS2_082"),
	}
	r["VAN_HERO_04bp"] = {  # Reinforce
		"can_play": _board_has_room,
		"hero_power": func(g, me, _t): g.summon(me.controller, "VAN_CS2_101t"),
	}
	r["VAN_HERO_05bp"] = {  # Steady Shot
		"hero_power": func(g, me, _t):
			g.damage(me, g.players[g.opponent(me.controller)].hero, g.hp_dmg(me, 2)),
	}
	r["VAN_HERO_06bp"] = {  # Shapeshift
		"hero_power": func(g, me, _t):
			g.buff(g.players[me.controller].hero, 1, 0, true)
			g.gain_armor(me.controller, 1),
	}
	r["VAN_HERO_07bp"] = {  # Life Tap. 2014: damage first, then draw (as Fireplace).
		"hero_power": func(g, me, _t):
			g.damage(me, g.players[me.controller].hero, g.hp_dmg(me, 2))
			g.draw(me.controller),
	}
	r["VAN_HERO_08bp"] = {  # Fireblast
		"target": T.ANY,
		"hero_power": func(g, me, t): g.damage(me, t, g.hp_dmg(me, 1)),
	}
	r["VAN_HERO_09bp"] = {  # Lesser Heal
		"target": T.ANY,
		"hero_power": func(g, me, t): g.heal(me, t, g.heal_amt(me, 2)),
	}
	r["VAN_EX1_tk33"] = {  # INFERNO! (Lord Jaraxxus)
		"can_play": _board_has_room,
		"hero_power": func(g, me, _t): g.summon(me.controller, "VAN_EX1_tk34"),
	}
	r["EX1_625t"] = {  # Mind Spike (Shadowform)
		"target": T.ANY,
		"hero_power": func(g, me, t): g.damage(me, t, g.hp_dmg(me, 2)),
	}
	r["EX1_625t2"] = {  # Mind Shatter (Shadowform twice)
		"target": T.ANY,
		"hero_power": func(g, me, t): g.damage(me, t, g.hp_dmg(me, 3)),
	}
