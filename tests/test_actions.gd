extends TestCase


func _setup_cards() -> void:
	H.card("TEST_BOLT", {"type": "SPELL", "cost": 1},
		{"target": T.ANY, "spell": func(g, me, t): g.damage(me, t, g.spell_dmg(me, 2))})
	H.card("TEST_BC", {"type": "MINION", "cost": 1, "attack": 1, "health": 1},
		{"target": T.ENEMY_MINION, "battlecry": func(g, me, t): g.damage(me, t, 1)})
	H.card("TEST_COMBO", {"type": "MINION", "cost": 1, "attack": 1, "health": 1},
		{"battlecry": func(g, me, _t): g.gain_armor(me.controller, 1),
		 "combo": func(g, me, _t): g.gain_armor(me.controller, 5)})


func test_play_minion_pays_and_places() -> void:
	var g := H.game()
	var w := H.hand(g, 0, H.WISP)
	var r := H.play(g, w)
	check(r.ok, r.error)
	eq(w.zone, "PLAY", "on board")
	eq(g.players[0].mana, 10, "wisp costs 0")
	check(g.players[0].hand.is_empty(), "hand empty")


func test_not_enough_mana() -> void:
	var g := H.game()
	g.players[0].mana = 3
	var m := H.hand(g, 0, "VAN_CS2_029")  # Fireball, 4
	check(not H.play(g, m, g.players[1].hero).ok, "rejected")


func test_targeted_spell() -> void:
	_setup_cards()
	var g := H.game()
	var s := H.hand(g, 0, "TEST_BOLT")
	check(H.play(g, s, g.players[1].hero).ok, "ok")
	eq(g.players[1].hero.health(), 28, "2 damage")
	eq(s.zone, "GRAVEYARD", "spell gone")


func test_spell_without_valid_target_is_unplayable() -> void:
	H.card("TEST_MINION_SPELL", {"type": "SPELL", "cost": 0},
		{"target": T.ENEMY_MINION, "spell": func(g, me, t): g.destroy(t)})
	var g := H.game()
	var s := H.hand(g, 0, "TEST_MINION_SPELL")
	for a in g.legal_actions():
		check(not (a.type == "play" and a.entity == s.id), "no legal play")


func test_battlecry_without_target_still_playable() -> void:
	_setup_cards()
	var g := H.game()
	var m := H.hand(g, 0, "TEST_BC")
	check(H.play(g, m).ok, "played without target")


func test_battlecry_hits_target() -> void:
	_setup_cards()
	var g := H.game()
	var enemy := H.board(g, 1, H.WISP)
	var m := H.hand(g, 0, "TEST_BC")
	check(H.play(g, m, enemy).ok, "ok")
	eq(enemy.zone, "GRAVEYARD", "killed")


func test_combo() -> void:
	_setup_cards()
	var g := H.game()
	H.play(g, H.hand(g, 0, "TEST_COMBO"))
	eq(g.players[0].hero.tags.ARMOR, 1, "no combo first")
	H.play(g, H.hand(g, 0, "TEST_COMBO"))
	eq(g.players[0].hero.tags.ARMOR, 6, "combo second")


func test_overload_from_card_data() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_247"))  # Stormforged Axe, Overload (1)
	eq(g.players[0].overload_owed, 1, "owed")


func test_attack_minion_trade() -> void:
	var g := H.game()
	var a := H.board(g, 0, "VAN_CS2_120")  # River Crocolisk 2/3
	var d := H.board(g, 1, "VAN_CS1_042")  # Goldshire Footman 1/2
	check(H.attack(g, a, d).ok, "ok")
	eq(d.zone, "GRAVEYARD", "defender dead")
	eq(a.health(), 2, "attacker took 1")


func test_cannot_attack_when_exhausted() -> void:
	var g := H.game()
	var a := H.hand(g, 0, "VAN_CS2_120")
	H.play(g, a)
	check(not H.attack(g, a, g.players[1].hero).ok, "summoning sickness")


func test_charge_attacks_at_once() -> void:
	var g := H.game()
	var a := H.hand(g, 0, "VAN_CS2_171")  # Stonetusk Boar
	H.play(g, a)
	check(H.attack(g, a, g.players[1].hero).ok, "charge")


func test_taunt_blocks() -> void:
	var g := H.game()
	var a := H.board(g, 0, "VAN_CS2_120")
	H.board(g, 1, "VAN_CS1_042")  # taunt
	check(not H.attack(g, a, g.players[1].hero).ok, "must hit taunt")


func test_stealth_taunt_does_not_block() -> void:
	var g := H.game()
	var a := H.board(g, 0, "VAN_CS2_120")
	var t := H.board(g, 1, "VAN_CS1_042")
	t.give_tag("STEALTH")
	check(H.attack(g, a, g.players[1].hero).ok, "stealthed taunt ignored")


func test_windfury_two_attacks() -> void:
	var g := H.game()
	var a := H.board(g, 0, "VAN_CS2_120")
	a.give_tag("WINDFURY")
	check(H.attack(g, a, g.players[1].hero).ok, "first")
	check(H.attack(g, a, g.players[1].hero).ok, "second")
	check(not H.attack(g, a, g.players[1].hero).ok, "third")


