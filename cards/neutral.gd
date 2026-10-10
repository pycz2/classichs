extends RefCounted
## Neutral cards and their tokens.


static func register(r: Dictionary) -> void:
	_basic(r)
	_common(r)
	_rare(r)
	_epic(r)
	_legendary(r)
	_legendary_tokens(r)


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
			if ev.get("secret", false):
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


## Faceless Manipulator: transforms me into a copy of t, with t's damage,
## enchantments, keywords and Silence. Auras are not copied; the copy is a new
## minion (summoning sickness, not Frozen).
static func copy_minion(g, me: Entity, t: Entity) -> Entity:
	var n: Entity = g.transform(me, t.card_id)
	if n == null:
		return null
	if t.silenced:
		n.silence()
	n.tags = t.tags.duplicate()
	for k in ["FROZEN", "FROZEN_THIS_TURN", "ATTACKS", "TO_DESTROY", "DIED_POS"]:
		n.tags.erase(k)
	n.give_tag("EXHAUSTED")
	n.enchantments = t.enchantments.duplicate(true)
	n.damage = t.damage
	return n


static func _epic(r: Dictionary) -> void:
	r["VAN_NEW1_017"] = {  # Hungry Crab
		"target": [T.MINION, func(_g, _me, t): return t.race() == "MURLOC"],
		"battlecry": func(g, me, t):
			g.destroy(t)
			g.buff(me, 2, 2),
	}
	r["VAN_NEW1_016"] = {  # Captain's Parrot
		"battlecry": func(g, me, _t):
			var pirates: Array = g.players[me.controller].deck.filter(func(e): return e.race() == "PIRATE")
			var e: Entity = g.random_choice(pirates)
			if e:
				g.draw_entity(me.controller, e),
	}
	r["VAN_NEW1_021"] = {  # Doomsayer
		"on": {"turn_start": func(g, me, ev):
			if ev.player == me.controller:
				for m in g.all_minions():
					g.destroy(m)},
	}
	r["VAN_EX1_005"] = {  # Big Game Hunter
		"target": [T.MINION, func(_g, _me, t): return t.atk() >= 7],
		"battlecry": func(g, _me, t): g.destroy(t),
	}
	r["VAN_EX1_590"] = {  # Blood Knight
		"battlecry": func(g, me, _t):
			var n := 0
			for m in g.all_minions():
				if m.has("DIVINE_SHIELD"):
					m.tags.erase("DIVINE_SHIELD")
					n += 1
			g.buff(me, 3 * n, 3 * n),
	}
	r["VAN_EX1_507"] = {  # Murloc Warleader
		"aura": func(g, me):
			for m in g.all_minions():
				if m != me and m.race() == "MURLOC":
					g.aura_add(m, 2, 1),
	}
	r["VAN_NEW1_027"] = {  # Southsea Captain
		"aura": func(g, me):
			for m in g.others(me):
				if m.race() == "PIRATE":
					g.aura_add(m, 1, 1),
	}
	r["VAN_EX1_564"] = {  # Faceless Manipulator
		"target": [T.MINION, _not_me],
		"battlecry": func(g, me, t): copy_minion(g, me, t),
	}
	r["VAN_EX1_586"] = {  # Sea Giant
		"cost_mod": func(g, _me): return -g.all_minions().size(),
	}
	r["VAN_EX1_105"] = {  # Mountain Giant
		"cost_mod": func(g, me): return -(g.players[me.controller].hand.size() - 1),
	}
	r["VAN_EX1_620"] = {  # Molten Giant
		"cost_mod": func(g, me): return -g.hero(me.controller).damage,
	}


const DREAMS := ["VAN_DREAM_01", "VAN_DREAM_02", "VAN_DREAM_03", "VAN_DREAM_04", "VAN_DREAM_05"]
const CHORDS := ["PRO_001a", "PRO_001b", "VAN_PRO_001c"]
const HORDE := ["VAN_CS2_121", "VAN_CS2_179", "VAN_EX1_023", "VAN_EX1_390", "VAN_EX1_021", "VAN_EX1_110"]
const INVENTIONS := ["Mekka1", "Mekka2", "Mekka3", "Mekka4"]


static func _own_turn_start(fn: Callable) -> Dictionary:
	return {"turn_start": func(g, me, ev):
		if ev.player == me.controller:
			fn.call(g, me)}


static func _own_turn_end(fn: Callable) -> Dictionary:
	return {"turn_end": func(g, me, ev):
		if ev.player == me.controller:
			fn.call(g, me)}


