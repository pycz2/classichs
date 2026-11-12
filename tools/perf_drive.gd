extends Node
## A test driver for the performance harness (tools/perf/): plays tournaments by itself through the
## game's own screens, as a player would, for hours. PerfLog adds it under main when asked:
## the browser `?perf=1&drive=1&server=ws://127.0.0.1:PORT&user=NAME`, desktop
## `-- --perf --drive --server=ws://… --user=NAME`. On the server: registers (or logs in), keeps 3
## decks there, then again and again creates a tournament (round robin, single elimination, Swiss in
## turn; best of 3 or 5), joins it, adds tournament bots up to the maximum and waits; the harness moves
## the start to now (the database: the server takes 11 minutes at least). In it: accepts, bans, picks,
## plays every game with random legal moves through the table (MatchView._act), goes back to the
## tournament's page, looks at the bracket, and watches others' matches while it waits. Prints
## "DRIVE: …" lines (the harness reads them). Never part of a normal game: nothing adds it unasked.

const PASSWORD := "perf harness 1"
const TICK := 0.25

var main: Node
var url := ""
var user := ""
var tours := 1000  # tournaments to play (then it stops)
var link: ServerLink
var phase := "boot"
var made := 0  # tournaments created by this account (the server allows 10 a day)
var account := 0
var tid: Variant = null  # the tournament now
var games := 0
var watched := 0
var _left := 0.0
var _wait_until := 0
var _turn_acts := 0
var _turn_key := ""
var _watch_since := 0
var _tab_flip := 0
var _over_since := 0
var _panel_since := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "PerfDrive"
	process_mode = Node.PROCESS_MODE_ALWAYS
	url = _arg("server", "ws://127.0.0.1:7390")
	user = _arg("user", "perf%d" % (Time.get_unix_time_from_system() as int % 100000))
	tours = int(_arg("tours", "1000"))
	_rng.seed = hash(user)
	say("start %s as %s" % [url, user])


func _arg(k: String, def: String) -> String:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--%s=" % k):
			return a.split("=", true, 1)[1]
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("new URLSearchParams(location.search).get('%s') || ''" % k, true)
		if str(v) != "":
			return str(v)
	return def


func say(s: String) -> void:
	print("DRIVE: ", s)


func now() -> int:
	return Time.get_ticks_msec()


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = TICK
	if main == null or not main.get("screen"):
		return
	if now() < _wait_until:
		return
	match phase:
		"boot":
			_boot()
		"auth", "decks", "done":
			pass
		_:
			_tournament()
	if link and link.logged_in():
		_panel()
		_table()
		_watching()


func _boot() -> void:
	Settings.data.servers = [{"id": url, "url": url, "name": "perf"}]
	Settings.save()
	main.sync_server_links()
	link = main.link_for(url)
	link.message.connect(_on_message)
	link.opened.connect(func():
		link.send({"t": "register", "user": _account(), "password": PASSWORD}), CONNECT_ONE_SHOT)
	link.open(url)
	main.mode = "server"
	phase = "auth"


func _account() -> String:
	return user if account == 0 else "%s_%d" % [user, account]


func _on_message(msg: Dictionary) -> void:
	match msg.get("t"):
		"error":
			if phase == "auth" and msg.get("code") == "taken":
				link.send({"t": "login", "user": _account(), "password": PASSWORD})
			elif msg.get("code") != "rate_limited":
				say("error %s: %s" % [msg.get("code"), msg.get("text")])
		"auth":
			if phase == "auth" and msg.get("ok", false):
				say("logged in as " + _account())
				phase = "decks"
				_after_login.call_deferred()
		"game_over":
			if not msg.get("watch", false):
				games += 1


func _after_login() -> void:
	while not link.has_decks:  # the client asks chats, packs, decks after the login
		await get_tree().create_timer(0.2).timeout
	var classic: Pack = null
	for p: Pack in Packs.all():
		if p.id() == Packs.CLASSIC:
			classic = p
	main.server_link = link
	main.enter_game(classic)
	var have := link.decks_of(classic)
	var classes := {}
	for d in have:
		classes[d.card_class()] = true
	for t in Decks.templates():
		if classes.size() >= 3:
			break
		var d: Deck = t.deck
		if classes.has(d.card_class()):
			continue
		classes[d.card_class()] = true
		link.send({"t": "deck_save", "deck": {"name": t.name, "hero": d.hero, "cards": Array(d.cards)}})
	while link.decks_of(classic).size() < 3:
		await get_tree().create_timer(0.2).timeout
	say("decks ready: %d" % link.decks_of(classic).size())
	phase = "create"