func test_frozen_cannot_attack() -> void:
	var g := H.game()
	var a := H.board(g, 0, "VAN_CS2_120")
	a.tags["FROZEN"] = true
	check(not H.attack(g, a, g.players[1].hero).ok, "frozen")


func test_hero_attacks_with_weapon() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_106"))  # Fiery War Axe 3/2
	var hero := g.players[0].hero
	check(H.attack(g, hero, g.players[1].hero).ok, "hero attack")
	eq(g.players[1].hero.health(), 27, "3 damage")
	eq(int(g.players[0].weapon.tags.DURABILITY), 1, "durability -1")


func test_weapon_inactive_on_enemy_turn() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_106"))
	H.end_turn(g)
	var a := H.board(g, 1, "VAN_CS2_120")
	H.attack(g, a, g.players[0].hero)
	eq(a.health(), 3, "hero deals no damage back on enemy turn")


func test_attacking_breaks_stealth() -> void:
	var g := H.game()
	var a := H.board(g, 0, "VAN_CS2_120")
	a.give_tag("STEALTH")
	H.attack(g, a, g.players[1].hero)
	check(not a.has("STEALTH"), "stealth lost")


func test_hero_power_once_per_turn() -> void:
	var g := H.game()  # Jaina, Fireblast
	check(H.power(g, g.players[1].hero).ok, "first")
	eq(g.players[1].hero.health(), 29, "1 damage")
	check(not H.power(g, g.players[1].hero).ok, "second rejected")


func test_apply_accepts_json_roundtrip() -> void:
	var g := H.game()
	var w := H.hand(g, 0, H.WISP)
	var action := {"type": "play", "player": 0, "entity": w.id, "target": -1, "pos": 0, "choice": -1}
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(action))
	check(g.apply(parsed).ok, "float fields accepted")


func test_illegal_action_keeps_state() -> void:
	var g := H.game()
	var before := g.state_hash()
	var r := g.apply({"type": "attack", "player": 0, "attacker": 999, "defender": 1})
	check(not r.ok, "rejected")
	eq(g.state_hash(), before, "state unchanged")


func test_no_actions_after_game_over() -> void:
	var g := H.game()
	g.apply({"type": "concede", "player": 0})
	eq(g.legal_actions(), [], "no actions")
	check(not H.end_turn(g).ok, "rejected")


func test_full_board_blocks_minion_play() -> void:
	var g := H.game()
	for i in 7:
		H.board(g, 0, H.WISP)
	var w := H.hand(g, 0, H.WISP)
	check(not H.play(g, w).ok, "board full")


func test_legal_positions() -> void:
	var g := H.game()
	H.board(g, 0, H.WISP)
	H.board(g, 0, H.WISP)
	var w := H.hand(g, 0, H.WISP)
	var pos := []
	for a in g.legal_actions():
		if a.type == "play" and a.entity == w.id:
			pos.append(a.pos)
	eq(pos, [0, 1, 2], "3 positions")


func test_choose_one() -> void:
	H.card("TEST_OPT_A", {"type": "SPELL"}, {"effect": func(g, me, _t): g.gain_armor(me.controller, 1)})
	H.card("TEST_OPT_B", {"type": "SPELL"}, {"target": T.ENEMY_CHAR,
		"effect": func(g, me, t): g.damage(me, t, 3)})
	H.card("TEST_CHOOSE", {"type": "SPELL", "cost": 0}, {"choose_one": ["TEST_OPT_A", "TEST_OPT_B"]})
	var g := H.game()
	var c := H.hand(g, 0, "TEST_CHOOSE")
	check(H.play(g, c, g.players[1].hero, -1, 1).ok, "option B")
	eq(g.players[1].hero.health(), 27, "3 damage")


func test_pending_choice_blocks_other_actions() -> void:
	H.card("TEST_PICK", {"type": "SPELL", "cost": 0}, {
		"spell": func(g, me, _t):
			var opts: Array[int] = []
			for e in g.players[me.controller].deck.slice(-2):
				opts.append(e.id)
			g.request_choice(me, opts),
		"on_choose": func(g, me, opt):
			g.players[me.controller].deck.erase(opt)
			opt.zone = "HAND"
			g.players[me.controller].hand.append(opt)})
	var g := H.game()
	H.play(g, H.hand(g, 0, "TEST_PICK"))
	var acts := g.legal_actions()
	eq(acts.size(), 2, "only choices")
	eq(acts[0].type, "choose", "choose action")
	check(g.apply(acts[0]).ok, "choose ok")
	eq(g.players[0].hand.size(), 1, "picked card in hand")
	check(g.pending.is_empty(), "pending cleared")


func test_targeted_battlecry_without_target_does_nothing() -> void:
	H.card("TEST_BUFF_BC", {"type": "MINION", "cost": 0, "attack": 1, "health": 1},
		{"target": T.FRIENDLY_MINION, "battlecry": func(g, _me, t): g.buff(t, 1, 1)})
	var g := H.game()
	var m := H.hand(g, 0, "TEST_BUFF_BC")
	check(H.play(g, m).ok, "played with no friendly minion to target")
	eq(m.atk(), 1, "no effect")
