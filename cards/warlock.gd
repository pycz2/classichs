extends RefCounted
## Warlock cards and their tokens.


static func _is_demon(_g, _me, t) -> bool:
	return t.race() == "DEMON"


static func _discard(n: int) -> Callable:
	return func(g, me, _t): g.discard_random(me.controller, n)


## Damage, then true if the target is now dying (Mortal Coil, Bane of Doom).
static func _kills(g, me, t, amount: int) -> bool:
	g.damage(me, t, amount)
	return t.zone == "PLAY" and t.health() <= 0


static func _collectible_demons() -> Array:
	return CardDb.collectible().filter(func(id):
		var c := CardDb.card(id)
		return c.type == "MINION" and c.get("race", "") == "DEMON")


static func register(r: Dictionary) -> void:
	r["VAN_NEW1_003"] = {  # Sacrificial Pact: any Demon, Lord Jaraxxus as hero included.
		"target": _is_demon,
		"spell": func(g, me, t):
			g.destroy(t)
			g.heal(me, g.hero(me.controller), g.heal_amt(me, 5)),
	}
	r["VAN_EX1_308"] = {  # Soulfire
		"target": T.ANY,
		"spell": func(g, me, t):
			g.damage(me, t, g.spell_dmg(me, 4))
			g.discard_random(me.controller),
	}
	r["VAN_CS2_059"] = {  # Blood Imp
		"on": {"turn_end": func(g, me, ev):
			if ev.player == me.controller:
				var t: Entity = g.random_alive(g.others(me))
				if t:
					g.buff(t, 0, 1)},
	}
	r["VAN_CS2_063"] = {  # Corruption
		"target": T.ENEMY_MINION,
		"spell": func(_g, me, t): t.add_enchant({"hooks": "ench:corruption", "player": me.controller}),
	}
	r["ench:corruption"] = {  # At the start of the caster's turn, destroy it.
		"on": {"turn_start": func(g, me, ev):
			for e in me.enchantments:
				if e.get("hooks") == "ench:corruption" and ev.player == e.player:
					g.destroy(me)},
	}
	r["VAN_EX1_319"] = {"battlecry": func(g, me, _t): g.damage(me, g.hero(me.controller), 3)}  # Flame Imp
	r["VAN_EX1_302"] = {  # Mortal Coil
		"target": T.MINION,
		"spell": func(g, me, t):
			if _kills(g, me, t, g.spell_dmg(me, 1)):
				g.draw(me.controller),
	}
	r["VAN_EX1_316"] = {  # Power Overwhelming
		"target": T.FRIENDLY_MINION,
		"spell": func(g, _me, t):
			g.buff(t, 4, 4, true)
			t.add_enchant({"hooks": "ench:power_overwhelming"}),
	}
	r["ench:power_overwhelming"] = {"on": {"turn_end": func(g, me, _ev): g.destroy(me)}}
	r["VAN_EX1_596"] = {  # Demonfire
		"target": T.MINION,
		"spell": func(g, me, t):
			if t.controller == me.controller and t.race() == "DEMON":
				g.buff(t, 2, 2)
			else:
				g.damage(me, t, g.spell_dmg(me, 2)),
	}
	r["VAN_EX1_306"] = {"battlecry": _discard(1)}  # Felstalker
	r["VAN_CS2_061"] = {  # Drain Life
		"target": T.ANY,
		"spell": func(g, me, t):
			g.damage(me, t, g.spell_dmg(me, 2))
			g.heal(me, g.hero(me.controller), g.heal_amt(me, 2)),
	}
	r["VAN_EX1_301"] = {  # Felguard
		"battlecry": func(g, me, _t):
			var p: Player = g.players[me.controller]
			p.max_mana = maxi(0, p.max_mana - 1)
			p.mana = mini(p.mana, p.max_mana),
	}
	r["VAN_EX1_317"] = {  # Sense Demons: missing demons become Worthless Imps.
		"spell": func(g, me, _t):
			var demons: Array = g.players[me.controller].deck.filter(func(e): return e.race() == "DEMON")
			g.shuffle(demons)
			for i in 2:
				if i < demons.size():
					g.draw_entity(me.controller, demons[i])
				else:
					g.add_to_hand(me.controller, "EX1_317t"),
	}
	r["VAN_CS2_057"] = {  # Shadow Bolt
		"target": T.MINION,
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 4)),
	}
	r["VAN_EX1_304"] = {  # Void Terror
		"battlecry": func(g, me, _t):
			var atk := 0
			var hp := 0
			for m in g.adjacent(me):
				atk += m.atk()
				hp += m.health()
				g.destroy(m)
			g.buff(me, atk, hp),
	}
	r["VAN_CS2_062"] = {  # Hellfire
		"spell": func(g, me, _t):
			for c in g.all_chars():
				g.damage(me, c, g.spell_dmg(me, 3)),
	}
	r["VAN_EX1_313"] = {"battlecry": func(g, me, _t): g.damage(me, g.hero(me.controller), 5)}  # Pit Lord
	r["VAN_EX1_303"] = {  # Shadowflame
		"target": T.FRIENDLY_MINION,
		"spell": func(g, me, t):
			var n: int = g.spell_dmg(me, t.atk())
			g.destroy(t)
			for m in g.minions(g.opponent(me.controller)):
				g.damage(me, m, n),
	}
	r["VAN_EX1_315"] = {  # Summoning Portal
		"cost_aura": func(_g, me, card, c):
			if card.controller != me.controller or not card.is_minion() or card.zone != "HAND" or c <= 1:
				return c
			return maxi(1, c - 2),
	}
	r["VAN_EX1_320"] = {  # Bane of Doom
		"target": T.ANY,
		"spell": func(g, me, t):
			if _kills(g, me, t, g.spell_dmg(me, 3)):
				g.summon(me.controller, g.random_choice(_collectible_demons())),
	}
	r["VAN_EX1_310"] = {"battlecry": _discard(2)}  # Doomguard
	r["VAN_CS2_064"] = {  # Dread Infernal
		"battlecry": func(g, me, _t):
			for c in g.all_chars():
				if c != me:
					g.damage(me, c, 1),
	}
	r["VAN_EX1_309"] = {  # Siphon Soul
		"target": T.MINION,
		"spell": func(g, me, t):
			g.destroy(t)
			g.heal(me, g.hero(me.controller), g.heal_amt(me, 3)),
	}
	r["VAN_EX1_312"] = {  # Twisting Nether
		"spell": func(g, _me, _t):
			for m in g.all_minions():
				g.destroy(m),
	}
	r["VAN_EX1_323"] = {  # Lord Jaraxxus: new 15/15 hero, Blood Fury, INFERNO!; secrets stay.
		"battlecry": func(g, me, _t):
			var p: int = me.controller
			g.players[p].board.erase(me)
			me.zone = "SETASIDE"
			g.replace_hero(p, "EX1_323h")
			g.equip(p, "EX1_323w")
			g.set_hero_power(p, "VAN_EX1_tk33"),
	}
