extends TestCase


func _deck(n: int) -> Array:
	var d := []
	for i in n:
		d.append(H.WISP)
	return d


func test_innervate() -> void:
	var g := H.game()
	g.players[0].mana = 3
	H.play(g, H.hand(g, 0, "VAN_EX1_169"))
	eq(g.players[0].mana, 5, "+2")
	g.players[0].mana = 9
	H.play(g, H.hand(g, 0, "VAN_EX1_169"))
	eq(g.players[0].mana, 10, "capped")


func test_moonfire_with_spell_damage() -> void:
	var g := H.scene({"hero": "HERO_06", "board": ["VAN_CS2_142"]})
	H.play(g, H.hand(g, 0, "VAN_CS2_008"), g.hero(1))
	eq(g.hero(1).health(), 28, "1 + 1")


func test_claw_and_bite() -> void:
	var g := H.scene({"hero": "HERO_06"})
	H.play(g, H.hand(g, 0, "VAN_CS2_005"))
	H.play(g, H.hand(g, 0, "VAN_EX1_570"))
	var hero := g.hero(0)
	eq([g.hero_atk(hero), int(hero.tags.ARMOR)], [6, 6], "+2/+4 attack, 2+4 armor")
	H.end_turn(g)
	eq(hero.atk(), 0, "attack this turn only")


func test_naturalize() -> void:
	var g := H.scene({"hero": "HERO_06"}, {"hero": "HERO_01", "deck": _deck(3)})
	var t := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_161"), t)
	eq(t.zone, "GRAVEYARD", "destroyed")
	eq(g.players[1].hand.size(), 2, "opponent drew 2")


func test_savagery() -> void:
	var g := H.scene({"hero": "HERO_06"})
	var t := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_005"))  # Claw: +2 attack
	H.play(g, H.hand(g, 0, "VAN_EX1_578"), t)
	eq(t.health(), 3, "2 damage")
	check(not H.play(g, H.hand(g, 0, "VAN_EX1_578"), g.hero(1)).ok, "minions only")


func test_mark_of_the_wild() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_CS2_009"), w)
	eq([w.atk(), w.max_health(), w.has("TAUNT")], [3, 3, true], "+2/+2 taunt")


func test_power_of_the_wild_both_options() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_160"), null, -1, 0)
	eq([w.atk(), w.max_health()], [2, 2], "+1/+1")
	H.play(g, H.hand(g, 0, "VAN_EX1_160"), null, -1, 1)
	eq(g.players[0].board.back().card_id, "EX1_160t", "panther")


func test_wild_growth() -> void:
	var g := H.game()
	g.players[0].max_mana = 5
	g.players[0].mana = 5
	H.play(g, H.hand(g, 0, "VAN_CS2_013"))
	eq([g.players[0].max_mana, g.players[0].mana], [6, 3], "empty crystal")


func test_wild_growth_at_ten_gives_excess_mana() -> void:
	var g := H.scene({"hero": "HERO_06", "deck": _deck(2)})
	H.play(g, H.hand(g, 0, "VAN_CS2_013"))
	eq(g.players[0].hand[0].card_id, "CS2_013t", "excess mana")
	H.play(g, g.players[0].hand[0])
	eq(g.players[0].hand.size(), 1, "excess mana draws")


func test_wrath() -> void:
	var g := H.scene({"hero": "HERO_06", "deck": _deck(2)})
	var a := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_154"), a, -1, 0)
	eq(a.health(), 2, "3 damage")
	H.play(g, H.hand(g, 0, "VAN_EX1_154"), a, -1, 1)
	eq([a.health(), g.players[0].hand.size()], [1, 1], "1 damage and draw")


func test_healing_touch() -> void:
	var g := H.scene({"hero": "HERO_06", "damage": 10})
	H.play(g, H.hand(g, 0, "VAN_CS2_007"), g.hero(0))
	eq(g.hero(0).health(), 28, "+8")


func test_mark_of_nature() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_155"), w, -1, 0)
	eq(w.atk(), 5, "+4 attack")
	H.play(g, H.hand(g, 0, "VAN_EX1_155"), w, -1, 1)
	eq([w.max_health(), w.has("TAUNT")], [5, true], "+4 health taunt")


func test_savage_roar() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_CS2_011"))
	eq([w.atk(), g.hero_atk(g.hero(0))], [3, 2], "+2 all own characters")
	H.end_turn(g)
	eq(w.atk(), 1, "this turn only")


func test_keeper_of_the_grove() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS1_042")
	H.play(g, H.hand(g, 0, "VAN_EX1_166"), g.hero(1), -1, 0)
	eq(g.hero(1).health(), 28, "2 damage")
	H.play(g, H.hand(g, 0, "VAN_EX1_166"), t, -1, 1)
	check(t.silenced, "silence")


