extends TestCase


func _deck(n: int) -> Array:
	var d := []
	for i in n:
		d.append(H.WISP)
	return d


func _secret_then_pass(g: Game, id: String) -> Entity:
	var s := H.hand(g, 0, id)
	H.play(g, s)
	H.end_turn(g)
	return s


func test_blessings_and_humility() -> void:
	var g := H.game()
	var w := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_087"), w)
	eq(w.atk(), 7, "might +3")
	H.play(g, H.hand(g, 0, "VAN_CS2_092"), w)
	eq([w.atk(), w.max_health()], [11, 9], "kings +4/+4")
	H.play(g, H.hand(g, 0, "VAN_EX1_360"), w)
	eq(w.atk(), 1, "humility")


func test_blessing_of_wisdom() -> void:
	var g := H.scene({"hero": "HERO_04", "deck": _deck(3)}, {"hero": "HERO_01", "deck": _deck(3)})
	var w := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_363"), w)
	H.end_turn(g)
	var before := g.players[0].hand.size()
	H.attack(g, w, g.hero(0))
	eq(g.players[0].hand.size(), before + 1, "caster draws when it attacks")


func test_eye_for_an_eye() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_132")
	H.attack(g, H.board(g, 1, "VAN_CS2_182"), g.hero(0))
	eq(g.hero(1).health(), 26, "4 back")


func test_hand_of_protection() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_371"), w)
	check(w.has("DIVINE_SHIELD"), "shield")


func test_noble_sacrifice() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_130")
	var a := H.board(g, 1, "VAN_CS2_182")
	H.attack(g, a, g.hero(0))
	eq(g.hero(0).health(), 30, "defender took the hit")
	eq(a.health(), 3, "defender hit back for 2")
	eq(g.players[0].board.size(), 0, "defender died")


func test_redemption() -> void:
	var g := H.game()
	var y := H.board(g, 0, "VAN_CS2_182")
	_secret_then_pass(g, "VAN_EX1_136")
	g.destroy(y)
	g.resolve()
	var back: Entity = g.players[0].board[0]
	eq([back.card_id, back.health()], ["VAN_CS2_182", 1], "back with 1 health")


func test_repentance() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_379")
	var m := H.hand(g, 1, "VAN_CS2_182")
	H.play(g, m)
	eq([m.health(), m.max_health()], [1, 1], "health 1")


func test_argent_protector() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_362"), w)
	check(w.has("DIVINE_SHIELD"), "shield")


func test_equality() -> void:
	var g := H.game()
	var a := H.board(g, 0, "VAN_CS2_182")
	var b := H.board(g, 1, "VAN_CS2_201")
	H.play(g, H.hand(g, 0, "VAN_EX1_619"))
	eq([a.health(), b.health(), b.atk()], [1, 1, 9], "health 1, attack kept")


func test_holy_light_and_lay_on_hands() -> void:
	var g := H.scene({"hero": "HERO_04", "damage": 20, "deck": _deck(4)})
	H.play(g, H.hand(g, 0, "VAN_CS2_089"), g.hero(0))
	eq(g.hero(0).health(), 16, "+6")
	g.players[0].mana = 10
	H.play(g, H.hand(g, 0, "VAN_EX1_354"), g.hero(0))
	eq([g.hero(0).health(), g.players[0].hand.size()], [24, 3], "+8, draw 3")


func test_aldor_peacekeeper() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS2_201")
	H.play(g, H.hand(g, 0, "VAN_EX1_382"), t)
	eq(t.atk(), 1, "attack 1")


func test_divine_favor() -> void:
	var g := H.scene({"hero": "HERO_04", "deck": _deck(5)})
	for i in 4:
		H.hand(g, 1, H.WISP)
	H.hand(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_349"))
	eq(g.players[0].hand.size(), 4, "drew up to 4")


func test_sword_of_justice() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_366"))
	var w := H.hand(g, 0, H.WISP)
	H.play(g, w)
	eq([w.atk(), w.max_health()], [2, 2], "+1/+1")
	eq(int(g.players[0].weapon.tags.DURABILITY), 4, "-1 durability")


func test_consecration() -> void:
	var g := H.game()
	var e := H.board(g, 1, "VAN_CS2_182")
	var m := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_093"))
	eq([e.health(), m.health(), g.hero(1).health()], [3, 5, 28], "2 to all enemies")


func test_hammer_of_wrath() -> void:
	var g := H.scene({"hero": "HERO_04", "deck": _deck(2)})
	H.play(g, H.hand(g, 0, "VAN_CS2_094"), g.hero(1))
	eq([g.hero(1).health(), g.players[0].hand.size()], [27, 1], "3 and draw")


func test_truesilver_champion() -> void:
	var g := H.scene({"hero": "HERO_04", "damage": 10})
	H.play(g, H.hand(g, 0, "VAN_CS2_097"))
	H.attack(g, g.hero(0), g.hero(1))
	eq([g.hero(0).health(), g.hero(1).health()], [22, 26], "heal 2, hit 4")


func test_blessed_champion() -> void:
	var g := H.game()
	var w := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_355"), w)
	eq(w.atk(), 8, "doubled")


func test_holy_wrath() -> void:
	var g := H.scene({"hero": "HERO_04", "deck": ["VAN_CS2_182"]})
	H.play(g, H.hand(g, 0, "VAN_EX1_365"), g.hero(1))
	eq(g.hero(1).health(), 26, "4 = yeti cost")


func test_holy_wrath_empty_deck() -> void:
	var g := H.game()
	g.players[0].deck.clear()
	H.play(g, H.hand(g, 0, "VAN_EX1_365"), g.hero(1))
	eq(g.hero(1).health(), 30, "no card, no damage")
	eq(g.hero(0).health(), 29, "fatigue")


func test_avenging_wrath() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_384"))
	eq(g.hero(1).health(), 22, "8 missiles")


func test_guardian_of_kings() -> void:
	var g := H.scene({"hero": "HERO_04", "damage": 10})
	H.play(g, H.hand(g, 0, "VAN_CS2_088"))
	eq(g.hero(0).health(), 26, "+6")


func test_tirion_fordring() -> void:
	var g := H.game()
	var t := H.board(g, 0, "VAN_EX1_383")
	check(t.has("TAUNT") and t.has("DIVINE_SHIELD"), "keywords")
	g.destroy(t)
	g.resolve()
	var w := g.players[0].weapon
	eq([w.card_id, w.atk(), int(w.tags.DURABILITY)], ["EX1_383t", 5, 3], "Ashbringer")
