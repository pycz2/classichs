class_name ArenaSession
extends Node
## The online Arena: both players draft a deck (ArenaDraft), see each other's
## progress, then play games over the same connection until one has WINS wins.
## Each game is a normal NetSession over a ChannelTransport (number n).
## Messages: hello {mode: "arena"} → rules {deck, keep} (the host's choice) →
## status {hero, cards, ready, deciding} → game {g, m} … concede {} (the sender
## gives up the Arena) and bye {} (the sender left).

signal changed  # the opponent's progress, the score or the end of the Arena
signal game_started(session: NetSession, m: Match)
signal failed(reason: String)

const WINS := 3

var transport: Transport
var host := false
var player_name := ""
var remote_name := ""
var version: String = ProjectSettings.get_setting("application/config/version", "0")
var draft: ArenaDraft
## The Arena's rules, chosen by the host for both: "one" deck for the whole
## Arena or "each" game a new draft ("" = not chosen yet); may_keep lets a
## player keep the last deck instead of drafting again ("each" only).
var rules := ""
var may_keep := false
## After a game with rules "each" and may_keep: this side chooses a new deck or the same.
var deck_choice := false
var connected := false
var is_ready := false
## The opponent's progress (never which hero).
var remote := {"hero": false, "cards": 0, "ready": false, "deciding": false}
var score := [0, 0]  # [this side, the opponent]
var games := 0  # games started
var game: NetSession  # the game being played (null in the lobby)
var over := false  # the Arena has a winner
var winner := -1  # 0 = this side won the Arena, 1 = the opponent
var remote_left := false
var failure := ""  # why the connection broke ("" = it did not)
var _channel: ChannelTransport
var _pending := {}  # game number -> messages that came before that game started here
var _done := false
var _seed := -1


func setup(t: Transport, is_host: bool, p_name: String, seed := -1) -> void:
	transport = t
	host = is_host
	player_name = Profile.clean(p_name)
	_seed = seed
	draft = ArenaDraft.new(seed)
	t.opened.connect(say_hello)
	t.received.connect(_on_message)
	t.closed.connect(_on_closed)


func local_player() -> int:
	return 0 if host else 1


func say_hello() -> void:
	transport.send({"t": "hello", "mode": "arena", "protocol": NetSession.PROTOCOL, "version": version,
		"data": CardDb.data_hash(), "name": player_name})


## Tells the opponent how far this side is (after every pick).
func send_status() -> void:
	if not _done:
		transport.send({"t": "status", "hero": draft.hero != "", "cards": draft.cards.size(), "ready": is_ready,
			"deciding": deck_choice})


## The host chooses the rules once; the guest gets them.
func set_rules(deck: String, keep := false) -> void:
	if not host or rules != "" or not deck in ["one", "each"] or _done:
		return
	rules = deck
	may_keep = keep and deck == "each"
	transport.send({"t": "rules", "deck": rules, "keep": may_keep})
	changed.emit()


## After a game (rules "each" with keeping allowed): draft a new deck …
func new_deck() -> void:
	deck_choice = false
	draft = ArenaDraft.new(-1 if _seed < 0 else _seed + games * 1000)
	send_status()
	changed.emit()


## … or keep the one just played.
func keep_deck() -> void:
	deck_choice = false
	send_status()
	changed.emit()


## Ready for the next game (the deck must be complete); the game starts when both are.
func set_ready() -> void:
	if over or _done or not draft.done() or game != null or deck_choice:
		return
	is_ready = true
	send_status()
	_maybe_start()


## Gives up the Arena: the opponent wins it.
func concede() -> void:
	if over or _done:
		return
	transport.send({"t": "concede"})
	_finish(1)


func leave() -> void:
	if not _done:
		_done = true
		transport.send({"t": "bye"})
	_close_soon()


## Closes on the next frame so the last message (bye) gets out first.
func _close_soon() -> void:
	if is_inside_tree():
		transport.call_deferred("close", "left")
	else:
		transport.close("left")


## The game is over and the players are back in the lobby.
func end_game() -> void:
	for n: Node in [game, _channel]:
		if n == null:
			continue
		if n.is_inside_tree():
			n.queue_free()
		else:
			n.free()
	game = null
	_channel = null


