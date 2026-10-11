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
	var pair := FakeRtc.fake_pair()
	var g := OnlineView.new()
	g.transport_factory = func(): return pair[1]
	root().add_child(g)
	g.join_game(SignalCode.pack("answer", "x", []))
	eq(g.state, "failed", "refused")
	check(g.status.text.contains("answer"), g.status.text)
	g.free()
	pair[0].free()


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
