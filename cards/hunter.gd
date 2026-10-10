extends RefCounted
## Hunter cards and their tokens.

const COMPANIONS := ["VAN_NEW1_032", "VAN_NEW1_033", "VAN_NEW1_034"]


static func _is_beast(_g, _me, t) -> bool:
	return t.race() == "BEAST"


static func _has_enemy_minions(n: int) -> Callable:
	return func(g, me): return g.minions(g.opponent(me.controller)).size() >= n


static func _attacks_my_hero(g, me, ev) -> bool:
	return ev.defender == g.hero(me.controller).id


static func register(r: Dictionary) -> void:
	r["VAN_CS2_084"] = {  # Hunter's Mark
		"target": T.MINION,
		"spell": func(g, _me, t): g.set_stats(t, -1, 1),
	}
	r["VAN_DS1_185"] = {  # Arcane Shot
		"target": T.ANY,
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 2)),
	}
	r["VAN_EX1_549"] = {  # Bestial Wrath. 2014: any Beast.
		"target": [T.MINION, _is_beast],
		"spell": func(g, _me, t):
			g.buff(t, 2, 0, true)
			t.give_tag("IMMUNE", true),
	}
	r["VAN_EX1_544"] = {  # Flare
		"spell": func(g, me, _t):
			for m in g.all_minions():
				m.tags.erase("STEALTH")
			var enemy: Player = g.players[g.opponent(me.controller)]
			for s in enemy.secrets.duplicate():
				enemy.secrets.erase(s)
				s.zone = "GRAVEYARD"
				g.log_event({"type": "destroy", "target": s.id})
			g.draw(me.controller),
	}
	r["VAN_DS1_175"] = {  # Timber Wolf
		"aura": func(g, me):
			for m in g.others(me):
				if m.race() == "BEAST":
					g.aura_add(m, 1, 0),
	}
	r["VAN_DS1_184"] = {  # Tracking
		"spell": func(g, me, _t):
			var opts: Array[int] = []
			for e in g.players[me.controller].deck.slice(-3):
				opts.append(e.id)
			if not opts.is_empty():
				g.request_choice(me, opts),
		"on_choose": func(g, me, opt, still: Array):
			var deck: Array = g.players[me.controller].deck
			var rest: Array = still.filter(func(id): return id != opt.id).map(func(id): return g.ent(id))
			g.draw_entity(me.controller, opt)
			for e in rest:
				deck.erase(e)
				e.zone = "GRAVEYARD"
				g.log_event({"type": "discard", "player": me.controller, "entity": e.id, "card": e.card_id}),
	}
	r["VAN_EX1_610"] = Cards.secret("attack", _attacks_my_hero, func(g, me, _ev):  # Explosive Trap
		for c in g.chars(g.opponent(me.controller)):
			g.damage(me, c, g.spell_dmg(me, 2)))
	r["VAN_EX1_611"] = Cards.secret("attack",  # Freezing Trap
		func(g, me, ev): return g.ent(ev.attacker).is_minion() and ev.player != me.controller,
		func(g, _me, ev):
			var n: Entity = g.return_to_hand(g.ent(ev.attacker))
			if n:
				n.add_enchant({"cost": 2}))
	r["VAN_EX1_533"] = Cards.secret("attack", _attacks_my_hero, func(g, me, ev):  # Misdirection
		var pool: Array = g.all_chars().filter(func(c): return c.id != ev.attacker and c != g.hero(me.controller))
		var t: Entity = g.random_alive(pool)
		if t:
			ev.defender = t.id)
	r["VAN_EX1_531"] = {  # Scavenging Hyena
		"on": {"death": func(g, me, ev):
			if ev.minion and ev.player == me.controller and CardDb.card(ev.card).get("race", "") == "BEAST":
				g.buff(me, 2, 1)},
	}
	r["VAN_EX1_554"] = Cards.secret("attack",  # Snake Trap
		func(g, me, ev):
			var d: Entity = g.ent(ev.defender)
			return d.is_minion() and d.controller == me.controller and g.minions(me.controller).size() < GameState.MAX_BOARD,
		func(g, me, _ev):
			for i in 3:
				g.summon(me.controller, "VAN_EX1_554t"))
	r["VAN_EX1_609"] = Cards.secret("after_summon",  # Snipe
		func(_g, me, ev): return ev.get("played", false) and ev.player != me.controller,
		func(g, me, ev): g.damage(me, g.ent(ev.entity), g.spell_dmg(me, 4)))
	r["VAN_CS2_237"] = {  # Starving Buzzard
		"on": {"summon": func(g, me, ev):
			if ev.player == me.controller and ev.entity != me.id and g.ent(ev.entity).race() == "BEAST":
				g.draw(me.controller)},
	}
	r["VAN_NEW1_031"] = {  # Animal Companion
		"spell": func(g, me, _t): g.summon(me.controller, g.random_choice(COMPANIONS)),
	}
	r["VAN_NEW1_033"] = {  # Leokk: your other minions have +1 Attack.
		"aura": func(g, me):
			for m in g.others(me):
				g.aura_add(m, 1, 0),
	}
	r["VAN_EX1_617"] = {  # Deadly Shot
		"can_play": _has_enemy_minions(1),
		"spell": func(g, me, _t): g.destroy(g.random_alive(g.minions(g.opponent(me.controller)))),
	}
	r["VAN_EX1_536"] = {  # Eaglehorn Bow
		"on": {"secret_revealed": func(_g, me, ev):
			if ev.player == me.controller:
				me.tags.DURABILITY = int(me.tags.DURABILITY) + 1},
	}
	r["VAN_EX1_539"] = {  # Kill Command
		"target": T.ANY,
		"spell": func(g, me, t):
			var beast: bool = g.minions(me.controller).any(func(m): return m.race() == "BEAST")
			g.damage(me, t, g.spell_dmg(me, 5 if beast else 3)),
	}
	r["VAN_EX1_538"] = {  # Unleash the Hounds
		"can_play": _has_enemy_minions(1),
		"spell": func(g, me, _t):
			for i in g.minions(g.opponent(me.controller)).size():
				g.summon(me.controller, "EX1_538t"),
	}
	r["VAN_DS1_070"] = {  # Houndmaster
		"target": [T.FRIENDLY_MINION, _is_beast],
		"battlecry": func(g, _me, t):
			g.buff(t, 2, 2)
			t.give_tag("TAUNT"),
	}
	r["VAN_DS1_183"] = {  # Multi-Shot. 2014: needs two enemy minions (as Fireplace).
		"can_play": _has_enemy_minions(2),
		"spell": func(g, me, _t):
			var pool: Array = g.minions(g.opponent(me.controller))
			g.shuffle(pool)
			for m in pool.slice(0, 2):
				g.damage(me, m, g.spell_dmg(me, 3)),
	}
	r["VAN_EX1_537"] = {  # Explosive Shot
		"target": T.MINION,
		"spell": func(g, me, t):
			var near: Array = g.adjacent(t)
			g.damage(me, t, g.spell_dmg(me, 5))
			for m in near:
				g.damage(me, m, g.spell_dmg(me, 2)),
	}
	r["VAN_DS1_178"] = {  # Tundra Rhino: your Beasts have Charge.
		"aura": func(g, me):
			for m in g.minions(me.controller):
				if m.race() == "BEAST":
					g.aura_add(m, 0, 0, {"CHARGE": true}),
	}
	r["VAN_EX1_534"] = {  # Savannah Highmane
		"deathrattle": func(g, me, _ev):
			for i in 2:
				g.summon(me.controller, "EX1_534t", me.tags.DIED_POS),
	}
	r["VAN_DS1_188"] = {"immune_while_attacking": true}  # Gladiator's Longbow
