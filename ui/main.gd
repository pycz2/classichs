extends Control
## Root of the game: switches screens and owns the running match.

var screen: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Locale.load_all()
	Sprites.load_all()
	Settings.load_settings()
	Settings.apply()
	theme = Fonts.theme()  # the medieval font and tavern buttons everywhere below (the active pack's look)
	add_child(Sound.new())
	if OS.has_feature("web"):
		add_child(WebPaste.new())  # Ctrl+V pastes the clipboard of now, not the one before
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) and DisplayServer.is_touchscreen_available():
		add_child(KeyboardLift.new())  # a field under the on-screen keyboard rises above it
	if Settings.data.fullscreen and not OS.has_feature("web"):  # the browser needs a click first
		Settings.set_fullscreen(true)
	get_viewport().gui_focus_changed.connect(func(c: Control):
		if c is LineEdit or c is TextEdit:
			_fresh_clipboard())
	_start_server_link()
	if not await _wait_for_rules():
		return
	if Settings.first_run:
		show_language_picker()
	else:
		show_menu()


## The rules engine must be there before anything can be played: the browser
## loads rules.wasm a moment after the page; a build without its native library
## says so instead of starting without rules.
func _wait_for_rules() -> bool:
	var t0 := Time.get_ticks_msec()
	while Rules.missing() == "loading" and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	var why := Rules.missing()
	if why == "":
		return true
	push_error("rules engine: " + why)
	var l := Palette.label(tr("The game cannot start: its rules engine is missing.") + "\n" + why, 20)
	l.name = "RulesMissing"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_set_screen(l)
	return false


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
	if social:
		sync_server_links()  # the list may have changed in the settings
		social.screen_changed(s)


## The main menu; play=true opens it at the Play submenu (coming back from a game mode).
func show_menu(play := false) -> void:
	var m := MainMenu.new()
	m.training.connect(show_training_setup)
	m.collection.connect(show_collection)
	m.online.connect(show_online)
	m.tutorial.connect(show_tutorial)
	m.settings.connect(show_settings)
	m.games.connect(show_games)
	m.quit.connect(func(): get_tree().quit())
	_set_screen(m)
	if play:
		m.show_play()


## The game packs: which game the whole client shows and plays.
func show_games() -> GamesView:
	var g := GamesView.new()
	g.links = server_links
	g.back.connect(show_menu)
	_set_screen(g)
	return g


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
		start_match({"decks": [{"hero": deck.hero, "cards": Array(deck.cards)},
			{"hero": Decks.hero(bot), "cards": Decks.basic(bot)}], "seed": randi()}, [false, true], false))
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
	var m := Match.new()
	var why := m.setup({"mission": n}, [false, true])
	assert(why == "", why)
	var v := MatchView.new()
	v.tutorial = Tutorial.new(n, m)
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
	o.arena.connect(show_arena)
	o.server.connect(show_server)
	_set_screen(o)


func start_online_match(session: NetSession, m: Match) -> MatchView:
	var v := MatchView.new()
	v.leave.connect(show_menu)
	session.reparent(v)  # keep the session and its transport alive across the screen change
	session.transport.reparent(v)
	_set_screen(v)
	v.bind_online(m, session)
	return v


## The Arena between games (draft and lobby). Its session and connection live
## here, across the Arena's screens.
func show_arena(s: ArenaSession) -> ArenaView:
	for n: Node in [s, s.transport]:
		if n.get_parent() == null:
			add_child(n)
		elif n.get_parent() != self:
			n.reparent(self)
	s.end_game()
	var a := ArenaView.new()
	a.session = s
	a.play.connect(func(game, m): start_arena_match(s, game, m))
	a.exit.connect(func():
		s.leave()
		s.queue_free()
		s.transport.queue_free()
		show_menu(true))
	_set_screen(a)
	return a


## Playing through game servers (D14: several, each with its own session, friends and
## chats). A connection per server lives here for the whole run of the game (the player
## stays logged in across screens), with the friends overlay. server_link is the server
## chosen in the lobby.
var server_links: Array[ServerLink] = []
var server_link: ServerLink
var social: Social


