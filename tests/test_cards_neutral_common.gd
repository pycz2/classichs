extends TestCase


func test_keyword_only_cards() -> void:
	for id in ["VAN_CS2_231", "VAN_EX1_008", "VAN_EX1_405", "VAN_EX1_010", "VAN_CS2_169", "VAN_EX1_017",
			"VAN_EX1_020", "VAN_EX1_021", "VAN_EX1_396", "VAN_EX1_023", "VAN_CS1_069", "VAN_EX1_028",
			"VAN_EX1_033", "VAN_NEW1_023"]:
		var g := H.game()
		var e := H.hand(g, 0, id)
		check(H.play(g, e).ok, id + " playable")
		for m in ["TAUNT", "DIVINE_SHIELD", "STEALTH", "WINDFURY", "ELUSIVE"]:
			eq(e.has(m), e.card().get("mechanics", []).has(m), id + " " + m)


func test_abusive_sergeant_and_dark_iron_dwarf() -> void:
	for id in ["VAN_CS2_188", "VAN_EX1_046"]:
		var g := H.game()
		var enemy := H.board(g, 1, H.WISP)
		H.play(g, H.hand(g, 0, id), enemy)
		eq(enemy.atk(), 3, id + " +2 this turn")
		H.end_turn(g)
		eq(enemy.atk(), 1, id + " expired")


func test_leper_gnome() -> void:
	var g := H.game()
	var l := H.board(g, 0, "VAN_EX1_029")
	g.destroy(l)
	g.resolve()
	eq(g.players[1].hero.health(), 28, "2 to enemy hero")


func test_southsea_deckhand_charge_with_weapon() -> void:
	var g := H.game()
	var d := H.hand(g, 0, "VAN_CS2_146")
	H.play(g, d)
	check(not H.attack(g, d, g.players[1].hero).ok, "no weapon, no charge")
	H.play(g, H.hand(g, 0, "VAN_CS2_106"))
	check(H.attack(g, d, g.players[1].hero).ok, "charge with weapon")


func test_enrage_amani_and_tauren() -> void:
	for id in ["VAN_EX1_393", "VAN_EX1_390"]:
		var g := H.game()
		var m := H.board(g, 0, id)
		var base := m.atk()
		g.damage(g.players[1].hero, m, 1)
		g.resolve()
		eq(m.atk(), base + 3, id + " enraged")
		g.heal(m, m, 5)
		g.resolve()
		eq(m.atk(), base, id + " healed")
	check(CardDb.card("VAN_EX1_390").mechanics.has("TAUNT"), "Tauren Warrior has taunt")


func test_raging_worgen() -> void:
	var g := H.game()
	var m := H.board(g, 0, "VAN_EX1_412")
	g.damage(g.players[1].hero, m, 1)
	g.resolve()
	eq(m.atk(), 4, "+1 attack")
	check(m.has("WINDFURY"), "windfury")


func test_bloodsail_raider() -> void:
	var g := H.scene({"hero": "HERO_01", "weapon": "VAN_CS2_106"})
	var r := H.hand(g, 0, "VAN_NEW1_018")
	H.play(g, r)
	eq(r.atk(), 5, "2 + 3")


func test_dire_wolf_alpha_adjacent_only() -> void:
	var g := H.game()
	var a := H.board(g, 0, H.WISP)
	var b := H.board(g, 0, H.WISP)
	var c := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_162"), null, 1)  # between a and b
	eq([a.atk(), b.atk(), c.atk()], [2, 2, 1], "adjacent +1")


func test_ironbeak_owl_and_spellbreaker() -> void:
	for id in ["VAN_CS2_203", "VAN_EX1_048"]:
		var g := H.game()
		var t := H.board(g, 1, "VAN_CS1_042")
		H.play(g, H.hand(g, 0, id), t)
		check(not t.has("TAUNT") and t.silenced, id + " silenced")


func test_loot_hoarder() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": [H.WISP]})
	var l := H.board(g, 0, "VAN_EX1_096")
	g.destroy(l)
	g.resolve()
	eq(g.players[0].hand.size(), 1, "drew")


func test_mad_bomber_three_damage_not_self() -> void:
	var g := H.game()
	var b := H.hand(g, 0, "VAN_EX1_082")
	H.play(g, b)
	var total := 60 - g.players[0].hero.health() - g.players[1].hero.health()
	eq(total, 3, "3 damage to heroes (only other characters)")
	eq(b.health(), 2, "bomber untouched")


