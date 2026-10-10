extends TestCase


func test_hungry_crab() -> void:
	var g := H.game()
	var m := H.board(g, 1, "VAN_CS2_168")
	var c := H.hand(g, 0, "VAN_NEW1_017")
	check(not H.play(g, c, H.board(g, 1, H.WISP)).ok, "murlocs only")
	H.play(g, c, m)
	eq(m.zone, "GRAVEYARD", "murloc destroyed")
	eq([c.atk(), c.max_health()], [3, 4], "+2/+2")


func test_captains_parrot() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": ["VAN_NEW1_018", H.WISP, H.WISP]})
	H.play(g, H.hand(g, 0, "VAN_NEW1_016"))
	eq(g.players[0].hand.map(func(e): return e.card_id), ["VAN_NEW1_018"], "pirate drawn")
	eq(g.players[0].deck.size(), 2, "deck shrank")


func test_captains_parrot_no_pirate() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": [H.WISP]})
	H.play(g, H.hand(g, 0, "VAN_NEW1_016"))
	eq(g.players[0].hand.size(), 0, "nothing")


func test_doomsayer() -> void:
	var g := H.game()
	var d := H.board(g, 0, "VAN_NEW1_021")
	var e := H.board(g, 1, "VAN_CS2_182")
	H.end_turn(g)
	eq(d.zone, "PLAY", "not on enemy turn")
	H.end_turn(g)
	eq([d.zone, e.zone], ["GRAVEYARD", "GRAVEYARD"], "all destroyed at start of own turn")


func test_big_game_hunter() -> void:
	var g := H.game()
	var big := H.board(g, 1, "VAN_CS2_201")  # Core Hound 9/5
	var small := H.board(g, 1, "VAN_CS2_182")
	check(not H.play(g, H.hand(g, 0, "VAN_EX1_005"), small).ok, "7+ only")
	H.play(g, H.hand(g, 0, "VAN_EX1_005"), big)
	eq(big.zone, "GRAVEYARD", "destroyed")


func test_blood_knight() -> void:
	var g := H.game()
	var a := H.board(g, 0, "VAN_EX1_008")
	var b := H.board(g, 1, "VAN_EX1_008")
	var k := H.hand(g, 0, "VAN_EX1_590")
	H.play(g, k)
	check(not a.has("DIVINE_SHIELD") and not b.has("DIVINE_SHIELD"), "shields gone")
	eq([k.atk(), k.max_health()], [9, 9], "+6/+6")


func test_murloc_warleader() -> void:
	var g := H.game()
	var mine := H.board(g, 0, "VAN_CS2_168")
	var theirs := H.board(g, 1, "VAN_CS2_168")
	var w := H.hand(g, 0, "VAN_EX1_507")
	H.play(g, w)
	eq([mine.atk(), mine.max_health(), theirs.atk(), w.atk()], [4, 2, 4, 3], "other murlocs +2/+1")


func test_southsea_captain() -> void:
	var g := H.game()
	var mine := H.board(g, 0, "VAN_NEW1_018")
	var theirs := H.board(g, 1, "VAN_NEW1_018")
	H.play(g, H.hand(g, 0, "VAN_NEW1_027"))
	eq([mine.atk(), theirs.atk()], [3, 2], "own other pirates")


func test_faceless_copies_damage_and_enchantments() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS2_182")  # Yeti 4/5
	g.buff(t, 2, 2)
	t.damage = 3
	var f := H.hand(g, 0, "VAN_EX1_564")
	H.play(g, f, t)
	var copy := g.players[0].board[0]
	eq(copy.card_id, "VAN_CS2_182", "became a yeti")
	eq([copy.atk(), copy.max_health(), copy.health()], [6, 7, 4], "buffs and damage copied")
	check(copy.has("EXHAUSTED"), "summoning sickness")


func test_faceless_copies_silence() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS1_042")
	g.silence(t)
	H.play(g, H.hand(g, 0, "VAN_EX1_564"), t)
	var copy := g.players[0].board[0]
	check(copy.silenced and not copy.has("TAUNT"), "silenced copy")


func test_faceless_aura_not_copied() -> void:
	var g := H.game()
	H.board(g, 1, "VAN_CS2_222")  # Stormwind Champion
	var t := H.board(g, 1, H.WISP)
	g.update_auras()
	t.damage = 1  # 2/2 with aura, 1 damage
	H.play(g, H.hand(g, 0, "VAN_EX1_564"), t)
	eq(g.players[0].board.size(), 0, "copy dies without the aura")


func test_faceless_cannot_copy_stealthed_enemy() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_EX1_010")  # Worgen Infiltrator, Stealth
	check(not H.play(g, H.hand(g, 0, "VAN_EX1_564"), t).ok, "stealth")


func test_giants_costs() -> void:
	var g := H.scene({"hero": "HERO_08", "damage": 12, "board": [H.WISP, H.WISP]}, {"hero": "HERO_01", "board": [H.WISP]})
	var sea := H.hand(g, 0, "VAN_EX1_586")
	var mountain := H.hand(g, 0, "VAN_EX1_105")
	var molten := H.hand(g, 0, "VAN_EX1_620")
	eq(g.cost(sea), 7, "10 - 3 minions")
	eq(g.cost(mountain), 10, "12 - 2 other cards")
	eq(g.cost(molten), 8, "20 - 12 damage")
