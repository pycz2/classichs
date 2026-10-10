extends TestCase


func test_keyword_only_cards() -> void:
	for id in ["VAN_CS2_161", "VAN_EX1_067", "VAN_EX1_032", "VAN_EX1_045"]:
		var g := H.game()
		var e := H.hand(g, 0, id)
		check(H.play(g, e).ok, id)
		for m in ["TAUNT", "CHARGE", "DIVINE_SHIELD", "STEALTH", "CANT_ATTACK"]:
			eq(e.has(m), e.card().get("mechanics", []).has(m), id + " " + m)


func test_ancient_watcher_cannot_attack() -> void:
	var g := H.game()
	var w := H.board(g, 0, "VAN_EX1_045")
	check(not H.attack(g, w, g.players[1].hero).ok, "can't attack")


func test_angry_chicken() -> void:
	var g := H.game()
	var c := H.board(g, 0, "VAN_EX1_009")
	c.add_enchant({"hp": 1})
	g.damage(g.players[1].hero, c, 1)
	g.resolve()
	eq(c.atk(), 6, "+5")


func test_bloodsail_corsair() -> void:
	var g := H.scene({"hero": "HERO_08"}, {"hero": "HERO_01", "weapon": "VAN_CS2_106"})
	H.play(g, H.hand(g, 0, "VAN_NEW1_025"))
	eq(int(g.players[1].weapon.tags.DURABILITY), 1, "-1 durability")


func test_bloodsail_corsair_breaks_last_durability() -> void:
	var g := H.scene({"hero": "HERO_08"}, {"hero": "HERO_01", "weapon": {"card": "VAN_CS2_106", "durability": 1}})
	H.play(g, H.hand(g, 0, "VAN_NEW1_025"))
	eq(g.players[1].weapon, null, "destroyed")


func test_lightwarden() -> void:
	var g := H.scene({"hero": "HERO_09", "damage": 5})
	var l := H.board(g, 0, "VAN_EX1_001")
	H.power(g, g.players[0].hero)
	eq(l.atk(), 3, "+2 on heal")
	g.players[0].hero_power.tags.erase("USED")
	g.players[0].hero.damage = 0
	H.power(g, g.players[0].hero)
	eq(l.atk(), 3, "no heal at full health, no trigger")


func test_murloc_tidecaller() -> void:
	var g := H.game()
	var t := H.board(g, 0, "VAN_EX1_509")
	H.play(g, H.hand(g, 0, "VAN_EX1_506"))  # Tidehunter + Scout = 2 murlocs
	g.summon(1, "VAN_CS2_168")  # enemy murloc counts too
	g.resolve()
	eq(t.atk(), 4, "+3")


func test_secretkeeper() -> void:
	var g := H.game()
	var s := H.board(g, 0, "VAN_EX1_080")
	H.play(g, H.hand(g, 0, "VAN_EX1_287"))  # Counterspell
	eq([s.atk(), s.max_health()], [2, 3], "+1/+1")


func test_young_priestess() -> void:
	var g := H.game()
	var p := H.board(g, 0, "VAN_EX1_004")
	var w := H.board(g, 0, H.WISP)
	H.end_turn(g)
	eq([w.max_health(), p.max_health()], [2, 1], "other friendly +1 health")


func test_crazed_alchemist() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_CS2_120")  # 2/3
	t.damage = 1
	H.play(g, H.hand(g, 0, "VAN_EX1_059"), t)
	eq([t.atk(), t.health(), t.max_health()], [2, 2, 2], "2/2 from 2 attack, 2 current health")


func test_crazed_alchemist_zero_attack_dies() -> void:
	var g := H.game()
	var t := H.board(g, 1, "VAN_EX1_405")  # Shieldbearer 0/4
	H.play(g, H.hand(g, 0, "VAN_EX1_059"), t)
	eq(t.zone, "GRAVEYARD", "0 health")


func test_knife_juggler() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_NEW1_019")
	H.play(g, H.hand(g, 0, H.WISP))
	eq(g.players[1].hero.health(), 29, "1 damage to the only enemy")


func test_knife_juggler_ignores_itself_and_enemy_summons() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_NEW1_019"))
	eq(g.players[1].hero.health(), 30, "own summon not counted")
	g.summon(1, H.WISP)
	g.resolve()
	eq(g.players[0].hero.health(), 30, "enemy summon not counted")


