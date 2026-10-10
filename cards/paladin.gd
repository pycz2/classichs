extends RefCounted
## Paladin cards and their tokens.


static func _board_has_room(g, me) -> bool:
	return g.players[me.controller].board.size() < GameState.MAX_BOARD


static func register(r: Dictionary) -> void:
	r["VAN_CS2_087"] = {"target": T.MINION, "spell": func(g, _me, t): g.buff(t, 3, 0)}  # Blessing of Might
	r["VAN_EX1_363"] = {  # Blessing of Wisdom
		"target": T.MINION,
		"spell": func(_g, me, t): t.add_enchant({"hooks": "ench:blessing_of_wisdom", "player": me.controller}),
	}
	r["ench:blessing_of_wisdom"] = {  # Whenever it attacks, the caster draws a card.
		"on": {"attack": func(g, me, ev):
			if ev.attacker == me.id:
				for e in me.enchantments:
					if e.get("hooks") == "ench:blessing_of_wisdom":
						g.draw(e.player)},
	}
	r["VAN_EX1_132"] = Cards.secret("damage",  # Eye for an Eye
		func(g, me, ev): return ev.target == g.hero(me.controller).id,
		func(g, me, ev): g.damage(me, g.hero(g.opponent(me.controller)), ev.amount))
	r["VAN_EX1_371"] = {"target": T.MINION, "spell": func(_g, _me, t): t.give_tag("DIVINE_SHIELD")}  # Hand of Protection
	r["VAN_EX1_360"] = {"target": T.MINION, "spell": func(g, _me, t): g.set_stats(t, 1)}  # Humility
	r["VAN_EX1_130"] = Cards.secret("attack",  # Noble Sacrifice
		func(g, me, ev): return ev.player != me.controller and _board_has_room(g, me),
		func(g, me, ev):
			var n: Entity = g.summon(me.controller, "VAN_EX1_130a")
			if n:
				ev.defender = n.id)
	r["VAN_EX1_136"] = Cards.secret("death",  # Redemption
		func(_g, me, ev): return ev.minion and ev.player == me.controller,
		func(g, me, ev):
			var dead: Entity = g.ent(ev.entity)
			var n: Entity = g.summon(me.controller, ev.card, dead.tags.get("DIED_POS", -1))
			if n:
				n.damage = n.max_health() - 1)
	r["VAN_EX1_379"] = Cards.secret("after_summon",  # Repentance
		func(_g, me, ev): return ev.get("played", false) and ev.player != me.controller,
		func(g, _me, ev): g.set_stats(g.ent(ev.entity), -1, 1))
	r["VAN_EX1_362"] = {  # Argent Protector
		"target": [T.FRIENDLY_MINION, func(_g, me, t): return t != me],
		"battlecry": func(_g, _me, t): t.give_tag("DIVINE_SHIELD"),
	}
	r["VAN_EX1_619"] = {  # Equality
		"spell": func(g, _me, _t):
			for m in g.all_minions():
				g.set_stats(m, -1, 1),
	}
	r["VAN_CS2_089"] = {  # Holy Light
		"target": T.ANY,
		"spell": func(g, me, t): g.heal(me, t, g.heal_amt(me, 6)),
	}
	r["VAN_EX1_382"] = {"target": T.ENEMY_MINION, "battlecry": func(g, _me, t): g.set_stats(t, 1)}  # Aldor Peacekeeper
	r["VAN_EX1_349"] = {  # Divine Favor
		"spell": func(g, me, _t):
			var n: int = g.players[g.opponent(me.controller)].hand.size() - g.players[me.controller].hand.size()
			if n > 0:
				g.draw(me.controller, n),
	}
	r["VAN_EX1_366"] = {  # Sword of Justice
		"on": {"after_summon": func(g, me, ev):
			if ev.player == me.controller:
				g.buff(g.ent(ev.entity), 1, 1)
				me.tags.DURABILITY = int(me.tags.DURABILITY) - 1},
	}
	r["VAN_CS2_092"] = {"target": T.MINION, "spell": func(g, _me, t): g.buff(t, 4, 4)}  # Blessing of Kings
	r["VAN_CS2_093"] = {  # Consecration
		"spell": func(g, me, _t):
			for c in g.chars(g.opponent(me.controller)):
				g.damage(me, c, g.spell_dmg(me, 2)),
	}
	r["VAN_CS2_094"] = {  # Hammer of Wrath
		"target": T.ANY,
		"spell": func(g, me, t):
			g.damage(me, t, g.spell_dmg(me, 3))
			g.draw(me.controller),
	}
	r["VAN_CS2_097"] = {  # Truesilver Champion
		"on": {"attack": func(g, me, ev):
			var hero: Entity = g.hero(me.controller)
			if ev.attacker == hero.id:
				g.heal(me, hero, g.heal_amt(me, 2))},
	}
	r["VAN_EX1_355"] = {"target": T.MINION, "spell": func(g, _me, t): g.buff(t, t.atk(), 0)}  # Blessed Champion
	r["VAN_EX1_365"] = {  # Holy Wrath
		"target": T.ANY,
		"spell": func(g, me, t):
			var drawn: Array = g.draw(me.controller)
			if not drawn.is_empty():
				g.damage(me, t, g.spell_dmg(me, g.cost(drawn[0]))),
	}
	r["VAN_EX1_384"] = {  # Avenging Wrath: spell damage adds missiles.
		"spell": func(g, me, _t):
			for i in g.spell_dmg(me, 8):
				g.damage(me, g.random_alive(g.chars(g.opponent(me.controller))), 1),
	}
	r["VAN_CS2_088"] = {  # Guardian of Kings
		"battlecry": func(g, me, _t): g.heal(me, g.hero(me.controller), g.heal_amt(me, 6)),
	}
	r["VAN_EX1_354"] = {  # Lay on Hands
		"target": T.ANY,
		"spell": func(g, me, t):
			g.heal(me, t, g.heal_amt(me, 8))
			g.draw(me.controller, 3),
	}
	r["VAN_EX1_383"] = {  # Tirion Fordring
		"deathrattle": func(g, me, _ev): g.equip(me.controller, "EX1_383t"),
	}
