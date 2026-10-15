extends TestCase


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _deck() -> Array:
	var d := []
	for i in 30:
		d.append("VAN_CS2_120")
	return d


func _view(timer: bool) -> MatchView:
	var v := MatchView.new()
	v.timer_enabled = timer
	root().add_child(v)
	var m := H.decks({"hero": "HERO_08", "cards": _deck()}, {"hero": "HERO_01", "cards": _deck()}, 3, 0, [false, true])
	v.bind(m)
	return v


func _ended_by(g: GameView, p: int) -> bool:
	return g.history.any(func(h): return h.action.get("type") == "end_turn" and h.player == p)


func test_time_out_keeps_mulligan_then_ends_turn() -> void:
	var v := _view(true)
	var g := v.g
	v.tick(MatchView.MULLIGAN_SECONDS + 1)
	eq(g.phase, "PLAY", "mulligan kept on time out")
	var rope := v.find_child("Rope", true, false) as Control
	v.tick(MatchView.TURN_SECONDS - MatchView.ROPE_SECONDS - 1)
	eq(rope.visible, false, "no rope before the last seconds")
	v.tick(2)
	eq(rope.visible, true, "rope burns in the last seconds")
	v.tick(MatchView.ROPE_SECONDS)
	check(_ended_by(g, 0), "turn ended on time out")
	v.free()


func test_time_out_takes_the_first_choice() -> void:
	# Tracking (choose one of the top three cards) in the hand, on the online timer
	var deck := []
	for i in 10:
		deck.append(H.WISP)
	var m := H.scene({"hero": "HERO_05", "hand": ["VAN_DS1_184"], "deck": deck}, {"hero": "HERO_01", "deck": deck.duplicate()}, 0, [false, true])
	var v := MatchView.new()
	v.timer_enabled = true
	root().add_child(v)
	v.bind(m)
	var g := v.g
	v.controller.submit({"type": "play", "player": 0, "entity": g.players[0].hand[0].id, "target": -1, "pos": -1, "choice": -1})
	check(not g.pending.is_empty(), "a choice is open")
	v.tick(MatchView.TURN_SECONDS + 1)
	check(g.pending.is_empty() and _ended_by(g, 0), "choice taken and turn ended")
	v.free()


func test_no_timer_against_the_bot() -> void:
	var v := _view(false)
	v.tick(500)
	eq(v.g.phase, "MULLIGAN", "nothing happens without the timer")
	eq((v.find_child("Rope", true, false) as Control).visible, false, "no rope")
	v.free()
