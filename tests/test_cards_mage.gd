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


func test_arcane_missiles() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_277"))
	eq(g.hero(1).health(), 27, "3 missiles at the only enemy")


func test_arcane_missiles_spell_damage_adds_missiles() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_CS2_142")
	H.play(g, H.hand(g, 0, "VAN_EX1_277"))
	eq(g.hero(1).health(), 26, "4 missiles")


func test_ice_lance() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_031"), t)
	check(t.has("FROZEN") and t.health() == 5, "freeze first")
	H.play(g, H.hand(g, 0, "VAN_CS2_031"), t)
	eq(t.health(), 1, "4 damage when frozen")


func test_mana_wyrm() -> void:
	var g := H.game()
	var w := H.board(g, 0, "VAN_NEW1_012")
	H.play(g, H.hand(g, 0, "GAME_005"))
	eq(w.atk(), 2, "+1")


func test_mirror_image() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_027"))
	eq(g.players[0].board.map(func(m): return m.card_id), ["VAN_CS2_mirror", "VAN_CS2_mirror"], "two 0/2")
	check(g.players[0].board[0].has("TAUNT"), "taunt")


func test_arcane_explosion_flamestrike_blizzard() -> void:
	var g := H.game()
	var a := H.board(g, 1, "VAN_CS2_182")
	var mine := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_025"))
	eq([a.health(), mine.health(), g.hero(1).health()], [4, 5, 30], "arcane explosion 1")
	H.play(g, H.hand(g, 0, "VAN_CS2_028"))
	eq(a.health(), 2, "blizzard 2")
	check(a.has("FROZEN"), "blizzard freezes")
	g.players[0].mana = 10
	H.play(g, H.hand(g, 0, "VAN_CS2_032"))
	eq(a.zone, "GRAVEYARD", "flamestrike 4")


func test_frostbolt() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_024"), g.hero(1))
	eq(g.hero(1).health(), 27, "3")
	check(g.hero(1).has("FROZEN"), "frozen")


func test_sorcerers_apprentice() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_EX1_608")
	eq([g.cost(H.hand(g, 0, "VAN_CS2_029")), g.cost(H.hand(g, 0, "VAN_CS2_182")), g.cost(H.hand(g, 1, "VAN_CS2_029"))],
		[3, 4, 4], "own spells -1")


func test_arcane_intellect() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": _deck(3)})
	H.play(g, H.hand(g, 0, "VAN_CS2_023"))
	eq(g.players[0].hand.size(), 2, "draw 2")


func test_counterspell() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_287")
	var fb := H.hand(g, 1, "VAN_CS2_029")
	check(H.play(g, fb, g.hero(0)).ok, "cast")
	eq(g.hero(0).health(), 30, "countered")
	eq(g.players[1].mana, 6, "mana still spent")


func test_frost_nova() -> void:
	var g := H.game()
	var a := H.board(g, 1, H.WISP)
	var mine := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_CS2_026"))
	check(a.has("FROZEN") and not mine.has("FROZEN"), "enemy minions frozen")


func test_ice_barrier() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_289")
	H.attack(g, H.board(g, 1, "VAN_CS2_182"), g.hero(0))
	eq([g.hero(0).health(), int(g.hero(0).tags.ARMOR)], [30, 4], "8 armor, 4 absorbed")


func test_ice_block() -> void:
	var g := H.scene({"hero": "HERO_08", "damage": 25})
	_secret_then_pass(g, "VAN_EX1_295")
	H.attack(g, H.board(g, 1, "VAN_CS2_201"), g.hero(0))  # Core Hound 9
	eq(g.hero(0).health(), 5, "fatal damage prevented")
	check(g.hero(0).has("IMMUNE"), "immune this turn")
	check(not g.game_over, "alive")


func test_ice_block_ignores_non_fatal() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_295")
	H.attack(g, H.board(g, 1, "VAN_CS2_182"), g.hero(0))
	eq(g.hero(0).health(), 26, "normal damage")
	eq(g.players[0].secrets.size(), 1, "still armed")


func test_kirin_tor_mage() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_612"))
	var s1 := H.hand(g, 0, "VAN_EX1_287")
	var s2 := H.hand(g, 0, "VAN_EX1_289")
	eq(g.cost(s1), 0, "next secret free")
	H.play(g, s1)
	eq(g.cost(s2), 3, "only one")


func test_kirin_tor_mage_expires() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_612"))
	var s := H.hand(g, 0, "VAN_EX1_287")
	H.end_turn(g)
	H.end_turn(g)
	eq(g.cost(s), 3, "this turn only")


func test_mirror_entity() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_294")
	H.play(g, H.hand(g, 1, "VAN_CS2_182"))
	eq(g.players[0].board.map(func(m): return m.card_id), ["VAN_CS2_182"], "copy for me")


func test_spellbender() -> void:
	var g := H.game()
	var mine := H.board(g, 0, "VAN_CS2_182")
	_secret_then_pass(g, "VAN_tt_010")
	H.play(g, H.hand(g, 1, "VAN_CS2_029"), mine)
	eq(mine.health(), 5, "redirected")
	eq(g.players[0].board.size(), 1, "spellbender minion died to the fireball")


func test_spellbender_ignores_hero_target() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_tt_010")
	H.play(g, H.hand(g, 1, "VAN_CS2_029"), g.hero(0))
	eq(g.hero(0).health(), 24, "hero hit")
	eq(g.players[0].secrets.size(), 1, "still armed")


func test_vaporize() -> void:
	var g := H.game()
	_secret_then_pass(g, "VAN_EX1_594")
	var a := H.board(g, 1, "VAN_CS2_182")
	H.attack(g, a, g.hero(0))
	eq([a.zone, g.hero(0).health()], ["GRAVEYARD", 30], "destroyed before damage")


func test_cone_of_cold() -> void:
	var g := H.game()
	var a := H.board(g, 1, "VAN_CS2_182")
	var b := H.board(g, 1, "VAN_CS2_182")
	var c := H.board(g, 1, "VAN_CS2_182")
	var d := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_275"), b)
	eq([a.health(), b.health(), c.health(), d.health()], [4, 4, 4, 5], "target and neighbours")
	check(a.has("FROZEN") and c.has("FROZEN") and not d.has("FROZEN"), "frozen")


func test_ethereal_arcanist() -> void:
	var g := H.game()
	var e := H.board(g, 0, "VAN_EX1_274")
	H.end_turn(g)
	H.end_turn(g)
	eq(e.atk(), 3, "no secret")
	H.play(g, H.hand(g, 0, "VAN_EX1_287"))
	H.end_turn(g)
	eq([e.atk(), e.max_health()], [5, 5], "+2/+2 with secret")


func test_fireball_polymorph_pyroblast() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_029"), g.hero(1))
	eq(g.hero(1).health(), 24, "fireball 6")
	var y := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_022"), y)
	eq(g.players[1].board[0].card_id, "VAN_CS2_tk1", "sheep")
	g.players[0].mana = 10
	H.play(g, H.hand(g, 0, "VAN_EX1_279"), g.hero(1))
	eq(g.hero(1).health(), 14, "pyroblast 10")


func test_water_elemental() -> void:
	var g := H.game()
	var w := H.board(g, 0, "VAN_CS2_033")
	var y := H.board(g, 1, "VAN_CS2_182")
	H.attack(g, w, y)
	check(y.has("FROZEN"), "target frozen")


func test_archmage_antonidas() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_EX1_559")
	H.play(g, H.hand(g, 0, "GAME_005"))
	eq(g.players[0].hand.map(func(e): return e.card_id), ["VAN_CS2_029"], "fireball")
