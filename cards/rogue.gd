extends RefCounted
## Rogue cards and their tokens.


static func _weapon(g, me) -> Entity:
	return g.players[me.controller].weapon


static func _has_weapon(g, me) -> bool:
	return _weapon(g, me) != null


static func register(r: Dictionary) -> void:
	r["VAN_CS2_072"] = {  # Backstab
		"target": [T.MINION, func(_g, _me, t): return t.damage == 0],
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 2)),
	}
	r["VAN_EX1_145"] = {  # Preparation
		"spell": func(g, me, _t): g.add_cost_mod(me.controller, {"kind": "spell", "delta": -3, "until": "use"}),
	}
	r["VAN_EX1_144"] = {  # Shadowstep
		"target": T.FRIENDLY_MINION,
		"spell": func(g, _me, t):
			var n: Entity = g.return_to_hand(t)
			if n:
				n.add_enchant({"cost": -2}),
	}
	r["VAN_CS2_073"] = {  # Cold Blood
		"target": T.MINION,
		"spell": func(g, _me, t): g.buff(t, 2, 0),
		"combo": func(g, _me, t): g.buff(t, 4, 0),
	}
	r["VAN_EX1_128"] = {  # Conceal: Stealth until your next turn.
		"spell": func(g, me, _t):
			for m in g.minions(me.controller):
				m.give_tag("STEALTH")
				m.add_enchant({"hooks": "ench:conceal", "player": me.controller}),
	}
	r["ench:conceal"] = {
		"on": {"turn_start": func(_g, me, ev):
			for e in me.enchantments.duplicate():
				if e.get("hooks") == "ench:conceal" and ev.player == e.player:
					me.enchantments.erase(e)
					me.tags.erase("STEALTH")},
	}
	r["VAN_CS2_074"] = {  # Deadly Poison
		"can_play": _has_weapon,
		"spell": func(g, me, _t): g.buff(_weapon(g, me), 2, 0),
	}
	r["VAN_CS2_075"] = {  # Sinister Strike
		"spell": func(g, me, _t): g.damage(me, g.hero(g.opponent(me.controller)), g.spell_dmg(me, 3)),
	}
	r["VAN_EX1_126"] = {  # Betrayal
		"target": T.ENEMY_MINION,
		"spell": func(g, _me, t):
			for m in g.adjacent(t):
				g.damage(t, m, t.atk()),
	}
	r["VAN_CS2_233"] = {  # Blade Flurry
		"can_play": _has_weapon,
		"spell": func(g, me, _t):
			var w: Entity = _weapon(g, me)
			var n: int = g.spell_dmg(me, w.atk())
			g.destroy(w)
			for c in g.chars(g.opponent(me.controller)):
				g.damage(me, c, n),
	}
	r["VAN_EX1_131"] = {  # Defias Ringleader
		"combo": func(g, me, _t): g.summon_right(me, "EX1_131t"),
	}
	r["VAN_EX1_124"] = {  # Eviscerate
		"target": T.ANY,
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 2)),
		"combo": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 4)),
	}
	r["VAN_EX1_522"] = {  # Patient Assassin
		"on": {"damage": func(g, me, ev):
			var t: Entity = g.ent(ev.target)
			if ev.source == me.id and t.is_minion():
				g.destroy(t)},
	}
	r["VAN_EX1_581"] = {"target": T.ENEMY_MINION, "spell": func(g, _me, t): g.return_to_hand(t)}  # Sap
	r["VAN_EX1_278"] = {  # Shiv
		"target": T.ANY,
		"spell": func(g, me, t):
			g.damage(me, t, g.spell_dmg(me, 1))
			g.draw(me.controller),
	}
	r["VAN_EX1_613"] = {  # Edwin VanCleef
		"combo": func(g, me, _t):
			var n: int = 2 * (g.players[me.controller].cards_played_this_turn - 1)
			g.buff(me, n, n),
	}
	r["VAN_EX1_129"] = {  # Fan of Knives
		"spell": func(g, me, _t):
			for m in g.minions(g.opponent(me.controller)):
				g.damage(me, m, g.spell_dmg(me, 1))
			g.draw(me.controller),
	}
	r["VAN_EX1_137"] = {  # Headcrack
		"spell": func(g, me, _t): g.damage(me, g.hero(g.opponent(me.controller)), g.spell_dmg(me, 2)),
		"combo": func(g, me, _t):
			g.damage(me, g.hero(g.opponent(me.controller)), g.spell_dmg(me, 2))
			g.hero(me.controller).add_enchant({"hooks": "ench:headcrack", "player": me.controller}),
	}
	r["ench:headcrack"] = {  # Return Headcrack to the hand at the start of the next own turn.
		"on": {"turn_start": func(g, me, ev):
			for e in me.enchantments.duplicate():
				if e.get("hooks") == "ench:headcrack" and ev.player == e.player:
					me.enchantments.erase(e)
					g.add_to_hand(e.player, "VAN_EX1_137")},
	}
	r["VAN_EX1_133"] = {  # Perdition's Blade
		"target": T.ANY,
		"battlecry": func(g, me, t): g.damage(me, t, 1),
		"combo": func(g, me, t): g.damage(me, t, 2),
	}
	r["VAN_EX1_134"] = {  # SI:7 Agent: targets only with Combo.
		"combo_target": T.ANY,
		"combo": func(g, me, t): g.damage(me, t, 2),
	}
	r["VAN_NEW1_014"] = {  # Master of Disguise
		"target": [T.FRIENDLY_MINION, func(_g, me, t): return t != me],
		"battlecry": func(_g, _me, t): t.give_tag("STEALTH"),
	}
	r["VAN_CS2_076"] = {"target": T.ENEMY_MINION, "spell": func(g, _me, t): g.destroy(t)}  # Assassinate
	r["VAN_NEW1_005"] = {  # Kidnapper
		"combo_target": T.MINION,
		"combo": func(g, _me, t): g.return_to_hand(t),
	}
	r["VAN_NEW1_004"] = {  # Vanish
		"spell": func(g, _me, _t):
			for m in g.all_minions():
				g.return_to_hand(m),
	}
	r["VAN_CS2_077"] = {"spell": func(g, me, _t): g.draw(me.controller, 4)}  # Sprint
