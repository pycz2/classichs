extends TestCase


func _deck(cls: String) -> Deck:
	var d := Deck.new()
	d.hero = Decks.hero(cls)
	d.name = cls
	for id in Decks.basic(cls):
		d.cards.append(id)
	return d


## Host and guest sessions on a loopback pair. Returns [host, guest, transports, matches].
func _pair(host_deck := "MAGE", guest_deck := "WARRIOR") -> Array:
	var tr := LoopbackTransport.pair()
	var h := NetSession.new()
	var g := NetSession.new()
	h.setup(tr[0], true, "Host", _deck(host_deck))
	g.setup(tr[1], false, "Guest", _deck(guest_deck))
	var matches := [null, null]
	var fails := [[], []]
	h.started.connect(func(m): matches[0] = m)
	g.started.connect(func(m): matches[1] = m)
	h.failed.connect(func(r): fails[0].append(r))
	g.failed.connect(func(r): fails[1].append(r))
	h.say_hello()
	g.say_hello()
	LoopbackTransport.pump(tr)
	return [h, g, tr, matches, fails]


func _free(p: Array) -> void:
	for m in p[3]:
		if m:
			m.free()
	for t in p[2]:
		t.free()
	p[0].free()
	p[1].free()


func test_both_sides_start_the_same_game() -> void:
	var p := _pair()
	var m: Array = p[3]
	check(m[0] != null and m[1] != null, "both started")
	eq(m[0].state_hash, m[1].state_hash, "same state")
	eq([m[0].viewer(), m[1].viewer()], [0, 1], "host is player 0")
	eq(p[1].remote_name, "Host", "guest knows the host's name")
	_free(p)


func test_full_match_over_the_network_stays_in_sync() -> void:
	var p := _pair("PRIEST", "HUNTER")
	var m: Array = p[3]
	var steps := 0
	while not m[0].game.game_over and steps < 800:
		var acted := false
		for side in 2:
			var match_: Match = m[side]
			if match_.game.game_over:
				continue
			if match_.actor() == side or (match_.game.phase == "MULLIGAN" and not match_.game.players[side].mulliganed):
				var a = Rules.request({"op": "bot", "game": match_.id, "player": side}).get("action")
				if a is Dictionary and match_.submit(a).ok:
					acted = true
		LoopbackTransport.pump(p[2])
		steps += 1
		if not acted and not m[0].game.game_over:
			break
	check(m[0].game.game_over and m[1].game.game_over, "both finished in %d rounds" % steps)
	eq(m[0].game.winner, m[1].game.winner, "same winner")
	eq(m[0].state_hash, m[1].state_hash, "same final state")
	eq(p[4], [[], []], "no failures")
	_free(p)


func test_version_mismatch_closes_with_message() -> void:
	var tr := LoopbackTransport.pair()
	var h := NetSession.new()
	var g := NetSession.new()
	h.setup(tr[0], true, "Host", _deck("MAGE"))
	g.setup(tr[1], false, "Guest", _deck("MAGE"))
	g.version = "9.9.9"
	var fails := [[], []]
	h.failed.connect(func(r): fails[0].append(r))
	g.failed.connect(func(r): fails[1].append(r))
	h.say_hello()
	g.say_hello()
	LoopbackTransport.pump(tr)
	check(not fails[0].is_empty() and fails[0][0].contains("9.9.9"), "host told: %s" % str(fails[0]))
	check(not fails[1].is_empty(), "guest told")
	for t in tr:
		t.free()
	h.free()
	g.free()


func test_action_for_the_wrong_player_is_a_desync() -> void:
	var p := _pair()
	p[2][1].send({"t": "action", "n": 0, "action": {"type": "concede", "player": 0}, "hash": ""})  # guest concedes for the host
	LoopbackTransport.pump(p[2])
	check(not p[4][0].is_empty(), "host refuses: %s" % str(p[4][0]))
	check(not p[3][0].game.game_over, "no concede applied")
	_free(p)


func test_tampered_hash_is_a_desync() -> void:
	var p := _pair()
	var m: Array = p[3]
	for side in 2:
		m[side].submit({"type": "mulligan", "player": side, "replace": []})
	LoopbackTransport.pump(p[2])
	var actor: int = m[0].game.current
	var legal: Array = m[actor].legal().filter(func(a): return a.player == actor and a.type == "end_turn")
	p[2][actor].send({"t": "action", "n": 1, "action": legal[0], "hash": "bad"})
	LoopbackTransport.pump(p[2])
	check(not p[4][1 - actor].is_empty(), "receiver detects the desync")
	var said := str(TranslationServer.translate(NetSession.DESYNC))
	eq(p[4][1 - actor], [said], "the receiver: the two games differ, nobody is banned")
	eq(p[4][actor], [said], "the sender is told the same")
	_free(p)


func test_garbage_message_fails_cleanly() -> void:
	var p := _pair()
	p[2][1].inbox.append("[1, 2, 3]")
	p[2][1].inbox.append("{\"t\": \"nonsense\"}")
	LoopbackTransport.pump(p[2])
	check(not p[4][1].is_empty(), "guest reports a protocol error")
	_free(p)


