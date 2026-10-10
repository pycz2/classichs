extends TestCase


func _deck(n: int) -> Array:
	var d := []
	for i in n:
		d.append(H.WISP)
	return d


func test_backstab() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_072"), t)
	eq(t.health(), 3, "2 damage")
	check(not H.play(g, H.hand(g, 0, "VAN_CS2_072"), t).ok, "undamaged only")


func test_preparation() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_145"))
	var fb := H.hand(g, 0, "VAN_CS2_029")
	var y := H.hand(g, 0, "VAN_CS2_182")
	eq([g.cost(fb), g.cost(y)], [1, 4], "next spell -3")
	H.play(g, fb, g.hero(1))
	eq(g.cost(H.hand(g, 0, "VAN_CS2_029")), 4, "only one spell")


func test_shadowstep() -> void:
	var g := H.game()
	var y := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_144"), y)
	var back: Entity = g.players[0].hand[0]
	eq([back.card_id, g.cost(back)], ["VAN_CS2_182", 2], "back, costs 2 less")


func test_cold_blood_and_combo() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_CS2_073"), w)
	eq(w.atk(), 3, "+2")
	H.play(g, H.hand(g, 0, "VAN_CS2_073"), w)
	eq(w.atk(), 7, "combo +4")


func test_conceal() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_128"))
	check(w.has("STEALTH"), "stealth")
	H.end_turn(g)
	check(w.has("STEALTH"), "through enemy turn")
	H.end_turn(g)
	check(not w.has("STEALTH"), "gone at my next turn")


func test_deadly_poison() -> void:
	var g := H.scene({"hero": "HERO_03", "weapon": "VAN_CS2_082"})
	H.play(g, H.hand(g, 0, "VAN_CS2_074"))
	eq(g.players[0].weapon.atk(), 3, "+2")
	var g2 := H.game()
	check(not H.play(g2, H.hand(g2, 0, "VAN_CS2_074")).ok, "needs a weapon")


func test_sinister_strike() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_075"))
	eq(g.hero(1).health(), 27, "3")


func test_betrayal() -> void:
	var g := H.game()
	var a := H.board(g, 1, "VAN_CS2_182")
	var b := H.board(g, 1, "VAN_CS2_201")  # 9 attack
	var c := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_126"), b)
	eq([a.zone, b.health(), c.zone], ["GRAVEYARD", 5, "GRAVEYARD"], "neighbours take 9")


func test_blade_flurry() -> void:
	var g := H.scene({"hero": "HERO_03", "weapon": "VAN_CS2_080"})  # 3/4
	var e := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_233"))
	eq([e.health(), g.hero(1).health()], [2, 27], "3 to all enemies")
	eq(g.players[0].weapon, null, "weapon destroyed")


func test_defias_ringleader() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_131"))
	eq(g.players[0].board.size(), 1, "no combo")
	H.play(g, H.hand(g, 0, "VAN_EX1_131"))
	eq(g.players[0].board[2].card_id, "EX1_131t", "bandit on combo")


func test_eviscerate() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_124"), g.hero(1))
	H.play(g, H.hand(g, 0, "VAN_EX1_124"), g.hero(1))
	eq(g.hero(1).health(), 24, "2 then 4")


func test_patient_assassin() -> void:
	var g := H.game()
	var a := H.board(g, 0, "VAN_EX1_522")
	check(a.has("STEALTH"), "stealth")
	var y := H.board(g, 1, "VAN_CS2_182")
	H.attack(g, a, y)
	eq(y.zone, "GRAVEYARD", "destroyed")


func test_sap_and_assassinate() -> void:
	var g := H.game()
	var a := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_581"), a)
	eq(g.players[1].hand.back().card_id, "VAN_CS2_182", "sapped")
	var b := H.board(g, 1, "VAN_CS2_201")
	H.play(g, H.hand(g, 0, "VAN_CS2_076"), b)
	eq(b.zone, "GRAVEYARD", "assassinated")


func test_shiv_and_fan_of_knives() -> void:
	var g := H.scene({"hero": "HERO_03", "deck": _deck(3)})
	var w := H.board(g, 1, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_278"), g.hero(1))
	H.play(g, H.hand(g, 0, "VAN_EX1_129"))
	eq([g.hero(1).health(), w.zone, g.players[0].hand.size()], [29, "GRAVEYARD", 2], "1 + fan, 2 draws")


func test_edwin_vancleef() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "GAME_005"))
	H.play(g, H.hand(g, 0, "GAME_005"))
	var e := H.hand(g, 0, "VAN_EX1_613")
	H.play(g, e)
	eq([e.atk(), e.max_health()], [6, 6], "+2/+2 per earlier card")


func test_headcrack() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_137"))
	eq(g.hero(1).health(), 28, "2")
	H.play(g, H.hand(g, 0, "GAME_005"))
	H.play(g, H.hand(g, 0, "VAN_EX1_137"))
	H.end_turn(g)
	eq(g.players[0].hand.size(), 0, "not on enemy turn")
	H.end_turn(g)
	check(g.players[0].hand.any(func(e): return e.card_id == "VAN_EX1_137"), "back next turn")


func test_perditions_blade() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_133"), g.hero(1))
	eq(g.hero(1).health(), 29, "1")
	H.play(g, H.hand(g, 0, "VAN_EX1_133"), g.hero(1))
	eq(g.hero(1).health(), 27, "combo 2")


func test_si7_agent() -> void:
	var g := H.game()
	var a := H.hand(g, 0, "VAN_EX1_134")
	check(not H.play(g, a, g.hero(1)).ok, "no target without combo")
	H.play(g, a)
	H.play(g, H.hand(g, 0, "VAN_EX1_134"), g.hero(1))
	eq(g.hero(1).health(), 28, "combo 2")


func test_master_of_disguise() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_NEW1_014"), w)
	check(w.has("STEALTH"), "stealth")


func test_kidnapper() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "GAME_005"))
	H.play(g, H.hand(g, 0, "VAN_NEW1_005"), t)
	eq(g.players[1].hand.back().card_id, "VAN_CS2_182", "returned")


func test_vanish() -> void:
	var g := H.game()
	H.board(g, 0, H.WISP)
	H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_NEW1_004"))
	eq(g.all_minions().size(), 0, "board empty")
	eq([g.players[0].hand.size(), g.players[1].hand.size()], [1, 1], "back to owners")


func test_vanish_full_hand_destroys() -> void:
	var g := H.game()
	H.board(g, 0, H.WISP)
	for i in 10:
		H.hand(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_NEW1_004"))
	eq(g.players[0].hand.size(), 10, "no room: destroyed")
	eq(g.all_minions().size(), 0, "not on board either")


func test_sprint() -> void:
	var g := H.scene({"hero": "HERO_03", "deck": _deck(5)})
	H.play(g, H.hand(g, 0, "VAN_CS2_077"))
	eq(g.players[0].hand.size(), 4, "draw 4")