static func _legendary(r: Dictionary) -> void:
	r["VAN_EX1_012"] = {  # Bloodmage Thalnos
		"deathrattle": func(g, me, _ev): g.draw(me.controller),
	}
	r["VAN_EX1_100"] = {  # Lorewalker Cho
		"on": {"play": func(g, _me, ev):
			if ev.kind == "spell":
				g.add_to_hand(g.opponent(ev.player), ev.card)},
	}
	r["VAN_NEW1_029"] = {  # Millhouse Manastorm: enemy spells cost (0) next turn.
		"battlecry": func(g, me, _t):
			g.players[g.opponent(me.controller)].cost_mods.append(
				{"kind": "spell", "set": 0, "until": "turn_end", "turn": g.turn + 1}),
	}
	r["VAN_EX1_557"] = {  # Nat Pagle
		"on": _own_turn_start(func(g, me):
			if g.rng.randi_range(0, 1) == 1:
				g.draw(me.controller)),
	}
	r["VAN_EX1_014"] = {  # King Mukla
		"battlecry": func(g, me, _t):
			for i in 2:
				g.add_to_hand(g.opponent(me.controller), "EX1_014t"),
	}
	r["VAN_EX1_083"] = {  # Tinkmaster Overspark
		"battlecry": func(g, me, _t):
			var t: Entity = g.random_alive(g.all_minions().filter(func(m): return m != me))
			if t:
				g.transform(t, g.random_choice(["VAN_EX1_tk29", "VAN_EX1_tk28"])),
	}
	r["VAN_EX1_116"] = {  # Leeroy Jenkins
		"battlecry": func(g, me, _t):
			for i in 2:
				g.summon(g.opponent(me.controller), "EX1_116t"),
	}
	r["VAN_EX1_062"] = {  # Old Murk-Eye
		"aura": func(g, me):
			var n: int = g.all_minions().filter(func(m): return m != me and m.race() == "MURLOC").size()
			g.aura_add(me, n, 0),
	}
	r["VAN_NEW1_024"] = {  # Captain Greenskin
		"battlecry": func(g, me, _t):
			var w: Entity = _weapon(g, me.controller)
			if w:
				g.buff(w, 1, 0)
				w.tags.DURABILITY = int(w.tags.DURABILITY) + 1,
	}
	r["VAN_PRO_001"] = {  # Elite Tauren Chieftain
		"battlecry": func(g, me, _t):
			for p in [me.controller, g.opponent(me.controller)]:
				g.add_to_hand(p, g.random_choice(CHORDS)),
	}
	r["VAN_EX1_558"] = {  # Harrison Jones
		"battlecry": func(g, me, _t):
			var w: Entity = _weapon(g, g.opponent(me.controller))
			if w:
				var n := int(w.tags.DURABILITY)
				g.destroy(w)
				g.draw(me.controller, n),
	}
	r["VAN_EX1_110"] = {  # Cairne Bloodhoof
		"deathrattle": func(g, me, _ev): g.summon(me.controller, "VAN_EX1_110t", me.tags.DIED_POS),
	}
	r["VAN_EX1_112"] = {  # Gelbin Mekkatorque
		"battlecry": func(g, me, _t): g.summon_right(me, g.random_choice(INVENTIONS)),
	}
	r["VAN_NEW1_040"] = {  # Hogger
		"on": _own_turn_end(func(g, me): g.summon_right(me, "NEW1_040t")),
	}
	r["VAN_EX1_614"] = {  # Illidan Stormrage. 2014: any card you play, The Coin included.
		"on": {"play": func(g, me, ev):
			if ev.player == me.controller and ev.entity != me.id:
				g.summon_right(me, "VAN_TU4e_002t")},
	}
	r["VAN_EX1_016"] = {  # Sylvanas Windrunner
		"deathrattle": func(g, me, _ev):
			var t: Entity = g.random_alive(g.minions(g.opponent(me.controller)))
			if t:
				g.take_control(t, me.controller),
	}
	r["VAN_EX1_577"] = {  # The Beast
		"deathrattle": func(g, me, _ev): g.summon(g.opponent(me.controller), "VAN_EX1_finkle"),
	}
	r["VAN_EX1_002"] = {  # The Black Knight
		"target": [T.ENEMY_MINION, func(_g, _me, t): return t.has("TAUNT")],
		"battlecry": func(g, _me, t): g.destroy(t),
	}
	r["VAN_EX1_249"] = {  # Baron Geddon
		"on": _own_turn_end(func(g, me):
			for c in g.all_chars():
				if c != me:
					g.damage(me, c, 2)),
	}
	r["VAN_NEW1_038"] = {  # Gruul: at the end of each turn.
		"on": {"turn_end": func(g, me, _ev): g.buff(me, 1, 1)},
	}
	r["VAN_EX1_298"] = {  # Ragnaros the Firelord
		"on": _own_turn_end(func(g, me):
			g.damage(me, g.random_alive(g.chars(g.opponent(me.controller))), 8)),
	}
	r["VAN_EX1_561"] = {  # Alexstrasza: set a hero's remaining Health to 15.
		"target": [T.ANY, func(_g, _me, t): return t.is_hero()],
		"battlecry": func(g, _me, t):
			t.damage = maxi(0, t.max_health() - 15)
			g.log_event({"type": "set_health", "target": t.id, "health": t.health()}),
	}
	r["VAN_EX1_562"] = {  # Onyxia: whelps alternate right and left until the side is full.
		"battlecry": func(g, me, _t):
			var board: Array = g.players[me.controller].board
			var right := true
			while board.size() < GameState.MAX_BOARD:
				var i: int = board.find(me)
				g.summon(me.controller, "ds1_whelptoken", i + 1 if right else i)
				right = not right,
	}
	r["VAN_EX1_572"] = {  # Ysera
		"on": _own_turn_end(func(g, me): g.add_to_hand(me.controller, g.random_choice(DREAMS))),
	}
	r["VAN_NEW1_030"] = {  # Deathwing
		"battlecry": func(g, me, _t):
			for m in g.all_minions():
				if m != me:
					g.destroy(m)
			var p: Player = g.players[me.controller]
			for e in p.hand.duplicate():
				p.hand.erase(e)
				e.zone = "GRAVEYARD"
				g.emit({"type": "discard", "player": me.controller, "entity": e.id, "card": e.card_id}),
	}


