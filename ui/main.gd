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
## The UI watch debug mode (tools/ui_watch.gd, docs/ui-watch.md), only under `-- --ui-watch`.
var ui_watch: Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--ui-watch" in args or "--ui-watch-real" in args:  # (its own user:// unless -real: set before anything reads it)
		ui_watch = load("res://tools/ui_watch.gd").new(self, not "--ui-watch-real" in args)
		add_child(ui_watch)
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
	add_child(FpsCounter.new())  # over every screen, when the settings say so
	add_child(PackInstallsView.new())  # game packs installing or uploading, over every screen
	add_child(PerfLog.new())  # the performance log, when the settings (or ?perf=1, --perf) say so
	add_child(TouchInput.new())  # a finger drag scrolls any list, also over its buttons
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) and DisplayServer.is_touchscreen_available():
		add_child(KeyboardLift.new())  # a field under the on-screen keyboard rises above it
	if TouchInput.phone:
		var turn := CanvasLayer.new()  # in portrait: turn the phone
		turn.layer = 120
		turn.add_child(TurnSign.new())
		add_child(turn)
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
	_set_screen(l, "show_language_picker")


## s becomes the screen; nav(args): the call of main that opened it (the UI watch builds it again by that).
func _set_screen(s: Control, nav := "", args := []) -> void:
	close_watch(false)  # (a game of one's own starts while watching one, say)
	if screen:
		screen.queue_free()
		screen.get_parent().remove_child(screen)
	screen = s
	add_child(s)
	if social:
		sync_server_links()  # the list may have changed
		social.enabled = mode == "server"  # friends and chats only through a server
		social.screen_changed(s)
	if ui_watch:
		ui_watch.screen_set(s, nav, args)


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
	_set_screen(m, "show_menu", [play])
	if play:
		m.show_play()


## The settings: the same everywhere; inside a game with that game's debug tools.
func show_settings() -> SettingsView:
	var s := SettingsView.new()
	var in_game := not Packs.shell
	s.back.connect(show_game_menu if in_game else show_menu)
	if in_game:
		s.debug.connect(show_debug_table)
	_set_screen(s, "show_settings")
	return s


# --- phones --------------------------------------------------------------------------------

## Phones (TouchInput.phone), as everywhere: every screen is the game's 1280x720, shown whole and as big as the
## screen allows (project.godot's stretch: "keep"; bars where the screen is not 16:9), laid out anew by the engine
## on every change of size: a foldable's outer and inner screens, a turn. No screen scrolls as a page (UI fix 58's
## zoom of the menus on screens wider than 16:9 left a part of the game out of sight and went stale on unfolding).
## In portrait a sign asks to turn the phone (TurnSign).


## Portrait on a phone: the whole screen asks to turn the phone (a phone turning on its side).
class TurnSign:
	extends ColorRect
	var _t := 0.0

	func _init() -> void:
		name = "TurnSign"
		color = Color.BLACK
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var l := Palette.label(tr("Turn your phone sideways to play"), 64, Palette.TEXT)
		l.name = "TurnText"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.position = Vector2(80, 520)
		l.size = Vector2(1120, 180)
		add_child(l)

	func _process(delta: float) -> void:
		var w := get_window().size
		visible = w.y > w.x  # (it stops clicks under it while shown)
		if visible:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var k := clampf(fmod(_t, 3.0) - 0.8, 0.0, 1.0)  # still, then turns, then rests on its side
		var a := PI / 2.0 * (k * k * (3.0 - 2.0 * k))  # (clockwise, as the arrow)
		var c := Vector2(640, 280)
		draw_arc(c, 230, -PI * 0.95, -PI * 0.6, 24, Color(Palette.ATTACK, 0.8), 8.0, true)  # the turn's arrow
		var tip := c + Vector2.from_angle(-PI * 0.6) * 230
		draw_colored_polygon(PackedVector2Array([tip + Vector2(-6, -26), tip + Vector2(30, 6), tip + Vector2(-18, 22)]), Color(Palette.ATTACK, 0.8))
		draw_set_transform(c, a)
		var body := Rect2(Vector2(-95, -170), Vector2(190, 340))
		draw_style_box(Palette.raw_box(Color(0.12, 0.13, 0.16), 28, Palette.TEXT, 8), body)
		draw_rect(body.grow(-24), Color(0.25, 0.32, 0.45))
		draw_circle(Vector2(0, 156), 6, Palette.TEXT)
		draw_set_transform(Vector2.ZERO, 0.0)


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
	_set_screen(g, "show_library")
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
	_set_screen(t, "show_pack_tools")
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
	m.tournaments.connect(show_tournaments)
	m.tutorial.connect(show_tutorial)
	m.replays.connect(show_replays)
	m.settings.connect(show_settings)
	m.leave.connect(leave_game)
	_set_screen(m, "show_game_menu")
	return m


