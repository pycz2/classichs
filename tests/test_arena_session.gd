extends TestCase
## The online Arena over a loopback pair: hello, the opponent's progress, the
## games of the series over one connection, the score, conceding and leaving.


## Host and guest Arena sessions, connected. Returns [host, guest, transports, games, fails].
func _pair() -> Array:
	var tr := LoopbackTransport.pair()
	var h := ArenaSession.new()
	var g := ArenaSession.new()
	h.setup(tr[0], true, "Host", 1)
	g.setup(tr[1], false, "Guest", 2)
	var games := [[], []]
	var fails := [[], []]
	h.game_started.connect(func(_s, m): games[0].append(m))
	g.game_started.connect(func(_s, m): games[1].append(m))
	h.failed.connect(func(r): fails[0].append(r))
	g.failed.connect(func(r): fails[1].append(r))
	h.say_hello()
	g.say_hello()
	LoopbackTransport.pump(tr)
	return [h, g, tr, games, fails]


## A pair with the rules chosen by the host.
func _pair_with(rules: String) -> Array:
	var p := _pair()
	p[0].set_rules(rules)
	LoopbackTransport.pump(p[2])
	return p


func _free(p: Array) -> void:
	for side in p[3]:
		for m in side:
			if is_instance_valid(m):
				m.free()
	for s in [p[0], p[1]]:
		s.end_game()
	for t in p[2]:
		t.free()
	p[0].free()
	p[1].free()


func _draft(s: ArenaSession) -> void:
	s.draft.choose_hero(0)
	while not s.draft.done():
		s.draft.pick(0)
	s.send_status()


## Both drafted and ready: game 1 starts on both sides.
func _to_first_game(p: Array) -> void:
	for s in [p[0], p[1]]:
		_draft(s)
		s.set_ready()
	LoopbackTransport.pump(p[2])


## The guest concedes the current game; both go back to the lobby.
func _guest_concedes(p: Array) -> void:
	var m: Match = p[3][1][-1]
	m.submit({"type": "concede", "player": m.viewer()})
	LoopbackTransport.pump(p[2])
	for s in [p[0], p[1]]:
		s.end_game()


func test_hello_connects_and_names() -> void:
	var p := _pair()
	check(p[0].connected and p[1].connected, "both connected")
	eq(p[0].remote_name, "Guest", "host knows the guest")
	eq(p[1].remote_name, "Host", "guest knows the host")
	eq(p[4], [[], []], "no failures")
	_free(p)


func test_the_opponent_sees_progress_but_not_the_hero() -> void:
	var p := _pair()
	var h: ArenaSession = p[0]
	eq(p[1].remote, {"hero": false, "cards": 0, "ready": false, "deciding": false}, "choosing a hero")
	h.draft.choose_hero(1)
	h.draft.pick(0)
	h.draft.pick(2)
	h.send_status()
	LoopbackTransport.pump(p[2])
	eq(p[1].remote, {"hero": true, "cards": 2, "ready": false, "deciding": false}, "a hero is chosen, 2 cards")
	check(not str(p[2][1]).contains(h.draft.hero), "the hero itself is not sent")
	_free(p)


func test_ready_needs_a_full_deck() -> void:
	var p := _pair()
	p[0].draft.choose_hero(0)
	p[0].set_ready()
	check(not p[0].is_ready, "not ready with 0 cards")
	_free(p)


func test_both_ready_start_the_same_game_with_the_arena_decks() -> void:
	var p := _pair()
	_to_first_game(p)
	var games: Array = p[3]
	eq([games[0].size(), games[1].size()], [1, 1], "game 1 started on both sides")
	var hm: Match = games[0][0]
	var gm: Match = games[1][0]
	eq(hm.game.state_hash(), gm.game.state_hash(), "the same game")
	var cards := []
	for e in hm.game.players[0].deck + hm.game.players[0].hand:
		cards.append(e.card_id)
	cards.sort()
	var drafted: Array = p[0].draft.cards.duplicate()
	drafted.sort()
	if hm.game.players[0].hand.any(func(e): return e.card_id == "GAME_005"):
		drafted.append("GAME_005")
		drafted.sort()
	eq(cards, drafted, "the host plays its drafted cards")
	eq(hm.game.players[1].hero.card_id, p[1].draft.hero, "against the guest's drafted hero")
	check(not p[0].is_ready and not p[1].is_ready, "ready is cleared for the next game")
	_free(p)


