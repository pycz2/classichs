extends RefCounted
## Warrior cards and their tokens.


static func _damaged(_g, _me, t) -> bool:
	return t.damage > 0


static func _hit_and_rage(g, me, t) -> void:
	g.damage(me, t, g.spell_dmg(me, 1) if me.type() == "SPELL" else 1)
	g.buff(t, 2, 0)


static func register(r: Dictionary) -> void:
	r["VAN_EX1_607"] = {"target": T.MINION, "spell": _hit_and_rage}  # Inner Rage
	r["VAN_CS2_108"] = {"target": [T.ENEMY_MINION, _damaged], "spell": func(g, _me, t): g.destroy(t)}  # Execute
	r["VAN_EX1_410"] = {  # Shield Slam
		"target": T.MINION,
		"spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, int(g.hero(me.controller).tags.ARMOR))),
	}
	r["VAN_EX1_409"] = {  # Upgrade!
		"spell": func(g, me, _t):
			var w: Entity = g.players[me.controller].weapon
			if w:
				g.buff(w, 1, 0)
				w.tags.DURABILITY = int(w.tags.DURABILITY) + 1
			else:
				g.equip(me.controller, "EX1_409t"),
	}
	r["VAN_EX1_400"] = {  # Whirlwind
		"spell": func(g, me, _t):
			for m in g.all_minions():
				g.damage(me, m, g.spell_dmg(me, 1)),
	}
	r["VAN_EX1_402"] = {  # Armorsmith
		"on": {"damage": func(g, me, ev):
			var t: Entity = g.ent(ev.target)
			if t.is_minion() and t.controller == me.controller:
				g.gain_armor(me.controller, 1)},
	}
	r["VAN_EX1_392"] = {  # Battle Rage
		"spell": func(g, me, _t):
			g.draw(me.controller, g.chars(me.controller).filter(func(c): return c.damage > 0).size()),
	}
	r["VAN_CS2_114"] = {  # Cleave
		"can_play": func(g, me): return g.minions(g.opponent(me.controller)).size() >= 2,
		"spell": func(g, me, _t):
			var pool: Array = g.minions(g.opponent(me.controller))
			g.shuffle(pool)
			for m in pool.slice(0, 2):
				g.damage(me, m, g.spell_dmg(me, 2)),
	}
	r["VAN_NEW1_036"] = {  # Commanding Shout: lives on the hero this turn, so later minions count too.
		"spell": func(g, me, _t):
			g.hero(me.controller).add_enchant({"hooks": "ench:commanding_shout", "eot": true})
			g.draw(me.controller),
	}
	r["ench:commanding_shout"] = {
		"now": {"predamage": func(g, me, ev):
			var t: Entity = g.ent(ev.target)
			if t.is_minion() and t.controller == me.controller:
				ev.amount = mini(ev.amount, maxi(0, t.health() - 1))},
	}
	r["VAN_EX1_603"] = {"target": T.MINION, "battlecry": _hit_and_rage}  # Cruel Taskmaster
	r["VAN_CS2_105"] = {"spell": func(g, me, _t): g.buff(g.hero(me.controller), 4, 0, true)}  # Heroic Strike
	r["VAN_CS2_104"] = {"target": [T.MINION, _damaged], "spell": func(g, _me, t): g.buff(t, 3, 3)}  # Rampage
	r["VAN_EX1_391"] = {  # Slam
		"target": T.MINION,
		"spell": func(g, me, t):
			g.damage(me, t, g.spell_dmg(me, 2))
			if t.zone == "PLAY" and t.health() > 0:
				g.draw(me.controller),
	}
	r["VAN_CS2_103"] = {  # Charge
		"target": T.FRIENDLY_MINION,
		"spell": func(g, _me, t):
			g.buff(t, 2, 0)
			t.give_tag("CHARGE"),
	}
	r["VAN_EX1_604"] = {  # Frothing Berserker
		"on": {"damage": func(g, me, ev):
			if g.ent(ev.target).is_minion():
				g.buff(me, 1, 0)},
	}
	r["VAN_EX1_606"] = {  # Shield Block
		"spell": func(g, me, _t):
			g.gain_armor(me.controller, 5)
			g.draw(me.controller),
	}
	r["VAN_EX1_084"] = {  # Warsong Commander (2014): summoned minions with 3 or less Attack get Charge.
		"on": {"summon": func(g, me, ev):
			var m: Entity = g.ent(ev.entity)
			if ev.player == me.controller and m != me and m.atk() <= 3:
				m.give_tag("CHARGE")},
	}
	r["VAN_EX1_398"] = {"battlecry": func(g, me, _t): g.equip(me.controller, "EX1_398t")}  # Arathi Weaponsmith
	r["VAN_EX1_408"] = {  # Mortal Strike
		"target": T.ANY,
		"spell": func(g, me, t):
			var n := 6 if g.hero(me.controller).health() <= 12 else 4
			g.damage(me, t, g.spell_dmg(me, n)),
	}
	r["VAN_EX1_407"] = {  # Brawl
		"can_play": func(g, _me): return g.all_minions().size() >= 2,
		"spell": func(g, _me, _t):
			var all: Array = g.all_minions()
			var keep: Entity = g.random_choice(all)
			for m in all:
				if m != keep:
					g.destroy(m),
	}
	r["VAN_EX1_411"] = {  # Gorehowl: attacking a minion costs 1 Attack instead of 1 Durability.
		"durability_on_attack": func(g, w, defender):
			if not defender.is_minion():
				return true
			g.buff(w, -1, 0)
			if w.atk() <= 0:
				g.destroy(w)
			return false,
	}
	r["VAN_EX1_414"] = {  # Grommash Hellscream: Enrage +6 Attack.
		"aura": func(g, me):
			if me.damage > 0:
				g.aura_add(me, 6, 0),
	}
