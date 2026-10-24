extends TestCase
## A game on a server (the server keeps the game; the client sends `act` and
## draws the `state` it gets: its own view only), against a fake server: a
## FakeLink and a game in the local engine standing in for the server's.

const GAME := "s1"


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## The fake server: its game, the seat of the client, and the link.
class Fake:
	var link := FakeLink.new()
	var you := 1
	var id := Rules.new_id("srv")

	func start() -> void:
		Rules.request({"op": "new", "game": id, "seed": 9, "first": 0,
			"decks": [{"hero": "HERO_01", "cards": Decks.basic("WARRIOR")}, {"hero": "HERO_08", "cards": Decks.basic("MAGE")}]})

	func state(events: Array, deadline := 75) -> Dictionary:
		var s: Dictionary = Rules.request({"op": "snapshot", "game": id, "view": you}).state
		return {"t": "state", "game": GAME, "view": s, "events": events,
			"result": {"over": s.game_over, "winner": s.winner, "turn": s.turn, "current": s.current, "phase": s.phase, "deadline": deadline}}

	## Plays what the client sent (act), then the opponent's moves (the engine's bot) until it is the client's turn.
	func serve(opponent := true) -> void:
		var acts := link.of("act")
		link.sent.clear()
		for m in acts:
			var r := Rules.request({"op": "act", "game": id, "action": m.action, "view": you})
			if not r.ok or m.game != GAME:
				link.dispatch({"t": "act_error", "game": GAME, "error": str(r.get("error", "wrong game"))})
				continue
			link.dispatch(state(r.events))
		for i in (200 if opponent else 0):
			var a = Rules.request({"op": "bot", "game": id, "player": 1 - you}).action
			if a == null or snapshot().game_over:
				return
			var r := Rules.request({"op": "act", "game": id, "action": a, "view": you})
			link.dispatch(state(r.events))

	func snapshot() -> Dictionary:
		return Rules.request({"op": "snapshot", "game": id}).state

	func legal(p: int) -> Array:
		return Rules.request({"op": "legal", "game": id, "player": p}).actions


func _deck() -> Deck:
	return Deck.from_dict({"name": "", "hero": "HERO_08", "cards": Decks.basic("MAGE")})


## A server game shown in a MatchView, as main shows it.
func _table(f: Fake) -> MatchView:
	f.start()
	var s := f.link.session({"t": "match", "game": GAME, "mode": "ranked", "you": f.you, "opponent": {"user": "bob", "tag": "Bob1"}}, _deck())
	var v := MatchView.new()
	v.lobby = true
	root().add_child(v)
	s.started.connect(func(m: Match): v.bind_online(m, s))
	f.link.dispatch(f.state(Rules.request({"op": "history", "game": f.id, "view": f.you}).history[0].events))
	return v


func test_the_table_shows_the_servers_view_and_sends_acts() -> void:
	var f := Fake.new()
	var v := _table(f)
	check(v.controller != null and v.controller.is_server(), "the first state opens the table")
	var g := v.g
	eq(v.viewer(), 1, "the client's seat is the viewer")
	eq(g.players[0].hand.map(func(e): return e.card_id), ["", "", ""], "the opponent's hand is hidden")
	check(g.players[1].hand.all(func(e): return e.card_id != ""), "the own hand is known")
	eq(g.players[1].deck.size(), 26, "the own deck comes from the own list (tracker)")
	eq(v.player_names, ["bob", ""] if Profile.load_name() == "" else ["bob", v.player_names[1]], "the opponent's name")
	# the mulligan: an act to the server, the table waits for its state
	v.controller.submit({"type": "mulligan", "player": 1, "replace": []})
	eq(f.link.of("act"), [{"t": "act", "game": GAME, "action": {"type": "mulligan", "player": 1, "replace": []}}], "the act")
	check(v.controller.waiting(), "waiting for the server")
	f.serve()
	check(not v.controller.waiting(), "the state came")
	eq(g.phase, "PLAY", "both kept their hands: the game runs")
	v.free()


## Every move comes from the client's own legal actions (computed on its view by
## the engine), the server agrees with them, and no hidden card ever shows.
func test_a_whole_game_through_the_server() -> void:
	var f := Fake.new()
	var v := _table(f)
	var m := v.controller
	var g := v.g
	for step in 400:
		f.serve()
		if g.game_over:
			break
		for e in g.players[0].hand + g.players[0].secrets:
			eq(e.card_id, "", "hidden: the opponent's hand and Secrets")
		var mine: Array = m.legal().filter(func(a): return a.player == f.you)
		eq(mine, f.legal(f.you), "the view's legal actions are the server's (step %d)" % step)
		if mine.is_empty():
			continue
		var play: Array = mine.filter(func(a): return a.type in ["play", "attack", "hero_power"])
		var a: Dictionary = play[0] if not play.is_empty() and step % 3 != 2 else mine.filter(func(x): return x.type != "concede")[0]
		m.submit(a)
	check(g.game_over, "the game ended")
	eq(g.game_over, f.snapshot().game_over, "the same end as the server")
	check(g.history.size() > 10, "a history from the states")
	check(v.find_child("GameOver", true, false) != null, "the result shows")
	v.free()


