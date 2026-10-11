extends TestCase


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_full_code_exchange_starts_both_games() -> void:
	Profile.path = "user://test_profile_ui.json"
	var pair := FakeRtc.fake_pair()
	var h := OnlineView.new()
	var g := OnlineView.new()
	h.transport_factory = func(): return pair[0]
	g.transport_factory = func():  # a fresh transport per attempt, like the real factory
		var t := FakeRtc.new()
		t.peer = pair[0]
		pair[0].peer = t
		pair[1] = t
		return t
	root().add_child(h)
	root().add_child(g)
	var played := [null, null]
	h.play.connect(func(_s, m): played[0] = m)
	g.play.connect(func(_s, m): played[1] = m)
	h.name_edit.text = "Alice"
	g.name_edit.text = "Bob"
	h.host_game()
	eq(h.state, "code", "invite ready")
	g.join_game("garbage")
	eq(g.state, "failed", "bad invite refused")
	g.join_game(h.code_out.text)
	eq(g.state, "code", "answer ready")
	h.finish(g.code_out.text)
	LoopbackTransport.pump([pair[0], pair[1]])
	check(played[0] != null and played[1] != null, "both games started")
	eq(h.session.remote_name, "Bob", "host sees the guest's name")
	eq(g.session.remote_name, "Alice", "guest sees the host's name")
	h.free()
	g.free()
	DirAccess.remove_absolute(Profile.path)
	Profile.path = Profile.DEFAULT_PATH


func test_answer_pasted_as_invite_is_refused() -> void:
	Profile.path = "user://test_profile_ui2.json"
	var pair := FakeRtc.fake_pair()
	var g := OnlineView.new()
	g.transport_factory = func(): return pair[1]
	root().add_child(g)
	g.join_game(SignalCode.pack("answer", "x", []))
	eq(g.state, "failed", "refused")
	check(g.status.text.contains("answer"), g.status.text)
	g.free()
	pair[0].free()
	DirAccess.remove_absolute(Profile.path)
	Profile.path = Profile.DEFAULT_PATH


func _deck(cls: String) -> Deck:
	var d := Deck.new()
	d.hero = Decks.hero(cls)
	for id in Decks.basic(cls):
		d.cards.append(id)
	return d


func test_online_names_emotes_and_mute() -> void:
	var tr := LoopbackTransport.pair()
	var v := [MatchView.new(), MatchView.new()]
	var s := [NetSession.new(), NetSession.new()]
	for side in 2:
		root().add_child(v[side])
		s[side].setup(tr[side], side == 0, ["Alice", "Bob"][side], _deck(["MAGE", "WARRIOR"][side]))
		var view: MatchView = v[side]
		var sess: NetSession = s[side]
		sess.started.connect(func(m): view.bind_online(m, sess))
	s[0].say_hello()
	s[1].say_hello()
	LoopbackTransport.pump(tr)
	check(v[0].controller != null and v[1].controller != null, "both views bound")
	check(v[0]._names[1].text.contains("Bob"), "host sees Bob: " + v[0]._names[1].text)
	v[0].send_emote("greetings")
	LoopbackTransport.pump(tr)
	check(v[0].bubble_text(0).contains("Greetings"), "own bubble")
	check(v[1].bubble_text(0).contains("Greetings"), "the guest sees the host's emote")
	v[1].muted = true
	v[0].send_emote("wow")
	LoopbackTransport.pump(tr)
	check(not v[1].bubble_text(0).contains("Wow"), "muted emote hidden")
	for side in 2:
		v[side].free()
	for t in tr:
		if is_instance_valid(t):  # bound transports were freed with their view
			t.free()


func test_connection_lost_overlay() -> void:
	var tr := LoopbackTransport.pair()
	var v := [MatchView.new(), MatchView.new()]
	var s := [NetSession.new(), NetSession.new()]
	for side in 2:
		root().add_child(v[side])
		s[side].setup(tr[side], side == 0, "P", _deck("MAGE"))
		var view: MatchView = v[side]
		var sess: NetSession = s[side]
		sess.started.connect(func(m): view.bind_online(m, sess))
	s[0].say_hello()
	s[1].say_hello()
	LoopbackTransport.pump(tr)
	tr[0].close("network")
	LoopbackTransport.pump(tr)
	check(v[1].find_child("ConnectionLost", true, false) != null, "overlay shown")
	for side in 2:
		v[side].free()
	for t in tr:
		if is_instance_valid(t):  # bound transports were freed with their view
			t.free()


func test_local_player_cannot_move_for_remote() -> void:
	var tr := LoopbackTransport.pair()
	var v := MatchView.new()
	root().add_child(v)
	var s := NetSession.new()
	var other := NetSession.new()
	s.setup(tr[0], true, "A", _deck("MAGE"))
	other.setup(tr[1], false, "B", _deck("MAGE"))
	s.started.connect(func(m): v.bind_online(m, s))
	s.say_hello()
	other.say_hello()
	LoopbackTransport.pump(tr)
	check(not v.controller.submit({"type": "mulligan", "player": 1, "replace": []}).ok, "refused")
	v.free()
	other.free()
	for t in tr:
		if is_instance_valid(t):  # bound transports were freed with their view
			t.free()


func test_training_emote_shows_locally() -> void:
	var g := H.scene({"hero": "HERO_08"})
	var v := MatchView.new()
	root().add_child(v)
	var m := Match.new()
	m.bot_delay = 0.0
	m.setup(g, [false, true])
	v.bind(m)
	v.send_emote("thanks")
	check(v.bubble_text(0).contains("Thanks"), "bubble")
	v.free()