func test_series_to_three_wins() -> void:
	var p := _pair()
	_to_first_game(p)
	for n in 3:
		_guest_concedes(p)
		eq(p[0].score, [n + 1, 0], "host score after game %d" % (n + 1))
		eq(p[1].score, [0, n + 1], "guest score after game %d" % (n + 1))
		if n < 2:
			check(not p[0].over, "not over yet")
			for s in [p[0], p[1]]:
				s.set_ready()
			LoopbackTransport.pump(p[2])
			eq(p[3][0].size(), n + 2, "game %d started" % (n + 2))
	check(p[0].over and p[1].over, "the series is over")
	eq([p[0].winner, p[1].winner], [0, 1], "the host won the Arena (0 = this side)")
	p[0].set_ready()
	LoopbackTransport.pump(p[2])
	eq(p[3][0].size(), 3, "no fourth game")
	_free(p)


func test_a_draw_does_not_count() -> void:
	var p := _pair()
	p[0].record(-1)
	eq(p[0].score, [0, 0], "no score for a draw")
	p[0].record(p[0].local_player())
	eq(p[0].score, [1, 0], "a win for this side")
	_free(p)


func test_concede_the_arena() -> void:
	var p := _pair()
	_to_first_game(p)
	_guest_concedes(p)
	p[1].concede()
	LoopbackTransport.pump(p[2])
	check(p[0].over and p[1].over, "over on both sides")
	eq([p[0].winner, p[1].winner], [0, 1], "the host wins")
	_free(p)


func test_leaving_gives_the_arena_to_the_other() -> void:
	var p := _pair()
	_to_first_game(p)
	p[1].leave()
	LoopbackTransport.pump(p[2])
	check(p[0].over, "over")
	eq(p[0].winner, 0, "the host wins")
	check(p[0].remote_left, "the guest left")
	_free(p)


func test_connection_loss_fails() -> void:
	var p := _pair()
	p[2][1].close("gone")
	LoopbackTransport.pump(p[2])
	eq(p[4][0].size(), 1, "the host is told")
	_free(p)


func test_arena_and_normal_game_do_not_mix() -> void:
	var tr := LoopbackTransport.pair()
	var a := ArenaSession.new()
	var n := NetSession.new()
	a.setup(tr[0], true, "A", 1)
	var d := Deck.new()
	d.hero = "HERO_08"
	d.cards.assign(Decks.basic("MAGE"))
	n.setup(tr[1], false, "N", d)
	var fails := [[], []]
	a.failed.connect(func(r): fails[0].append(r))
	n.failed.connect(func(r): fails[1].append(r))
	a.say_hello()
	n.say_hello()
	LoopbackTransport.pump(tr)
	eq(fails[0].size(), 1, "the Arena side fails")
	eq(fails[1].size(), 1, "the game side fails")
	check(fails[0][0].contains("normal game") or fails[0][0].contains("other kind"), "a clear reason: " + str(fails[0]))
	for t in tr:
		t.free()
	a.free()
	n.free()


func test_a_broken_message_ends_the_arena_on_both_sides() -> void:
	var p := _pair()
	p[2][1].send({"t": "nonsense"})
	LoopbackTransport.pump(p[2])
	eq(p[4][0].size(), 1, "the host fails")
	check(p[1].failure != "", "the guest is told too: " + p[1].failure)
	check(not p[1].over, "nobody wins an Arena that broke")
	_free(p)


func test_concede_while_a_game_is_starting_does_not_start_it() -> void:
	var p := _pair()
	for s in [p[0], p[1]]:
		_draft(s)
	p[1].set_ready()
	LoopbackTransport.pump(p[2])
	p[0].set_ready()  # the host starts game 1 and sends its hello
	p[1].concede()  # the guest gives up before the hello comes
	LoopbackTransport.pump(p[2])
	check(p[0].over and p[1].over, "over")
	eq(p[3][1].size(), 0, "the guest is not pulled into a game")
	eq(p[4], [[], []], "no failure on either side")
	_free(p)


