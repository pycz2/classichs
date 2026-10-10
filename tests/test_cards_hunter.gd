extends TestCase


func _deck(n: int) -> Array:
	var d := []
	for i in n:
		d.append(H.WISP)
	return d


## Plays a secret for player 0, then passes the turn so player 1 acts.
func _secret_then_pass(g: Game, id: String) -> Entity:
	var s := H.hand(g, 0, id)
	H.play(g, s)
	H.end_turn(g)
	return s


func test_hunters_mark() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_084"), t)
	eq([t.health(), t.max_health()], [1, 1], "health 1")


func test_arcane_shot() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_DS1_185"), g.hero(1))
	eq(g.hero(1).health(), 28, "2")


func test_bestial_wrath() -> void:
	var g := H.game()
	var b := H.board(g, 0, "VAN_CS2_120")  # crocolisk, beast
	check(not H.play(g, H.hand(g, 0, "VAN_EX1_549"), H.board(g, 0, H.WISP)).ok, "beasts only")
	H.play(g, H.hand(g, 0, "VAN_EX1_549"), b)
	eq(b.atk(), 4, "+2")
	check(b.has("IMMUNE"), "immune")
	H.end_turn(g)
	check(not b.has("IMMUNE") and b.atk() == 2, "this turn only")


func test_flare() -> void:
	var g := H.scene({"hero": "HERO_05", "deck": _deck(2)}, {"hero": "HERO_08", "secrets": ["VAN_EX1_289"]})
	var s := H.board(g, 1, "VAN_EX1_010")
	H.play(g, H.hand(g, 0, "VAN_EX1_544"))
	check(not s.has("STEALTH"), "stealth removed")
	eq(g.players[1].secrets.size(), 0, "enemy secret destroyed")
	eq(g.players[0].hand.size(), 1, "drew")


func test_timber_wolf() -> void:
	var g := H.game()
	var b := H.board(g, 0, "VAN_CS2_120")
	var w := H.board(g, 0, H.WISP)
	var tw := H.hand(g, 0, "VAN_DS1_175")
	H.play(g, tw)
	eq([b.atk(), w.atk(), tw.atk()], [3, 1, 1], "other beasts +1")


func test_tracking() -> void:
	var g := H.scene({"hero": "HERO_05", "deck": ["VAN_CS2_120", "VAN_CS2_182", "VAN_CS2_029", "VAN_CS2_231"]})
	H.play(g, H.hand(g, 0, "VAN_DS1_184"))
	var acts := g.legal_actions()
	eq(acts.size(), 3, "3 options")
	var top3: Array = g.players[0].deck.slice(-3).map(func(e): return e.id)
	eq(acts.map(func(a): return a.option), top3, "top 3 cards")
	g.apply(acts[0])
	eq(g.players[0].hand.size(), 1, "one drawn")
	eq(g.players[0].deck.size(), 1, "two discarded")


func test_explosive_trap() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_610")
	var a := H.board(g, 1, "VAN_CS2_120")
	H.attack(g, a, g.hero(0))
	eq(a.health(), 1, "2 damage to attacker")
	eq(g.hero(1).health(), 28, "enemy hero too")
	eq(g.hero(0).health(), 28, "attack still happens")


func test_explosive_trap_kills_attacker_before_damage() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_610")
	var a := H.board(g, 1, "VAN_CS2_118")  # Magma Rager 5/1
	H.attack(g, a, g.hero(0))
	eq(g.hero(0).health(), 30, "attack cancelled")


func test_freezing_trap() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_611")
	var a := H.board(g, 1, "VAN_CS2_182")
	H.attack(g, a, g.hero(0))
	eq(g.hero(0).health(), 30, "no damage")
	var back: Entity = g.players[1].hand.back()
	eq([back.card_id, g.cost(back)], ["VAN_CS2_182", 6], "back in hand, costs 2 more")


func test_misdirection() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_533")
	var a := H.board(g, 1, "VAN_CS2_182")
	H.attack(g, a, g.hero(0))
	eq(g.hero(0).health(), 30, "not my hero")
	eq(g.hero(1).health(), 26, "only other character: enemy hero")


func test_scavenging_hyena() -> void:
	var g := H.game()
	var h := H.board(g, 0, "VAN_EX1_531")
	var b := H.board(g, 0, "VAN_CS2_120")
	g.destroy(b)
	g.resolve()
	eq([h.atk(), h.max_health()], [4, 3], "+2/+1")


func test_snake_trap() -> void:
	var g := H.game()
	var mine := H.board(g, 0, "VAN_CS2_182")
	_secret_then_pass(g, "VAN_EX1_554")
	var a := H.board(g, 1, "VAN_CS2_120")
	H.attack(g, a, mine)
	eq(g.players[0].board.size(), 4, "3 snakes")


