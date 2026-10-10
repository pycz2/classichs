extends TestCase


func _deck(n: int) -> Array:
	var d := []
	for i in n:
		d.append(H.WISP)
	return d


func test_sacrificial_pact() -> void:
	var g := H.scene({"hero": "HERO_07", "damage": 10})
	var d := H.board(g, 1, "VAN_EX1_319")  # Flame Imp, demon
	check(not H.play(g, H.hand(g, 0, "VAN_NEW1_003"), H.board(g, 1, H.WISP)).ok, "demons only")
	H.play(g, H.hand(g, 0, "VAN_NEW1_003"), d)
	eq([d.zone, g.hero(0).health()], ["GRAVEYARD", 25], "destroyed, +5")


func test_sacrificial_pact_kills_jaraxxus_hero() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_323"))
	H.end_turn(g)
	H.play(g, H.hand(g, 1, "VAN_NEW1_003"), g.hero(0))
	check(g.game_over and g.winner == 1, "Jaraxxus destroyed")


func test_soulfire() -> void:
	var g := H.game()
	H.hand(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_308"), g.hero(1))
	eq([g.hero(1).health(), g.players[0].hand.size()], [26, 0], "4 and discard")


func test_blood_imp() -> void:
	var g := H.game()
	var b := H.board(g, 0, "VAN_CS2_059")
	var w := H.board(g, 0, H.WISP)
	check(b.has("STEALTH"), "stealth")
	H.end_turn(g)
	eq(w.max_health(), 2, "+1 health to another")


func test_corruption() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_063"), t)
	H.end_turn(g)
	eq(t.zone, "PLAY", "alive on their turn")
	H.end_turn(g)
	eq(t.zone, "GRAVEYARD", "destroyed at start of my turn")


func test_flame_imp_and_pit_lord() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_319"))
	H.play(g, H.hand(g, 0, "VAN_EX1_313"))
	eq(g.hero(0).health(), 22, "3 + 5 to own hero")


func test_mortal_coil() -> void:
	var g := H.scene({"hero": "HERO_07", "deck": _deck(2)})
	var y := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_302"), y)
	eq(g.players[0].hand.size(), 0, "survived: no draw")
	var w := H.board(g, 1, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_302"), w)
	eq(g.players[0].hand.size(), 1, "killed: draw")


func test_power_overwhelming() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_316"), w)
	eq([w.atk(), w.max_health()], [5, 5], "+4/+4")
	H.end_turn(g)
	eq(w.zone, "GRAVEYARD", "dies at end of turn")


func test_demonfire() -> void:
	var g := H.game()
	var d := H.board(g, 0, "VAN_EX1_319")
	H.play(g, H.hand(g, 0, "VAN_EX1_596"), d)
	eq([d.atk(), d.max_health(), d.health()], [5, 4, 4], "friendly demon +2/+2")
	var y := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_596"), y)
	eq(y.health(), 3, "2 damage otherwise")


func test_felstalker_and_doomguard() -> void:
	var g := H.game()
	for i in 3:
		H.hand(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_306"))
	eq(g.players[0].hand.size(), 2, "discard 1")
	var dg := H.hand(g, 0, "VAN_EX1_310")
	H.play(g, dg)
	eq(g.players[0].hand.size(), 0, "discard 2")
	check(H.attack(g, dg, g.hero(1)).ok, "charge")


func test_drain_life_and_siphon_soul() -> void:
	var g := H.scene({"hero": "HERO_07", "damage": 10})
	H.play(g, H.hand(g, 0, "VAN_CS2_061"), g.hero(1))
	eq([g.hero(1).health(), g.hero(0).health()], [28, 22], "2 and +2")
	var y := H.board(g, 1, "VAN_CS2_182")
	g.players[0].mana = 10
	H.play(g, H.hand(g, 0, "VAN_EX1_309"), y)
	eq([y.zone, g.hero(0).health()], ["GRAVEYARD", 25], "destroy, +3")


func test_felguard() -> void:
	var g := H.game()
	g.players[0].max_mana = 6
	g.players[0].mana = 6
	H.play(g, H.hand(g, 0, "VAN_EX1_301"))
	eq([g.players[0].max_mana, g.players[0].mana], [5, 3], "one crystal destroyed")


func test_sense_demons() -> void:
	var g := H.scene({"hero": "HERO_07", "deck": ["VAN_EX1_319", H.WISP, H.WISP]})
	H.play(g, H.hand(g, 0, "VAN_EX1_317"))
	eq(g.players[0].hand.map(func(e): return e.card_id).duplicate(), ["VAN_EX1_319", "EX1_317t"], "demon + worthless imp")


func test_shadow_bolt() -> void:
	var g := H.game()
	var y := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_057"), y)
	eq(y.health(), 1, "4")
	check(not H.play(g, H.hand(g, 0, "VAN_CS2_057"), g.hero(1)).ok, "minions only")


func test_void_terror() -> void:
	var g := H.game()
	var a := H.board(g, 0, "VAN_CS2_182")
	var b := H.board(g, 0, "VAN_CS2_120")
	var v := H.hand(g, 0, "VAN_EX1_304")
	H.play(g, v, null, 1)
	eq([a.zone, b.zone], ["GRAVEYARD", "GRAVEYARD"], "neighbours destroyed")
	eq([v.atk(), v.max_health()], [9, 11], "3+4+2 / 3+5+3")


func test_hellfire_and_dread_infernal() -> void:
	var g := H.game()
	var w := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_062"))
	eq([g.hero(0).health(), g.hero(1).health(), w.health()], [27, 27, 2], "3 to all")
	var d := H.hand(g, 0, "VAN_CS2_064")
	g.players[0].mana = 10
	H.play(g, d)
	eq([g.hero(0).health(), w.health(), d.health()], [26, 1, 6], "1 to all others")


func test_shadowflame() -> void:
	var g := H.game()
	var mine := H.board(g, 0, "VAN_CS2_182")
	var e := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_303"), mine)
	eq([mine.zone, e.health(), g.hero(1).health()], ["GRAVEYARD", 1, 30], "4 to enemy minions")


func test_summoning_portal() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_EX1_315")
	eq([g.cost(H.hand(g, 0, "VAN_CS2_182")), g.cost(H.hand(g, 0, "VAN_CS2_120")), g.cost(H.hand(g, 0, H.WISP)),
		g.cost(H.hand(g, 0, "VAN_CS2_029"))], [2, 1, 0, 4], "minions -2, not below 1")


func test_bane_of_doom() -> void:
	var g := H.game()
	var w := H.board(g, 1, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_320"), w)
	eq(g.players[0].board.size(), 1, "demon summoned")
	eq(g.players[0].board[0].race(), "DEMON", "a demon")
	var y := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_320"), y)
	eq(g.players[0].board.size(), 1, "survived: nothing")


func test_twisting_nether() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_CS2_182")
	H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_312"))
	eq(g.all_minions().size(), 0, "all destroyed")


func test_lord_jaraxxus() -> void:
	var g := H.scene({"hero": "HERO_07", "damage": 20, "armor": 5, "weapon": "VAN_CS2_106", "secrets": ["VAN_EX1_132"]})
	var j := H.hand(g, 0, "VAN_EX1_323")
	H.play(g, j)
	var hero := g.hero(0)
	eq([hero.card_id, hero.health(), hero.max_health(), int(hero.tags.ARMOR)], ["EX1_323h", 15, 15, 0], "new hero")
	eq(g.players[0].weapon.card_id, "EX1_323w", "Blood Fury")
	eq(g.players[0].hero_power.card_id, "VAN_EX1_tk33", "INFERNO!")
	eq(g.players[0].secrets.size(), 1, "secrets kept")
	eq(g.players[0].board.size(), 0, "minion gone")
	g.players[0].mana = 10
	check(H.power(g).ok, "INFERNO! usable this turn")
