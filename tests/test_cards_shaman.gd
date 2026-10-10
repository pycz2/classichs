extends TestCase


func test_keyword_and_overload_cards() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_243"))  # Dust Devil
	eq(g.players[0].overload_owed, 2, "overload 2")
	H.play(g, H.hand(g, 0, "VAN_EX1_567"))  # Doomhammer
	var hero := g.hero(0)
	check(H.attack(g, hero, g.hero(1)).ok and H.attack(g, hero, g.hero(1)).ok, "windfury weapon")
	var al := H.hand(g, 0, "VAN_NEW1_010")
	for m in ["CHARGE", "DIVINE_SHIELD", "TAUNT", "WINDFURY"]:
		check(al.has(m), "Al'Akir " + m)


func test_ancestral_healing() -> void:
	var g := H.game()
	var y := H.board(g, 0, "VAN_CS2_182")
	y.damage = 4
	H.play(g, H.hand(g, 0, "VAN_CS2_041"), y)
	eq([y.health(), y.has("TAUNT")], [5, true], "full health and taunt")


func test_totemic_might() -> void:
	var g := H.game()
	var t := H.board(g, 0, "VAN_EX1_565")
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_244"))
	eq([t.max_health(), w.max_health()], [5, 1], "totems only")


func test_earth_shock() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_EX1_008")  # Argent Squire, divine shield
	H.play(g, H.hand(g, 0, "VAN_EX1_245"), t)
	eq(t.zone, "GRAVEYARD", "silence removes the shield first")


func test_forked_lightning() -> void:
	var g := H.game()
	H.board(g, 1, "VAN_CS2_182")
	check(not H.play(g, H.hand(g, 0, "VAN_EX1_251")).ok, "needs 2 enemy minions")
	H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_251"))
	eq(g.players[1].board.map(func(m): return m.health()), [3, 3], "2 each")
	eq(g.players[0].overload_owed, 2, "overload")


func test_frost_shock() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_037"), g.hero(1))
	check(g.hero(1).health() == 29 and g.hero(1).has("FROZEN"), "1 and freeze")
	check(not H.play(g, H.hand(g, 0, "VAN_CS2_037"), g.hero(0)).ok, "enemies only")


func test_lightning_bolt_and_lava_burst() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_238"), g.hero(1))
	H.play(g, H.hand(g, 0, "VAN_EX1_241"), g.hero(1))
	eq([g.hero(1).health(), g.players[0].overload_owed], [22, 3], "3 + 5, overload 1 + 2")


func test_rockbiter_weapon() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_045"), g.hero(0))
	eq(g.hero_atk(g.hero(0)), 3, "+3 hero")
	H.end_turn(g)
	eq(g.hero(0).atk(), 0, "this turn only")


func test_ancestral_spirit() -> void:
	var g := H.game()
	var y := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_038"), y)
	g.destroy(y)
	g.resolve()
	var back: Entity = g.players[0].board[0]
	eq([back.card_id, back.health()], ["VAN_CS2_182", 5], "returns fresh")


func test_flametongue_totem() -> void:
	var g := H.game()
	var a := H.board(g, 0, H.WISP)
	var b := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_565"), null, 1)
	eq([a.atk(), b.atk()], [3, 3], "+2 adjacent")


func test_windfury_and_windspeaker() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_CS2_039"), w)
	check(w.has("WINDFURY"), "windfury spell")
	var v := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_587"), v)
	check(v.has("WINDFURY"), "windspeaker")


func test_far_sight() -> void:
	var g := H.scene({"hero": "HERO_02", "deck": ["VAN_CS2_182"]})
	H.play(g, H.hand(g, 0, "VAN_CS2_053"))
	eq(g.cost(g.players[0].hand[0]), 1, "4 - 3")


func test_feral_spirit() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_248"))
	eq(g.players[0].board.map(func(m): return m.card_id), ["VAN_EX1_tk11", "VAN_EX1_tk11"], "2 wolves")
	check(g.players[0].board[0].has("TAUNT"), "taunt")


func test_hex() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS2_201")
	H.play(g, H.hand(g, 0, "VAN_EX1_246"), t)
	var f: Entity = g.players[1].board[0]
	eq([f.card_id, f.has("TAUNT")], ["hexfrog", true], "frog")


func test_lightning_storm() -> void:
	var g := H.game()
	H.board(g, 1, "VAN_CS2_182")
	H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_259"))
	for m in g.players[1].board:
		check(m.damage == 2 or m.damage == 3, "2-3 damage: %d" % m.damage)


func test_mana_tide_totem() -> void:
	var g := H.scene({"hero": "HERO_02", "deck": [H.WISP, H.WISP], "board": ["VAN_EX1_575"]})
	H.end_turn(g)
	eq(g.players[0].hand.size(), 1, "drew at end of turn")


func test_unbound_elemental() -> void:
	var g := H.game()
	var u := H.board(g, 0, "VAN_EX1_258")
	H.play(g, H.hand(g, 0, "VAN_EX1_238"), g.hero(1))
	H.play(g, H.hand(g, 0, H.WISP))
	eq([u.atk(), u.max_health()], [3, 5], "+1/+1 only for overload")


func test_bloodlust() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_CS2_046"))
	eq(w.atk(), 4, "+3")
	H.end_turn(g)
	eq(w.atk(), 1, "this turn only")


func test_fire_elemental() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_042"), g.hero(1))
	eq(g.hero(1).health(), 27, "3")