static func _legendary_tokens(r: Dictionary) -> void:
	r["EX1_014t"] = {  # Bananas
		"target": T.MINION,
		"spell": func(g, _me, t): g.buff(t, 1, 1),
	}
	r["PRO_001a"] = {  # I Am Murloc
		"spell": func(g, me, _t):
			for i in g.rng.randi_range(3, 5):
				g.summon(me.controller, "PRO_001at"),
	}
	r["PRO_001b"] = {  # Rogues Do It...
		"target": T.ANY,
		"spell": func(g, me, t):
			g.damage(me, t, g.spell_dmg(me, 4))
			g.draw(me.controller),
	}
	r["VAN_PRO_001c"] = {  # Power of the Horde
		"spell": func(g, me, _t): g.summon(me.controller, g.random_choice(HORDE)),
	}
	r["Mekka1"] = {  # Homing Chicken
		"on": _own_turn_start(func(g, me):
			g.destroy(me)
			g.draw(me.controller, 3)),
	}
	r["Mekka2"] = {  # Repair Bot
		"on": _own_turn_end(func(g, me):
			var hurt: Array = g.all_chars().filter(func(c): return c.damage > 0 and c.health() > 0)
			var t: Entity = g.random_choice(hurt)
			if t:
				g.heal(me, t, g.heal_amt(me, 6))),
	}
	r["Mekka3"] = {  # Emboldener 3000
		"on": _own_turn_end(func(g, me):
			var t: Entity = g.random_alive(g.all_minions())
			if t:
				g.buff(t, 1, 1)),
	}
	r["Mekka4"] = {  # Poultryizer
		"on": _own_turn_start(func(g, me):
			var t: Entity = g.random_alive(g.all_minions())
			if t:
				g.transform(t, "Mekka4t")),
	}
	r["VAN_DREAM_02"] = {  # Ysera Awakens
		"spell": func(g, me, _t):
			for c in g.all_chars():
				if c.card_id != "VAN_EX1_572":
					g.damage(me, c, g.spell_dmg(me, 5)),
	}
	r["VAN_DREAM_04"] = {  # Dream
		"target": T.MINION,
		"spell": func(g, _me, t): g.return_to_hand(t),
	}
	r["VAN_DREAM_05"] = {  # Nightmare
		"target": T.MINION,
		"spell": func(g, me, t):
			g.buff(t, 5, 5)
			t.add_enchant({"hooks": "ench:nightmare", "player": me.controller}),
	}
	r["ench:nightmare"] = {  # At the start of the caster's next turn, destroy it.
		"on": {"turn_start": func(g, me, ev):
			for e in me.enchantments:
				if e.get("hooks") == "ench:nightmare" and ev.player == e.player:
					g.destroy(me)},
	}