func test_the_host_chooses_the_rules() -> void:
	var p := _pair()
	eq([p[0].rules, p[1].rules], ["", ""], "not chosen yet")
	p[1].set_rules("each", true)
	LoopbackTransport.pump(p[2])
	eq([p[0].rules, p[1].rules], ["", ""], "the guest can't choose")
	p[0].set_rules("each", true)
	LoopbackTransport.pump(p[2])
	eq([p[0].rules, p[1].rules], ["each", "each"], "the host's choice reaches the guest")
	eq([p[0].may_keep, p[1].may_keep], [true, true], "the same on both sides")
	p[0].set_rules("one")
	LoopbackTransport.pump(p[2])
	eq([p[0].rules, p[1].rules], ["each", "each"], "chosen once")
	_free(p)


func test_one_deck_for_the_whole_arena() -> void:
	var p := _pair()
	p[0].set_rules("one")
	LoopbackTransport.pump(p[2])
	_to_first_game(p)
	var cards: Array = p[0].draft.cards.duplicate()
	_guest_concedes(p)
	eq(p[0].draft.cards, cards, "the same deck after a game")
	check(p[0].draft.done(), "and still complete")
	_free(p)


func test_a_new_deck_for_every_game() -> void:
	var p := _pair()
	p[0].set_rules("each", false)
	LoopbackTransport.pump(p[2])
	_to_first_game(p)
	var first: Array = p[0].draft.cards.duplicate()
	_guest_concedes(p)
	for s in [p[0], p[1]]:
		eq(s.draft.hero, "", "a new hero to choose")
		eq(s.draft.cards.size(), 0, "a new deck to draft")
	LoopbackTransport.pump(p[2])
	eq(p[1].remote, {"hero": false, "cards": 0, "ready": false, "deciding": false}, "the opponent sees the new draft")
	for s in [p[0], p[1]]:
		_draft(s)
		s.set_ready()
	LoopbackTransport.pump(p[2])
	eq(p[3][0].size(), 2, "game 2 starts")
	var m: Match = p[3][0][1]
	var cards := []
	for e in m.game.players[0].deck + m.game.players[0].hand:
		if e.card_id != "GAME_005":
			cards.append(e.card_id)
	cards.sort()
	var second: Array = p[0].draft.cards.duplicate()
	second.sort()
	eq(cards, second, "game 2 is played with the new deck")
	check(second != first, "a different deck")
	eq(p[0].score, [1, 0], "the score goes on")
	_free(p)


func test_keeping_the_deck_when_allowed() -> void:
	var p := _pair()
	p[0].set_rules("each", true)
	LoopbackTransport.pump(p[2])
	_to_first_game(p)
	var host_cards: Array = p[0].draft.cards.duplicate()
	_guest_concedes(p)
	check(p[0].deck_choice and p[1].deck_choice, "both decide: a new deck or the same")
	p[0].set_ready()
	check(not p[0].is_ready, "no Ready before deciding")
	LoopbackTransport.pump(p[2])
	check(p[1].remote.deciding, "the guest sees the host deciding")
	p[0].keep_deck()
	p[1].new_deck()
	LoopbackTransport.pump(p[2])
	eq(p[0].draft.cards, host_cards, "the host keeps the deck")
	eq(p[1].draft.cards.size(), 0, "the guest drafts again")
	eq(p[0].remote, {"hero": false, "cards": 0, "ready": false, "deciding": false}, "the host sees the guest's new draft")
	_draft(p[1])
	p[0].set_ready()
	p[1].set_ready()
	LoopbackTransport.pump(p[2])
	eq(p[3][0].size(), 2, "game 2 starts")
	_free(p)


func test_no_choice_when_keeping_is_not_allowed() -> void:
	var p := _pair()
	p[0].set_rules("each", false)
	LoopbackTransport.pump(p[2])
	_to_first_game(p)
	_guest_concedes(p)
	check(not p[0].deck_choice and not p[1].deck_choice, "no choice: a new deck is a must")
	eq(p[0].draft.cards.size(), 0, "drafting again")
	_free(p)