## The tournament's life, one step a tick.
func _tournament() -> void:
	if main.get("watch_view") != null or main.screen is MatchView:
		return
	var tv := main.screen as TournamentsView
	match phase:
		"create":
			if made >= tours:
				say("all %d tournaments played; games %d, watched %d" % [made, games, watched])
				phase = "done"
				return
			if made > 0 and made % 9 == 0 and account < made / 9:  # (10 a day per creator)
				account = made / 9
				say("a new account: " + _account())
				link.log_out()
				phase = "auth"
				link.send({"t": "register", "user": _account(), "password": PASSWORD})
				return
			tv = main.show_tournaments()
			var f := TournamentsView.default_form()
			var fmt: String = ["round_robin", "elimination", "swiss"][made % 3]
			f.name = "Perf %d %s" % [made + 1, fmt]
			f.format = fmt
			f.best_of = [3, 5][(made / 3) % 2]
			f.max_players = 6  # (the server has 2 tournament bots a level: 5 bots of easy, medium, hard)
			f.spectators = true
			f.start_at = TournamentsView.now_ms() + 12 * 60000
			tv.form = f
			tv.form_mode = "create"
			tv.submit_form()
			made += 1
			tid = null
			say("create %s (best of %d, %d players)" % [f.name, f.best_of, f.max_players])
			phase = "join"
		"join":
			if tv == null or tv.page_id == null or tv.page.is_empty():
				return
			tid = tv.page_id
			var need := TournamentsView.decks_needed(tv.page)
			var picked := []
			var classes := {}
			for d in tv.decks_for(tv.page):
				if not classes.has(d.card_class()) and picked.size() < need:
					classes[d.card_class()] = true
					picked.append(d)
			tv.chosen = picked
			tv.send_decks(false)
			say("join %s with %d decks" % [str(tid), picked.size()])
			phase = "bots"
			_wait_until = now() + 1500
		"bots":
			# the server's pool has 2 bots a level: the places are filled level by level
			var es = tv.page.get("entrants")
			var n: int = int(TournamentsView.opt(tv.page, "max_players", 6)) - (es.size() if es is Array else 1)
			for l in ["easy", "medium", "hard"]:
				if n > 0:
					tv.link.send({"t": "t_add_bots", "id": TournamentsView.wire_id(tid), "level": l, "count": mini(2, n)})
					say("add %d %s bots" % [mini(2, n), l])
					n -= 2
			phase = "wait_start"
			_wait_until = now() + 2000
		"wait_start", "running":
			if tv == null or tv.page_id == null:
				tv = main.show_tournaments(tid)
				return
			var st := str(tv.page.get("status", ""))
			if phase == "wait_start" and st == "running":
				say("tournament %s running" % str(tid))
				phase = "running"
			if st in ["finished", "closed", "cancelled"]:
				say("tournament %s %s; games %d, watched %d" % [str(tid), st, games, watched])
				phase = "create"
				_wait_until = now() + 3000
				return
			if now() > _tab_flip:  # the bracket and the overview in turn, as a player looks around
				_tab_flip = now() + 15000
				tv.page_tab = "bracket" if tv.page_tab == "overview" else "overview"
				tv._build_page()
			if phase == "running" and tv.page_tab == "bracket" and not main.tournament_panel.visible and _rng.randf() < 0.05:
				_watch_one(tv)


## Watches a match being played (the bracket's match dialog, Watch).
func _watch_one(tv: TournamentsView) -> void:
	for m in TournamentBracket.matches_of(tv.page):
		if TournamentBracket.is_live(m) and not TournamentBracket.players(m).has(tv.me()):
			tv.show_match(m)
			var w := tv.find_child("Watch", true, false) as Button
			if w:
				w.pressed.emit()
				_watch_since = now()
				watched += 1
				say("watch match %s" % str(m.get("id")))
			else:
				tv.close_overlay()
			return


## The tournament panel's step: accept, ban the first, pick the first usable deck.
func _panel() -> void:
	var p: TournamentPanel = main.tournament_panel
	if p == null or not p.visible or p.answered or not p.phase() in ["accept", "ban", "pick"]:
		_panel_since = 0
		return
	if _panel_since == 0:
		_panel_since = now()
	if now() - _panel_since < 1500:  # a moment to look, as a player would
		return
	if main.get("watch_view") != null:
		main.close_watch()
	match p.phase():
		"accept":
			p.accept()
		"ban":
			p.ban(_first_ok(p.cur.get("theirs", [])))
		"pick":
			p.pick(_first_ok(p.cur.get("mine", [])))
	_panel_since = 0


static func _first_ok(list: Variant) -> int:
	var items: Array = list if list is Array else []
	for i in items.size():
		if items[i] is Dictionary and str(items[i].get("state", "ok")) == "ok":
			return i
	return 0


## The own game: random legal moves through the table; after the end, back to the tournament.
func _table() -> void:
	var v := main.screen as MatchView
	if v == null or v.watching or v.controller == null:
		return
	var m: Match = v.controller
	if m.game.game_over:
		if _over_since == 0:
			_over_since = now()
		elif now() - _over_since > 3000 and v.find_child("BackToLobby", true, false):
			_over_since = 0
			say("game over (%d games)" % games)
			v._leave()
		return
	_over_since = 0
	if v._busy or m.waiting() or not v._pending_acts.is_empty():
		return
	var me := m.viewer()
	if m.actor() != me:
		return
	var mine := m.legal().filter(func(a): return int(a.get("player", -1)) == me and a.type != "concede")
	if mine.is_empty():
		return
	var key := "%d/%d" % [m.game.turn, me]
	if key != _turn_key:
		_turn_key = key
		_turn_acts = 0
	_turn_acts += 1
	var pick: Dictionary = {}
	for a in mine:
		if a.type == "mulligan":
			pick = {"type": "mulligan", "player": me, "replace": []}
			break
		if a.type == "choose":
			pick = a
			break
	if pick.is_empty():
		var moves := mine.filter(func(a): return a.type != "end_turn")
		if moves.is_empty() or _turn_acts > 12 or _rng.randf() < 0.1:
			pick = mine.filter(func(a): return a.type == "end_turn").front() if mine.any(func(a): return a.type == "end_turn") else moves.front()
		else:
			pick = moves[_rng.randi() % moves.size()]
	if pick.type in ["mulligan", "choose"]:  # (the overlay's buttons send these the same way)
		m.submit(pick)
	else:
		v._act(pick)
	_wait_until = now() + 400


## A watched game: left when it ends, or after a while.
func _watching() -> void:
	var w: MatchView = main.get("watch_view")
	if w == null:
		return
	if (w.controller and w.controller.game.game_over) or now() - _watch_since > 120000:
		main.close_watch()
		say("left the watched game")
