extends TestCase
## Replays (game/replay.gd): a played local game rebuilt by the engine, files, the store of
## the last games, the replay table (ui/replay_view.gd) and the list (ui/replays_view.gd).


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## A game the bots played to the end (mulligans included), and its replay.
func _played(seed := 4) -> Array:
	var m := Match.new()
	m.bot_delay = 0.0
	var why := m.setup({"decks": [{"hero": "HERO_08", "cards": Decks.basic("MAGE")}, {"hero": "HERO_01", "cards": Decks.basic("WARRIOR")}],
		"seed": seed}, [true, true])
	eq(why, "", "the game starts")
	m.start()
	check(m.game.game_over, "the bots played it out")
	return [m, Replay.from_match(m, ["Alice", "Bob"], "training", 0)]


func _clear_store() -> void:
	for f in DirAccess.get_files_at(Replay.dir):
		DirAccess.remove_absolute(Replay.dir.path_join(f))


func test_rebuilds_to_the_same_game() -> void:
	var x := _played()
	var m: Match = x[0]
	var r: Replay = x[1]
	check(r != null, "a replay of the game")
	eq(r.size(), m.game.history.size() - 1, "every applied action")
	eq(r.data.actions[0].type, "mulligan", "the mulligans too")
	eq(r.hash_at(r.size()), m.state_hash, "the end: the same state")
	eq(r.data.hash, m.state_hash, "the final hash kept")
	var k := r.size() / 2
	var g := r.build(k)  # going back from the end
	eq(g.turn, int(m.game.history[k].turn), "the middle: the right turn")
	eq(g.history.size(), k + 1, "and its history")
	var starts := r.turn_starts()
	eq(starts[0], [0, 0], "the mulligan first")
	check(starts.size() >= 4 and starts[-1][0] == m.game.turn, "a start for every turn up to the last")
	eq(r.build(starts[2][1]).turn, starts[2][0], "a turn's start is that turn")
	eq(r.build(r.size()).winner, m.game.winner, "the winner")
	m.free()


func test_export_import_round_trip() -> void:
	var r: Replay = _played(7)[1]
	var path := "user://test_runner_export." + Replay.EXT
	check(r.to_file(path), "written")
	var back := Replay.from_file(path)
	check(back != null, "read")
	eq(back.data, r.data, "the same replay")
	eq(back.hash_at(back.size()), r.data.hash, "rebuilds to the same end")
	check(r.file_name().ends_with(".chsreplay") and r.file_name().begins_with("Alice-vs-Bob-"), "named " + r.file_name())
	DirAccess.remove_absolute(path)
	eq(Replay.from_text("{\"format\": \"other\"}"), null, "not a replay")
	# the list's Import: kept when its game is here, else it says which game is needed
	_clear_store()
	var v := ReplaysView.new()
	root().add_child(v)
	check(v.find_child("Empty", true, false) != null, "an empty list says so")
	check(v.find_child("ImportEmpty", true, false) != null, "with Import in it")
	check(v.import_text(r.to_text()) != null, "imported")
	eq(Replay.kept().size(), 1, "kept")
	check(v.find_child("Replay0", true, false) != null, "a row for it")
	var other := r.data.duplicate(true)
	other.pack = "0123456789abcdef"
	other.pack_name = "Neon Duel 2.0"
	eq(v.import_text(JSON.stringify(other)), null, "a game not on this device")
	check(v._note.text.contains("Neon Duel 2.0"), "says which: " + v._note.text)
	eq(v.import_text("hello"), null, "not a file of replays")
	v.free()
	_clear_store()


func test_store_keeps_the_last_ten() -> void:
	_clear_store()
	var r: Replay = _played(9)[1]
	for i in 12:
		var x := Replay.from_data(r.data)
		x.data.game = "g%d" % i
		x.data.ended = 1000 + i
		Replay.keep(x)
	var kept := Replay.kept()
	eq(kept.size(), Replay.KEEP, "ten kept")
	eq([kept[0].data.game, kept[-1].data.game], ["g11", "g2"], "the newest first, the oldest gone")
	var again := Replay.from_data(r.data)
	again.data.game = "g5"
	again.data.ended = 2000
	Replay.keep(again)
	eq(Replay.kept().size(), Replay.KEEP, "the same game replaces itself")
	eq(Replay.kept()[0].data.game, "g5", "now the newest")
	_clear_store()


func test_a_finished_table_game_is_kept() -> void:
	_clear_store()
	var m := Match.new()
	m.bot_delay = 0.0
	m.setup({"decks": [{"hero": "HERO_08", "cards": Decks.basic("MAGE")}, {"hero": "HERO_01", "cards": Decks.basic("WARRIOR")}], "seed": 11}, [true, true])
	var v := MatchView.new()
	root().add_child(v)
	v.bind(m)
	check(m.game.game_over, "played out")
	var kept := Replay.kept()
	eq(kept.size(), 1, "kept when it ended")
	eq(kept[0].data.mode, "training", "a game with the bot")
	eq(kept[0].hash_at(kept[0].size()), m.state_hash, "the whole game")
	v.free()
	_clear_store()


