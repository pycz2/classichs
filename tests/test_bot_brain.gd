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
	Settings.load_settings()
	eq(Settings.data.bot_level, "hard", "and saved")
	Settings.data.bot_level = was
	t.free()
