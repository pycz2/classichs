extends TestCase
## The game server screen on messages as the Rust server sends them
## (server/src/ws.rs): a tag and an Arena run may be null, rank 0 is Legend.


func _view() -> ServerView:
	var keep: String = Settings.data.server
	Settings.data.server = "ws://127.0.0.1:9"  # nothing listens there; the view is freed first
	var v := ServerView.new()
	v.link = ServerLink.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	Settings.data.server = keep
	return v


func _free(v: ServerView) -> void:
	var l := v.link
	v.free()
	l.free()


const ME := {"user": "anna", "tag": null, "arena": null, "season": "2026-10",
	"rank": {"rank": 25.0, "stars": 1.0, "streak": 1.0, "legend": null}}


func test_null_tag_and_arena_after_login() -> void:
	var v := _view()
	v._on_message({"t": "auth", "ok": true, "token": "x", "me": ME})
	eq(v.stage, "lobby")
	check(not v._subtitle.text.contains("null"), "no <null> in the subtitle: " + v._subtitle.text)
	check(v._subtitle.text.begins_with("anna  ·  "), v._subtitle.text)
	eq(v.arena, {})
	v._on_message({"t": "arena", "state": null})
	eq(v.arena, {})
	_free(v)


func test_player_label() -> void:
	eq(ServerView.player_label({"user": "anna", "tag": null}), "anna")
	eq(ServerView.player_label({"user": "anna", "tag": "Moon7"}), "anna#Moon7")


func test_arena_run_from_login_and_after_games() -> void:
	var v := _view()
	var me := ME.duplicate(true)
	me.arena = {"heroes": ["HERO_01", "HERO_02", "HERO_03"], "hero": "HERO_01", "cards": [], "offer": [], "done": false, "wins": 2.0, "losses": 1.0}
	v._on_message({"t": "auth", "ok": true, "token": "x", "me": me})
	eq(v.arena.get("hero"), "HERO_01")
	v._on_message({"t": "game_over", "game": "g", "result": "win", "reason": "over", "arena": {"wins": 3.0, "losses": 1.0, "over": false}})
	eq(int(v.arena.wins), 3)
	eq(v.arena.get("hero"), "HERO_01")
	v._on_message({"t": "game_over", "game": "g2", "result": "loss", "reason": "over", "arena": {"wins": 3.0, "losses": 3.0, "over": true}})
	eq(v.arena.get("status"), "over")
	v._on_message({"t": "me", "me": ME})  # the run is gone on the server
	eq(v.arena.get("status"), "over", "the last result stays")
	eq(int(v.arena.losses), 3)
	_free(v)


func test_rank_text_legend() -> void:
	var v := _view()
	check(v.rank_text({"rank": 0.0, "stars": 0.0, "legend": 42.0}).ends_with(" 42"), v.rank_text({"rank": 0.0, "legend": 42.0}))
	eq(v.rank_text({"rank": 0.0, "stars": 0.0, "legend": null}), tr("Legend"))
	check(v.rank_text({"rank": 18.0, "stars": 2.0, "legend": null}).contains("18"), "rank 18")
	_free(v)


## MatchView.bind_online moves the game's channel under itself: it must still get the game's messages.
func test_channel_gets_messages_after_reparent() -> void:
	var l := ServerLink.new()
	var c := l.channel("g1")
	l.add_child(c)
	(Engine.get_main_loop() as SceneTree).root.add_child(l)
	var other := Node.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(other)
	c.reparent(other)
	var got := []
	c.received.connect(func(m): got.append(m))
	l.dispatch({"t": "game", "game": "g1", "m": {"t": "action", "n": 0}})
	eq(got.size(), 1, "the message reaches the channel")
	other.free()
	l.dispatch({"t": "game", "game": "g1", "m": {"t": "action", "n": 1}})  # a freed channel: dropped
	l.free()


## The server's run has no "status": a run with heroes is active (heroes to choose, then the draft).
func test_arena_tab_shows_the_run() -> void:
	var v := _view()
	v._on_message({"t": "auth", "ok": true, "token": "x", "me": ME})
	v.tab = "Arena"
	v._on_message({"t": "arena", "state": {"heroes": ["HERO_01", "HERO_08", "HERO_06"], "hero": "", "cards": [], "offer": [], "done": false, "wins": 0.0, "losses": 0.0}})
	check(v.find_child("ArenaStart", true, false) == null, "no start button during a run")
	v._on_message({"t": "arena", "state": null})
	check(v.find_child("ArenaStart", true, false) != null, "the start button without a run")
	_free(v)