## Counts a game's result (winner = the player number in the game; -1 = a draw).
func record(game_winner: int) -> void:
	if over:
		changed.emit()
		return
	if game_winner < 0:  # a draw counts for nobody, but the next game still gets its deck
		_next_deck()
		changed.emit()
		return
	var side := 0 if game_winner == local_player() else 1
	score[side] += 1
	if score[side] >= WINS:
		_finish(side)
		return
	_next_deck()
	changed.emit()


## With rules "each" a game is followed by a new draft (or the choice to keep the deck).
func _next_deck() -> void:
	if rules != "each":
		return
	if may_keep:
		deck_choice = true
		send_status()
	else:
		new_deck()


func _finish(side: int) -> void:
	over = true
	winner = side
	is_ready = false
	changed.emit()


## The Arena breaks: the opponent is told, the connection closes; nobody wins it.
func _fail(reason: String) -> void:
	if _done:
		return
	_done = true
	failure = reason
	transport.send({"t": "bye", "code": "error"})
	_close_soon()
	failed.emit(reason)


func _maybe_start() -> void:
	if not is_ready or not remote.ready or over or game != null:
		return
	games += 1
	is_ready = false
	remote.ready = false
	_channel = ChannelTransport.new()
	_channel.parent = transport
	_channel.game = games
	game = NetSession.new()
	game.arena = true
	if is_inside_tree():
		add_child(_channel)
		add_child(game)
	game.setup(_channel, host, player_name, draft.deck())
	var g := game
	game.started.connect(func(m: Match):
		m.finished.connect(func(w): record(w))
		if not over:  # e.g. the opponent conceded the Arena while this game was starting
			game_started.emit(g, m))
	game.failed.connect(func(reason):
		if not over:
			_fail(reason))
	game.say_hello()
	for msg in _pending.get(games, []):
		_channel.received.emit(msg)
	_pending.erase(games)
	changed.emit()


func _tr(s: String) -> String:
	return TranslationServer.translate(s)


func _on_message(msg: Variant) -> void:
	if _done:
		return
	if not msg is Dictionary or not msg.get("t") is String:
		_fail(_tr("The opponent sent a broken message"))
		return
	match msg.t:
		"hello":
			if connected:
				_fail(_tr("The opponent sent an unexpected message"))
			elif msg.get("mode") != "arena":
				transport.send({"t": "bye", "code": "mode"})
				_fail(_tr("The opponent chose a normal game, not the Arena"))
			elif msg.get("protocol") != float(NetSession.PROTOCOL) or msg.get("version") != version:
				_fail(_tr("Different game versions: yours %s, the opponent's %s") % [version, str(msg.get("version", "?")).left(20)])
			elif msg.get("data") != CardDb.data_hash():
				_fail(_tr("Your card data differs from the opponent's: update the game on both sides"))
			else:
				connected = true
				remote_name = Profile.clean(str(msg.get("name", "")))
				send_status()
				changed.emit()
		"rules":
			if host or rules != "" or not msg.get("deck") in ["one", "each"]:
				_fail(_tr("The opponent sent an unexpected message"))
			else:
				rules = msg.deck
				may_keep = msg.get("keep") == true and rules == "each"
				changed.emit()
		"status":
			var cards = msg.get("cards")
			remote = {"hero": msg.get("hero") == true, "cards": clampi(int(cards), 0, ArenaDraft.PICKS) if cards is float else 0,
				"ready": msg.get("ready") == true, "deciding": msg.get("deciding") == true}
			changed.emit()
			_maybe_start()
		"game":
			var n = msg.get("g")
			if not n is float or not msg.get("m") is Dictionary:
				_fail(_tr("The opponent sent a broken message"))
			elif int(n) == games and _channel:
				_channel.received.emit(msg.m)
			elif int(n) > games:
				if not _pending.has(int(n)):
					_pending[int(n)] = []
				_pending[int(n)].append(msg.m)
		"concede":
			if not over:
				_finish(0)
		"bye":
			_done = true
			if msg.get("code") in ["mode", "error"]:
				failure = _tr("The opponent chose a normal game, not the Arena") if msg.code == "mode" \
					else _tr("The Arena broke on the opponent's side")
				failed.emit(failure)
				return
			remote_left = true
			if not over:
				_finish(0)
			else:
				changed.emit()
		_:
			_fail(_tr("The opponent sent an unknown message"))


func _on_closed(_reason: String) -> void:
	if _channel:
		_channel.closed.emit("connection")
	if _done:
		return
	if over:
		_done = true
		return
	_fail(_tr("Connection lost"))