## The game's Replays: the last games on this device (and, through a server, the player's games there).
func show_replays() -> ReplaysView:
	var r := ReplaysView.new()
	r.link = server_link if mode == "server" and server_link and server_link.logged_in() else null
	r.back.connect(show_game_menu)
	r.watch.connect(func(x: Replay): show_replay(x))
	_set_screen(r, "show_replays")
	return r


## Watches a replay (its game becomes the active one, as a server game's does); back_to: where
## Back goes (default: the Replays list).
func show_replay(r: Replay, back_to := Callable()) -> ReplayView:
	var have := r.pack()
	if have == null:
		social.toast(r.missing())
		return null
	if Packs.active() != have:
		Packs.set_active(have)
	Packs.set_shell(false)
	var v := ReplayView.new()
	v.replay = r
	v.back.connect(back_to if back_to.is_valid() else show_replays)
	_set_screen(v)
	return v


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
		var req := {"decks": [{"hero": deck.hero, "cards": Array(deck.cards)},
			{"hero": Decks.hero(bot), "cards": Decks.basic(bot, t.format)}], "seed": randi()}
		if t.format != "":
			req.format = t.format  # (Standard: the engine checks the decks and makes only Standard cards)
		start_match(req, [false, true], false, str(Settings.data.get("bot_level", "medium"))))
	_set_screen(t, "show_training_setup")


func show_tutorial() -> void:
	var t := TutorialView.new()
	t.back.connect(show_game_menu)
	t.start.connect(start_tutorial)
	_set_screen(t, "show_tutorial")


## Mission n's intro as its own screen, then the mission (Back: the mission list).
func show_tutorial_intro(n: int) -> void:
	var intro := TutorialIntro.make(n)
	intro.done.connect(start_tutorial.bind(n))
	intro.back.connect(show_tutorial)
	_set_screen(intro, "show_tutorial_intro", [n])


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
	_set_screen(o, "show_online")


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
	_set_screen(a, "show_arena", [s])
	return a


# --- through a server --------------------------------------------------------------------

## Playing through game servers (D14: several connections, each with its own session, friends
## and chats; the same address may be there twice with other logins). A connection per entry of
## the list lives here; in the server mode they are open (a saved session logs in again by
## itself, silently), with the friends overlay. server_link is the one chosen.
var server_links: Array[ServerLink] = []
var server_link: ServerLink
var social: Social
## The player's tournament match over any screen (`t_match`).
var tournament_panel: TournamentPanel


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
	tournament_panel = TournamentPanel.new()
	add_child(tournament_panel)
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
	_set_screen(c, "show_connections")
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
	_set_screen(v, "open_connection", [id])


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
	_set_screen(h, "show_server_home")
	return h


## The game's Play through the server: casual, ranked, the Arena (Back: the game's menu).
func show_server() -> ServerView:
	if server_link == null:
		show_connections()
		return null
	var v := ServerView.new()
	v.link = server_link
	v.back.connect(show_game_menu)
	_set_screen(v, "show_server")
	return v


func start_server_match(session: ServerSession, m: Match, mode_: String) -> MatchView:
	var v := MatchView.new()
	v.lobby = true
	var tid = session.link.get_meta("tournament", null) if mode_ == "tournament" else null
	if mode_ == "tournament":
		v.lobby_label = tr("Back to the tournament")
	v.lobby_back.connect(func():
		if session.link is ServerLink and server_links.has(session.link):
			server_link = session.link
		if mode_ == "tournament":  # back to the tournament's page, not the lobby
			show_tournaments(tid)
		else:
			show_server())
	session.link.set_meta("mode", mode_)
	_set_screen(v)
	v.bind_online(m, session)
	return v


