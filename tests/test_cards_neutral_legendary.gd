extends TestCase


func _deck(n: int) -> Array:
	var d := []
	for i in n:
		d.append(H.WISP)
	return d


func test_bloodmage_thalnos() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": _deck(2)})
	var t := H.board(g, 0, "VAN_EX1_012")
	eq(g.spell_dmg(g.hero(0), 1), 2, "spell damage +1")
	g.destroy(t)
	g.resolve()
	eq(g.players[0].hand.size(), 1, "drew")


func test_lorewalker_cho() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_EX1_100")
	H.play(g, H.hand(g, 0, "GAME_005"))
	eq(g.players[1].hand.map(func(e): return e.card_id), ["GAME_005"], "copy to the other player")


func test_millhouse_manastorm() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_NEW1_029"))
	var fb := H.hand(g, 1, "VAN_CS2_029")
	eq(g.cost(fb), 4, "not on my turn")
	H.end_turn(g)
	eq(g.cost(fb), 0, "free on their next turn")
	eq(g.cost(H.hand(g, 1, "VAN_CS2_182")), 4, "minions unaffected")
	H.end_turn(g)
	H.end_turn(g)
	eq(g.cost(fb), 4, "gone after that turn")


func test_nat_pagle_sometimes_draws() -> void:
	var draws := 0
	for seed in 20:
		var g := H.game(seed + 1)
		H.board(g, 0, "VAN_EX1_557")
		H.end_turn(g)
		var before := g.players[0].hand.size()
		H.end_turn(g)
		draws += g.players[0].hand.size() - before - 1
	check(draws > 2 and draws < 18, "about half the time: %d/20" % draws)


func test_king_mukla_and_bananas() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_014"))
	var hand := g.players[1].hand
	eq(hand.map(func(e): return e.card_id), ["EX1_014t", "EX1_014t"], "2 bananas")
	H.end_turn(g)
	var w := H.board(g, 1, H.WISP)
	check(H.play(g, hand[0], w).ok, "banana played")
	eq([w.atk(), w.max_health()], [2, 2], "+1/+1")


func test_tinkmaster_overspark() -> void:
	var g := H.game()
	var w := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_083"))
	var n: Entity = g.players[1].board[0]
	check(n.card_id in ["VAN_EX1_tk29", "VAN_EX1_tk28"], "devilsaur or squirrel")
	eq(w.zone, "SETASIDE", "old minion gone")


func test_tinkmaster_alone_does_nothing() -> void:
	var g := H.game()
	var t := H.hand(g, 0, "VAN_EX1_083")
	H.play(g, t)
	eq(g.players[0].board, [t], "does not transform itself")


func test_leeroy_jenkins() -> void:
	var g := H.game()
	var l := H.hand(g, 0, "VAN_EX1_116")
	H.play(g, l)
	eq(g.players[1].board.map(func(m): return m.card_id), ["EX1_116t", "EX1_116t"], "2 whelps for opponent")
	check(H.attack(g, l, g.hero(1)).ok, "charge")


func test_old_murk_eye() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_CS2_168")
	H.board(g, 1, "VAN_CS2_168")
	var m := H.hand(g, 0, "VAN_EX1_062")
	H.play(g, m)
	eq(m.atk(), 4, "2 + 2 murlocs")
	check(H.attack(g, m, g.hero(1)).ok, "charge")


func test_captain_greenskin() -> void:
	var g := H.scene({"hero": "HERO_01", "weapon": "VAN_CS2_106"})
	H.play(g, H.hand(g, 0, "VAN_NEW1_024"))
	var w := g.players[0].weapon
	eq([w.atk(), int(w.tags.DURABILITY)], [4, 3], "+1/+1")


func test_elite_tauren_chieftain() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_PRO_001"))
	for p in 2:
		eq(g.players[p].hand.size(), 1, "player %d got a chord" % p)
		check(g.players[p].hand[0].card_id in ["PRO_001a", "PRO_001b", "VAN_PRO_001c"], "power chord")