func test_snipe() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_609")
	var m := H.hand(g, 1, "VAN_CS2_182")
	H.play(g, m)
	eq(m.health(), 1, "4 damage")


func test_snipe_ignores_tokens() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_609")
	g.summon(1, "VAN_CS2_182")
	g.resolve()
	eq(g.players[0].secrets.size(), 1, "still armed")


func test_secret_not_on_own_turn() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_609"))
	H.play(g, H.hand(g, 0, "VAN_CS2_182"))
	eq(g.players[0].secrets.size(), 1, "own minion does not trigger")


func test_starving_buzzard() -> void:
	var g := H.scene({"hero": "HERO_05", "deck": _deck(3)})
	H.board(g, 0, "VAN_CS2_237")
	H.play(g, H.hand(g, 0, "VAN_CS2_120"))
	H.play(g, H.hand(g, 0, H.WISP))
	eq(g.players[0].hand.size(), 1, "drew only for the beast")


func test_animal_companion_and_leokk() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_NEW1_031"))
	check(g.players[0].board[0].card_id in ["VAN_NEW1_032", "VAN_NEW1_033", "VAN_NEW1_034"], "companion")
	var g2 := H.game()
	var w := H.board(g2, 0, H.WISP)
	H.board(g2, 0, "VAN_NEW1_033")
	g2.resolve()
	eq(w.atk(), 2, "Leokk: others +1")


func test_deadly_shot() -> void:
	var g := H.game()
	check(not H.play(g, H.hand(g, 0, "VAN_EX1_617")).ok, "needs an enemy minion")
	var t := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_617"))
	eq(t.zone, "GRAVEYARD", "destroyed")


func test_eaglehorn_bow() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_536"))
	_secret_then_pass(g, "VAN_EX1_610")
	H.attack(g, H.board(g, 1, "VAN_CS2_182"), g.hero(0))
	eq(int(g.players[0].weapon.tags.DURABILITY), 3, "+1 durability")


func test_kill_command() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_539"), g.hero(1))
	eq(g.hero(1).health(), 27, "3 without beast")
	H.board(g, 0, "VAN_CS2_120")
	H.play(g, H.hand(g, 0, "VAN_EX1_539"), g.hero(1))
	eq(g.hero(1).health(), 22, "5 with beast")


func test_unleash_the_hounds() -> void:
	var g := H.game()
	check(not H.play(g, H.hand(g, 0, "VAN_EX1_538")).ok, "needs enemy minions")
	H.board(g, 1, H.WISP)
	H.board(g, 1, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_538"))
	var b := g.players[0].board
	eq(b.size(), 2, "2 hounds")
	check(H.attack(g, b[0], g.hero(1)).ok, "charge")


func test_houndmaster() -> void:
	var g := H.game()
	var b := H.board(g, 0, "VAN_CS2_120")
	H.play(g, H.hand(g, 0, "VAN_DS1_070"), b)
	eq([b.atk(), b.max_health(), b.has("TAUNT")], [4, 5, true], "+2/+2 taunt")


func test_multi_shot() -> void:
	var g := H.game()
	H.board(g, 1, "VAN_CS2_182")
	check(not H.play(g, H.hand(g, 0, "VAN_DS1_183")).ok, "needs 2 enemy minions")
	H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_DS1_183"))
	eq(g.players[1].board.map(func(m): return m.health()), [2, 2], "3 to each")


func test_explosive_shot() -> void:
	var g := H.game()
	var a := H.board(g, 1, "VAN_CS2_182")
	var b := H.board(g, 1, "VAN_CS2_182")
	var c := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_537"), b)
	eq([a.health(), b.health(), c.health()], [3, 0, 3], "5 + 2 to neighbours")


func test_tundra_rhino() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_DS1_178")
	var b := H.hand(g, 0, "VAN_CS2_120")
	H.play(g, b)
	check(H.attack(g, b, g.hero(1)).ok, "beasts have charge")


func test_savannah_highmane() -> void:
	var g := H.game()
	var s := H.board(g, 0, "VAN_EX1_534")
	g.destroy(s)
	g.resolve()
	eq(g.players[0].board.map(func(m): return m.card_id), ["EX1_534t", "EX1_534t"], "2 hyenas")


func test_gladiators_longbow() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_DS1_188"))
	var y := H.board(g, 1, "VAN_CS2_182")
	H.attack(g, g.hero(0), y)
	eq(g.hero(0).health(), 30, "immune while attacking")
	eq(y.zone, "GRAVEYARD", "5 damage")
