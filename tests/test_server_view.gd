extends TestCase
## The game server screen and the connection, on messages as the Rust server
## sends them (server/src/ws.rs): a tag and an Arena run may be null, rank 0 is Legend.

const ME := {"user": "anna", "tag": null, "arena": null, "season": "2026-10",
	"rank": {"rank": 25.0, "stars": 1.0, "streak": 1.0, "legend": null}}
const RUN := {"heroes": ["HERO_01", "HERO_08", "HERO_06"], "hero": "", "cards": [], "offer": [], "done": false, "wins": 0.0, "losses": 0.0}


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _view(logged_in := false) -> ServerView:
	var v := ServerView.new()
	var l := FakeLink.new()
	l.url = Settings.data.server
	v.link = l
	if logged_in:
		l.dispatch({"t": "auth", "ok": true, "token": "x", "me": ME})
	root().add_child(v)
	return v


func _free(v: ServerView) -> void:
	var l := v.link
	v.free()
	l.free()


func _press(parent: Node, button_name: String) -> void:
	var b := parent.find_child(button_name, true, false) as Button
	check(b != null and b.is_visible_in_tree() and not b.disabled, button_name + " shown")
	if b:
		b.pressed.emit()


func test_null_tag_and_arena_after_login() -> void:
	var v := _view()
	eq(v.stage, "login", "an open connection without a session: log in")
	v.link.dispatch({"t": "auth", "ok": true, "token": "x", "me": ME})
	eq(v.stage, "lobby")
	var who := v.find_child("PlayerName", true, false) as Label
	eq(who.text, "anna", "no <null> tag")
	check((v.find_child("RankLine", true, false) as Label).text.contains("25"), "the rank in the top bar")
	eq(v.arena, {})
	v.link.dispatch({"t": "arena", "state": null})
	eq(v.arena, {})
	_free(v)


func test_player_label() -> void:
	eq(ServerView.player_label({"user": "anna", "tag": null}), "anna")
	eq(ServerView.player_label({"user": "anna", "tag": "Moon7"}), "anna#Moon7")


func test_arena_run_from_login_and_after_games() -> void:
	var v := _view()
	var me := ME.duplicate(true)
	me.arena = {"heroes": ["HERO_01", "HERO_02", "HERO_03"], "hero": "HERO_01", "cards": [], "offer": [], "done": false, "wins": 2.0, "losses": 1.0}
	v.link.dispatch({"t": "auth", "ok": true, "token": "x", "me": me})
	eq(v.arena.get("hero"), "HERO_01")
	v.link.dispatch({"t": "game_over", "game": "g", "result": "win", "reason": "over", "arena": {"wins": 3.0, "losses": 1.0, "over": false}})
	eq(int(v.arena.wins), 3)
	eq(v.arena.get("hero"), "HERO_01")
	v.link.dispatch({"t": "game_over", "game": "g2", "result": "loss", "reason": "over", "arena": {"wins": 3.0, "losses": 3.0, "over": true}})
	eq(v.arena.get("status"), "over")
	v.link.dispatch({"t": "me", "me": ME})  # the run is gone on the server
	eq(v.arena.get("status"), "over", "the last result stays")
	eq(int(v.arena.losses), 3)
	_free(v)


func test_rank_text_legend() -> void:
	var v := _view()
	check(v.rank_text({"rank": 0.0, "stars": 0.0, "legend": 42.0}).ends_with(" 42"), v.rank_text({"rank": 0.0, "legend": 42.0}))
	eq(v.rank_text({"rank": 0.0, "stars": 0.0, "legend": null}), tr("Legend"))
	check(v.rank_text({"rank": 18.0, "stars": 2.0, "legend": null}).contains("18"), "rank 18")
	eq([ServerView.stars_needed(25), ServerView.stars_needed(16), ServerView.stars_needed(11), ServerView.stars_needed(3)], [2, 3, 4, 5])
	_free(v)


## MatchView.bind_online moves the game's channel under itself: it must still get the game's messages.
func test_channel_gets_messages_after_reparent() -> void:
	var l := ServerLink.new()
	var c := l.channel("g1")
	l.add_child(c)
	root().add_child(l)
	var other := Node.new()
	root().add_child(other)
	c.reparent(other)
	var got := []
	c.received.connect(func(m): got.append(m))
	l.dispatch({"t": "game", "game": "g1", "m": {"t": "action", "n": 0}})
	eq(got.size(), 1, "the message reaches the channel")
	other.free()
	l.dispatch({"t": "game", "game": "g1", "m": {"t": "action", "n": 1}})  # a freed channel: dropped
	l.free()


