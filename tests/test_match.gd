extends TestCase


func _game(seed := 1) -> Game:
	return Game.new({"hero": "HERO_08", "deck": Decks.basic("MAGE")}, {"hero": "HERO_01", "deck": Decks.basic("WARRIOR")}, seed, 0)


func test_human_vs_bot_turns() -> void:
	var m := Match.new()
	m.bot_delay = 0.0
	m.setup(_game(), [false, true])
	m.start()
	check(m.game.players[1].mulliganed, "bot mulliganed at once")
	eq(m.actor(), 0, "human to mulligan")
	check(m.submit({"type": "mulligan", "player": 0, "replace": []}).ok, "human mulligan")
	eq([m.game.phase, m.actor()], ["PLAY", 0], "human starts")
	m.submit({"type": "end_turn", "player": 0})
	eq(m.actor(), 0, "bot played its turn and passed back")
	check(m.game.turn >= 3, "turns advanced")
	m.free()


func test_bot_vs_bot_finishes_once() -> void:
	var m := Match.new()
	m.bot_delay = 0.0
	var winners := []
	m.finished.connect(func(w): winners.append(w))
	m.setup(_game(4), [true, true])
	m.start()
	check(m.game.game_over, "finished")
	eq(winners.size(), 1, "signal once")
	m.free()


func test_illegal_submit_emits_nothing() -> void:
	var m := Match.new()
	m.bot_delay = 0.0
	var count := [0]
	m.changed.connect(func(_e): count[0] += 1)
	m.setup(_game(), [false, true])
	m.start()
	count[0] = 0
	check(not m.submit({"type": "end_turn", "player": 0}).ok, "illegal during mulligan")
	eq(count[0], 0, "no change signal")
	m.free()


func test_hot_seat_viewer_follows_actor() -> void:
	var m := Match.new()
	m.setup(_game(), [false, false])
	m.start()
	m.submit({"type": "mulligan", "player": 0, "replace": []})
	m.submit({"type": "mulligan", "player": 1, "replace": []})
	eq(m.viewer(), 0, "player 0 sees")
	m.submit({"type": "end_turn", "player": 0})
	eq(m.viewer(), 1, "player 1 sees on its turn")
	m.free()


func test_viewer_is_human_against_bot() -> void:
	var m := Match.new()
	m.bot_delay = 0.0
	m.setup(_game(), [true, false])
	m.start()
	eq(m.viewer(), 1, "the human side")
	m.free()
