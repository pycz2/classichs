extends Control
## Root of the game: switches screens and owns the running match.

var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Fonts.theme()  # the medieval font and tavern buttons everywhere below
	Locale.load_all()
	Sprites.load_all()
	Settings.load_settings()
	Settings.apply()
	add_child(Sound.new())
	if Settings.data.fullscreen and not OS.has_feature("web"):  # the browser needs a click first
		Settings.set_fullscreen(true)
	get_viewport().gui_focus_changed.connect(func(c: Control):
		if c is LineEdit or c is TextEdit:
			_fresh_clipboard())
	if Settings.first_run:
		show_language_picker()
	else:
		show_menu()


## The first run: pick the language, then the menu.
func show_language_picker() -> void:
	var l := LanguagePicker.new()
	l.chosen.connect(func(code: String):
		Settings.data.language = code
		Settings.save()
		Settings.first_run = false
		Settings.apply()
		show_menu())
	_set_screen(l)


## In the browser Godot gets the clipboard late: a paste uses the text read on
## the paste before. Reading it when a text field is focused (and when the tab
## comes back) makes the first Cmd/Ctrl+V paste what was just copied.
func _fresh_clipboard() -> void:
	if OS.has_feature("web"):
		DisplayServer.clipboard_get()


func _set_screen(s: Control) -> void:
	if screen:
		screen.queue_free()
		remove_child(screen)
	screen = s
	add_child(s)


## The main menu; play=true opens it at the Play submenu (coming back from a game mode).
func show_menu(play := false) -> void:
	var m := MainMenu.new()
	m.training.connect(show_training_setup)
	m.collection.connect(show_collection)
	m.online.connect(show_online)
	m.tutorial.connect(show_tutorial)
	m.settings.connect(show_settings)
	m.quit.connect(func(): get_tree().quit())
	_set_screen(m)
	if play:
		m.show_play()


func show_settings() -> void:
	var s := SettingsView.new()
	s.back.connect(show_menu)
	s.debug.connect(show_debug_table)
	_set_screen(s)


func show_training_setup() -> void:
	var t := TrainingSetup.new()
	t.back.connect(show_menu.bind(true))
	t.edit_decks.connect(show_collection)
	t.start.connect(func(deck: Deck, bot: String):
		var g := Game.new({"hero": deck.hero, "deck": deck.cards.duplicate()},
			{"hero": Decks.hero(bot), "deck": Decks.basic(bot)}, randi())
		start_match(g, [false, true], false))
	_set_screen(t)


func show_tutorial() -> void:
	var t := TutorialView.new()
	t.back.connect(show_menu.bind(true))
	t.start.connect(start_tutorial)
	_set_screen(t)


## Mission n's intro as its own screen, then the mission (Back: the mission list).
func show_tutorial_intro(n: int) -> void:
	var intro := TutorialIntro.make(n)
	intro.done.connect(start_tutorial.bind(n))
	intro.back.connect(show_tutorial)
	_set_screen(intro)


func start_tutorial(n: int) -> MatchView:
	var r := Tutorial.start(n)
	var m := Match.new()
	m.setup(r.game, [false, true])
	var v := MatchView.new()
	v.tutorial = r.tutorial
	v.leave.connect(show_tutorial)
	v.tutorial_next.connect(show_tutorial_intro)
	v.tutorial_retry.connect(start_tutorial)
	_set_screen(v)
	v.bind(m)
	return v


func show_online() -> void:
	var o := OnlineView.new()
	o.back.connect(show_menu.bind(true))
	o.edit_decks.connect(show_collection)
	o.play.connect(start_online_match)
	_set_screen(o)


func start_online_match(session: NetSession, m: Match) -> MatchView:
	var v := MatchView.new()
	v.leave.connect(show_menu)
	session.reparent(v)  # keep the session and its transport alive across the screen change
	session.transport.reparent(v)
	_set_screen(v)
	v.bind_online(m, session)
	return v


func show_collection() -> void:
	var c := DeckListView.new()
	c.back.connect(show_menu)
	_set_screen(c)


## The debug tools (opened from the settings), at a tab: DebugTable.SCENE, TESTS...
func show_debug_table(tab := DebugTable.SCENE) -> void:
	var d := DebugTable.new()
	d.tab = tab
	d.back.connect(show_settings)
	d.start.connect(func(g, bots): start_match(g, bots, true))
	d.run_test.connect(start_card_test)
	_set_screen(d)


## A card test (CardTests format) played in a hot-seat match: its steps go through
## the controller one by one; leaving comes back to the Interaction test tab.
func start_card_test(test: Dictionary) -> MatchView:
	var m := Match.new()
	m.setup(Scenario.build(test.scene).game, [false, false])
	var v := MatchView.new()
	v.debug_mode = true
	v.leave.connect(show_debug_table.bind(DebugTable.TESTS))
	_set_screen(v)
	v.bind(m)
	var run := DebugTable.Run.new(test, v)
	run.again.connect(start_card_test.bind(test))
	v.add_child(run)
	run.play()
	return v


func start_match(g: Game, bots: Array, debug := false) -> MatchView:
	var m := Match.new()
	m.setup(g, bots)
	var v := MatchView.new()
	v.debug_mode = debug
	v.leave.connect(show_debug_table if debug else show_menu)
	_set_screen(v)
	v.bind(m)
	return v


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_fresh_clipboard()
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		Cards.unload()
