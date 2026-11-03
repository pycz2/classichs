extends Control
## Root of the game: switches screens and owns the running match. The screens:
## the main menu (the client's own look and music): Play -> Direct (without a server) or Server
## (through one), Settings, Exit (not on the web).
## Direct: the game library (GamesView) -> a game's menu (MainMenu with a pack, in its look):
## Collection, Training, Code play, Tutorial (when the pack has one), Settings (+ the game's debug
## tools), Leave the game (the library).
## Server: the connections (ConnectionsView) -> the login (ServerView, login_only) -> the server's
## home (ServerHome: friends, the player's name, the server's games) -> a game's menu: Play (the
## lobby: casual, ranked, the Arena), Collection (the server's decks of the game), Training,
## Tutorial, Settings (+ debug tools), Leave the game (the server's home).

var screen: Control
## "" in the main menu, "direct" (without a server) or "server" (through one).
var mode := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Locale.load_all()
	Sprites.load_all()
	Settings.load_settings()
	Migration.run()  # the player's files of before 0.40, once
	Settings.apply()
	get_window().title = App.NAME
	Packs.set_shell(true)  # the main menu: no game styles it
	theme = Fonts.theme()  # the look everywhere below: the client's own, or the game's inside a game
	add_child(Sound.new())
	if OS.has_feature("web"):
		add_child(WebPaste.new())  # Ctrl+V pastes the clipboard of now, not the one before
	add_child(TouchInput.new())  # a finger drag scrolls any list, also over its buttons
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) and DisplayServer.is_touchscreen_available():
		add_child(KeyboardLift.new())  # a field under the on-screen keyboard rises above it
	if Settings.data.fullscreen and not OS.has_feature("web"):  # the browser needs a click first
		Settings.set_fullscreen(true)
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


func _set_screen(s: Control) -> void:
	if screen:
		screen.queue_free()
		remove_child(screen)
	screen = s
	add_child(s)
	if social:
		sync_server_links()  # the list may have changed
		social.enabled = mode == "server"  # friends and chats only through a server
		social.screen_changed(s)


## The main menu; play=true opens it at the Play submenu (coming back from a mode). Leaving
## the server mode closes the connections (their sessions stay saved).
func show_menu(play := false) -> void:
	if mode == "server":
		for l in server_links:
			l.close()
	mode = ""
	DeckStore.link = null
	Packs.set_shell(true)
	var m := MainMenu.new()
	m.direct.connect(show_library)
	m.server.connect(show_connections)
	m.settings.connect(show_settings)
	m.quit.connect(func(): get_tree().quit())
	_set_screen(m)
	if play:
		m.show_play()


## The settings: the same everywhere; inside a game with that game's debug tools.
func show_settings() -> SettingsView:
	var s := SettingsView.new()
	var in_game := not Packs.shell
	s.back.connect(show_game_menu if in_game else show_menu)
	if in_game:
		s.debug.connect(show_debug_table)
	_set_screen(s)
	return s


# --- without a server --------------------------------------------------------------------

## The game library: the games on this device.
func show_library() -> GamesView:
	mode = "direct"
	DeckStore.link = null
	Packs.set_shell(true)
	var g := GamesView.new()
	g.back.connect(show_menu.bind(true))
	g.entered.connect(enter_game)
	g.tools.connect(show_pack_tools)
	_set_screen(g)
	return g


## Pack tools: build, check and try a pack; a test game opens Training with it (a player without
## decks of that game gets its ready decks, so there is one to play).
func show_pack_tools() -> PackTools:
	var t := PackTools.new()
	t.back.connect(show_library)
	t.play.connect(func(p: Pack):
		enter_game(p)
		if DeckStore.count_local(p.id()) == 0:
			DeckStore.save_all(Decks.templates().map(func(x): return x.deck))
		show_training_setup())
	_set_screen(t)
	return t


## Opens a game: it becomes the active pack and its menu shows, in its look. Through a server
## (mode "server") its decks are the server's and its art and music choice the server's.
func enter_game(p: Pack) -> MainMenu:
	var sets := {}
	if mode == "server" and server_link:
		for kind in ["art", "music"]:
			var v := server_link.game_setting(p, kind)
			if v != "":
				sets[kind] = v
		DeckStore.link = server_link if server_link.has_decks else null
	Packs.enter(p, sets)
	if mode == "server" and server_link:
		server_link.request_me()  # the rank in this game
	return show_game_menu()


## The active game's menu.
func show_game_menu() -> MainMenu:
	Packs.set_shell(false)
	var m := MainMenu.new()
	m.pack = Packs.active()
	m.through_server = mode == "server"
	m.collection.connect(show_collection)
	m.training.connect(show_training_setup)
	m.code_play.connect(show_online)
	m.play.connect(show_server)
	m.tutorial.connect(show_tutorial)
	m.settings.connect(show_settings)
	m.leave.connect(leave_game)
	_set_screen(m)
	return m


## Leaves the game: the library, or the server's home.
func leave_game() -> void:
	DeckStore.link = null
	if mode == "server":
		show_server_home()
	else:
		show_library()


func show_training_setup() -> void:
	var t := TrainingSetup.new()
	t.back.connect(show_game_menu)
	t.edit_decks.connect(show_collection)
	t.start.connect(func(deck: Deck, bot: String):
		start_match({"decks": [{"hero": deck.hero, "cards": Array(deck.cards)},
			{"hero": Decks.hero(bot), "cards": Decks.basic(bot)}], "seed": randi()}, [false, true], false,
			str(Settings.data.get("bot_level", "medium"))))
	_set_screen(t)


