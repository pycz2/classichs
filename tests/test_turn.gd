extends TestCase


func _new_game(seed := 3, first := 0) -> Game:
	var deck: Array = []
	for i in 30:
		deck.append(H.WISP)
	return Game.new({"hero": "HERO_08", "deck": deck}, {"hero": "HERO_01", "deck": deck.duplicate()}, seed, first)


func test_opening_hands_and_coin() -> void:
	var g := _new_game()
	eq(g.phase, "MULLIGAN", "phase")
	eq(g.players[0].hand.size(), 3, "first player 3")
	eq(g.players[1].hand.size(), 4, "second player 4")
	g.apply({"type": "mulligan", "player": 0, "replace": []})
	g.apply({"type": "mulligan", "player": 1, "replace": []})
	eq(g.phase, "PLAY", "play phase")
	eq(g.players[1].hand.back().card_id, "GAME_005", "coin for second")
	eq(g.players[0].hand.size(), 4, "first player drew")
	eq([g.players[0].mana, g.players[0].max_mana], [1, 1], "1 mana")


func test_mulligan_replaces_with_other_cards() -> void:
	var g := _new_game()
	var old := g.players[0].hand.duplicate()
	var ids: Array = [old[0].id, old[1].id]
	ids.sort()
	var r := g.apply({"type": "mulligan", "player": 0, "replace": ids})
	check(r.ok, "ok")
	eq(g.players[0].hand.size(), 3, "same size")
	check(not g.players[0].hand.has(old[0]), "replaced card left the hand")
	eq(g.players[0].deck.size(), 27, "deck size kept")


func test_first_player_by_rng_is_deterministic() -> void:
	var a := _new_game(11, -1)
	var b := _new_game(11, -1)
	eq(a.current, b.current, "same first player")


func test_mana_grows_and_caps() -> void:
	var g := H.game()
	g.players[0].max_mana = 8
	for i in 6:
		H.end_turn(g)
	eq(g.players[0].max_mana, 10, "8 -> 9 -> 10 -> stays 10")


func test_overload_locks_next_turn() -> void:
	var g := H.game()
	g.players[0].overload_owed = 2
	g.players[0].max_mana = 5
	H.end_turn(g)
	H.end_turn(g)
	eq(g.players[0].max_mana, 6, "crystal gained")
	eq(g.players[0].mana, 4, "2 locked")
	eq(g.players[0].overload_locked, 2, "locked")


func test_fatigue_grows() -> void:
	var g := H.game()
	g.players[1].deck.clear()
	H.end_turn(g)
	eq(g.players[1].hero.health(), 29, "fatigue 1")
	H.end_turn(g)
	H.end_turn(g)
	eq(g.players[1].hero.health(), 27, "fatigue 2")


func test_full_hand_burns() -> void:
	var g := H.game()
	for i in 10:
		H.hand(g, 1, H.WISP)
	var deck_before := g.players[1].deck.size()
	var r := H.end_turn(g)
	eq(g.players[1].hand.size(), 10, "still 10")
	eq(g.players[1].deck.size(), deck_before - 1, "card left deck")
	check(H.types(r.events).has("burn"), "burn event")


func test_exhausted_cleared_on_own_turn() -> void:
	var g := H.game()
	var m := g.summon(0, H.WISP)
	check(m.has("EXHAUSTED"), "sick")
	H.end_turn(g)
	check(m.has("EXHAUSTED"), "still sick on enemy turn")
	H.end_turn(g)
	check(not m.has("EXHAUSTED"), "ready")


func test_eot_buff_expires() -> void:
	var g := H.game()
	var m := H.board(g, 0, H.WISP)
	g.buff(m, 3, 0, true)
	H.end_turn(g)
	eq(m.atk(), 1, "expired")


func test_freeze_thaws_end_of_own_turn() -> void:
	var g := H.game()
	H.end_turn(g)  # player 1 turn
	var m := H.board(g, 0, H.WISP)
	g.freeze(m)
	H.end_turn(g)  # player 0 turn: frozen
	check(m.has("FROZEN"), "frozen on own turn")
	H.end_turn(g)  # thaws at end of player 0 turn
	check(not m.has("FROZEN"), "thawed")


func test_frozen_after_attacking_stays_next_turn() -> void:
	var g := H.game()
	var m := H.board(g, 0, H.WISP)
	m.tags["ATTACKS"] = 1
	g.freeze(m)  # frozen on own turn after attacking
	H.end_turn(g)
	check(m.has("FROZEN"), "still frozen")
	H.end_turn(g)
	check(m.has("FROZEN"), "frozen through next own turn")
	H.end_turn(g)
	check(not m.has("FROZEN"), "thawed after it")


func test_concede() -> void:
	var g := H.game()
	var r := g.apply({"type": "concede", "player": 0})
	check(r.ok, "ok")
	check(g.game_over, "over")
	eq(g.winner, 1, "opponent wins")


func test_history_records_everything() -> void:
	var g := _new_game()
	eq(g.history[0].action.type, "start", "start entry")
	eq(H.types(g.history[0].events).count("draw"), 7, "opening draws")
	g.apply({"type": "mulligan", "player": 0, "replace": []})
	g.apply({"type": "mulligan", "player": 1, "replace": []})
	g.players[1].deck.clear()
	g.apply({"type": "end_turn", "player": g.current})
	var last: Dictionary = g.history.back()
	eq(last.action.type, "end_turn", "action stored")
	eq(last.player, 0, "who acted")
	check(H.types(last.events).has("fatigue"), "fatigue in history")
	eq(g.history.size(), 4, "start + 2 mulligans + end_turn")


func test_history_is_not_trimmed() -> void:
	var g := H.game()
	var before := g.history.size()
	for i in 300:
		var next := g.opponent(g.current)
		var card := g.new_entity(H.WISP, next)
		card.zone = "DECK"
		g.players[next].deck.append(card)  # no fatigue death
		check(H.end_turn(g).ok, "end_turn %d" % i)
	eq(g.history.size(), before + 300, "every action kept")


func test_wrong_player_rejected() -> void:
	var g := H.game()
	var r := g.apply({"type": "end_turn", "player": 1})
	check(not r.ok, "rejected")
	eq(g.current, 0, "turn kept")
