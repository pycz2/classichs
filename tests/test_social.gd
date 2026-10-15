extends TestCase
## The friends overlay over every screen (ui/social.gd), owned by main with the
## server connection: shown only when logged in, unread badges, chats, invites.

const ME := {"user": "anna", "tag": "Moon7", "arena": null, "season": "2026-10",
	"rank": {"rank": 20.0, "stars": 1.0, "streak": 0.0, "legend": null}}
const FRIENDS := {"t": "friends", "list": [{"user": "bob", "tag": "Bob1", "online": true, "status": "online"},
		{"user": "cid", "tag": null, "online": false, "status": "offline"}],
	"requests_in": [{"user": "dan", "tag": "Dan9"}], "requests_out": [], "blocked": []}


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## main with a fake connection (logged in unless told otherwise).
func _main(logged_in := true) -> Node:
	var m: Node = load("res://ui/main.tscn").instantiate()
	m.server_link = FakeLink.new()
	m.server_link.url = Settings.data.server
	root().add_child(m)
	if logged_in:
		_login(m)
	return m


func _login(m: Node) -> void:
	m.server_link.dispatch({"t": "auth", "ok": true, "token": "t", "me": ME})
	m.server_link.dispatch(FRIENDS)
	m.social._process(0.0)


func _sent(m: Node, t: String) -> Array:
	return (m.server_link as FakeLink).of(t)


func test_shown_only_when_logged_in_and_on_every_screen() -> void:
	var m := _main(false)
	var s: Social = m.social
	s._process(0.0)
	eq(s.visible, false, "hidden before login")
	_login(m)
	eq(s.visible, true, "shown after login")
	eq(s.button.text, "1", "one friend online")
	eq(s.button.position, Vector2(12, 668), "bottom left in the menu")
	for show in [m.show_collection, m.show_settings, m.show_training_setup, m.show_server]:
		show.call()
		s._process(0.0)
		check(m.social == s and s.visible, "still there on " + str(m.screen.get_class()))
	m.start_match({"decks": [{"hero": "HERO_08", "cards": Decks.basic("MAGE")}, {"hero": "HERO_01", "cards": Decks.basic("WARRIOR")}], "seed": 1}, [false, true])
	eq([s.in_match, s.button.position], [true, Vector2(1188, 4)], "beside the gear in a game")
	m.show_menu()
	eq(s.in_match, false, "back to the corner")
	m.server_link.dispatch({"t": "logged_out"})
	m.server_link.token = ""
	s._process(0.0)
	eq([s.visible, s.friends.list.size()], [false, 0], "logout hides and clears it")
	m.free()


func test_panel_lists_friends_requests_and_adds_by_tag() -> void:
	var m := _main()
	var s: Social = m.social
	s.button.pressed.emit()
	eq(s.panel_open, true, "the button opens the panel")
	eq(_sent(m, "friends").size(), 2, "fresh presence on opening")
	var list := s.find_child("FriendList", true, false)
	check(list.find_child("Friend_bob", false, false) != null and list.find_child("Friend_cid", false, false) != null, "friends listed")
	var rows := list.get_children().filter(func(c): return c is Social.FriendRow and c.kind == "friend")
	eq(rows.map(func(r): return r.user), ["bob", "cid"], "online first")
	(list.find_child("Friend_dan", false, false).find_child("Accept", true, false) as Button).pressed.emit()
	eq(_sent(m, "friend_accept"), [{"t": "friend_accept", "user": "dan"}], "accept a request")
	var tag := s.find_child("FriendTag", true, false) as LineEdit
	tag.text = "eve#Star5"
	tag.text_submitted.emit(tag.text)
	eq(_sent(m, "friend_add"), [{"t": "friend_add", "tag": "Star5"}], "Enter adds by tag")
	check((list.find_child("Friend_cid", false, false).find_child("Invite", true, false) as Button).disabled, "no invite to an offline friend")
	s._catcher.gui_input.emit(_click())
	eq(s.panel_open, false, "a click beside closes it")
	m.free()


func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	return e


func test_presence_pushes_and_older_statuses() -> void:
	var m := _main()
	var s: Social = m.social
	m.server_link.dispatch({"t": "presence", "user": "cid", "online": true, "status": "searching"})
	eq([s.status.cid, s.online_count(), s.button.text], ["searching", 2, "2"], "a push updates the presence")
	m.server_link.dispatch({"t": "presence", "user": "bob", "online": true, "status": "in_game"})
	eq(s.status_text("bob"), tr("In a game"))
	eq([Social.presence("game"), Social.presence("queue"), Social.presence(null, true), Social.presence(null, false)],
		["in_game", "searching", "online", "offline"], "an older server's words")
	m.free()


