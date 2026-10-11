extends TestCase


func _boss(hero: String, power: String, board := [], hand := []) -> Game:
	return H.scene({"hero": "HERO_08", "deck": [H.WISP, H.WISP]},
		{"hero": hero, "hero_power": power, "board": board, "hand": hand, "deck": [H.WISP, H.WISP]}, 1)


func test_locked_hero_power_not_legal() -> void:
	var r := Scenario.build({"players": [{"hero": "HERO_08", "mana": 10, "max_mana": 10, "hero_power_locked": true}, {"hero": "HERO_01"}]})
	eq(r.error, "", "built")
	var g: Game = r.game
	check(g.players[0].hero_power.has("LOCKED"), "tag")
	check(not g.legal_actions().any(func(a): return a.type == "hero_power"), "not offered")
	check(Scenario.dump(g).players[0].get("hero_power_locked", false), "dumped")


func test_hogger_smash() -> void:
	var g := _boss("TU4a_001", "VAN_HERO_08bp", [], ["TU4a_004"])
	H.play(g, g.players[1].hand[0], g.hero(0))
	eq(g.hero(0).health(), 26, "4 damage")


func test_mukla_cards() -> void:
	var g := _boss("TU4c_001", "VAN_HERO_08bp", ["TU4c_003"], ["TU4c_002", "TU4c_004", "TU4c_006", "TU4c_008"])
	var m := H.board(g, 0, "VAN_CS2_182")
	var p := g.players[1]
	H.play(g, p.hand[0], g.hero(0))  # Barrel Toss
	eq(g.hero(0).health(), 28, "barrel toss 2")
	H.play(g, p.hand[0])  # Stomp
	eq([g.hero(0).health(), m.health()], [26, 3], "stomp 2 to all enemies")
	var barrel: Entity = p.board[0]
	H.play(g, p.hand[0], barrel)  # Bananas on a friendly minion
	eq(barrel.max_health(), 3, "bananas +1/+1")
	g.hero(1).damage = 10
	H.play(g, p.hand[0], g.hero(1))  # Will of Mukla
	eq(g.hero(1).health(), 24, "heal 8 (26 max)")
	g.destroy(barrel)
	g.resolve()
	eq(p.board[0].card_id, "TU4c_005", "hidden gnome out of the barrel")


func test_crazy_monkey_throws_bananas() -> void:
	var g := _boss("TU4c_001", "VAN_HERO_08bp", [], ["TU4f_007"])
	H.play(g, g.players[1].hand[0])
	eq(g.players[1].hand.map(func(e): return e.card_id), ["TU4c_006"], "bananas in hand")


func test_hemet_and_illidan_powers() -> void:
	var g := H.scene({"hero": "HERO_08"}, {"hero": "TU4d_001", "hero_power": "TU4d_003"}, 1)
	H.power(g, g.hero(0))
	eq(g.hero(0).health(), 29, "shotgun blast 1")
	var g2 := H.scene({"hero": "HERO_08"}, {"hero": "TU4e_001", "hero_power": "TU4e_002"}, 1)
	H.power(g2)
	eq(g2.players[1].board.map(func(m): return m.card_id), ["TU4e_002t", "TU4e_002t"], "two flames")


func test_flame_burst() -> void:
	var g := _boss("TU4e_001", "TU4e_002", [], ["TU4e_005"])
	H.play(g, g.players[1].hand[0])
	eq(g.hero(0).health(), 25, "5 missiles at the only enemy")


func test_legacy_of_the_emperor() -> void:
	var g := _boss("TU4f_001", "VAN_HERO_08bp", ["TU4f_002", "TU4f_003"], ["TU4f_004"])
	H.play(g, g.players[1].hand[0])
	eq(g.players[1].board.map(func(m): return m.atk()), [3, 4], "+2 attack")


func test_transcendence() -> void:
	var g := _boss("TU4f_001", "VAN_HERO_08bp", ["TU4f_002"], ["TU4f_006"])
	H.play(g, g.players[1].hand[0])
	H.end_turn(g)
	var w := H.board(g, 0, "VAN_CS2_120")
	check(not g.legal_actions().any(func(a): return a.type == "attack" and a.defender == g.hero(1).id), "Cho can't be attacked")
	check(not g.targets(g.hero(0), T.ENEMY_CHAR, true).has(g.hero(1)), "Cho can't be targeted")
	H.attack(g, w, g.players[1].board[0])
	check(not g.hero(1).has("STEALTH"), "minions dead: Cho can be attacked again")



func test_flame_burst_spell_damage_boosts_each_missile() -> void:
	var g := _boss("TU4e_001", "TU4e_002", ["VAN_CS2_142"], ["TU4e_005"])  # Kobold Geomancer: +1
	H.play(g, g.players[1].hand[0])
	eq(g.hero(0).health(), 20, "5 missiles of 2 damage")
