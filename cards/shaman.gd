extends RefCounted
## Shaman cards and their tokens. Overload comes from card data.


static func register(r: Dictionary) -> void:
	r["VAN_CS2_041"] = {  # Ancestral Healing
		"target": T.MINION,
		"spell": func(g, me, t):
			g.heal(me, t, t.damage)
			t.give_tag("TAUNT"),
	}
	r["VAN_EX1_244"] = {  # Totemic Might
		"spell": func(g, me, _t):
			for m in g.minions(me.controller):
				if m.race() == "TOTEM":
					g.buff(m, 0, 2),
	}
	r["VAN_EX1_245"] = {  # Earth Shock
		"target": T.MINION,
		"spell": func(g, me, t):
			g.silence(t)
			g.damage(me, t, g.spell_dmg(me, 1)),
	}
	r["VAN_EX1_251"] = {  # Forked Lightning
		"can_play": func(g, me): return g.minions(g.opponent(me.controller)).size() >= 2,
		"spell": func(g, me, _t):
			var pool: Array = g.minions(g.opponent(me.controller))
			g.shuffle(pool)
			for m in pool.slice(0, 2):
				g.damage(me, m, g.spell_dmg(me, 2)),
	}
	r["VAN_CS2_037"] = {  # Frost Shock
		"target": T.ENEMY_CHAR,
		"spell": func(g, me, t):
			g.damage(me, t, g.spell_dmg(me, 1))
			g.freeze(t),
	}
	r["VAN_EX1_238"] = {  # Lightning Bolt
		"target": T.ANY,
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 3)),
	}
	r["VAN_CS2_045"] = {"target": T.FRIENDLY_CHAR, "spell": func(g, _me, t): g.buff(t, 3, 0, true)}  # Rockbiter Weapon
	r["VAN_CS2_038"] = {  # Ancestral Spirit
		"target": T.MINION,
		"spell": func(_g, _me, t): t.add_enchant({"hooks": "ench:ancestral_spirit"}),
	}
	r["ench:ancestral_spirit"] = {
		"deathrattle": func(g, me, _ev): g.summon(me.controller, me.card_id, me.tags.DIED_POS),
	}
	r["VAN_EX1_565"] = {  # Flametongue Totem
		"aura": func(g, me):
			for m in g.adjacent(me):
				g.aura_add(m, 2, 0),
	}
	r["VAN_CS2_039"] = {"target": T.MINION, "spell": func(_g, _me, t): t.give_tag("WINDFURY")}  # Windfury
	r["VAN_CS2_053"] = {  # Far Sight
		"spell": func(g, me, _t):
			for e in g.draw(me.controller):
				e.add_enchant({"cost": -3}),
	}
	r["VAN_EX1_248"] = {  # Feral Spirit
		"spell": func(g, me, _t):
			for i in 2:
				g.summon(me.controller, "VAN_EX1_tk11"),
	}
	r["VAN_EX1_246"] = {"target": T.MINION, "spell": func(g, _me, t): g.transform(t, "hexfrog")}  # Hex
	r["VAN_EX1_241"] = {  # Lava Burst
		"target": T.ANY,
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 5)),
	}
	r["VAN_EX1_259"] = {  # Lightning Storm: 2-3 damage, rolled per minion.
		"spell": func(g, me, _t):
			for m in g.minions(g.opponent(me.controller)):
				g.damage(me, m, g.spell_dmg(me, g.rng.randi_range(2, 3))),
	}
	r["VAN_EX1_575"] = {  # Mana Tide Totem
		"on": {"turn_end": func(g, me, ev):
			if ev.player == me.controller:
				g.draw(me.controller)},
	}
	r["VAN_EX1_258"] = {  # Unbound Elemental
		"on": {"play": func(g, me, ev):
			if ev.player == me.controller and ev.entity != me.id and CardDb.card(ev.card).get("overload", 0) > 0:
				g.buff(me, 1, 1)},
	}
	r["VAN_EX1_587"] = {  # Windspeaker
		"target": [T.FRIENDLY_MINION, func(_g, me, t): return t != me],
		"battlecry": func(_g, _me, t): t.give_tag("WINDFURY"),
	}
	r["VAN_CS2_046"] = {  # Bloodlust
		"spell": func(g, me, _t):
			for m in g.minions(me.controller):
				g.buff(m, 3, 0, true),
	}
	r["VAN_CS2_042"] = {  # Fire Elemental
		"target": T.ANY,
		"battlecry": func(g, me, t): g.damage(me, t, 3),
	}
