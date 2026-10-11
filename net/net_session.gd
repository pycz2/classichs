class_name NetSession
extends Node
## The online protocol over a Transport: hello → start → actions/emotes → bye.
## The host is player 0 and chooses the seed; both sides then run the same Game
## (lockstep) and check each other's state hash after every action.

signal started(m: Match)
signal failed(reason: String)
signal emote_received(player: int, id: String)

const PROTOCOL := 1
const EMOTES := ["greetings", "well_played", "thanks", "wow", "oops", "threaten"]

var transport: Transport
var host := false
var player_name := ""
var deck: Deck
var version: String = ProjectSettings.get_setting("application/config/version", "0")
var remote_name := ""
var match_: Match
var _remote: Dictionary = {}
var _sent := 0
var _received := 0
var _done := false


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


func leave() -> void:
	if not _done:
		_done = true
		transport.send({"t": "bye", "reason": "left"})
		transport.close("left")


func _fail(reason: String, tell_peer := true) -> void:
	if _done:
		return
	_done = true
	if tell_peer:
		transport.send({"t": "bye", "reason": reason})
		transport.close(reason)
	failed.emit(reason)


func _tr(s: String) -> String:
	return TranslationServer.translate(s)


func _on_message(msg: Variant) -> void:
	if _done:
		return
	if not msg is Dictionary or not msg.get("t") is String:
		_fail(_tr("The opponent sent a broken message"))
		return
	match msg.t:
		"hello": _on_hello(msg)
		"start": _on_start(msg)
		"action": _on_action(msg)
		"emote":
			if match_ and EMOTES.has(msg.get("id")):
				emote_received.emit(match_.remote, msg.id)
		"bye":
			_fail(_tr("The opponent left: %s") % str(msg.get("reason", "")), false)
		_:
			_fail(_tr("The opponent sent an unknown message"))


func _on_hello(msg: Dictionary) -> void:
	if msg.get("protocol") != float(PROTOCOL) or msg.get("version") != version or msg.get("data") != CardDb.data_hash():
		_fail(_tr("Different game versions: yours %s, the opponent's %s") % [version, str(msg.get("version", "?"))])
		return
	var d := Deck.from_dict({"name": "", "hero": msg.get("hero"), "cards": msg.get("cards")})
	if d == null or d.validate() != "":
		_fail(_tr("The opponent's deck is not valid"))
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
		_fail(_tr("The opponent sent an unexpected message"))
		return
	var decks = msg.get("decks")
	if not decks is Array or decks.size() != 2 or not decks[1] is Array or decks[1].size() != 2 \
			or decks[1][0] != deck.hero or decks[1][1] != Array(deck.cards) \
			or decks[0][0] != _remote.hero or decks[0][1] != _remote.cards or not msg.get("seed") is float:
		_fail(_tr("The opponent started a different game"))
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
		_fail(_tr("The opponent sent a move before the game started"))
		return
	if msg.get("n") != float(_received):
		_fail(_tr("Out of sync: a move was lost"))
		return
	_received += 1
	var a = msg.get("action")
	var simultaneous: bool = a is Dictionary and a.get("type") in ["mulligan", "concede"]
	var why := match_.submit_remote(a, "" if simultaneous else str(msg.get("hash", "")))
	if why != "":
		_fail(_tr("Out of sync: %s") % why)


func _on_closed(_reason: String) -> void:
	if match_ and match_.game.game_over:
		_done = true
		return
	_fail(_tr("Connection lost"), false)
