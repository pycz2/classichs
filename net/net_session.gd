class_name NetSession
extends Node
## The online protocol over a Transport: hello → start → actions/emotes → bye.
## The host is player 0 and chooses the seed; both sides then run the same Game
## (lockstep) and check each other's state hash after every action.

signal started(m: Match)
signal failed(reason: String)
signal emote_received(player: int, id: String)
## The opponent hovers, aims or looks at something (not part of the game state).
signal intent_received(intent: Dictionary)

const PROTOCOL := 1
const EMOTES := ["greetings", "well_played", "thanks", "wow", "oops", "threaten"]

var transport: Transport
var host := false
var player_name := ""
var deck: Deck
## A game of the Arena: the opponent's deck may have any number of copies.
var arena := false
var version: String = ProjectSettings.get_setting("application/config/version", "0")
var remote_name := ""
var match_: Match
var _remote: Dictionary = {}
var _sent := 0
var _received := 0
var _done := false
## Why the session ended: "left", "connection", "version", "desync" or "protocol".
var failure_kind := ""

const BYE_TEXT := {"left": "The opponent left the game", "version": "The opponent has a different version of the game",
	"desync": "Out of sync with the opponent", "protocol": "The opponent's game sent something unexpected",
	"mode": "The opponent chose the Arena, not a normal game"}


func setup(t: Transport, is_host: bool, p_name: String, d: Deck) -> void:
	transport = t
	host = is_host
	player_name = Profile.clean(p_name)
	deck = d
	t.opened.connect(say_hello)
	t.received.connect(_on_message)
	t.closed.connect(_on_closed)


func local_player() -> int:
	return 0 if host else 1


func say_hello() -> void:
	transport.send({"t": "hello", "protocol": PROTOCOL, "version": version, "data": CardDb.data_hash(),
		"name": player_name, "hero": deck.hero, "cards": deck.cards})


func send_emote(id: String) -> void:
	if EMOTES.has(id):
		transport.send({"t": "emote", "id": id})


## What the local player points at: {"k": "hover", "i"}, {"k": "aim", "from", "to", "x", "y"},
## {"k": "look", "id"} or {"k": "none"}. Outside the lockstep: never changes the game.
func send_intent(intent: Dictionary) -> void:
	if not _done:
		transport.send({"t": "intent", "i": intent})


## A clean copy of an intent, or {} when it is malformed (then it is dropped).
static func clean_intent(i: Variant) -> Dictionary:
	if not i is Dictionary:
		return {}
	var num := func(v) -> bool: return v is int or v is float
	match i.get("k"):
		"none":
			return {"k": "none"}
		"hover":
			if num.call(i.get("i")) and int(i.i) >= 0 and int(i.i) < 10:
				return {"k": "hover", "i": int(i.i)}
		"look":
			if num.call(i.get("id")):
				return {"k": "look", "id": int(i.id)}
		"aim":
			if num.call(i.get("from")) and num.call(i.get("to")):
				return {"k": "aim", "from": int(i.from), "to": int(i.to),
					"x": clampf(float(i.get("x", 640)), 0, 1280) if num.call(i.get("x", 0)) else 640.0,
					"y": clampf(float(i.get("y", 360)), 0, 720) if num.call(i.get("y", 0)) else 360.0}
	return {}


func leave() -> void:
	if not _done:
		_done = true
		failure_kind = "left"
		transport.send({"t": "bye", "code": "left"})
		_close_soon()


## Closes on the next frame so the last message (bye) gets out first.
func _close_soon() -> void:
	if is_inside_tree():
		transport.call_deferred("close", failure_kind)
	else:
		transport.close(failure_kind)


func _fail(reason: String, kind: String, tell_peer := true) -> void:
	if _done:
		return
	_done = true
	failure_kind = kind
	if tell_peer:
		transport.send({"t": "bye", "code": kind})
	_close_soon()
	failed.emit(reason)


func _tr(s: String) -> String:
	return TranslationServer.translate(s)


