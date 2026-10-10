extends RefCounted
## Neutral cards and their tokens.


static func register(r: Dictionary) -> void:
	_basic(r)


static func _basic(r: Dictionary) -> void:
	r["VAN_CS2_189"] = {  # Elven Archer
		"target": T.ANY,
		"battlecry": func(g, me, t): g.damage(me, t, 1),
	}
	r["VAN_EX1_508"] = {  # Grimscale Oracle: ALL other Murlocs have +1 Attack.
		"aura": func(g, me):
			for m in g.all_minions():
				if m != me and m.race() == "MURLOC":
					g.aura_add(m, 1, 0),
	}
	r["VAN_EX1_011"] = {  # Voodoo Doctor
		"target": T.ANY,
		"battlecry": func(g, me, t): g.heal(me, t, g.heal_amt(me, 2)),
	}
	r["VAN_EX1_066"] = {  # Acidic Swamp Ooze
		"battlecry": func(g, me, _t): g.destroy(g.players[g.opponent(me.controller)].weapon),
	}
	r["VAN_EX1_506"] = {  # Murloc Tidehunter
		"battlecry": func(g, me, _t): g.summon_right(me, "VAN_EX1_506a"),
	}
	r["VAN_EX1_015"] = {  # Novice Engineer
		"battlecry": func(g, me, _t): g.draw(me.controller),
	}
	r["VAN_CS2_147"] = {  # Gnomish Inventor
		"battlecry": func(g, me, _t): g.draw(me.controller),
	}
	r["VAN_CS2_141"] = {  # Ironforge Rifleman
		"target": T.ANY,
		"battlecry": func(g, me, t): g.damage(me, t, 1),
	}
	r["VAN_CS2_122"] = {  # Raid Leader
		"aura": func(g, me):
			for m in g.others(me):
				g.aura_add(m, 1, 0),
	}
	r["VAN_CS2_196"] = {  # Razorfen Hunter
		"battlecry": func(g, me, _t): g.summon_right(me, "VAN_CS2_boar"),
	}
	r["VAN_EX1_019"] = {  # Shattered Sun Cleric
		"target": T.FRIENDLY_MINION,
		"battlecry": func(g, me, t): g.buff(t, 1, 1),
	}
	r["VAN_EX1_025"] = {  # Dragonling Mechanic
		"battlecry": func(g, me, _t): g.summon_right(me, "EX1_025t"),
	}
	r["VAN_DS1_055"] = {  # Darkscale Healer
		"battlecry": func(g, me, _t):
			for c in g.chars(me.controller):
				g.heal(me, c, g.heal_amt(me, 2)),
	}
	r["VAN_CS2_226"] = {  # Frostwolf Warlord
		"battlecry": func(g, me, _t):
			var n: int = g.others(me).size()
			g.buff(me, n, n),
	}
	r["VAN_EX1_399"] = {  # Gurubashi Berserker
		"on": {"damage": func(g, me, ev):
			if ev.target == me.id:
				g.buff(me, 3, 0)},
	}
	r["VAN_EX1_593"] = {  # Nightblade
		"battlecry": func(g, me, _t): g.damage(me, g.hero(g.opponent(me.controller)), 3),
	}
	r["VAN_CS2_150"] = {  # Stormpike Commando
		"target": T.ANY,
		"battlecry": func(g, me, t): g.damage(me, t, 2),
	}
	r["VAN_CS2_222"] = {  # Stormwind Champion
		"aura": func(g, me):
			for m in g.others(me):
				g.aura_add(m, 1, 1),
	}
