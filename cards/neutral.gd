extends RefCounted
## Neutral cards and their tokens.


static func register(r: Dictionary) -> void:
	_basic(r)
	_common(r)
	_rare(r)


static func _not_me(_g, me, t) -> bool:
	return t != me


## Enrage: while damaged, the minion gets atk and tags.
static func _enrage(atk: int, tags := {}) -> Callable:
	return func(g, me):
		if me.damage > 0:
			g.aura_add(me, atk, 0, tags)


static func _weapon(g, p: int) -> Entity:
	return g.players[p].weapon


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


static func _common(r: Dictionary) -> void:
	r["VAN_CS2_188"] = {  # Abusive Sergeant
		"target": T.MINION,
		"battlecry": func(g, _me, t): g.buff(t, 2, 0, true),
	}
	r["VAN_EX1_029"] = {  # Leper Gnome
		"deathrattle": func(g, me, _ev): g.damage(me, g.hero(g.opponent(me.controller)), 2),
	}
	r["VAN_CS2_146"] = {  # Southsea Deckhand
		"aura": func(g, me):
			if _weapon(g, me.controller):
				g.aura_add(me, 0, 0, {"CHARGE": true}),
	}
	r["VAN_EX1_393"] = {"aura": _enrage(3)}  # Amani Berserker
	r["VAN_NEW1_018"] = {  # Bloodsail Raider
		"battlecry": func(g, me, _t):
			var w: Entity = _weapon(g, me.controller)
			if w:
				g.buff(me, w.atk(), 0),
	}
	r["VAN_EX1_162"] = {  # Dire Wolf Alpha
		"aura": func(g, me):
			for m in g.adjacent(me):
				g.aura_add(m, 1, 0),
	}
	r["VAN_CS2_203"] = {  # Ironbeak Owl
		"target": T.MINION,
		"battlecry": func(g, _me, t): g.silence(t),
	}
	r["VAN_EX1_096"] = {  # Loot Hoarder
		"deathrattle": func(g, me, _ev): g.draw(me.controller),
	}
	r["VAN_EX1_082"] = {  # Mad Bomber: 3 damage randomly split between all other characters.
		"battlecry": func(g, me, _t):
			for i in 3:
				var pool: Array = g.all_chars().filter(func(c): return c != me and c.health() > 0)
				g.damage(me, g.random_choice(pool), 1),
	}
	r["VAN_EX1_049"] = {  # Youthful Brewmaster
		"target": [T.FRIENDLY_MINION, _not_me],
		"battlecry": func(g, _me, t): g.return_to_hand(t),
	}
	r["VAN_EX1_007"] = {  # Acolyte of Pain
		"on": {"damage": func(g, me, ev):
			if ev.target == me.id:
				g.draw(me.controller)},
	}
	r["VAN_CS2_117"] = {  # Earthen Ring Farseer
		"target": T.ANY,
		"battlecry": func(g, me, t): g.heal(me, t, g.heal_amt(me, 3)),
	}
	r["VAN_tt_004"] = {  # Flesheating Ghoul
		"on": {"death": func(g, me, ev):
			if ev.minion:
				g.buff(me, 1, 0)},
	}
	r["VAN_EX1_556"] = {  # Harvest Golem
		"deathrattle": func(g, me, _ev): g.summon(me.controller, "VAN_skele21", me.tags.DIED_POS),
	}
	r["VAN_EX1_412"] = {"aura": _enrage(1, {"WINDFURY": true})}  # Raging Worgen
	r["VAN_EX1_390"] = {"aura": _enrage(3)}  # Tauren Warrior
	r["VAN_EX1_057"] = {  # Ancient Brewmaster
		"target": [T.FRIENDLY_MINION, _not_me],
		"battlecry": func(g, _me, t): g.return_to_hand(t),
	}
	r["VAN_EX1_595"] = {  # Cult Master. 2014: no draw if it dies at the same time.
		"on": {"death": func(g, me, ev):
			if ev.minion and ev.player == me.controller:
				g.draw(me.controller)},
	}
	r["VAN_EX1_046"] = {  # Dark Iron Dwarf
		"target": T.MINION,
		"battlecry": func(g, _me, t): g.buff(t, 2, 0, true),
	}
	r["VAN_NEW1_022"] = {  # Dread Corsair
		"cost_mod": func(g, me):
			var w: Entity = _weapon(g, me.controller)
			return -w.atk() if w else 0,
	}
	r["VAN_EX1_048"] = {  # Spellbreaker
		"target": T.MINION,
		"battlecry": func(g, _me, t): g.silence(t),
	}
	r["VAN_CS2_151"] = {  # Silver Hand Knight
		"battlecry": func(g, me, _t): g.summon_right(me, "VAN_CS2_152"),
	}
	r["VAN_CS2_221"] = {  # Spiteful Smith
		"aura": func(g, me):
			var w: Entity = _weapon(g, me.controller)
			if w and me.damage > 0:
				g.aura_add(w, 2, 0),
	}
	r["VAN_CS2_227"] = {  # Venture Co. Mercenary
		"cost_aura": func(_g, me, card, c):
			return c + 3 if card.controller == me.controller and card.is_minion() and card.zone == "HAND" else c,
	}
	r["VAN_EX1_283"] = {  # Frost Elemental
		"target": T.ANY,
		"battlecry": func(g, _me, t): g.freeze(t),
	}
	r["VAN_EX1_583"] = {  # Priestess of Elune
		"battlecry": func(g, me, _t): g.heal(me, g.hero(me.controller), g.heal_amt(me, 4)),
	}