func test_replay_table() -> void:
	var r: Replay = _played(4)[1]
	var v := ReplayView.new()
	v.replay = r
	root().add_child(v)
	var t := v.view
	check(t != null and t.replay, "the table in its replay mode")
	check(t.find_child("Concede", true, false) == null, "nothing to concede")
	eq(t.controller.game.phase, "MULLIGAN", "from the opening hands")
	v._show_at(r.turn_starts()[3][1])
	t = v.view
	var opp := 1 - r.me()
	var hand: Array = t.controller.game.players[opp].hand
	check(not hand.is_empty(), "the opponent holds cards")
	check((t._views[hand[0].id] as CardView).face_up, "the opponent's hand is face up")
	check(not t.my_action(), "nothing can be done at the table")
	eq(v._turn_line.text, "Turn %d — %s" % [r.turn_starts()[3][0], r.name(t.controller.game.current)], "the turn and who moves")
	var before := v.at
	v.step()
	eq(v.at, before + 1, "an action on")
	eq(t.controller.state_hash, r.hash_at(v.at), "the same game as the replay")
	v._buttons.TurnForward.pressed.emit()
	eq(v.at, r.turn_starts()[4][1], "a turn on")
	v._buttons.TurnBack.pressed.emit()
	eq(v.at, r.turn_starts()[3][1], "a turn back")
	v._buttons.ToEnd.pressed.emit()
	eq(v.at, r.size(), "to the end")
	check(v.view.controller.game.game_over, "the game is over there")
	check(v._result.text != "", "the result shows")
	check(v.view.find_child("GameOver", true, false) == null, "no end screen over the table")
	check(v._buttons.StepForward.disabled, "nothing after the end")
	v.toggle_play()
	eq(v.at, 0, "Play at the end starts again")
	check(v.playing, "playing")
	v._scrub.seek.emit(5, true)
	eq([v.at, v.playing], [5, false], "the scrubber seeks and pauses")
	v.free()


func test_server_list() -> void:
	var r: Replay = _played(4)[1]
	var link := FakeLink.new()
	root().add_child(link)
	var v := ReplaysView.new()
	v.link = link
	root().add_child(v)
	v.show_tab("server")
	eq(link.of("replays").size(), 1, "asks for the server's games")
	link.dispatch({"t": "replays", "list": [{"game": "s1", "mode": "ranked", "pack": r.data.pack, "pack_name": "Classic",
		"opponent": "Bob", "won": true, "winner": 1, "you": 1, "started": 1, "ended": 2, "turns": 9,
		"heroes": ["HERO_08", "HERO_01"], "players": ["Bob", "Alice"]}]})
	check(v.find_child("Replay0", true, false) != null, "a row")
	var got := []
	v.watch.connect(func(x): got.append(x))
	(v.find_child("Watch", true, false) as Button).pressed.emit()
	eq(link.of("replay"), [{"t": "replay", "game": "s1"}], "fetches it")
	link.dispatch({"t": "replay", "game": "s1", "data": r.data})
	eq(got.size(), 1, "and watches it")
	eq(got[0].me(), 1, "from the player's seat")
	v.free()
	link.free()


func test_server_game_over_keeps_its_replay() -> void:
	_clear_store()
	var r: Replay = _played(4)[1]
	var link := FakeLink.new()
	root().add_child(link)
	var s := link.session({"game": "s9", "you": 1, "opponent": {"user": "Bob"}}, null)
	link.dispatch({"t": "game_over", "game": "s9", "result": "win", "reason": "over"})
	eq(link.of("replay"), [{"t": "replay", "game": "s9"}], "asks for the replay after the game")
	var data := r.data.duplicate(true)
	data.game = "s9"
	link.dispatch({"t": "replay", "game": "s9", "data": data})
	eq(Replay.kept().size(), 1, "kept")
	eq(Replay.kept()[0].me(), 1, "with the player's seat")
	s.free()
	link.free()
	_clear_store()


## Found in the 0.50 check: the friends button sat over the replay bar's Back (bottom left).
func test_the_friends_button_leaves_the_replay_bar_free() -> void:
	var m: Node = load("res://ui/main.tscn").instantiate()
	root().add_child(m)
	var v: ReplayView = m.show_replay(_played(4)[1])
	var back := (v.find_child("ReplayBack", true, false) as Control).get_global_rect()
	var b: Control = m.social.button
	check(not back.intersects(Rect2(b.position, b.size)), "Back is not under the friends button")
	var list: ReplaysView = m.show_replays()
	b = m.social.button
	check(not (list.find_child("Back", true, false) as Control).get_global_rect().intersects(Rect2(b.position, b.size)), "nor the list's Back")
	m.free()