func test_power_chords() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": _deck(3)})
	H.play(g, H.hand(g, 0, "PRO_001a"))
	var n := g.players[0].board.size()
	check(n >= 3 and n <= 5, "3-5 murlocs: %d" % n)
	g.players[0].mana = 10
	H.play(g, H.hand(g, 0, "PRO_001b"), g.hero(1))
	eq(g.hero(1).health(), 26, "4 damage")
	eq(g.players[0].hand.size(), 1, "drew")
	g.players[0].mana = 10
	H.play(g, H.hand(g, 0, "VAN_PRO_001c"))
	eq(g.players[0].board.size(), n + 1, "horde warrior")


func test_harrison_jones() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": _deck(3)}, {"hero": "HERO_01", "weapon": "VAN_CS2_106"})
	H.play(g, H.hand(g, 0, "VAN_EX1_558"))
	eq(g.players[1].weapon, null, "destroyed")
	eq(g.players[0].hand.size(), 2, "drew 2 for durability")


func test_cairne_bloodhoof() -> void:
	var g := H.game()
	var c := H.board(g, 0, "VAN_EX1_110")
	g.destroy(c)
	g.resolve()
	eq(g.players[0].board[0].card_id, "VAN_EX1_110t", "Baine")


func test_gelbin_and_inventions() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_112"))
	check(g.players[0].board[1].card_id in ["Mekka1", "Mekka2", "Mekka3", "Mekka4"], "invention")


func test_homing_chicken() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": _deck(5), "board": ["Mekka1"]})
	H.end_turn(g)
	H.end_turn(g)
	eq(g.players[0].board.size(), 0, "destroyed itself")
	eq(g.players[0].hand.size(), 4, "3 + normal draw")


func test_repair_bot() -> void:
	var g := H.scene({"hero": "HERO_08", "damage": 10, "board": ["Mekka2"]})
	H.end_turn(g)
	eq(g.hero(0).health(), 26, "+6 to the only damaged character")


func test_emboldener_3000() -> void:
	var g := H.scene({"hero": "HERO_08", "board": ["Mekka3"]})
	var e: Entity = g.players[0].board[0]
	H.end_turn(g)
	eq([e.atk(), e.max_health()], [1, 5], "itself is the only minion")


func test_poultryizer() -> void:
	var g := H.scene({"hero": "HERO_08", "board": ["Mekka4"]})
	H.end_turn(g)
	H.end_turn(g)
	eq(g.players[0].board[0].card_id, "Mekka4t", "chicken")


func test_hogger() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_NEW1_040")
	H.end_turn(g)
	eq(g.players[0].board[1].card_id, "NEW1_040t", "gnoll")
	check(g.players[0].board[1].has("TAUNT"), "taunt")


func test_illidan_stormrage() -> void:
	var g := H.game()
	var i := H.hand(g, 0, "VAN_EX1_614")
	H.play(g, i)
	eq(g.players[0].board.size(), 1, "not on its own play")
	H.play(g, H.hand(g, 0, "GAME_005"))
	eq(g.players[0].board[1].card_id, "VAN_TU4e_002t", "flame on any card")


func test_sylvanas_windrunner() -> void:
	var g := H.game()
	var s := H.board(g, 0, "VAN_EX1_016")
	var e := H.board(g, 1, "VAN_CS2_182")
	g.destroy(s)
	g.resolve()
	eq(e.controller, 0, "stolen")


func test_the_beast() -> void:
	var g := H.game()
	var b := H.board(g, 0, "VAN_EX1_577")
	g.destroy(b)
	g.resolve()
	eq(g.players[1].board[0].card_id, "VAN_EX1_finkle", "Pip for opponent")


