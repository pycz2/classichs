extends RefCounted
## Cards of the tutorial bosses (TU4*).


static func register(r: Dictionary) -> void:
	r["TU4a_004"] = {  # Hogger SMASH!
		"target": T.ANY,
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 4)),
	}
	r["TU4c_002"] = {  # Barrel Toss
		"target": T.ANY,
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 2)),
	}
	r["TU4c_003"] = {  # Barrel: something hides inside.
		"deathrattle": func(g, me, _ev): g.summon(me.controller, "TU4c_005", me.tags.DIED_POS),
	}
	r["TU4c_004"] = {  # Stomp
		"spell": func(g, me, _t):
			for c in g.chars(g.opponent(me.controller)):
				g.damage(me, c, g.spell_dmg(me, 2)),
	}
	r["TU4c_006"] = {  # Bananas (tutorial): a friendly minion +1/+1
		"target": T.FRIENDLY_MINION,
		"spell": func(g, _me, t): g.buff(t, 1, 1),
	}
	r["TU4c_008"] = {  # Will of Mukla
		"target": T.ANY,
		"spell": func(g, me, t): g.heal(me, t, g.heal_amt(me, 8)),
	}
	r["TU4f_007"] = {  # Crazy Monkey: throws Bananas (into its owner's hand).
		"battlecry": func(g, me, _t): g.add_to_hand(me.controller, "TU4c_006"),
	}
	r["TU4d_003"] = {  # Shotgun Blast (Hemet)
		"target": T.ANY,
		"hero_power": func(g, me, t): g.damage(me, t, g.hp_dmg(me, 1)),
	}
	r["TU4e_002"] = {  # Flames of Azzinoth (Illidan)
		"can_play": func(g, me): return g.players[me.controller].board.size() < GameState.MAX_BOARD,
		"hero_power": func(g, me, _t):
			for i in 2:
				g.summon(me.controller, "TU4e_002t"),
	}
	r["TU4e_005"] = {  # Flame Burst: 5 missiles of 1 damage at random enemies
		"spell": func(g, me, _t):
			for i in g.spell_dmg(me, 5):
				g.damage(me, g.random_alive(g.chars(g.opponent(me.controller))), 1),
	}
	r["TU4f_004"] = {  # Legacy of the Emperor
		"spell": func(g, me, _t):
			for m in g.minions(me.controller):
				g.buff(m, 2, 2),
	}
	r["TU4f_006"] = {  # Transcendence: Cho can't be attacked or targeted until his minions are dead.
		"spell": func(g, me, _t):
			var hero: Entity = g.hero(me.controller)
			if not g.minions(me.controller).is_empty():
				hero.give_tag("STEALTH")
				hero.add_enchant({"hooks": "ench:transcendence"}),
	}
	r["ench:transcendence"] = {
		"on": {"death": func(g, me, _ev):
			if g.minions(me.controller).is_empty():
				me.tags.erase("STEALTH")
				me.enchantments = me.enchantments.filter(func(e): return e.get("hooks") != "ench:transcendence")},
	}