func _on_server_message(msg: Dictionary, l: ServerLink) -> void:
	match msg.get("t"):
		"game_over":  # the result arrives during the game: kept for the lobby after it
			if not (screen is ServerView and l == server_link) and l.get_meta("mode", "") != "tournament":
				l.set_meta("game_over", msg)
		"match":
			if str(msg.get("mode", "")) == "tournament" and tournament_panel:
				tournament_panel.hide_panel()
			start_server_game(msg, l)
		"t_match":
			tournament_panel.show_match(msg, l)
		"spectating":
			start_watch(msg, l)


# --- watching a friend's game ------------------------------------------------------------

## The spectator table, over the screen the player was on (hidden meanwhile: Leave or the
## game's end brings it back as it was), and that screen's game and look.
var watch_view: MatchView
var _before_watch := {}


## The server lets us watch a game (`spectating`): its first state opens the table.
func start_watch(msg: Dictionary, l: ServerLink) -> ServerSession:
	var s := l.watch(msg)
	l.add_child(s)
	if watch_view == null:
		_before_watch = {"pack": Packs.active(), "sets": Packs.server_sets, "shell": Packs.shell}
	s.started.connect(func(m: Match): _show_watch(s, m))
	s.failed.connect(func(reason):
		if s.match_ == null:
			social.toast(reason))
	return s


func _show_watch(s: ServerSession, m: Match) -> MatchView:
	close_watch(false)
	Packs.set_shell(false)
	var v := MatchView.new()
	v.name = "WatchView"
	v.leave.connect(close_watch)
	watch_view = v
	if screen:
		screen.visible = false
	add_child(v)
	v.bind_online(m, s)
	social.screen_changed(v)
	return v


## Leaves the spectator table (the server is told by the session); back: the screen before it.
func close_watch(back := true) -> void:
	if watch_view == null:
		return
	var v := watch_view
	watch_view = null
	if v.session and is_instance_valid(v.session):
		v.session.leave()
	v.queue_free()
	remove_child(v)
	if not back:
		return
	var was: Pack = _before_watch.get("pack")
	if was and was != Packs.active():
		Packs.set_active(was)
		Packs.server_sets = _before_watch.get("sets", {})
	Packs.set_shell(_before_watch.get("shell", Packs.shell))
	if screen:
		screen.visible = true
		if not screen is MatchView:
			Sound.music("menu")
		social.screen_changed(screen)


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
	if mode_ == "tournament":
		l.set_meta("tournament", msg.get("tournament"))
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


## The server's tournaments (the game menu's Tournaments); id: open that tournament's page.
func show_tournaments(id: Variant = null) -> TournamentsView:
	if server_link == null or not server_link.logged_in():
		show_connections()
		return null
	var t := TournamentsView.new()
	t.link = server_link
	t.page_id = id
	t.back.connect(show_game_menu)
	t.replay_ready.connect(func(data: Dictionary): open_replay(data, t.page_id))
	_set_screen(t, "show_tournaments", [id])
	return t


## A tournament game's replay (`replay {game}` answered): watched, then back to that tournament.
func open_replay(data: Dictionary, tournament: Variant = null) -> ReplayView:
	var r := Replay.from_data(data)
	if r == null:
		social.toast(tr("The server has no replay of this game"))
		return null
	return show_replay(r, func(): show_tournaments(tournament))


## The active game's decks (the server's in a server game).
func show_collection() -> void:
	var c := DeckListView.new()
	c.back.connect(show_game_menu)
	_set_screen(c, "show_collection")


## The debug tools of the active game (from its settings), at a tab: DebugTable.SCENE, TESTS...
func show_debug_table(tab := DebugTable.SCENE) -> void:
	var d := DebugTable.new()
	d.tab = tab
	d.back.connect(show_settings)
	d.start.connect(func(g, bots): start_match(g, bots, true))
	d.run_test.connect(start_card_test)
	_set_screen(d, "show_debug_table", [tab])


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