func test_mana_addict() -> void:
	var g := H.game()
	var m := H.board(g, 0, "VAN_EX1_055")
	H.play(g, H.hand(g, 0, "GAME_005"))
	eq(m.atk(), 3, "+2")
	H.end_turn(g)
	eq(m.atk(), 1, "this turn only")


func test_mana_wraith() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_EX1_616")
	eq([g.cost(H.hand(g, 0, H.WISP)), g.cost(H.hand(g, 1, H.WISP)), g.cost(H.hand(g, 0, "VAN_CS2_029"))],
		[1, 1, 4], "all minions +1")


func test_master_swordsmith() -> void:
	var g := H.game()
	var s := H.board(g, 0, "VAN_NEW1_037")
	var w := H.board(g, 0, H.WISP)
	H.end_turn(g)
	eq([w.atk(), s.atk()], [2, 1], "other +1 attack")


func test_pint_sized_summoner() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_EX1_076")
	var a := H.hand(g, 0, "VAN_CS2_120")
	eq(g.cost(a), 1, "first minion -1")
	H.play(g, a)
	eq(g.cost(H.hand(g, 0, "VAN_CS2_120")), 2, "second full price")


func test_sunfury_protector() -> void:
	var g := H.game()
	var a := H.board(g, 0, H.WISP)
	var b := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_058"), null, 1)
	check(a.has("TAUNT") and b.has("TAUNT"), "adjacent taunt")


func test_wild_pyromancer() -> void:
	var g := H.game()
	var p := H.board(g, 0, "VAN_NEW1_020")
	var w := H.board(g, 1, H.WISP)
	H.play(g, H.hand(g, 0, "GAME_005"))
	eq(w.zone, "GRAVEYARD", "1 to all minions")
	eq(p.health(), 1, "itself too")


