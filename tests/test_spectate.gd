extends TestCase
## Watching a friend's game on a server (server/README.md, "Spectators"): Watch in the friends
## list, the spectator table over any screen (read only, Leave), both hands open with full,
## the end, and back where the player was. Against a FakeLink; states go through JSON.

const ME := {"user": "anna", "tag": "Moon7", "arena": null, "season": "2026-10",
	"rank": {"rank": 20.0, "stars": 1.0, "streak": 0.0, "legend": null}}
const GAME := "w1"
const ENG := "spect_eng"


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## main logged in to a fake server, on the server's home; bob plays a game.
func _main() -> Node:
	if Settings.data.servers.is_empty():
		Settings.data.servers = [{"url": "ws://localhost:7377", "name": "localhost"}]
	Settings.save()
	var m: Node = load("res://ui/main.tscn").instantiate()
	m.server_link = FakeLink.new()
	root().add_child(m)
	m.show_connections()
	m.server_link.dispatch({"t": "auth", "ok": true, "token": "t", "me": ME})
	m.server_link.dispatch({"t": "friends", "list": [{"user": "bob", "tag": "Bob1", "online": true, "status": "in_game",
		"in_game": {"game": GAME, "mode": "casual"}}, {"user": "cid", "tag": null, "online": true, "status": "online"}],
		"requests_in": [], "requests_out": [], "blocked": []})
	m.social._process(0.0)
	m.show_server_home()
	FakeLink.engine_game(ENG)
	return m


## A spectate_state as the server sends it: seat's view (full: what both seats see).
static func _state(seat: int, full := false) -> Dictionary:
	var msg := FakeLink.state(GAME, ENG, seat)
	msg.t = "spectate_state"
	if full:
		var other: Dictionary = FakeLink.state(GAME, ENG, 1 - seat).view.entities
		for id in other:
			if not msg.view.entities.has(id) or msg.view.entities[id].card == "":
				msg.view.entities[id] = other[id]
	return JSON.parse_string(JSON.stringify(msg))


func _watch(m: Node, full := false) -> MatchView:
	m.server_link.dispatch({"t": "spectating", "game": GAME, "mode": "casual", "pack": Packs.active().rules_hash(),
		"players": ["bob", "eve"], "seat": 0, "full": full})
	m.server_link.dispatch(_state(0, full))
	return m.watch_view


func test_watch_is_offered_for_a_friend_in_a_game() -> void:
	var m := _main()
	var s: Social = m.social
	s.show_panel(true)
	var bob := s.find_child("Friend_bob", true, false)
	var cid := s.find_child("Friend_cid", true, false)
	check(bob.find_child("Watch", true, false) != null and bob.find_child("Invite", true, false) == null, "Watch, not Invite, in a game")
	check(cid.find_child("Watch", true, false) == null and cid.find_child("Invite", true, false) != null, "no Watch for one not in a game")
	(bob.find_child("Watch", true, false) as Button).pressed.emit()
	eq(m.server_link.of("spectate"), [{"t": "spectate", "user": "bob"}], "asked the server")
	eq(s.panel_open, false, "the panel makes room for the table")
	m.free()


func test_the_spectator_table_is_read_only_and_leaves_back_to_the_screen() -> void:
	var m := _main()
	var home: Control = m.screen
	var v := _watch(m)
	check(v != null and v.watching and v.is_inside_tree(), "the table opens over the screen")
	check(m.screen == home and not home.visible, "the screen waits under it")
	eq(v.viewer(), 0, "the friend's seat at the bottom")
	eq(v.g.players[1].hand.map(func(e): return e.card_id).filter(func(c): return c != ""), [], "the opponent's hand is hidden")
	check(v.g.players[0].hand.all(func(e): return e.card_id != ""), "the friend's hand is open")
	var title := (v.find_child("WatchTitle", true, false) as Label).text
	check(title.contains("bob") and title.contains("eve"), "who plays whom: " + title)
	check(v.find_child("SpectatorMark", true, false) != null, "the spectator mark")
	check(not v._end_turn.visible and (v.find_child("LeaveWatch", true, false) as Button).visible, "Leave where End Turn was")
	check(not (v.find_child("TrackerButton", true, false) as Control).visible, "no deck tracker")
	# nothing on the table acts: hand cards, End Turn, emotes, the mulligan
	eq(v.my_action(), false, "never the spectator's move")
	for e in v.g.players[0].hand:
		v.click_entity(e.id)
	v._on_end_turn()
	v.send_emote("wow")
	v._on_right_click(v._views[v.g.players[0].hero.id])
	eq(v._wheel.visible, false, "no emotes")
	v.refresh()
	check(v._overlay == null, "no mulligan screen for the spectator")
	eq(m.server_link.sent.filter(func(x): return x.t in ["act", "emote", "intent"]), [], "nothing sent")
	# a change on the server reaches the table
	Rules.request({"op": "act", "game": ENG, "action": {"type": "mulligan", "player": 0, "replace": []}})
	m.server_link.dispatch(_state(0))
	check(v.controller.game.players[0].mulliganed, "the next state")
	(v.find_child("LeaveWatch", true, false) as Button).pressed.emit()
	eq(m.server_link.of("unspectate"), [{"t": "unspectate"}], "the server is told (no fields: the server refuses any)")
	check(m.watch_view == null and m.screen == home and home.visible, "back where the player was")
	m.free()


func test_full_view_shows_both_hands_face_up() -> void:
	var m := _main()
	var v := _watch(m, true)
	check(v.full_view, "full")
	check(v.g.players[1].hand.all(func(e): return e.card_id != ""), "the other hand is known")
	var faces := v.g.players[1].hand.map(func(e): return (v._views[e.id] as CardView).face_up)
	check(not faces.is_empty() and faces.all(func(f): return f), "and face up %s" % [faces])
	m.free()


func test_the_end_of_a_watched_game() -> void:
	var m := _main()
	var v := _watch(m)
	m.server_link.dispatch({"t": "spectate_end", "game": GAME, "winner": 1, "reason": "disconnect"})
	var lost := v.find_child("ConnectionLost", true, false)
	check(lost != null, "the end shows")
	var texts := str(lost.find_children("*", "Label", true, false).map(func(l): return l.text))
	check(texts.contains(tr("The game is over")) and texts.contains("eve"), texts)
	(lost.find_child("LeaveWatch", true, false) as Button).pressed.emit()
	eq(m.server_link.of("unspectate"), [], "nothing to stop: the server ended it")
	check(m.watch_view == null and m.screen.visible, "back")
	# an end by the game's moves: the result names the winner
	v = _watch(m)
	Rules.request({"op": "act", "game": ENG, "action": {"type": "concede", "player": 1}})
	m.server_link.dispatch(_state(0))
	m.server_link.dispatch({"t": "spectate_end", "game": GAME, "winner": 0, "reason": "over"})
	v._ending = false
	v.refresh()
	var over := v.find_child("GameOver", true, false)
	check(over != null and (over.find_child("ResultTitle", true, false) as Label).text == tr("%s wins") % "bob", "bob wins")
	check(over.find_child("LeaveWatch", true, false) != null, "Leave")
	m.free()


## A game of one's own starting while watching closes the spectator table.
func test_an_own_game_replaces_the_watch() -> void:
	var m := _main()
	_watch(m)
	m.show_server()
	eq(m.watch_view, null, "closed")
	check(m.screen is ServerView and m.screen.visible, "the new screen shows")
	m.free()
