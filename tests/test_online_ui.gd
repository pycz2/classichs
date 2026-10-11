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
