extends Control
## Root of the game: switches screens and owns the running match.

var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	show_menu()


func _set_screen(s: Control) -> void:
	if screen:
		screen.queue_free()
		remove_child(screen)
	screen = s
	add_child(s)


func show_menu() -> void:
	var m := MainMenu.new()
	m.training.connect(show_training_setup)
	m.collection.connect(show_collection)
	m.online.connect(show_online)
	m.debug_table.connect(show_debug_table)
	m.quit.connect(func(): get_tree().quit())
	_set_screen(m)


func show_training_setup() -> void:
	var t := TrainingSetup.new()
	t.back.connect(show_menu)
	t.start.connect(func(deck: Deck, bot: String):
		var g := Game.new({"hero": deck.hero, "deck": deck.cards.duplicate()},
			{"hero": Decks.hero(bot), "deck": Decks.basic(bot)}, randi())
		start_match(g, [false, true], false))
	_set_screen(t)


func show_online() -> void:
	var o := OnlineView.new()
	o.back.connect(show_menu)
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


func show_debug_table() -> void:
	var d := DebugTable.new()
	d.back.connect(show_menu)
	d.start.connect(func(g, bots): start_match(g, bots, true))
	_set_screen(d)


func start_match(g: Game, bots: Array, debug := false) -> MatchView:
	var m := Match.new()
	m.setup(g, bots)
	var v := MatchView.new()
	v.debug_mode = debug
	v.leave.connect(show_menu)
	_set_screen(v)
	v.bind(m)
	return v


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		Cards.unload()
