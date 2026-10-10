extends RefCounted
## Priest cards and their tokens.


static func _board_has_room(g, me) -> bool:
	return g.players[me.controller].board.size() < GameState.MAX_BOARD


static func _max_attack(n: int) -> Callable:
	return func(_g, _me, t): return t.atk() <= n


static func register(r: Dictionary) -> void:
	r["VAN_EX1_621"] = {  # Circle of Healing
		"spell": func(g, me, _t):
			for m in g.all_minions():
				g.heal(me, m, g.heal_amt(me, 4)),
	}
	r["VAN_EX1_332"] = {"target": T.MINION, "spell": func(g, _me, t): g.silence(t)}  # Silence
	r["VAN_CS1_130"] = {  # Holy Smite
		"target": T.ANY,
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 2)),
	}
	r["VAN_CS1_129"] = {"target": T.MINION, "spell": func(g, _me, t): g.set_stats(t, t.health())}  # Inner Fire
	r["VAN_CS2_003"] = {  # Mind Vision
		"spell": func(g, me, _t):
			var e: Entity = g.random_choice(g.players[g.opponent(me.controller)].hand)
			if e:
				g.add_to_hand(me.controller, e.card_id),
	}
	r["VAN_CS2_235"] = {  # Northshire Cleric
		"on": {"heal": func(g, me, ev):
			if g.ent(ev.target).is_minion():
				g.draw(me.controller)},
	}
	r["VAN_CS2_004"] = {  # Power Word: Shield
		"target": T.MINION,
		"spell": func(g, me, t):
			g.buff(t, 0, 2)
			g.draw(me.controller),
	}
	r["VAN_CS2_236"] = {"target": T.MINION, "spell": func(g, _me, t): g.buff(t, 0, t.health())}  # Divine Spirit
	r["VAN_EX1_341"] = {  # Lightwell
		"on": {"turn_start": func(g, me, ev):
			if ev.player == me.controller:
				var hurt: Array = g.chars(me.controller).filter(func(c): return c.damage > 0 and c.health() > 0)
				var t: Entity = g.random_choice(hurt)
				if t:
					g.heal(me, t, g.heal_amt(me, 3))},
	}
	r["VAN_DS1_233"] = {  # Mind Blast
		"spell": func(g, me, _t): g.damage(me, g.hero(g.opponent(me.controller)), g.spell_dmg(me, 5)),
	}
	r["VAN_CS2_234"] = {"target": [T.MINION, _max_attack(3)], "spell": func(g, _me, t): g.destroy(t)}  # Shadow Word: Pain
	r["VAN_EX1_622"] = {  # Shadow Word: Death
		"target": [T.MINION, func(_g, _me, t): return t.atk() >= 5],
		"spell": func(g, _me, t): g.destroy(t),
	}
	r["VAN_EX1_625"] = {  # Shadowform: Mind Spike, then Mind Shatter. The new power is unused.
		"spell": func(g, me, _t):
			var cur: String = g.players[me.controller].hero_power.card_id
			g.set_hero_power(me.controller, "EX1_625t2" if cur.begins_with("EX1_625t") else "EX1_625t"),
	}
	r["VAN_EX1_339"] = {  # Thoughtsteal
		"spell": func(g, me, _t):
			var deck: Array = g.players[g.opponent(me.controller)].deck.duplicate()
			g.shuffle(deck)
			for e in deck.slice(0, 2):
				g.add_to_hand(me.controller, e.card_id),
	}
	r["VAN_EX1_591"] = {  # Auchenai Soulpriest
		"aura": func(g, me): g.aura_add(g.hero(me.controller), 0, 0, {"HEAL_IS_DAMAGE": true}),
	}
	r["VAN_EX1_335"] = {  # Lightspawn: attack always equals health; runs after all other auras.
		"aura_final": func(g, me): g.aura_add(me, me.health() - me.atk(), 0),
	}
	r["VAN_EX1_626"] = {  # Mass Dispel
		"spell": func(g, me, _t):
			for m in g.minions(g.opponent(me.controller)):
				g.silence(m)
			g.draw(me.controller),
	}
	r["VAN_EX1_345"] = {  # Mindgames
		"spell": func(g, me, _t):
			var pool: Array = g.players[g.opponent(me.controller)].deck.filter(func(e): return e.is_minion())
			var e: Entity = g.random_choice(pool)
			g.summon(me.controller, e.card_id if e else "VAN_EX1_345t"),
	}
	r["VAN_EX1_334"] = {  # Shadow Madness: control until end of turn; it can attack at once.
		"target": [T.ENEMY_MINION, _max_attack(3)],
		"can_play": _board_has_room,
		"spell": func(g, me, t):
			var owner: int = t.controller
			g.take_control(t, me.controller)
			t.tags.erase("EXHAUSTED")
			t.add_enchant({"hooks": "ench:shadow_madness", "player": owner}),
	}
	r["ench:shadow_madness"] = {
		"on": {"turn_end": func(g, me, _ev):
			for e in me.enchantments.duplicate():
				if e.get("hooks") == "ench:shadow_madness":
					me.enchantments.erase(e)
					g.take_control(me, e.player)},
	}
	r["VAN_CS1_112"] = {  # Holy Nova
		"spell": func(g, me, _t):
			for c in g.chars(g.opponent(me.controller)):
				g.damage(me, c, g.spell_dmg(me, 2))
			for c in g.chars(me.controller):
				g.heal(me, c, g.heal_amt(me, 2)),
	}
	r["VAN_EX1_091"] = {  # Cabal Shadow Priest
		"target": [T.ENEMY_MINION, _max_attack(2)],
		"battlecry": func(g, me, t): g.take_control(t, me.controller),
	}
	r["VAN_EX1_624"] = {  # Holy Fire
		"target": T.ANY,
		"spell": func(g, me, t):
			g.damage(me, t, g.spell_dmg(me, 5))
			g.heal(me, g.hero(me.controller), g.heal_amt(me, 5)),
	}
	r["VAN_EX1_623"] = {  # Temple Enforcer
		"target": [T.FRIENDLY_MINION, func(_g, me, t): return t != me],
		"battlecry": func(g, _me, t): g.buff(t, 0, 3),
	}
	r["VAN_EX1_350"] = {  # Prophet Velen
		"aura": func(g, me): g.aura_add(g.hero(me.controller), 0, 0, {"DOUBLE_HEAL_DAMAGE": 1}),
	}
	r["VAN_CS1_113"] = {  # Mind Control
		"target": T.ENEMY_MINION,
		"can_play": _board_has_room,
		"spell": func(g, me, t): g.take_control(t, me.controller),
	}
