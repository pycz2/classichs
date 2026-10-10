extends TestCase


func _deck(n: int) -> Array:
	var d := []
	for i in n:
		d.append(H.WISP)
	return d


func test_circle_of_healing() -> void:
	var g := H.scene({"hero": "HERO_09", "damage": 5, "board": [{"card": "VAN_CS2_182", "damage": 4}]},
		{"hero": "HERO_01", "board": [{"card": "VAN_CS2_182", "damage": 2}]})
	H.play(g, H.hand(g, 0, "VAN_EX1_621"))
	eq([g.players[0].board[0].health(), g.players[1].board[0].health(), g.hero(0).health()], [5, 5, 25], "all minions, not heroes")


func test_silence_spell() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS1_042")
	H.play(g, H.hand(g, 0, "VAN_EX1_332"), t)
	check(t.silenced, "silenced")


func test_holy_smite_and_mind_blast() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS1_130"), g.hero(1))
	H.play(g, H.hand(g, 0, "VAN_DS1_233"))
	eq(g.hero(1).health(), 23, "2 + 5")


func test_inner_fire_and_divine_spirit() -> void:
	var g := H.game()
	var w := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_236"), w)
	eq([w.health(), w.max_health()], [10, 10], "health doubled")
	H.play(g, H.hand(g, 0, "VAN_CS1_129"), w)
	eq(w.atk(), 10, "attack = health")