func test_soul_of_the_forest() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_158"))
	g.destroy(w)
	g.resolve()
	eq(g.players[0].board[0].card_id, "VAN_EX1_tk9", "treant")


func test_swipe() -> void:
	var g := H.game()
	var a := H.board(g, 1, "VAN_CS2_182")
	var b := H.board(g, 1, "VAN_CS2_182")
	var mine := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_012"), a)
	eq([a.health(), b.health(), g.hero(1).health(), mine.health()], [1, 4, 29, 5], "4 + 1 to other enemies")
	check(not H.play(g, H.hand(g, 0, "VAN_CS2_012"), mine).ok, "enemies only")


func test_druid_of_the_claw() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_165"), null, -1, 0)
	var cat: Entity = g.players[0].board[0]
	eq(cat.card_id, "VAN_EX1_165t1", "cat form")
	check(H.attack(g, cat, g.hero(1)).ok, "charge")
	H.play(g, H.hand(g, 0, "VAN_EX1_165"), null, -1, 1)
	var bear: Entity = g.players[0].board[1]
	eq([bear.card_id, bear.max_health(), bear.has("TAUNT")], ["VAN_EX1_165t2", 6, true], "bear form")


func test_nourish() -> void:
	var g := H.scene({"hero": "HERO_06", "deck": _deck(5)})
	g.players[0].max_mana = 5
	H.play(g, H.hand(g, 0, "VAN_EX1_164"), null, -1, 0)
	eq([g.players[0].max_mana, g.players[0].mana], [7, 7], "2 full crystals")
	H.play(g, H.hand(g, 0, "VAN_EX1_164"), null, -1, 1)
	eq(g.players[0].hand.size(), 3, "draw 3")


func test_starfall() -> void:
	var g := H.game()
	var a := H.board(g, 1, "VAN_CS2_182")
	var b := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_NEW1_007"), a, -1, 0)
	eq(a.health(), 0, "5 damage")
	H.play(g, H.hand(g, 0, "VAN_NEW1_007"), null, -1, 1)
	eq([b.health(), g.hero(1).health()], [3, 30], "2 to enemy minions only")


func test_force_of_nature() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_571"))
	var b := g.players[0].board
	eq(b.size(), 3, "3 treants")
	check(H.attack(g, b[0], g.hero(1)).ok, "charge")
	H.end_turn(g)
	eq(g.players[0].board.size(), 0, "die at end of turn")


func test_starfire() -> void:
	var g := H.scene({"hero": "HERO_06", "deck": _deck(2)})
	H.play(g, H.hand(g, 0, "VAN_EX1_173"), g.hero(1))
	eq([g.hero(1).health(), g.players[0].hand.size()], [25, 1], "5 damage, draw")


func test_ancient_of_lore() -> void:
	var g := H.scene({"hero": "HERO_06", "deck": _deck(3), "damage": 10})
	H.play(g, H.hand(g, 0, "VAN_NEW1_008"), null, -1, 0)
	eq(g.players[0].hand.size(), 2, "draw 2")
	g.players[0].mana = 10
	H.play(g, H.hand(g, 0, "VAN_NEW1_008"), g.hero(0), -1, 1)
	eq(g.hero(0).health(), 25, "+5")


func test_ancient_of_war() -> void:
	var g := H.game()
	var a := H.hand(g, 0, "VAN_EX1_178")
	H.play(g, a, null, -1, 0)
	eq(a.atk(), 10, "+5 attack")
	g.players[0].mana = 10
	var b := H.hand(g, 0, "VAN_EX1_178")
	H.play(g, b, null, -1, 1)
	eq([b.max_health(), b.has("TAUNT")], [10, true], "+5 health taunt")


func test_cenarius() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	var c := H.hand(g, 0, "VAN_EX1_573")
	H.play(g, c, null, -1, 0)
	eq([w.atk(), w.max_health(), c.atk()], [3, 3, 5], "others +2/+2")
	var g2 := H.game()
	var c2 := H.hand(g2, 0, "VAN_EX1_573")
	H.play(g2, c2, null, -1, 1)
	var b := g2.players[0].board
	eq(b.map(func(m): return m.card_id), ["VAN_EX1_tk9", "VAN_EX1_573", "VAN_EX1_tk9"], "treants on both sides")
	check(b[0].has("TAUNT") and b[2].has("TAUNT"), "taunt")


func test_ironbark_protector() -> void:
	var g := H.game()
	var i := H.hand(g, 0, "VAN_CS2_232")
	H.play(g, i)
	check(i.has("TAUNT"), "taunt")