## A message outside a game opens the chat by itself; in a game it is a badge and a toast.
func test_unread_badge_and_chats() -> void:
	var m := _main()
	var s: Social = m.social
	m.server_link.dispatch({"t": "chats", "list": [{"with": "bob", "tag": "Bob1", "online": true, "status": "online",
		"last": {"from": "bob", "text": "hi", "at": 1.0}, "unread": 2.0}]})
	eq([m.server_link.has_chats, s.unread_total(), s.button.unread], [true, 2, 3], "unread from the server (and a request)")
	m.server_link.dispatch({"t": "msg", "from": "cid", "text": "hello", "at": 2.0})
	var w: Social.ChatWindow = s.find_child("Chat_cid", true, false)
	check(w != null, "the chat opened by itself")
	eq(_sent(m, "history"), [{"t": "history", "with": "cid"}], "its history asked")
	eq(s.unread.get("cid"), 1, "unread until looked at")
	m.start_match({"decks": [{"hero": "HERO_08", "cards": Decks.basic("MAGE")}, {"hero": "HERO_01", "cards": Decks.basic("WARRIOR")}], "seed": 1}, [false, true])
	check(s.minimized.has("cid"), "open chats fold when a game starts")
	m.server_link.dispatch({"t": "msg", "from": "bob", "text": "gg", "at": 3.0})
	check(s.find_child("Chat_bob", true, false) == null, "no window pops up in a game")
	eq(s.button.unread, 5, "the badge counts")
	check(s._toast.visible and s._toast.text.contains("bob: gg"), "a toast: " + s._toast.text)
	s._toast.pressed.emit()
	w = s.find_child("Chat_bob", true, false)
	check(w != null, "the toast opens the chat")
	eq(s.unread.get("bob", 0), 0, "and reads it")
	eq(_sent(m, "read"), [{"t": "read", "with": "bob"}], "read sent (the server knows chats)")
	w.input.text_submitted.emit("see you")
	eq(_sent(m, "msg"), [{"t": "msg", "to": "bob", "text": "see you"}], "Enter sends")
	eq(s.chats.bob.back().text, "see you", "shown at once")
	eq(w.find_child("ChatLines", true, false).get_child_count(), 2, "both lines in the window")
	s.minimize_chat("bob")
	eq(w.size.y, 40.0, "minimized to its header")
	s.close_chat("bob")
	eq(s.open_chats, ["cid"] as Array[String], "closed")
	m.free()


## An invite can be accepted from any screen; the game starts in main with the deck sent.
func test_invite_from_anywhere_starts_the_game() -> void:
	var m := _main()
	var s: Social = m.social
	m.show_collection()
	m.server_link.dispatch({"t": "invite", "from": "bob"})
	var dlg := s.find_child("InviteDialog", true, false)
	check(dlg != null, "the invite over the collection")
	(dlg.find_child("InviteAccept", true, false) as Button).pressed.emit()
	var acc := _sent(m, "invite_accept")
	eq([acc.size(), acc[0].from], [1, "bob"], "accepted")
	eq(m.server_link.game_deck.hero, acc[0].deck.hero, "the game uses the deck sent")
	m.server_link.dispatch({"t": "match", "game": "g7", "mode": "friendly", "opponent": {"user": "bob", "tag": "Bob1"}, "you": 1.0})
	check(not m.screen is MatchView, "the table waits for the server's first state")
	FakeLink.engine_game("e7")
	m.server_link.dispatch(FakeLink.state("g7", "e7", 1))
	var v := m.screen as MatchView
	check(v != null and v.lobby, "the server's game on the table, back to the lobby after it")
	eq([v.controller.viewer(), v.controller.is_server(), v.player_names[0]], [1, true, "bob"], "seat 1 against bob, the server decides")
	eq(v.controller.game.players[0].hand.map(func(e): return e.card_id).filter(func(c): return c != ""), [], "the opponent's hand stays hidden")
	eq(v.controller.game.start_decks[1], m.server_link.game_deck.cards, "the own deck for the tracker")
	v.controller.submit({"type": "mulligan", "player": 1, "replace": []})
	eq(_sent(m, "act"), [{"t": "act", "game": "g7", "action": {"type": "mulligan", "player": 1, "replace": []}}], "a move goes to the server")
	m.server_link.dispatch({"t": "match", "game": "g8", "rejoin": true, "mode": "casual", "you": 0.0, "opponent": {"user": "cid", "tag": null}})
	m.server_link.dispatch(FakeLink.state("g8", "e7", 0))
	check(m.screen != v and m.screen is MatchView and m.screen.controller.viewer() == 0, "a rejoined game opens its table")
	Rules.request({"op": "drop", "game": "e7"})
	m.free()


## A saved session connects and logs in again at the start, without asking.
func test_main_resumes_a_saved_session() -> void:
	ServerLink.remember({"token": "saved", "server": "ws://saved:7377"})
	var m := _main(false)
	var l: FakeLink = m.server_link
	eq([l.url, l.resuming], ["ws://saved:7377", true], "the saved server, resuming")
	l.opened.emit()
	eq(l.of("resume"), [{"t": "resume", "token": "saved"}], "the token sent")
	l.dispatch({"t": "auth", "ok": true, "token": "saved", "me": ME})
	m.social._process(0.0)
	eq(m.social.visible, true, "logged in: the overlay is there")
	eq(l.of("friends").size(), 1, "the friends asked")
	m.free()


## A refused saved session is forgotten without a word.
func test_refused_session_is_silent() -> void:
	ServerLink.remember({"token": "old", "server": "ws://saved:7377"})
	var m := _main(false)
	m.server_link.opened.emit()
	m.server_link.dispatch({"t": "error", "code": "bad_token", "text": "The session expired: log in again"})
	eq([m.social._toast.visible, ServerLink.saved().get("token")], [false, null], "no toast, token gone")
	m.server_link.dispatch({"t": "error", "code": "not_found", "text": "No such player"})
	eq(m.social._toast.visible, true, "other errors show off the lobby")
	m.free()