func test_connect_timeout() -> void:
	Profile.path = "user://test_profile_ui3.json"
	var pair := FakeRtc.fake_pair()
	pair[0].never_open = true
	var h := OnlineView.new()
	h.transport_factory = func(): return pair[0]
	root().add_child(h)
	h.host_game()
	h.finish(SignalCode.pack("answer", "x", []))
	h._process(OnlineView.CONNECT_TIMEOUT + 1.0)
	eq(h.state, "failed", "gave up")
	check(h.status.text != "" and not h.status.text.ends_with("…"), h.status.text)
	h.free()
	pair[1].free()
	DirAccess.remove_absolute(Profile.path)
	Profile.path = Profile.DEFAULT_PATH


func _bound_pair() -> Array:
	var tr := LoopbackTransport.pair()
	var v := [MatchView.new(), MatchView.new()]
	var s := [NetSession.new(), NetSession.new()]
	for side in 2:
		root().add_child(v[side])
		s[side].setup(tr[side], side == 0, ["Alice", "Bob"][side], _deck("MAGE"))
		var view: MatchView = v[side]
		var sess: NetSession = s[side]
		sess.started.connect(func(m): view.bind_online(m, sess))
	s[0].say_hello()
	s[1].say_hello()
	LoopbackTransport.pump(tr)
	return [tr, v, s]


func _free_bound(b: Array) -> void:
	for view in b[1]:
		view.free()
	for t in b[0]:
		if is_instance_valid(t):
			t.free()


func test_guest_mulligans_without_waiting_for_host() -> void:
	var b := _bound_pair()
	var guest: MatchView = b[1][1]
	check(guest.find_child("Mulligan", true, false) != null, "guest sees its mulligan at once")
	_free_bound(b)


func test_desync_overlay_title() -> void:
	var b := _bound_pair()
	b[0][0].send({"t": "action", "n": 0, "action": {"type": "end_turn", "player": 0}, "hash": "zzz"})
	LoopbackTransport.pump(b[0])
	var ov = b[1][1].find_child("ConnectionLost", true, false)
	check(ov != null, "overlay")
	var labels: Array = ov.find_children("*", "Label", true, false).map(func(l): return l.text)
	check(labels.has("Out of sync"), str(labels))
	_free_bound(b)


func test_emote_cooldown_and_mute_hides_bubble() -> void:
	var b := _bound_pair()
	var host: MatchView = b[1][0]
	var guest: MatchView = b[1][1]
	host.send_emote("greetings")
	host.send_emote("wow")
	LoopbackTransport.pump(b[0])
	check(guest.bubble_text(0).contains("Greetings"), "second emote dropped by the cooldown")
	guest.set_muted(true)
	eq(guest.bubble_text(0), "", "mute hides the shown bubble")
	_free_bound(b)


func test_hot_seat_names() -> void:
	var g := H.scene({"hero": "HERO_08"})
	var v := MatchView.new()
	root().add_child(v)
	var m := Match.new()
	m.setup(g, [false, false])
	v.bind(m)
	check(v._names[0].text.begins_with("Player 1"), v._names[0].text)
	v.free()


func test_turn_timer_moves_reach_the_opponent() -> void:
	var b := _bound_pair()
	var v: Array = b[1]
	for side in 2:
		check(v[side].timer_enabled, "timer on in online games")
		v[side].tick(MatchView.MULLIGAN_SECONDS + 1)
		LoopbackTransport.pump(b[0])
	var g0: Game = v[0].g
	var g1: Game = v[1].g
	eq([g0.phase, g1.phase], ["PLAY", "PLAY"], "both mulligans kept on time out")
	var active: int = g0.current
	var turn := g0.turn
	v[active].tick(MatchView.TURN_SECONDS + 1)
	LoopbackTransport.pump(b[0])
	eq([g0.turn, g1.turn], [turn + 1, turn + 1], "turn ended on both sides")
	eq(g0.state_hash(), g1.state_hash(), "still in sync")
	check(v[0].find_child("ConnectionLost", true, false) == null and v[1].find_child("ConnectionLost", true, false) == null, "no desync")
	_free_bound(b)


func test_opponent_intents_are_shown() -> void:
	var b := _bound_pair()
	var v: Array = b[1]
	var got := []
	(b[2][1] as NetSession).intent_received.connect(func(i): got.append(i))
	(b[2][0] as NetSession).send_intent({"k": "hover", "i": 1})
	(b[2][0] as NetSession).send_intent({"k": "bad"})  # ignored, the game goes on
	LoopbackTransport.pump(b[0])
	eq(got, [{"k": "hover", "i": 1}], "hover intent arrives; a bad one is dropped")
	var guest: MatchView = v[1]
	check(guest.find_child("ConnectionLost", true, false) == null, "no failure for a bad intent")
	var opp_hand: Array = guest.g.players[0].hand
	var raised: Control = guest._views[opp_hand[1].id]
	var other: Control = guest._views[opp_hand[0].id]
	check(raised.scale.x > other.scale.x, "the card the opponent looks at is raised")
	guest.apply_intent({"k": "aim", "from": guest.g.hero(0).id, "to": guest.g.hero(1).id})
	check(guest._opp_arrow.visible, "the opponent's arrow")
	guest.apply_intent({"k": "none"})
	check(not guest._opp_arrow.visible, "cleared")
	_free_bound(b)
