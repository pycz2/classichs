extends TestCase


func _deck(n: int) -> Array:
	var d := []
	for i in n:
		d.append(H.WISP)
	return d


func test_inner_rage_and_cruel_taskmaster() -> void:
	var g := H.game()
	var y := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_607"), y)
	eq([y.atk(), y.health()], [6, 4], "1 damage, +2 attack")
	H.play(g, H.hand(g, 0, "VAN_EX1_603"), y)
	eq([y.atk(), y.health()], [8, 3], "taskmaster same")


func test_execute() -> void:
	var g := H.game()
	var y := H.board(g, 1, "VAN_CS2_182")
	check(not H.play(g, H.hand(g, 0, "VAN_CS2_108"), y).ok, "damaged only")
	y.damage = 1
	H.play(g, H.hand(g, 0, "VAN_CS2_108"), y)
	eq(y.zone, "GRAVEYARD", "destroyed")


func test_shield_slam() -> void:
	var g := H.scene({"hero": "HERO_01", "armor": 4})
	var y := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_410"), y)
	eq(y.health(), 1, "4 armor = 4 damage")


func test_upgrade() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_409"))
	var w := g.players[0].weapon
	eq([w.card_id, w.atk(), int(w.tags.DURABILITY)], ["EX1_409t", 1, 3], "heavy axe")
	H.play(g, H.hand(g, 0, "VAN_EX1_409"))
	eq([w.atk(), int(w.tags.DURABILITY)], [2, 4], "+1/+1")


func test_whirlwind() -> void:
	var g := H.game()
	var a := H.board(g, 0, "VAN_CS2_182")
	var b := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_400"))
	eq([a.health(), b.health(), g.hero(1).health()], [4, 4, 30], "1 to all minions")


func test_armorsmith() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_EX1_402")
	var w := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_400"))
	eq(int(g.hero(0).tags.ARMOR), 2, "1 per damaged friendly minion")


func test_battle_rage() -> void:
	var g := H.scene({"hero": "HERO_01", "damage": 3, "deck": _deck(5),
		"board": [{"card": "VAN_CS2_182", "damage": 1}, "VAN_CS2_182"]})
	H.play(g, H.hand(g, 0, "VAN_EX1_392"))
	eq(g.players[0].hand.size(), 2, "hero + 1 minion")


func test_cleave() -> void:
	var g := H.game()
	H.board(g, 1, "VAN_CS2_182")
	check(not H.play(g, H.hand(g, 0, "VAN_CS2_114")).ok, "needs 2")
	H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_114"))
	eq(g.players[1].board.map(func(m): return m.health()), [3, 3], "2 each")


func test_commanding_shout() -> void:
	var g := H.scene({"hero": "HERO_01", "deck": _deck(2)})
	var w := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_NEW1_036"))
	var late := H.hand(g, 0, H.WISP)
	H.play(g, late)
	H.play(g, H.hand(g, 0, "VAN_EX1_400"))  # Whirlwind
	g.damage(g.hero(1), w, 10)
	g.resolve()
	eq([w.health(), late.health()], [1, 1], "cannot drop below 1, also later minions")
	eq(g.players[0].hand.size(), 1, "drew")
	H.end_turn(g)
	g.damage(g.hero(1), w, 10)
	g.resolve()
	eq(w.zone, "GRAVEYARD", "this turn only")


func test_heroic_strike() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_105"))
	H.attack(g, g.hero(0), g.hero(1))
	eq(g.hero(1).health(), 26, "4")


func test_rampage() -> void:
	var g := H.game()
	var y := H.board(g, 0, "VAN_CS2_182")
	check(not H.play(g, H.hand(g, 0, "VAN_CS2_104"), y).ok, "damaged only")
	y.damage = 1
	H.play(g, H.hand(g, 0, "VAN_CS2_104"), y)
	eq([y.atk(), y.health()], [7, 7], "+3/+3")


func test_slam() -> void:
	var g := H.scene({"hero": "HERO_01", "deck": _deck(3)})
	var y := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_391"), y)
	eq(g.players[0].hand.size(), 1, "survived: draw")
	var w := H.board(g, 1, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_391"), w)
	eq(g.players[0].hand.size(), 1, "died: no draw")


func test_charge_spell() -> void:
	var g := H.game()
	var y := H.hand(g, 0, "VAN_CS2_182")
	H.play(g, y)
	H.play(g, H.hand(g, 0, "VAN_CS2_103"), y)
	eq(y.atk(), 6, "+2")
	check(H.attack(g, y, g.hero(1)).ok, "charge")


func test_frothing_berserker() -> void:
	var g := H.game()
	var f := H.board(g, 0, "VAN_EX1_604")
	H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_EX1_400"))
	eq(f.atk(), 4, "+1 per damaged minion (itself and the enemy)")


func test_shield_block() -> void:
	var g := H.scene({"hero": "HERO_01", "deck": _deck(2)})
	H.play(g, H.hand(g, 0, "VAN_EX1_606"))
	eq([int(g.hero(0).tags.ARMOR), g.players[0].hand.size()], [5, 1], "5 armor, draw")


func test_warsong_commander() -> void:
	var g := H.game()
	var w := H.hand(g, 0, "VAN_EX1_084")
	H.play(g, w)
	check(not H.attack(g, w, g.hero(1)).ok, "not itself")
	var small := H.hand(g, 0, "VAN_CS2_120")
	H.play(g, small)
	check(H.attack(g, small, g.hero(1)).ok, "3 or less gets charge")
	var big := H.hand(g, 0, "VAN_CS2_182")
	H.play(g, big)
	check(not big.has("CHARGE"), "4 attack does not")


func test_arathi_weaponsmith() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_398"))
	var w := g.players[0].weapon
	eq([w.card_id, w.atk(), int(w.tags.DURABILITY)], ["EX1_398t", 2, 2], "battle axe")


func test_mortal_strike() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_408"), g.hero(1))
	eq(g.hero(1).health(), 26, "4")
	g.hero(0).damage = 18
	H.play(g, H.hand(g, 0, "VAN_EX1_408"), g.hero(1))
	eq(g.hero(1).health(), 20, "6 at 12 health")


func test_brawl() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_CS2_182")
	check(not H.play(g, H.hand(g, 0, "VAN_EX1_407")).ok, "needs 2 minions")
	H.board(g, 1, "VAN_CS2_182")
	H.board(g, 1, "VAN_CS2_120")
	H.play(g, H.hand(g, 0, "VAN_EX1_407"))
	eq(g.all_minions().size(), 1, "one survivor")


func test_gorehowl() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_411"))
	var w := g.players[0].weapon
	H.attack(g, g.hero(0), H.board(g, 1, "VAN_CS2_182"))
	eq([w.atk(), int(w.tags.DURABILITY)], [6, 1], "minion: attack -1, durability kept")
	H.end_turn(g)
	H.end_turn(g)
	H.attack(g, g.hero(0), g.hero(1))
	eq(g.players[0].weapon, null, "hero: durability -1, broke")


func test_grommash_hellscream() -> void:
	var g := H.game()
	var gr := H.hand(g, 0, "VAN_EX1_414")
	H.play(g, gr)
	check(H.attack(g, gr, g.hero(1)).ok, "charge")
	g.damage(g.hero(1), gr, 1)
	g.resolve()
	eq(gr.atk(), 10, "enrage +6")
