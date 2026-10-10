extends RefCounted
## Mage cards and their tokens.


static func _attacks_my_hero(g, me, ev) -> bool:
	return ev.defender == g.hero(me.controller).id


static func _enemy_minions(g, me) -> Array:
	return g.minions(g.opponent(me.controller))


static func _board_has_room(g, me) -> bool:
	return g.players[me.controller].board.size() < GameState.MAX_BOARD


static func _enemy_spell(_g, me, ev) -> bool:
	return ev.kind == "spell" and ev.player != me.controller


static func register(r: Dictionary) -> void:
	r["VAN_EX1_277"] = {  # Arcane Missiles: spell damage adds missiles.
		"spell": func(g, me, _t):
			for i in g.spell_dmg(me, 3):
				g.damage(me, g.random_alive(g.chars(g.opponent(me.controller))), 1),
	}
	r["VAN_CS2_031"] = {  # Ice Lance
		"target": T.ANY,
		"spell": func(g, me, t):
			if t.has("FROZEN"):
				g.damage(me, t, g.spell_dmg(me, 4))
			else:
				g.freeze(t),
	}
	r["VAN_NEW1_012"] = {  # Mana Wyrm
		"on": {"play": func(g, me, ev):
			if ev.kind == "spell" and ev.player == me.controller:
				g.buff(me, 1, 0)},
	}
	r["VAN_CS2_027"] = {  # Mirror Image
		"spell": func(g, me, _t):
			for i in 2:
				g.summon(me.controller, "VAN_CS2_mirror"),
	}
	r["VAN_CS2_025"] = {  # Arcane Explosion
		"spell": func(g, me, _t):
			for m in _enemy_minions(g, me):
				g.damage(me, m, g.spell_dmg(me, 1)),
	}
	r["VAN_CS2_024"] = {  # Frostbolt
		"target": T.ANY,
		"spell": func(g, me, t):
			g.damage(me, t, g.spell_dmg(me, 3))
			g.freeze(t),
	}
	r["VAN_EX1_608"] = {  # Sorcerer's Apprentice
		"cost_aura": func(_g, me, card, c):
			return c - 1 if card.controller == me.controller and card.type() == "SPELL" and card.zone == "HAND" else c,
	}
	r["VAN_CS2_023"] = {"spell": func(g, me, _t): g.draw(me.controller, 2)}  # Arcane Intellect
	r["VAN_EX1_287"] = Cards.secret("play", _enemy_spell,  # Counterspell
		func(_g, _me, ev): ev.countered = true)
	r["VAN_CS2_026"] = {  # Frost Nova
		"spell": func(g, me, _t):
			for m in _enemy_minions(g, me):
				g.freeze(m),
	}
	r["VAN_EX1_289"] = Cards.secret("attack", _attacks_my_hero,  # Ice Barrier
		func(g, me, _ev): g.gain_armor(me.controller, 8))
	r["VAN_EX1_295"] = {  # Ice Block: replaces fatal damage to my hero.
		"now": {"predamage": func(g, me, ev):
			var hero: Entity = g.hero(me.controller)
			if g.secret_ready(me) and ev.target == hero.id and ev.amount >= hero.health() + int(hero.tags.ARMOR):
				ev.amount = 0
				g.reveal(me)
				hero.give_tag("IMMUNE", true)},
	}
	r["VAN_EX1_612"] = {  # Kirin Tor Mage
		"battlecry": func(g, me, _t): g.add_cost_mod(me.controller, {"kind": "secret", "set": 0, "until": "use"}),
	}
	r["VAN_EX1_294"] = Cards.secret("after_summon",  # Mirror Entity
		func(g, me, ev): return ev.get("played", false) and ev.player != me.controller and _board_has_room(g, me),
		func(g, me, ev): g.summon(me.controller, ev.card))
	r["VAN_tt_010"] = Cards.secret("play",  # Spellbender
		func(g, me, ev):
			return _enemy_spell(g, me, ev) and ev.target >= 0 and g.ent(ev.target).is_minion() and _board_has_room(g, me),
		func(g, me, ev):
			var n: Entity = g.summon(me.controller, "VAN_tt_010a")
			if n:
				ev.target = n.id)
	r["VAN_EX1_594"] = Cards.secret("attack",  # Vaporize
		func(g, me, ev): return _attacks_my_hero(g, me, ev) and g.ent(ev.attacker).is_minion(),
		func(g, _me, ev): g.destroy(g.ent(ev.attacker)))
	r["VAN_EX1_275"] = {  # Cone of Cold
		"target": T.MINION,
		"spell": func(g, me, t):
			var group: Array = [t]
			group.append_array(g.adjacent(t))
			for m in group:
				g.damage(me, m, g.spell_dmg(me, 1))
				g.freeze(m),
	}
	r["VAN_EX1_274"] = {  # Ethereal Arcanist
		"on": {"turn_end": func(g, me, ev):
			if ev.player == me.controller and not g.players[me.controller].secrets.is_empty():
				g.buff(me, 2, 2)},
	}
	r["VAN_CS2_029"] = {  # Fireball
		"target": T.ANY,
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 6)),
	}
	r["VAN_CS2_022"] = {  # Polymorph
		"target": T.MINION,
		"spell": func(g, _me, t): g.transform(t, "VAN_CS2_tk1"),
	}
	r["VAN_CS2_033"] = {  # Water Elemental
		"on": {"damage": func(g, me, ev):
			if ev.source == me.id:
				g.freeze(g.ent(ev.target))},
	}
	r["VAN_CS2_028"] = {  # Blizzard
		"spell": func(g, me, _t):
			for m in _enemy_minions(g, me):
				g.damage(me, m, g.spell_dmg(me, 2))
				g.freeze(m),
	}
	r["VAN_EX1_559"] = {  # Archmage Antonidas
		"on": {"play": func(g, me, ev):
			if ev.kind == "spell" and ev.player == me.controller:
				g.add_to_hand(me.controller, "VAN_CS2_029")},
	}
	r["VAN_CS2_032"] = {  # Flamestrike
		"spell": func(g, me, _t):
			for m in _enemy_minions(g, me):
				g.damage(me, m, g.spell_dmg(me, 4)),
	}
	r["VAN_EX1_279"] = {  # Pyroblast
		"target": T.ANY,
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 10)),
	}