static func _rare(r: Dictionary) -> void:
	r["VAN_EX1_009"] = {"aura": _enrage(5)}  # Angry Chicken
	r["VAN_NEW1_025"] = {  # Bloodsail Corsair
		"battlecry": func(g, me, _t):
			var w: Entity = _weapon(g, g.opponent(me.controller))
			if w:
				w.tags.DURABILITY = int(w.tags.DURABILITY) - 1,
	}
	r["VAN_EX1_001"] = {  # Lightwarden
		"on": {"heal": func(g, me, _ev): g.buff(me, 2, 0)},
	}
	r["VAN_EX1_509"] = {  # Murloc Tidecaller
		"on": {"summon": func(g, me, ev):
			if ev.entity != me.id and g.ent(ev.entity).race() == "MURLOC":
				g.buff(me, 1, 0)},
	}
	r["VAN_EX1_080"] = {  # Secretkeeper
		"on": {"play": func(g, me, ev):
			if ev.kind == "secret":
				g.buff(me, 1, 1)},
	}
	r["VAN_EX1_004"] = {  # Young Priestess
		"on": {"turn_end": func(g, me, ev):
			if ev.player == me.controller:
				var t: Entity = g.random_alive(g.others(me))
				if t:
					g.buff(t, 0, 1)},
	}
	r["VAN_EX1_059"] = {  # Crazed Alchemist
		"target": T.MINION,
		"battlecry": func(g, _me, t): g.set_stats(t, t.health(), t.atk()),
	}
	r["VAN_NEW1_019"] = {  # Knife Juggler
		"on": {"after_summon": func(g, me, ev):
			if ev.player == me.controller and ev.entity != me.id:
				g.damage(me, g.random_alive(g.chars(g.opponent(me.controller))), 1)},
	}
	r["VAN_EX1_055"] = {  # Mana Addict
		"on": {"play": func(g, me, ev):
			if ev.kind == "spell" and ev.player == me.controller:
				g.buff(me, 2, 0, true)},
	}
	r["VAN_EX1_616"] = {  # Mana Wraith
		"cost_aura": func(_g, _me, card, c): return c + 1 if card.is_minion() and card.zone == "HAND" else c,
	}
	r["VAN_NEW1_037"] = {  # Master Swordsmith
		"on": {"turn_end": func(g, me, ev):
			if ev.player == me.controller:
				var t: Entity = g.random_alive(g.others(me))
				if t:
					g.buff(t, 1, 0)},
	}
	r["VAN_EX1_076"] = {  # Pint-Sized Summoner
		"cost_aura": func(g, me, card, c):
			var first: bool = g.players[me.controller].minions_played_this_turn == 0
			return c - 1 if first and card.controller == me.controller and card.is_minion() and card.zone == "HAND" else c,
	}
	r["VAN_EX1_058"] = {  # Sunfury Protector
		"battlecry": func(g, me, _t):
			for m in g.adjacent(me):
				m.give_tag("TAUNT"),
	}
	r["VAN_NEW1_020"] = {  # Wild Pyromancer
		"on": {"after_spell": func(g, me, ev):
			if ev.player == me.controller:
				for m in g.all_minions():
					g.damage(me, m, 1)},
	}
	r["VAN_EX1_006"] = {  # Alarm-o-Bot
		"on": {"turn_start": func(g, me, ev):
			if ev.player != me.controller:
				return
			var p: Player = g.players[me.controller]
			var m: Entity = g.random_choice(p.hand.filter(func(e): return e.is_minion()))
			if m == null:
				return
			var pos := p.board.find(me)
			p.hand.erase(m)
			g.return_to_hand(me)
			g.summon_entity(m, pos)},
	}
	r["VAN_EX1_089"] = {  # Arcane Golem
		"battlecry": func(g, me, _t): g.gain_mana(g.opponent(me.controller), 1),
	}
	r["VAN_EX1_050"] = {  # Coldlight Oracle
		"battlecry": func(g, me, _t):
			g.draw(me.controller, 2)
			g.draw(g.opponent(me.controller), 2),
	}
	r["VAN_EX1_103"] = {  # Coldlight Seer
		"battlecry": func(g, me, _t):
			for m in g.all_minions():
				if m != me and m.race() == "MURLOC":
					g.buff(m, 0, 2),
	}
	r["VAN_EX1_102"] = {  # Demolisher
		"on": {"turn_start": func(g, me, ev):
			if ev.player == me.controller:
				g.damage(me, g.random_alive(g.chars(g.opponent(me.controller))), 2)},
	}
	r["VAN_EX1_170"] = {  # Emperor Cobra
		"on": {"damage": func(g, me, ev):
			var t: Entity = g.ent(ev.target)
			if ev.source == me.id and t.is_minion():
				g.destroy(t)},
	}
	r["VAN_EX1_597"] = {  # Imp Master
		"on": {"turn_end": func(g, me, ev):
			if ev.player == me.controller:
				g.damage(me, me, 1)
				g.summon_right(me, "VAN_EX1_598")},
	}
	r["VAN_CS2_181"] = {  # Injured Blademaster
		"battlecry": func(g, me, _t): g.damage(me, me, 4),
	}
	r["VAN_EX1_085"] = {  # Mind Control Tech
		"battlecry": func(g, me, _t):
			var enemy: Array = g.minions(g.opponent(me.controller))
			if enemy.size() >= 4:
				g.take_control(g.random_choice(enemy), me.controller),
	}
	r["VAN_EX1_044"] = {  # Questing Adventurer
		"on": {"play": func(g, me, ev):
			if ev.player == me.controller and ev.entity != me.id:
				g.buff(me, 1, 1)},
	}
	r["VAN_EX1_584"] = {  # Ancient Mage
		"battlecry": func(g, me, _t):
			for m in g.adjacent(me):
				m.tags["SPELLPOWER"] = int(m.tags.get("SPELLPOWER", 0)) + 1,
	}
	r["VAN_EX1_093"] = {  # Defender of Argus
		"battlecry": func(g, me, _t):
			for m in g.adjacent(me):
				g.buff(m, 1, 1)
				m.give_tag("TAUNT"),
	}
	r["VAN_EX1_043"] = {  # Twilight Drake
		"battlecry": func(g, me, _t): g.buff(me, 0, g.players[me.controller].hand.size()),
	}
	r["VAN_NEW1_026"] = {  # Violet Teacher
		"on": {"play": func(g, me, ev):
			if ev.kind == "spell" and ev.player == me.controller:
				g.summon_right(me, "VAN_NEW1_026t")},
	}
	r["VAN_EX1_097"] = {  # Abomination
		"deathrattle": func(g, me, _ev):
			for c in g.all_chars():
				g.damage(me, c, 2),
	}
	r["VAN_EX1_284"] = {  # Azure Drake
		"battlecry": func(g, me, _t): g.draw(me.controller),
	}
	r["VAN_EX1_095"] = {  # Gadgetzan Auctioneer
		"on": {"play": func(g, me, ev):
			if ev.kind == "spell" and ev.player == me.controller:
				g.draw(me.controller)},
	}
	r["VAN_NEW1_041"] = {  # Stampeding Kodo
		"battlecry": func(g, me, _t):
			var small: Array = g.minions(g.opponent(me.controller)).filter(func(m): return m.atk() <= 2)
			g.destroy(g.random_alive(small)),
	}