## The connections and the overlay; a saved session logs in again by itself, silently
## (a refused one is forgotten; an unreachable server is tried again next time; one
## another login took waits for the player).
func _start_server_link() -> void:
	if server_link != null and not server_links.has(server_link):  # (a test may put its own in first)
		if server_link.url == "" and not Settings.data.servers.is_empty():
			server_link.url = Settings.data.servers[0].url
		server_links.push_front(server_link)
	social = Social.new()
	social.name = "Social"
	add_child(social)
	sync_server_links()
	for l in server_links:
		if Settings.server_ok(l.url) and l.can_resume():
			l.open_and_resume(l.url)


## A connection for every server in the settings (new ones added, removed ones closed);
## server_link stays the chosen one (else the last chosen, else the first).
func sync_server_links() -> void:
	var want: Array = Settings.data.servers.map(func(e): return e.url)
	for l in server_links.duplicate():
		if not want.has(l.url):
			server_links.erase(l)
			l.close()
			l.queue_free()
	for u in want:
		if not server_links.any(func(l): return l.url == u):
			var l := ServerLink.new()
			l.url = u
			server_links.append(l)
	for l in server_links:
		if l.get_parent() == null:
			l.name = "ServerLink" if l == server_links[0] else "ServerLink%d" % server_links.find(l)
			add_child(l)
			l.message.connect(_on_server_message.bind(l))
	if not server_links.has(server_link):
		server_link = link_for(ServerLink.last())
	if server_link == null and not server_links.is_empty():
		server_link = server_links[0]
	social.links = server_links
	if server_link:
		social.link = server_link


## The connection to a server (null when it is not in the list).
func link_for(url: String) -> ServerLink:
	for l in server_links:
		if l.url == url:
			return l
	return null


## The lobby switched to another server.
func choose_server(l: ServerLink) -> void:
	server_link = l
	ServerLink.remember_last(l.url)
	social.link = l
	show_server()


func show_server() -> ServerView:
	sync_server_links()
	if server_link == null:  # every server was removed: the list to add one
		show_settings()
		screen.show_servers()
		return null
	var v := ServerView.new()
	v.link = server_link
	v.links = server_links
	v.back.connect(func(): show_menu(true))
	v.server_chosen.connect(choose_server)
	_set_screen(v)
	return v


func start_server_match(session: ServerSession, m: Match, mode: String) -> MatchView:
	var v := MatchView.new()
	v.lobby = true
	v.lobby_back.connect(func():
		if session.link is ServerLink and server_links.has(session.link):
			server_link = session.link
		show_server())
	session.link.set_meta("mode", mode)
	_set_screen(v)
	v.bind_online(m, session)
	return v


func _on_server_message(msg: Dictionary, l: ServerLink) -> void:
	match msg.get("t"):
		"game_over":  # the result arrives during the game: kept for the lobby after it
			if not (screen is ServerView and l == server_link):
				l.set_meta("game_over", msg)
		"match":
			start_server_game(msg, l)


## The server matched us (a queue, the Arena or an invite, from any screen, or
## a game still running after a reconnect: rejoin): the server keeps the game; its
## first state opens the table.
func start_server_game(msg: Dictionary, l: ServerLink = null) -> ServerSession:
	if l == null:
		l = server_link
	var mode := str(msg.get("mode", "casual"))
	var s := l.session(msg, l.game_deck)
	l.add_child(s)
	s.started.connect(func(m: Match): start_server_match(s, m, mode))
	s.failed.connect(func(reason):
		if s.match_ == null:
			social.toast(reason))
	return s


func start_arena_match(s: ArenaSession, game: NetSession, m: Match) -> MatchView:
	var v := MatchView.new()
	v.arena = s
	v.arena_back.connect(func(): show_arena(s))
	_set_screen(v)
	v.bind_online(m, game)
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
	var why := m.setup({"scenario": test.scene}, [false, false])
	if why != "":
		push_warning("card test: " + why)
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


## A local game: req is the engine's `new` request ({decks, seed} or {scenario}).
func start_match(req: Dictionary, bots: Array, debug := false) -> MatchView:
	var m := Match.new()
	var why := m.setup(req, bots)
	if why != "":
		push_error("cannot start the game: " + why)
		return null
	var v := MatchView.new()
	v.debug_mode = debug
	v.leave.connect(show_debug_table if debug else show_menu)
	_set_screen(v)
	v.bind(m)
	return v


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_fresh_clipboard()