func show_tutorial() -> void:
	var t := TutorialView.new()
	t.back.connect(show_game_menu)
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


## Code play: two players connect directly (WebRTC); the name is asked first.
func show_online() -> void:
	var o := OnlineView.new()
	o.back.connect(show_game_menu)
	o.edit_decks.connect(show_collection)
	o.play.connect(start_online_match)
	o.arena.connect(show_arena)
	_set_screen(o)


func start_online_match(session: NetSession, m: Match) -> MatchView:
	var v := MatchView.new()
	v.leave.connect(show_game_menu)
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
		show_game_menu())
	_set_screen(a)
	return a


# --- through a server --------------------------------------------------------------------

## Playing through game servers (D14: several connections, each with its own session, friends
## and chats; the same address may be there twice with other logins). A connection per entry of
## the list lives here; in the server mode they are open (a saved session logs in again by
## itself, silently), with the friends overlay. server_link is the one chosen.
var server_links: Array[ServerLink] = []
var server_link: ServerLink
var social: Social


## The connections and the overlay (closed until the server mode).
func _start_server_link() -> void:
	if server_link != null and not server_links.has(server_link):  # (a test may put its own in first)
		if server_link.url == "" and not Settings.data.servers.is_empty():
			server_link.url = Settings.data.servers[0].url
			server_link.id = str(Settings.data.servers[0].get("id", server_link.url))
		server_links.push_front(server_link)
	social = Social.new()
	social.name = "Social"
	add_child(social)
	sync_server_links()


## A connection for every entry of the list (new ones added, removed ones closed);
## server_link stays the chosen one (else the last chosen, else the first).
func sync_server_links() -> void:
	var want: Array = Settings.data.servers.map(func(e): return str(e.get("id", e.url)))
	for l in server_links.duplicate():
		if not want.has(l.id):
			server_links.erase(l)
			l.close()
			l.queue_free()
	for e in Settings.data.servers:
		var id := str(e.get("id", e.url))
		if not server_links.any(func(l): return l.id == id):
			var l := ServerLink.new()
			l.url = e.url
			l.id = id
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


## The connection with an id (null when it is not in the list).
func link_for(id: String) -> ServerLink:
	for l in server_links:
		if l.id == id:
			return l
	return null


## The connections: every saved session logs in again by itself (silently: a refused one is
## forgotten; an unreachable server is tried again next time; one another login took waits).
func show_connections() -> ConnectionsView:
	mode = "server"
	DeckStore.link = null
	Packs.set_shell(true)
	sync_server_links()
	for l in server_links:
		if not l.logged_in() and not l.resuming and Settings.server_ok(l.url) and l.can_resume():
			l.open_and_resume(l.url)
	var c := ConnectionsView.new()
	c.back.connect(show_menu.bind(true))
	c.chosen.connect(open_connection)
	_set_screen(c)
	return c


## A connection was opened: its home when logged in, else the login there.
func open_connection(id: String) -> void:
	var l := link_for(id)
	if l == null:
		return
	server_link = l
	ServerLink.remember_last(l.id)
	social.link = l
	if l.logged_in():
		show_server_home()
		return
	var v := ServerView.new()
	v.link = l
	v.login_only = true
	v.back.connect(show_connections)
	v.logged_in.connect(show_server_home)
	_set_screen(v)


## The chosen server's home: who the player is there, the friends, its games.
func show_server_home() -> ServerHome:
	DeckStore.link = null
	Packs.set_shell(true)
	if server_link == null or not server_link.logged_in():
		show_connections()
		return null
	var h := ServerHome.new()
	h.link = server_link
	h.back.connect(show_connections)
	h.entered.connect(enter_game)
	h.friends.connect(func(): social.show_panel(true))
	_set_screen(h)
	return h


## The game's Play through the server: casual, ranked, the Arena (Back: the game's menu).
func show_server() -> ServerView:
	if server_link == null:
		show_connections()
		return null
	var v := ServerView.new()
	v.link = server_link
	v.back.connect(show_game_menu)
	_set_screen(v)
	return v


func start_server_match(session: ServerSession, m: Match, mode_: String) -> MatchView:
	var v := MatchView.new()
	v.lobby = true
	v.lobby_back.connect(func():
		if session.link is ServerLink and server_links.has(session.link):
			server_link = session.link
		show_server())
	session.link.set_meta("mode", mode_)
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
## first state opens the table (in the server mode, in that game).
func start_server_game(msg: Dictionary, l: ServerLink = null) -> ServerSession:
	if l == null:
		l = server_link
	mode = "server"
	server_link = l
	DeckStore.link = l if l.has_decks else null
	var mode_ := str(msg.get("mode", "casual"))
	var s := l.session(msg, l.game_deck)
	l.add_child(s)
	s.started.connect(func(m: Match):
		Packs.set_shell(false)
		start_server_match(s, m, mode_))
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


## The active game's decks (the server's in a server game).
func show_collection() -> void:
	var c := DeckListView.new()
	c.back.connect(show_game_menu)
	_set_screen(c)


## The debug tools of the active game (from its settings), at a tab: DebugTable.SCENE, TESTS...
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


## A local game: req is the engine's `new` request ({decks, seed} or {scenario}); bot_level: Match.bot_level.
func start_match(req: Dictionary, bots: Array, debug := false, bot_level := "") -> MatchView:
	var m := Match.new()
	m.bot_level = bot_level
	var why := m.setup(req, bots)
	if why != "":
		push_error("cannot start the game: " + why)
		return null
	var v := MatchView.new()
	v.debug_mode = debug
	v.leave.connect(show_debug_table if debug else show_game_menu)
	_set_screen(v)
	v.bind(m)
	return v

