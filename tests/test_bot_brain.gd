extends TestCase
## The game's own bot at a level (BotBrain: rust/brain through the GDExtension class RulesBrain).


static func root() -> Window:
	return Engine.get_main_loop().root


func test_the_bot_thinks_from_its_own_view() -> void:
	check(BotBrain.available(), "the native library has RulesBrain")
	var m := H.decks("MAGE", "WARRIOR", 3)
	for lvl in BotBrain.LEVELS:
		var r := BotBrain.think_now(BotBrain.request(m.id, 1, Decks.basic("WARRIOR"), lvl))
		check(r.get("ok", false), "%s: %s" % [lvl, r])
		eq(r.get("action", {}).get("type"), "mulligan", "%s keeps or replaces cards first" % lvl)


func test_a_whole_game_between_two_levels() -> void:
	var m := H.decks("MAGE", "WARRIOR", 5, 0, [true, true])
	m.bot_level = "medium"
	check(m.uses_brain(), "Classic, a level, the library: the brain plays")
	var winners := []
	m.finished.connect(func(w): winners.append(w))
	m.start()
	check(m.game.game_over, "the game ends")
	eq(winners.size(), 1, "one end")


func test_thinking_in_a_thread_gives_the_same_kind_of_answer() -> void:
	var m := H.decks("MAGE", "WARRIOR", 7)
	var b := BotBrain.new()
	b.start(BotBrain.request(m.id, 0, Decks.basic("MAGE"), "hard"))
	var waited := 0
	while not b.done() and waited < 10000:
		OS.delay_msec(10)
		waited += 10
	check(b.done(), "the thread answers")
	check(b.reply().get("ok", false) and b.reply().get("action") is Dictionary, str(b.reply()))


func test_the_greedy_bot_without_a_level() -> void:
	var m := H.decks("MAGE", "WARRIOR", 5, 0, [true, true])
	check(not m.uses_brain(), "no level: the engine's bot (tutorial, debug)")


func test_training_picks_the_level() -> void:
	var was = Settings.data.get("bot_level", "medium")
	var t := TrainingSetup.new()
	root().add_child(t)
	for lvl in BotBrain.LEVELS:
		check(t.find_child("Level_" + lvl, true, false) is Button, lvl)
	(t.find_child("Level_hard", true, false) as Button).button_pressed = true
	eq(Settings.data.bot_level, "hard", "the choice is kept")
	eq((t.find_child("Level_hard", true, false) as Button).modulate, Color.WHITE, "the chosen level stands out")
	check((t.find_child("Level_easy", true, false) as Button).modulate.r < 1.0, "the others are dimmed")
	Settings.load_settings()
	eq(Settings.data.bot_level, "hard", "and saved")
	Settings.data.bot_level = was
	t.free()


## Super hard (the first Hard: up to 24 worlds, every action in every world) thinks until 10 s
## before its turn would end: half the time left per decision (its hard stop is twice that), at most
## 6 s; nearly out of time it plays on as Medium, so it never misses its turn.
func test_super_hard_keeps_to_its_turn() -> void:
	var m := H.decks("MAGE", "WARRIOR", 3)
	m.bot_level = "superhard"
	var req := m.brain_request(1)
	eq([req.level, req.budget_ms], ["superhard", Match.SUPER_HARD_MS], "a fresh turn: the full 6 s")
	m._bot_turn_ms -= 61000  # 61 s of a 75 s turn gone: 4 s left before the spare 10
	req = m.brain_request(1)
	check(req.budget_ms * 2 + 200 <= 4000 and req.budget_ms > 1000, "it stops before the spare: %s" % req.budget_ms)
	m._bot_turn_ms -= 3000
	req = m.brain_request(1)
	eq(req.level, "medium", "nearly out: quick decisions to end the turn")
	var r := BotBrain.think_now(m.brain_request(1))
	check(r.get("ok", false), "the brain knows the level: %s" % r)