func test_connection_lost_mid_game_and_quiet_after_game_over() -> void:
	var p := _pair()
	p[2][0].close("network")
	LoopbackTransport.pump(p[2])
	check(not p[4][1].is_empty(), "guest sees the loss")
	_free(p)
	var q := _pair()
	q[3][0].submit({"type": "concede", "player": 0})
	LoopbackTransport.pump(q[2])
	check(q[3][1].game.game_over, "guest saw the concede")
	q[2][0].close("done")
	LoopbackTransport.pump(q[2])
	eq(q[4][1], [], "no failure after the game is over")
	_free(q)


func test_concurrent_mulligans_and_concede() -> void:
	var p := _pair()
	var m: Array = p[3]
	m[1].submit({"type": "mulligan", "player": 1, "replace": []})
	m[0].submit({"type": "mulligan", "player": 0, "replace": []})
	LoopbackTransport.pump(p[2])
	eq(m[0].state_hash, m[1].state_hash, "same state after both mulligans")
	var actor: int = m[0].game.current
	var other := 1 - actor
	m[actor].submit({"type": "end_turn", "player": actor})
	m[other].submit({"type": "concede", "player": other})  # at the same moment
	LoopbackTransport.pump(p[2])
	eq(p[4], [[], []], "no desync")
	eq(m[0].game.winner, m[1].game.winner, "same winner")
	_free(p)


func test_emotes_reach_the_other_side() -> void:
	var p := _pair()
	var got := []
	p[1].emote_received.connect(func(player, id): got.append([player, id]))
	p[0].send_emote("well_played")
	p[0].send_emote("not_an_emote")
	LoopbackTransport.pump(p[2])
	eq(got, [[0, "well_played"]], "valid emote only")
	_free(p)



func test_typed_garbage_action_fails_cleanly() -> void:
	var p := _pair()
	p[2][1].send({"t": "action", "n": 0, "action": {"type": "end_turn", "player": [1]}, "hash": "x"})
	LoopbackTransport.pump(p[2])
	check(not p[4][0].is_empty(), "host reports it: %s" % str(p[4][0]))
	_free(p)


func test_garbage_start_fails_cleanly() -> void:
	var tr := LoopbackTransport.pair()
	var g := NetSession.new()
	g.setup(tr[1], false, "Guest", _deck("MAGE"))
	var fails := []
	g.failed.connect(func(r): fails.append(r))
	var hello := {"t": "hello", "protocol": NetSession.PROTOCOL, "version": g.version, "data": Rules.data_hash(), "name": "H", "hero": "HERO_08", "cards": Decks.basic("MAGE")}
	tr[0].send(hello)
	tr[0].send({"t": "start", "seed": 1.0, "decks": [5, ["HERO_08", Decks.basic("MAGE")]]})
	LoopbackTransport.pump(tr)
	check(not fails.is_empty(), "guest reports a broken start")
	for t in tr:
		t.free()
	g.free()


func test_second_hello_is_refused() -> void:
	var p := _pair()
	var starts := [0]
	p[0].started.connect(func(_m): starts[0] += 1)
	p[1].say_hello()
	LoopbackTransport.pump(p[2])
	eq(starts[0], 0, "no second game")
	check(not p[4][0].is_empty(), "host refuses")
	_free(p)


func test_wrong_sequence_number_fails() -> void:
	var p := _pair()
	p[2][1].send({"t": "action", "n": 5, "action": {"type": "concede", "player": 1}, "hash": ""})
	LoopbackTransport.pump(p[2])
	check(not p[4][0].is_empty(), "lost move detected")
	_free(p)


func test_empty_hash_only_for_mulligan_and_concede() -> void:
	var p := _pair()
	var m: Array = p[3]
	for side in 2:
		m[side].submit({"type": "mulligan", "player": side, "replace": []})
	LoopbackTransport.pump(p[2])
	var actor: int = m[0].game.current
	p[2][actor].send({"t": "action", "n": 1, "action": {"type": "end_turn", "player": actor}, "hash": ""})
	LoopbackTransport.pump(p[2])
	check(not p[4][1 - actor].is_empty(), "an end_turn without a hash is refused")
	_free(p)


func test_card_data_mismatch_message() -> void:
	var tr := LoopbackTransport.pair()
	var h := NetSession.new()
	h.setup(tr[0], true, "Host", _deck("MAGE"))
	var fails := []
	h.failed.connect(func(r): fails.append(r))
	tr[1].send({"t": "hello", "protocol": NetSession.PROTOCOL, "version": h.version, "data": "other", "name": "G", "hero": "HERO_08", "cards": Decks.basic("MAGE"),
		"pack": NetSession.pack_info(Packs.active())})
	LoopbackTransport.pump(tr)
	check(not fails.is_empty() and not fails[0].contains(h.version + ", the opponent's " + h.version), str(fails))
	check(fails[0].to_lower().contains("card"), "names the card data: " + str(fails))
	for t in tr:
		t.free()
	h.free()


func test_leave_shows_left_and_closes_transport() -> void:
	var p := _pair()
	p[0].leave()
	LoopbackTransport.pump(p[2])
	eq(p[4][1].size(), 1, "guest told once")
	check(p[4][1][0] == str(TranslationServer.translate("The opponent left the game")), str(p[4][1]))
	check(p[2][1]._closed, "guest transport closed")
	eq(p[1].failure_kind, "left", "kind")
	_free(p)