## The server's run has no "status": a run with heroes is active (heroes, then the draft, then the games).
func test_arena_tab_shows_the_run() -> void:
	var v := _view(true)
	_press(v, "TabArena")
	eq(ServerLink.saved().get("tab"), "Arena", "the tab is remembered")
	check(v.find_child("Ticket", true, false) != null, "no run: the ticket")
	_press(v, "ArenaStart")
	eq((v.link as FakeLink).of("arena_start").size(), 1, "Enter the Arena")
	v.link.dispatch({"t": "arena", "state": RUN})
	check(v.find_child("ArenaStart", true, false) == null, "no start button during a run")
	_press(v, "Hero_1")
	eq((v.link as FakeLink).of("arena_hero"), [{"t": "arena_hero", "i": 1}], "a hero")
	var draft := RUN.duplicate(true)
	draft.hero = "HERO_08"
	draft.offer = ["VAN_CS2_231", "VAN_CS2_189", "VAN_CS2_172"]
	draft.cards = ["VAN_CS2_231"]
	v.link.dispatch({"t": "arena", "state": draft})
	var offer := v.find_child("Offer2", true, false) as CardView
	check(offer != null, "three cards to choose from")
	offer.clicked.emit(offer)
	eq((v.link as FakeLink).of("arena_pick"), [{"t": "arena_pick", "i": 2}], "a pick")
	eq((v.find_child("ArenaDeck", true, false) as VBoxContainer).get_child_count(), 1, "the deck list")
	draft.done = true
	draft.offer = []
	draft.wins = 4.0
	draft.losses = 1.0
	v.link.dispatch({"t": "arena", "state": draft})
	var rec := v.find_child("Record", true, false)
	eq([rec.wins, rec.losses], [4, 1], "the record of the run")
	_press(v, "ArenaQueue")
	eq(v.queued, "arena", "searching")
	check(v.link.game_deck.arena and v.link.game_deck.hero == "HERO_08", "the Arena deck goes to the game")
	check(v.find_child("QueueTime", true, false) != null, "the search time")
	_press(v, "Unqueue")
	eq(v.queued, "", "cancelled")
	_press(v, "ArenaRetire")
	eq((v.link as FakeLink).of("arena_retire").size(), 0, "the first press only asks")
	_press(v, "ArenaRetire")
	eq((v.link as FakeLink).of("arena_retire").size(), 1, "the second retires")
	v.link.dispatch({"t": "arena", "state": null})
	check(v.find_child("ArenaStart", true, false) != null, "the ticket again without a run")
	_free(v)


## Play: the deck boxes, casual or ranked, one click to search; the deck and the mode are remembered.
func test_play_remembers_the_deck_and_the_mode() -> void:
	var v := _view(true)
	eq(v.tab, "Play")
	var grid := v.find_child("Decks", true, false)
	check(grid.get_child_count() >= 9, "a box per finished deck")
	var box: ServerView.DeckBox = grid.get_child(2)
	box.pressed.emit()
	eq(v.deck.name, box.deck.name, "the chosen deck")
	_press(v, "Mode_ranked")
	check(v.find_child("RankInfo", true, false) != null, "ranked shows the medal and the stars")
	var again := _view(true)
	eq([again.deck.name, again.deck.hero, again.mode], [box.deck.name, box.deck.hero, "ranked"], "remembered for the next time")
	_free(again)
	_press(v, "Queue_ranked")
	var q: Array = (v.link as FakeLink).of("queue")
	eq(q.size(), 1, "one click searches")
	eq([q[0].mode, q[0].deck.hero], ["ranked", box.deck.hero], "with the mode and the deck")
	eq(v.link.game_deck, v.deck, "the game will use that deck")
	(v.find_child("QueueTime", true, false) as Label).text = ""
	v._process(1.5)
	check((v.find_child("QueueTime", true, false) as Label).text.ends_with("0:01"), "the search time runs")
	v.link.dispatch({"t": "match", "game": "g", "host": true, "seed": 1.0, "mode": "ranked"})
	eq(v.queued, "", "a match ends the search")
	_free(v)


## The session: saved on login with its server, sent again by itself, forgotten on logout or refusal.
func test_session_is_saved_resumed_and_forgotten() -> void:
	var l := FakeLink.new()
	l.url = "ws://one"
	l.dispatch({"t": "auth", "ok": true, "token": "tok1", "me": ME})
	eq([ServerLink.saved().get("token"), ServerLink.saved().get("server")], ["tok1", "ws://one"], "saved with the server")
	eq(l.of("chats").size(), 1, "asks for the chats once")
	l.dispatch({"t": "error", "code": "bad_request", "text": "unknown variant `chats`"})
	eq(l.has_chats, false, "an older server: no chats")
	l.log_out()
	eq(l.of("logout").size(), 1, "logout sent")
	eq(ServerLink.saved().get("token"), null, "logout forgets the session")
	ServerLink.remember({"token": "tok2", "server": "ws://one"})
	var r := FakeLink.new()
	r.open_and_resume("ws://two")
	eq(r.resuming, false, "another server: no resume")
	r.open_and_resume("ws://one")
	eq(r.resuming, true, "the saved server: resume")
	r.opened.emit()
	eq(r.of("resume"), [{"t": "resume", "token": "tok2"}], "the token goes on opening")
	r.dispatch({"t": "chats", "list": []})
	r.dispatch({"t": "error", "code": "bad_token", "text": "The session expired: log in again"})
	eq([r.resuming, ServerLink.saved().get("token")], [false, null], "a refused session is forgotten")
	eq(ServerLink.saved().get("server"), "ws://one", "the address stays")
	l.free()
	r.free()


## A view opened while the saved session is being resumed waits, then shows the lobby.
func test_view_waits_for_the_resume() -> void:
	ServerLink.remember({"token": "tok", "server": "ws://test"})
	var v := ServerView.new()
	var l := FakeLink.new()
	l.up = false
	v.link = l
	var keep: String = Settings.data.server
	Settings.data.server = "ws://test"
	root().add_child(v)
	Settings.data.server = keep
	eq([v.stage, l.resuming], ["connecting", true], "connecting with the saved session")
	l.up = true
	l.opened.emit()
	eq(l.of("resume").size(), 1, "resume sent")
	l.dispatch({"t": "auth", "ok": true, "token": "tok", "me": ME})
	eq(v.stage, "lobby", "logged in again without the password")
	_press(v, "Logout")
	eq(v.stage, "login", "logout shows the login")
	eq(ServerLink.saved().get("token"), null, "and forgets the session")
	_free(v)


## Another address in the settings: the open connection is left for it.
func test_changed_address_reconnects() -> void:
	var v := ServerView.new()
	var l := FakeLink.new()
	l.url = "ws://old"
	l.token = "t"
	v.link = l
	root().add_child(v)
	eq([l.url, v.stage], [Settings.data.server, "connecting"], "connecting to the address in the settings")
	_free(v)