func _on_message(msg: Variant) -> void:
	if _done:
		return
	if not msg is Dictionary or not msg.get("t") is String:
		_fail(_tr("The opponent sent a broken message"), "protocol")
		return
	match msg.t:
		"hello": _on_hello(msg)
		"start": _on_start(msg)
		"action": _on_action(msg)
		"emote":
			if match_ and EMOTES.has(msg.get("id")):
				emote_received.emit(match_.remote, msg.id)
		"intent":
			var i := clean_intent(msg.get("i"))
			if match_ and not i.is_empty():
				intent_received.emit(i)
		"bye":
			var code := str(msg.get("code", "left"))
			_fail(_tr(BYE_TEXT.get(code, BYE_TEXT.left)), "left" if code == "left" else code, false)
		_:
			_fail(_tr("The opponent sent an unknown message"), "protocol")


func _on_hello(msg: Dictionary) -> void:
	if not _remote.is_empty():
		_fail(_tr("The opponent sent an unexpected message"), "protocol")
		return
	if msg.get("mode") == "arena":
		_fail(_tr("The opponent chose the Arena, not a normal game"), "mode")
		return
	if msg.get("protocol") != float(PROTOCOL) or msg.get("version") != version:
		_fail(_tr("Different game versions: yours %s, the opponent's %s") % [version, str(msg.get("version", "?")).left(20)], "version")
		return
	if msg.get("data") != CardDb.data_hash():
		_fail(_tr("Your card data differs from the opponent's: update the game on both sides"), "version")
		return
	var d := Deck.from_dict({"name": "", "hero": msg.get("hero"), "cards": msg.get("cards"), "arena": arena})
	if d == null or d.validate() != "":
		_fail(_tr("The opponent's deck is not valid"), "protocol")
		return
	_remote = msg
	remote_name = Profile.clean(str(msg.get("name", "")))
	if host:
		var seed := randi()
		var g := Game.new({"hero": deck.hero, "deck": deck.cards.duplicate()}, {"hero": d.hero, "deck": d.cards.duplicate()}, seed)
		transport.send({"t": "start", "seed": seed, "decks": [[deck.hero, deck.cards], [d.hero, d.cards]]})
		_begin(g)


func _on_start(msg: Dictionary) -> void:
	if host or match_ != null or _remote.is_empty():
		_fail(_tr("The opponent sent an unexpected message"), "protocol")
		return
	var decks = msg.get("decks")
	if not decks is Array or decks.size() != 2 or not decks[0] is Array or decks[0].size() != 2 \
			or not decks[1] is Array or decks[1].size() != 2 \
			or decks[1][0] != deck.hero or decks[1][1] != Array(deck.cards) \
			or decks[0][0] != _remote.hero or decks[0][1] != _remote.cards or not msg.get("seed") is float:
		_fail(_tr("The opponent started a different game"), "protocol")
		return
	var g := Game.new({"hero": _remote.hero, "deck": _remote.cards.duplicate()}, {"hero": deck.hero, "deck": deck.cards.duplicate()}, int(msg.seed))
	_begin(g)


func _begin(g: Game) -> void:
	match_ = Match.new()
	match_.setup(g, [false, false])
	match_.remote = 1 - local_player()
	match_.local_action.connect(_on_local_action)
	started.emit(match_)


func _on_local_action(action: Dictionary, state_hash: String) -> void:
	var simultaneous: bool = action.type in ["mulligan", "concede"]
	transport.send({"t": "action", "n": _sent, "action": action, "hash": "" if simultaneous else state_hash})
	_sent += 1


func _on_action(msg: Dictionary) -> void:
	if match_ == null:
		_fail(_tr("The opponent sent a move before the game started"), "protocol")
		return
	if msg.get("n") != float(_received):
		_fail(_tr("Out of sync: a move was lost"), "desync")
		return
	_received += 1
	var a = msg.get("action")
	var simultaneous: bool = a is Dictionary and a.get("type") in ["mulligan", "concede"]
	var expected := "" if simultaneous else str(msg.get("hash", ""))
	if not simultaneous and expected == "":
		_fail(_tr("Out of sync: a move came without a state check"), "desync")
		return
	var why := match_.submit_remote(a, expected)
	if why != "":
		_fail(_tr("Out of sync: %s") % why, "desync")


func _on_closed(_reason: String) -> void:
	if match_ and match_.game.game_over:
		_done = true
		return
	_fail(_tr("Connection lost"), "connection", false)