func test_mind_vision() -> void:
	var g := H.game()
	H.hand(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_003"))
	eq(g.players[0].hand.map(func(e): return e.card_id), ["VAN_CS2_182"], "copy")
	eq(g.players[1].hand.size(), 1, "original stays")


func test_northshire_cleric() -> void:
	var g := H.scene({"hero": "HERO_09", "deck": _deck(3), "board": ["VAN_CS2_235", {"card": "VAN_CS2_182", "damage": 2}]})
	H.power(g, g.players[0].board[1])
	eq(g.players[0].hand.size(), 1, "drew on minion heal")
	g.players[0].hero_power.tags.erase("USED")
	g.hero(0).damage = 5
	H.power(g, g.hero(0))
	eq(g.players[0].hand.size(), 1, "hero heal ignored")


func test_power_word_shield() -> void:
	var g := H.scene({"hero": "HERO_09", "deck": _deck(2)})
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_CS2_004"), w)
	eq([w.max_health(), g.players[0].hand.size()], [3, 1], "+2 health, draw")


func test_lightwell() -> void:
	var g := H.scene({"hero": "HERO_09", "damage": 10, "board": ["VAN_EX1_341"], "deck": _deck(2)})
	H.end_turn(g)
	H.end_turn(g)
	eq(g.hero(0).health(), 23, "+3 to the damaged hero")


func test_shadow_words() -> void:
	var g := H.game()
	var small := H.board(g, 1, "VAN_CS2_120")
	var big := H.board(g, 1, "VAN_CS2_201")
	check(not H.play(g, H.hand(g, 0, "VAN_CS2_234"), big).ok, "pain: 3 or less")
	H.play(g, H.hand(g, 0, "VAN_CS2_234"), small)
	check(not H.play(g, H.hand(g, 0, "VAN_EX1_622"), H.board(g, 1, H.WISP)).ok, "death: 5 or more")
	H.play(g, H.hand(g, 0, "VAN_EX1_622"), big)
	eq([small.zone, big.zone], ["GRAVEYARD", "GRAVEYARD"], "both destroyed")


func test_shadowform() -> void:
	var g := H.scene({"hero": "HERO_09"})
	H.power(g, g.hero(1))
	H.play(g, H.hand(g, 0, "VAN_EX1_625"))
	eq(g.players[0].hero_power.card_id, "EX1_625t", "mind spike")
	check(H.power(g, g.hero(1)).ok, "usable again this turn")
	eq(g.hero(1).health(), 28, "2 damage")
	g.players[0].mana = 10
	H.play(g, H.hand(g, 0, "VAN_EX1_625"))
	eq(g.players[0].hero_power.card_id, "EX1_625t2", "mind shatter")


func test_thoughtsteal() -> void:
	var g := H.scene({"hero": "HERO_09"}, {"hero": "HERO_01", "deck": ["VAN_CS2_182", "VAN_CS2_201", H.WISP]})
	H.play(g, H.hand(g, 0, "VAN_EX1_339"))
	eq(g.players[0].hand.size(), 2, "2 copies")
	eq(g.players[1].deck.size(), 3, "deck untouched")


func test_auchenai_soulpriest() -> void:
	var g := H.scene({"hero": "HERO_09"})
	H.board(g, 0, "VAN_EX1_591")
	H.power(g, g.hero(1))
	eq(g.hero(1).health(), 28, "heal deals damage")


func test_lightspawn() -> void:
	var g := H.game()
	var l := H.board(g, 0, "VAN_EX1_335")
	eq(l.atk(), 5, "attack = health")
	H.play(g, H.hand(g, 0, "VAN_CS2_087"), l)  # Blessing of Might
	eq(l.atk(), 5, "attack buffs do not matter")
	g.damage(g.hero(1), l, 2)
	g.resolve()
	eq(l.atk(), 3, "follows damage")
	g.silence(l)
	g.resolve()
	eq(l.atk(), 0, "silenced: plain 0/5")


func test_mass_dispel() -> void:
	var g := H.scene({"hero": "HERO_09", "deck": _deck(2)})
	var e := H.board(g, 1, "VAN_CS1_042")
	var m := H.board(g, 0, "VAN_CS1_042")
	H.play(g, H.hand(g, 0, "VAN_EX1_626"))
	check(e.silenced and not m.silenced, "enemy only")
	eq(g.players[0].hand.size(), 1, "drew")


func test_mindgames() -> void:
	var g := H.scene({"hero": "HERO_09"}, {"hero": "HERO_01", "deck": ["VAN_CS2_029", "VAN_CS2_182"]})
	H.play(g, H.hand(g, 0, "VAN_EX1_345"))
	eq(g.players[0].board[0].card_id, "VAN_CS2_182", "copy of the only minion")
	var g2 := H.scene({"hero": "HERO_09"}, {"hero": "HERO_01", "deck": ["VAN_CS2_029"]})
	H.play(g2, H.hand(g2, 0, "VAN_EX1_345"))
	eq(g2.players[0].board[0].card_id, "VAN_EX1_345t", "Shadow of Nothing")


func test_shadow_madness() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS2_120")
	check(not H.play(g, H.hand(g, 0, "VAN_EX1_334"), H.board(g, 1, "VAN_CS2_182")).ok, "3 or less attack")
	H.play(g, H.hand(g, 0, "VAN_EX1_334"), t)
	eq(t.controller, 0, "stolen")
	check(H.attack(g, t, g.hero(1)).ok, "can attack at once")
	H.end_turn(g)
	eq(t.controller, 1, "returned at end of turn")


func test_shadow_madness_silenced_stays() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS2_120")
	H.play(g, H.hand(g, 0, "VAN_EX1_334"), t)
	g.silence(t)
	H.end_turn(g)
	eq(t.controller, 0, "silence keeps it")


func test_holy_nova() -> void:
	var g := H.scene({"hero": "HERO_09", "damage": 5, "board": [{"card": "VAN_CS2_182", "damage": 3}]},
		{"hero": "HERO_01", "board": ["VAN_CS2_182"]})
	H.play(g, H.hand(g, 0, "VAN_CS1_112"))
	eq([g.hero(1).health(), g.players[1].board[0].health(), g.hero(0).health(), g.players[0].board[0].health()],
		[28, 3, 27, 4], "2 damage enemies, 2 heal friends")


func test_cabal_shadow_priest() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS2_120")
	check(not H.play(g, H.hand(g, 0, "VAN_EX1_091"), H.board(g, 1, "VAN_CS2_182")).ok, "2 or less")
	H.play(g, H.hand(g, 0, "VAN_EX1_091"), t)
	eq(t.controller, 0, "stolen")


func test_holy_fire() -> void:
	var g := H.scene({"hero": "HERO_09", "damage": 10})
	H.play(g, H.hand(g, 0, "VAN_EX1_624"), g.hero(1))
	eq([g.hero(1).health(), g.hero(0).health()], [25, 25], "5 and heal 5")


func test_temple_enforcer() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_623"), w)
	eq(w.max_health(), 4, "+3")


func test_prophet_velen() -> void:
	var g := H.scene({"hero": "HERO_09", "damage": 10})
	H.board(g, 0, "VAN_EX1_350")
	H.play(g, H.hand(g, 0, "VAN_DS1_233"))
	eq(g.hero(1).health(), 20, "mind blast 10")
	H.power(g, g.hero(0))
	eq(g.hero(0).health(), 24, "lesser heal 4")
	H.play(g, H.hand(g, 0, "VAN_EX1_011"), g.hero(0))
	eq(g.hero(0).health(), 26, "voodoo doctor (minion) not doubled")


func test_two_velens_quadruple() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_EX1_350")
	H.board(g, 0, "VAN_EX1_350")
	H.play(g, H.hand(g, 0, "VAN_DS1_233"))
	eq(g.hero(1).health(), 10, "mind blast 20")


func test_mind_control() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS1_113"), t)
	eq(t.controller, 0, "stolen")
	var g2 := H.game()
	for i in 7:
		H.board(g2, 0, H.WISP)
	check(not H.play(g2, H.hand(g2, 0, "VAN_CS1_113"), H.board(g2, 1, H.WISP)).ok, "needs room")