func test_wild_pyromancer_not_on_own_play() -> void:
	var g := H.game()
	var w := H.board(g, 1, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_NEW1_020"))
	eq(w.zone, "PLAY", "playing pyromancer is not a spell")


func test_alarm_o_bot_swaps_with_minion_in_hand() -> void:
	var g := H.game()
	H.board(g, 0, H.WISP)
	var bot := H.board(g, 0, "VAN_EX1_006")
	H.board(g, 0, H.WISP)
	H.hand(g, 0, "VAN_CS2_182")  # Yeti
	H.end_turn(g)
	H.end_turn(g)
	var ids := g.players[0].board.map(func(m): return m.card_id)
	eq(ids, [H.WISP, "VAN_CS2_182", H.WISP], "yeti took the bot's place")
	check(g.players[0].hand.any(func(e): return e.card_id == "VAN_EX1_006"), "bot in hand")
	eq(bot.zone, "SETASIDE", "old bot entity left play")


func test_alarm_o_bot_without_minions_in_hand() -> void:
	var g := H.game()
	var bot := H.board(g, 0, "VAN_EX1_006")
	H.hand(g, 0, "VAN_CS2_029")
	H.end_turn(g)
	H.end_turn(g)
	eq(bot.zone, "PLAY", "stays")


func test_arcane_golem() -> void:
	var g := H.game()
	g.players[1].max_mana = 3
	g.players[1].mana = 0
	var a := H.hand(g, 0, "VAN_EX1_089")
	H.play(g, a)
	eq([g.players[1].max_mana, g.players[1].mana], [4, 1], "full crystal for opponent")
	check(H.attack(g, a, g.players[1].hero).ok, "charge")


func test_coldlight_oracle() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": [H.WISP, H.WISP]}, {"hero": "HERO_01", "deck": [H.WISP, H.WISP]})
	H.play(g, H.hand(g, 0, "VAN_EX1_050"))
	eq([g.players[0].hand.size(), g.players[1].hand.size()], [2, 2], "both drew 2")


func test_coldlight_seer() -> void:
	var g := H.game()
	var mine := H.board(g, 0, "VAN_CS2_168")
	var theirs := H.board(g, 1, "VAN_CS2_168")
	var seer := H.hand(g, 0, "VAN_EX1_103")
	H.play(g, seer)
	eq([mine.max_health(), theirs.max_health(), seer.max_health()], [3, 3, 3], "others +2 health")


func test_demolisher() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_EX1_102")
	H.end_turn(g)
	H.end_turn(g)
	eq(g.players[1].hero.health(), 28, "2 at start of own turn")


func test_emperor_cobra() -> void:
	var g := H.game()
	var c := H.board(g, 0, "VAN_EX1_170")
	var y := H.board(g, 1, "VAN_CS2_182")
	H.attack(g, c, y)
	eq(y.zone, "GRAVEYARD", "destroyed")


func test_imp_master() -> void:
	var g := H.game()
	var m := H.board(g, 0, "VAN_EX1_597")
	H.end_turn(g)
	eq(m.health(), 4, "1 damage to itself")
	eq(g.players[0].board[1].card_id, "VAN_EX1_598", "imp to the right")


func test_injured_blademaster() -> void:
	var g := H.game()
	var b := H.hand(g, 0, "VAN_CS2_181")
	H.play(g, b)
	eq(b.health(), 3, "4 damage to itself")


func test_mind_control_tech() -> void:
	var g := H.game()
	for i in 4:
		H.board(g, 1, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_085"))
	eq([g.players[0].board.size(), g.players[1].board.size()], [2, 3], "stole one")


func test_mind_control_tech_needs_four() -> void:
	var g := H.game()
	for i in 3:
		H.board(g, 1, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_085"))
	eq(g.players[1].board.size(), 3, "nothing stolen")


func test_questing_adventurer() -> void:
	var g := H.game()
	var q := H.hand(g, 0, "VAN_EX1_044")
	H.play(g, q)
	eq(q.atk(), 2, "own play does not count")
	H.play(g, H.hand(g, 0, H.WISP))
	H.play(g, H.hand(g, 0, "GAME_005"))
	eq([q.atk(), q.max_health()], [4, 4], "+1/+1 per card")


func test_ancient_mage() -> void:
	var g := H.game()
	var a := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_584"), null, 0)
	eq(a.spellpower(), 1, "adjacent spell damage")
	eq(g.spell_dmg(g.players[0].hero, 6), 7, "fireball +1")


func test_defender_of_argus() -> void:
	var g := H.game()
	var a := H.board(g, 0, H.WISP)
	var b := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_093"), null, 1)
	for m in [a, b]:
		eq([m.atk(), m.max_health(), m.has("TAUNT")], [2, 2, true], "buffed")


func test_twilight_drake() -> void:
	var g := H.game()
	for i in 3:
		H.hand(g, 0, H.WISP)
	var d := H.hand(g, 0, "VAN_EX1_043")
	H.play(g, d)
	eq(d.max_health(), 4, "1 + 3 cards")


func test_violet_teacher() -> void:
	var g := H.game()
	H.board(g, 0, "VAN_NEW1_026")
	H.play(g, H.hand(g, 0, "GAME_005"))
	eq(g.players[0].board.back().card_id, "VAN_NEW1_026t", "apprentice")


func test_abomination() -> void:
	var g := H.game()
	var a := H.board(g, 0, "VAN_EX1_097")
	var w := H.board(g, 1, H.WISP)
	g.destroy(a)
	g.resolve()
	eq(w.zone, "GRAVEYARD", "2 to all")
	eq([g.players[0].hero.health(), g.players[1].hero.health()], [28, 28], "heroes too")


func test_azure_drake() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": [H.WISP]})
	var d := H.hand(g, 0, "VAN_EX1_284")
	H.play(g, d)
	eq(g.players[0].hand.size(), 1, "drew")
	eq(d.spellpower(), 1, "spell damage")


func test_gadgetzan_auctioneer() -> void:
	var g := H.scene({"hero": "HERO_08", "deck": [H.WISP]})
	H.board(g, 0, "VAN_EX1_095")
	H.play(g, H.hand(g, 0, "GAME_005"))
	eq(g.players[0].hand.size(), 1, "drew")


func test_stampeding_kodo() -> void:
	var g := H.game()
	var small := H.board(g, 1, H.WISP)
	var big := H.board(g, 1, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_NEW1_041"))
	eq([small.zone, big.zone], ["GRAVEYARD", "PLAY"], "only attack <= 2")