func test_the_black_knight() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS1_042")
	var w := H.board(g, 1, H.WISP)
	check(not H.play(g, H.hand(g, 0, "VAN_EX1_002"), w).ok, "taunt only")
	H.play(g, H.hand(g, 0, "VAN_EX1_002"), t)
	eq(t.zone, "GRAVEYARD", "destroyed")


func test_baron_geddon() -> void:
	var g := H.game()
	var b := H.board(g, 0, "VAN_EX1_249")
	var w := H.board(g, 0, "VAN_CS2_120")
	H.end_turn(g)
	eq([g.hero(0).health(), g.hero(1).health(), w.health(), b.health()], [28, 28, 1, 5], "all other characters")


func test_gruul() -> void:
	var g := H.game()
	var gr := H.board(g, 0, "VAN_NEW1_038")
	H.end_turn(g)
	H.end_turn(g)
	eq([gr.atk(), gr.max_health()], [9, 9], "+1/+1 each turn")


func test_ragnaros() -> void:
	var g := H.game()
	var r := H.board(g, 0, "VAN_EX1_298")
	check(not H.attack(g, r, g.hero(1)).ok, "can't attack")
	H.end_turn(g)
	eq(g.hero(1).health(), 22, "8 to the only enemy")


func test_alexstrasza() -> void:
	var g := H.scene({"hero": "HERO_08", "damage": 20})
	H.play(g, H.hand(g, 0, "VAN_EX1_561"), g.hero(1))
	eq([g.hero(1).health(), g.hero(1).max_health()], [15, 30], "enemy to 15")
	var g2 := H.scene({"hero": "HERO_08", "damage": 20})
	H.play(g2, H.hand(g2, 0, "VAN_EX1_561"), g2.hero(0))
	eq(g2.hero(0).health(), 15, "own hero from 10 to 15")
	check(not H.play(g2, H.hand(g2, 0, "VAN_EX1_561"), g2.players[0].board[0]).ok, "heroes only")


func test_onyxia_fills_board_both_sides() -> void:
	var g := H.game()
	H.board(g, 0, H.WISP)
	var o := H.hand(g, 0, "VAN_EX1_562")
	H.play(g, o, null, 1)
	var b := g.players[0].board
	eq(b.size(), 7, "full")
	eq(b.find(o), 3, "onyxia in the middle")


func test_ysera() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_EX1_572")
	H.end_turn(g)
	check(g.players[0].hand[0].card_id.begins_with("VAN_DREAM_"), "dream card")


func test_dream_cards() -> void:
	var g := H.game()
	var y := H.board(g, 0, "VAN_EX1_572")
	var w := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_DREAM_02"))  # Ysera Awakens
	eq([y.health(), w.health(), g.hero(0).health()], [12, 0, 25], "5 to all but Ysera")
	var g2 := H.game()
	var t := H.board(g2, 1, "VAN_CS2_182")
	H.play(g2, H.hand(g2, 0, "VAN_DREAM_04"), t)  # Dream
	eq(g2.players[1].hand[0].card_id, "VAN_CS2_182", "returned to owner")


func test_nightmare() -> void:
	var g := H.game()
	var t := H.board(g, 1, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_DREAM_05"), t)
	eq([t.atk(), t.max_health()], [6, 6], "+5/+5")
	H.end_turn(g)
	eq(t.zone, "PLAY", "survives their turn")
	H.end_turn(g)
	eq(t.zone, "GRAVEYARD", "destroyed at start of caster's next turn")


func test_deathwing() -> void:
	var g := H.game()
	H.board(g, 0, H.WISP)
	H.board(g, 1, H.WISP)
	H.hand(g, 0, "VAN_CS2_029")
	var d := H.hand(g, 0, "VAN_NEW1_030")
	H.play(g, d)
	eq(g.all_minions(), [d], "only deathwing")
	eq(g.players[0].hand.size(), 0, "hand discarded")


func test_malygos_spell_damage() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_EX1_563")
	eq(g.spell_dmg(g.hero(0), 1), 6, "+5")
