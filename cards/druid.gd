extends RefCounted
## Druid cards and their Choose One options. Option order follows the card text.


static func _hero_attack(g, me, n: int, armor: int) -> void:
	g.buff(g.hero(me.controller), n, 0, true)
	g.gain_armor(me.controller, armor)


static func _taunt_buff(g, t, atk: int, hp: int) -> void:
	g.buff(t, atk, hp)
	t.give_tag("TAUNT")


static func register(r: Dictionary) -> void:
	r["VAN_EX1_169"] = {  # Innervate
		"spell": func(g, me, _t):
			var p: Player = g.players[me.controller]
			p.mana = mini(GameState.MAX_MANA, p.mana + 2),
	}
	r["VAN_CS2_008"] = {  # Moonfire
		"target": T.ANY,
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 1)),
	}
	r["VAN_CS2_005"] = {"spell": func(g, me, _t): _hero_attack(g, me, 2, 2)}  # Claw
	r["VAN_EX1_570"] = {"spell": func(g, me, _t): _hero_attack(g, me, 4, 4)}  # Bite
	r["VAN_EX1_161"] = {  # Naturalize
		"target": T.MINION,
		"spell": func(g, me, t):
			g.destroy(t)
			g.draw(g.opponent(me.controller), 2),
	}
	r["VAN_EX1_578"] = {  # Savagery
		"target": T.MINION,
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, g.hero_atk(g.hero(me.controller)))),
	}
	r["VAN_CS2_009"] = {  # Mark of the Wild
		"target": T.MINION,
		"spell": func(g, _me, t): _taunt_buff(g, t, 2, 2),
	}
	r["VAN_EX1_160"] = {"choose_one": ["VAN_EX1_160b", "VAN_EX1_160a"]}  # Power of the Wild
	r["VAN_EX1_160b"] = {  # Leader of the Pack
		"effect": func(g, me, _t):
			for m in g.minions(me.controller):
				g.buff(m, 1, 1),
	}
	r["VAN_EX1_160a"] = {"effect": func(g, me, _t): g.summon(me.controller, "EX1_160t")}  # Summon a Panther
	r["VAN_CS2_013"] = {  # Wild Growth: at 10 crystals, Excess Mana instead.
		"spell": func(g, me, _t):
			if g.players[me.controller].max_mana >= GameState.MAX_MANA:
				g.add_to_hand(me.controller, "CS2_013t")
			else:
				g.gain_mana(me.controller, 1, true),
	}
	r["CS2_013t"] = {"spell": func(g, me, _t): g.draw(me.controller)}  # Excess Mana
	r["VAN_EX1_154"] = {"choose_one": ["VAN_EX1_154a", "VAN_EX1_154b"]}  # Wrath
	r["VAN_EX1_154a"] = {  # Solar Wrath
		"target": T.MINION,
		"effect": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 3)),
	}
	r["VAN_EX1_154b"] = {  # Nature's Wrath
		"target": T.MINION,
		"effect": func(g, me, t):
			g.damage(me, t, g.spell_dmg(me, 1))
			g.draw(me.controller),
	}
	r["VAN_CS2_007"] = {  # Healing Touch
		"target": T.ANY,
		"spell": func(g, me, t): g.heal(me, t, g.heal_amt(me, 8)),
	}
	r["VAN_EX1_155"] = {"choose_one": ["VAN_EX1_155a", "VAN_EX1_155b"]}  # Mark of Nature
	r["VAN_EX1_155a"] = {"target": T.MINION, "effect": func(g, _me, t): g.buff(t, 4, 0)}  # Tiger's Fury
	r["VAN_EX1_155b"] = {"target": T.MINION, "effect": func(g, _me, t): _taunt_buff(g, t, 0, 4)}  # Thick Hide
	r["VAN_CS2_011"] = {  # Savage Roar
		"spell": func(g, me, _t):
			for c in g.chars(me.controller):
				g.buff(c, 2, 0, true),
	}
	r["VAN_EX1_166"] = {"choose_one": ["VAN_EX1_166a", "VAN_EX1_166b"]}  # Keeper of the Grove
	r["VAN_EX1_166a"] = {"target": T.ANY, "effect": func(g, me, t): g.damage(me, t, 2)}  # Moonfire
	r["VAN_EX1_166b"] = {"target": T.MINION, "effect": func(g, _me, t): g.silence(t)}  # Dispel
	r["VAN_EX1_158"] = {  # Soul of the Forest
		"spell": func(g, me, _t):
			for m in g.minions(me.controller):
				m.add_enchant({"hooks": "ench:soul_of_the_forest"}),
	}
	r["ench:soul_of_the_forest"] = {
		"deathrattle": func(g, me, _ev): g.summon(me.controller, "VAN_EX1_tk9", me.tags.DIED_POS),
	}
	r["VAN_CS2_012"] = {  # Swipe
		"target": T.ENEMY_CHAR,
		"spell": func(g, me, t):
			var others: Array = g.chars(t.controller).filter(func(c): return c != t)
			g.damage(me, t, g.spell_dmg(me, 4))
			for c in others:
				g.damage(me, c, g.spell_dmg(me, 1)),
	}
	r["VAN_EX1_165"] = {"choose_one": ["VAN_EX1_165a", "VAN_EX1_165b"]}  # Druid of the Claw
	r["VAN_EX1_165a"] = {"effect": func(g, me, _t): g.transform(me, "VAN_EX1_165t1")}  # Cat Form
	r["VAN_EX1_165b"] = {"effect": func(g, me, _t): g.transform(me, "VAN_EX1_165t2")}  # Bear Form
	r["VAN_EX1_164"] = {"choose_one": ["VAN_EX1_164a", "VAN_EX1_164b"]}  # Nourish
	r["VAN_EX1_164a"] = {"effect": func(g, me, _t): g.gain_mana(me.controller, 2)}  # Rampant Growth
	r["VAN_EX1_164b"] = {"effect": func(g, me, _t): g.draw(me.controller, 3)}  # Enrich
	r["VAN_NEW1_007"] = {"choose_one": ["VAN_NEW1_007b", "VAN_NEW1_007a"]}  # Starfall
	r["VAN_NEW1_007b"] = {  # Starlord
		"target": T.MINION,
		"effect": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 5)),
	}
	r["VAN_NEW1_007a"] = {  # Stellar Drift
		"effect": func(g, me, _t):
			for m in g.minions(g.opponent(me.controller)):
				g.damage(me, m, g.spell_dmg(me, 2)),
	}
	r["VAN_EX1_571"] = {  # Force of Nature
		"spell": func(g, me, _t):
			for i in 3:
				g.summon(me.controller, "VAN_EX1_tk9b"),
	}
	r["VAN_EX1_tk9b"] = {  # Treant (Force of Nature): destroyed at the end of the turn.
		"on": {"turn_end": func(g, me, _ev): g.destroy(me)},
	}
	r["VAN_EX1_173"] = {  # Starfire
		"target": T.ANY,
		"spell": func(g, me, t):
			g.damage(me, t, g.spell_dmg(me, 5))
			g.draw(me.controller),
	}
	r["VAN_NEW1_008"] = {"choose_one": ["VAN_NEW1_008a", "VAN_NEW1_008b"]}  # Ancient of Lore
	r["VAN_NEW1_008a"] = {"effect": func(g, me, _t): g.draw(me.controller, 2)}  # Ancient Teachings
	r["VAN_NEW1_008b"] = {  # Ancient Secrets
		"target": T.ANY,
		"effect": func(g, me, t): g.heal(me, t, g.heal_amt(me, 5)),
	}
	r["VAN_EX1_178"] = {"choose_one": ["VAN_EX1_178b", "VAN_EX1_178a"]}  # Ancient of War
	r["VAN_EX1_178b"] = {"effect": func(g, me, _t): g.buff(me, 5, 0)}  # Uproot
	r["VAN_EX1_178a"] = {"effect": func(g, me, _t): _taunt_buff(g, me, 0, 5)}  # Rooted
	r["VAN_EX1_573"] = {"choose_one": ["VAN_EX1_573a", "VAN_EX1_573b"]}  # Cenarius
	r["VAN_EX1_573a"] = {  # Demigod's Favor
		"effect": func(g, me, _t):
			for m in g.others(me):
				g.buff(m, 2, 2),
	}
	r["VAN_EX1_573b"] = {  # Shan'do's Lesson: Treants with Taunt on both sides.
		"effect": func(g, me, _t):
			var right: Entity = g.summon_right(me, "VAN_EX1_tk9")
			var left: Entity = g.summon(me.controller, "VAN_EX1_tk9", g.players[me.controller].board.find(me))
			for t in [right, left]:
				if t:
					t.give_tag("TAUNT"),
	}