func test_a_refused_act_changes_nothing() -> void:
	var f := Fake.new()
	var v := _table(f)
	var refused := []
	v.controller.refused.connect(func(e): refused.append(e))
	var before := v.g.snapshot.duplicate(true)
	v.controller.submit({"type": "end_turn", "player": 1})  # the mulligan is not over
	f.serve(false)
	eq(refused.size(), 1, "act_error reaches the match")
	eq(v.g.snapshot, before, "nothing changed")
	check(not v.controller.waiting(), "no longer waiting")
	v.free()


func test_emotes_intents_and_the_timer_come_from_the_server() -> void:
	var f := Fake.new()
	var v := _table(f)
	v.send_emote("wow")
	eq(f.link.of("emote"), [{"t": "emote", "game": GAME, "id": "wow"}], "an emote goes to the server")
	f.link.dispatch({"t": "emote", "game": GAME, "id": "threaten", "from": 0})
	check(v.bubble_text(0) != "", "the opponent's emote shows")
	f.link.dispatch({"t": "emote", "game": GAME, "id": "oops", "from": 1})
	eq(v.bubble_text(1), VoiceLines.text("HERO_08", "wow") if VoiceLines.text("HERO_08", "wow") != "" else tr("Wow!"), "an echo of the own emote is ignored")
	f.link.dispatch({"t": "intent", "game": GAME, "i": {"k": "hover", "i": 1}, "from": 0})
	eq(v._opp_hover, 1, "the opponent's intent")
	f.link.dispatch(f.state([], 12))
	v.tick(0.0)
	check(v._time_left > 10.0 and v._time_left <= 12.0, "the turn's time is the server's deadline (%s)" % v._time_left)
	v.controller.timeout(1)
	eq(f.link.of("act"), [], "no own timeout moves: the server plays them")
	v.free()


func test_the_server_ends_a_game_that_does_not_add_up() -> void:
	var f := Fake.new()
	var v := _table(f)
	f.link.dispatch({"t": "game_over", "game": GAME, "result": "loss", "reason": "illegal",
		"message": "Something does not add up: your game and the server's differ. Nobody is banned."})
	var lost := v.find_child("ConnectionLost", true, false)
	check(lost != null, "the game ends with a message")
	check(lost != null and str(lost.find_children("*", "Label", true, false).map(func(l): return l.text)).contains("Nobody is banned"), "the server's message")
	v.free()


func test_leaving_a_running_game_concedes_it() -> void:
	var f := Fake.new()
	var v := _table(f)
	v._leave()
	eq(f.link.of("act"), [{"t": "act", "game": GAME, "action": {"type": "concede", "player": 1}}], "concede")
	v.free()


## main opens the table for a `match` (from any screen), also for a rejoin.
func test_main_opens_the_table_on_match_and_state() -> void:
	Settings.data.servers = [{"url": "ws://localhost:7377", "name": "localhost"}]  # one server (none by default)
	Settings.save()  # main reads the settings
	var m: Node = load("res://ui/main.tscn").instantiate()
	var f := Fake.new()
	f.start()
	m.server_link = f.link
	root().add_child(m)
	f.link.dispatch({"t": "auth", "ok": true, "token": "t", "me": {"user": "anna", "tag": "Moon7"}})
	f.link.dispatch({"t": "match", "game": GAME, "mode": "casual", "you": 1, "opponent": {"user": "bob", "tag": null}, "rejoin": true})
	check(not m.screen is MatchView, "the table waits for the first state")
	f.link.dispatch(f.state([]))
	check(m.screen is MatchView and (m.screen as MatchView).lobby, "a server game's table")
	var v: MatchView = m.screen
	eq(v.g.players[1].hand.size(), 4, "the own view")
	m.free()


## A `match` names its game's pack: the table shows that one. A pack the device has becomes
## active at once (a rejoin while another one was active); one it lacks is downloaded first
## and the states wait for it; when the download fails the game is not shown in a wrong pack.
func test_the_table_uses_the_games_pack() -> void:
	var classic := Packs.active()
	var neon: Pack = null
	for p in Packs.all():
		if p.builtin() and p.id() != Packs.CLASSIC:
			neon = p
	var f := Fake.new()
	f.start()
	var s := f.link.session({"t": "match", "game": GAME, "you": 1, "rejoin": true, "pack": neon.rules_hash()}, null)
	eq(Packs.active(), neon, "switched to the game's pack")
	s.free()
	Packs.set_active(classic)
	var other := "f".repeat(64)
	f.link.has_packs = true
	f.link.packs = {"server": [], "mine": [{"id": "x", "rules_hash": other, "content_hash": "e".repeat(64), "size": 9}]}
	s = f.link.session({"t": "match", "game": "s2", "you": 1, "rejoin": true, "pack": other}, null)
	var why := []
	s.failed.connect(func(r): why.append(r))
	var started := []
	s.started.connect(func(m): started.append(m))
	eq(f.link.http.back().path, "/packs/%s.cardpack" % ("e".repeat(64)), "the server's file is fetched")
	s.on_message(f.state([]))
	eq(started, [], "the table waits for the game's pack")
	f.link.http.back().done.call(404, PackedByteArray())
	eq(why.size(), 1, "a failed download ends it")
	eq([started, Packs.active()], [[], classic], "never shown in another pack")
	s.free()
	# another login took the account: the table says so, not "Connection lost"
	s = f.link.session({"t": "match", "game": "s3", "you": 1}, null)
	s.failed.connect(func(r): why.append(r))
	f.link.dispatch({"t": "kicked", "reason": "another_login"})
	s.on_closed()
	eq(str(why.back()), tr("You logged in on another device"), "why the game ended here")
	s.free()