func test_youthful_and_ancient_brewmaster() -> void:
	for id in ["VAN_EX1_049", "VAN_EX1_057"]:
		var g := H.game()
		var w := H.board(g, 0, "VAN_CS2_120")
		var bm := H.hand(g, 0, id)
		check(H.play(g, bm, w).ok, id)
		eq(g.players[0].hand.size(), 1, id + " returned")
		eq(g.players[0].hand[0].card_id, "VAN_CS2_120", id + " same card")


func test_brewmaster_cannot_return_itself_or_enemy() -> void:
	var g := H.game()
	var enemy := H.board(g, 1, H.WISP)
	var bm := H.hand(g, 0, "VAN_EX1_049")
	check(not H.play(g, bm, enemy).ok, "enemy not allowed")
	check(H.play(g, bm).ok, "no target when alone")
	eq(bm.zone, "PLAY", "stays")


func test_acolyte_of_pain() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": [H.WISP, H.WISP]})
	var a := H.board(g, 0, "VAN_EX1_007")
	g.damage(g.players[1].hero, a, 1)
	g.resolve()
	eq(g.players[0].hand.size(), 1, "drew")


func test_earthen_ring_farseer() -> void:
	var g := H.scene({"hero": "HERO_08", "damage": 10})
	H.play(g, H.hand(g, 0, "VAN_CS2_117"), g.players[0].hero)
	eq(g.players[0].hero.health(), 23, "+3")


func test_flesheating_ghoul() -> void:
	var g := H.game()
	var gh := H.board(g, 0, "VAN_tt_004")
	var w := H.board(g, 1, H.WISP)
	g.destroy(w)
	g.resolve()
	eq(gh.atk(), 3, "+1 per death")


func test_harvest_golem() -> void:
	var g := H.game()
	var hg := H.board(g, 0, "VAN_EX1_556")
	g.destroy(hg)
	g.resolve()
	eq(g.players[0].board[0].card_id, "VAN_skele21", "damaged golem")


func test_cult_master() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": [H.WISP, H.WISP]})
	var cm := H.board(g, 0, "VAN_EX1_595")
	var w := H.board(g, 0, H.WISP)
	g.destroy(w)
	g.resolve()
	eq(g.players[0].hand.size(), 1, "drew for friendly death")
	var e := H.board(g, 1, H.WISP)
	g.destroy(e)
	g.resolve()
	eq(g.players[0].hand.size(), 1, "enemy death ignored")


func test_cult_master_dying_together_draws_nothing() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": [H.WISP, H.WISP]})
	var cm := H.board(g, 0, "VAN_EX1_595")
	var w := H.board(g, 0, H.WISP)
	g.destroy(cm)
	g.destroy(w)
	g.resolve()
	eq(g.players[0].hand.size(), 0, "2014: no draw when Cult Master dies at the same time")


func test_dread_corsair_cost() -> void:
	var g := H.scene({"hero": "HERO_01", "weapon": "VAN_CS2_106"})
	var d := H.hand(g, 0, "VAN_NEW1_022")
	eq(g.cost(d), 1, "4 - 3")
	check(d.card().mechanics.has("TAUNT"), "taunt")


func test_silver_hand_knight() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_151"))
	eq(g.players[0].board.back().card_id, "VAN_CS2_152", "squire")


func test_spiteful_smith() -> void:
	var g := H.scene({"hero": "HERO_01", "weapon": "VAN_CS2_106"})
	var s := H.board(g, 0, "VAN_CS2_221")
	eq(g.hero_atk(g.players[0].hero), 3, "not enraged")
	g.damage(g.players[1].hero, s, 1)
	g.resolve()
	eq(g.hero_atk(g.players[0].hero), 5, "weapon +2")


func test_venture_co_mercenary() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_CS2_227")
	var mine := H.hand(g, 0, "VAN_CS2_120")
	var spell := H.hand(g, 0, "VAN_CS2_029")
	var theirs := H.hand(g, 1, "VAN_CS2_120")
	eq([g.cost(mine), g.cost(spell), g.cost(theirs)], [5, 4, 2], "own minions +3")


func test_frost_elemental() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_283"), g.players[1].hero)
	check(g.players[1].hero.has("FROZEN"), "frozen")


func test_priestess_of_elune() -> void:
	var g := H.scene({"hero": "HERO_08", "damage": 10})
	H.play(g, H.hand(g, 0, "VAN_EX1_583"))
	eq(g.players[0].hero.health(), 24, "+4")
