class_name ServerLink
extends Node
## The connection to a game server (docs/superpowers/specs/2026-10-15-server-design.md):
## one WebSocket with JSON messages {"t": …}. It lives as long as the player stays
## on the server, across screens. A game's messages (state, act_error, emote,
## intent, game_over) go to its ServerSession; the server keeps the game.

signal opened
signal message(msg: Dictionary)
signal closed(reason: String)

## The saved session (user://, per player): {token, server, deck: {name, hero}, mode, tab}.
## Tests point it at their own file.
const SESSION_DEFAULT_PATH := "user://server_session.json"
static var session_path := SESSION_DEFAULT_PATH

var url := ""
var socket := WebSocketPeer.new()
var token := ""  # the session after login (also saved: the player stays logged in)
var me := {}  # the player's profile from the server
## A saved session is being resumed (the answer is an auth or an error).
var resuming := false
## Whether the server answers `chats` and `read` (asked once after login; an older server does not).
var has_chats := false
## The deck sent with the last queue, invite or acceptance: the server's game uses it.
var game_deck: Deck
var _probing := false
var _was_open := false
var _closed := true  # nothing to close before open()
var _games := {}  # game id -> ServerSession


## The saved session file (an empty dictionary when there is none).
static func saved() -> Dictionary:
	var j := JSON.new()
	if not FileAccess.file_exists(session_path) or j.parse(FileAccess.get_file_as_string(session_path)) != OK or not j.data is Dictionary:
		return {}
	return j.data


## Merges values into the saved session (null removes one).
static func remember(values: Dictionary) -> void:
	var d := saved()
	for k in values:
		if values[k] == null:
			d.erase(k)
		else:
			d[k] = values[k]
	var f := FileAccess.open(session_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


## Logged in on an open connection.
func logged_in() -> bool:
	return token != "" and is_open()


## Opens the connection; with a saved session for this address it logs in again
## by itself (resume). A rejected session is forgotten.
func open_and_resume(address: String) -> Error:
	var err := open(address)
	var s := saved()
	if err == OK and str(s.get("token", "")) != "" and s.get("server") == address:
		resuming = true
		opened.connect(func():
			if resuming:
				send({"t": "resume", "token": s.token}), CONNECT_ONE_SHOT)
	return err


func log_out() -> void:
	send({"t": "logout"})
	token = ""
	me = {}
	remember({"token": null})


func open(address: String) -> Error:
	url = address
	_closed = false
	_was_open = false
	resuming = false
	token = ""
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1 << 20
	socket.outbound_buffer_size = 1 << 20
	return socket.connect_to_url(address)


## Whether the connection was ever open (else the server could not be reached).
func was_open() -> bool:
	return _was_open


func is_open() -> bool:
	return socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func send(msg: Dictionary) -> void:
	if is_open():
		socket.send_text(JSON.stringify(msg))


func close() -> void:
	resuming = false
	token = ""
	if not _closed:
		_closed = true
		socket.close()


## A session for a game the server started (`match`); its messages go to it.
func session(msg: Dictionary, d: Deck) -> ServerSession:
	var s := ServerSession.new()
	s.setup(self, msg, str(me.get("user", "")), d)
	_games[s.game] = s  # a freed session is dropped on its next message
	return s


func _process(_d: float) -> void:
	socket.poll()
	var st := socket.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _was_open:
		_was_open = true
		opened.emit()
	while socket.get_available_packet_count() > 0:
		var text := socket.get_packet().get_string_from_utf8()
		var msg = JSON.parse_string(text)
		if msg is Dictionary and msg.get("t") is String:
			dispatch(msg)
	if st == WebSocketPeer.STATE_CLOSED and not _closed:
		_closed = true
		resuming = false
		token = ""
		var why := socket.get_close_reason()
		for s in _games.values():
			if is_instance_valid(s):
				s.on_closed()
		closed.emit(why if why != "" else TranslationServer.translate("Connection lost"))


## A message from the server: a game's message goes to its channel, the rest to
## `message`. The session is kept here: saved on login, forgotten when refused.
func dispatch(msg: Dictionary) -> void:
	match msg.t:
		"auth":
			resuming = false
			if msg.get("ok", false):
				token = str(msg.get("token", ""))
				me = msg.get("me", {}) if msg.get("me") is Dictionary else {}
				remember({"token": token, "server": url})
				_probing = true
				send({"t": "chats"})
		"error":
			if resuming:
				resuming = false
				msg["resume"] = true  # the answer to the saved session: no one needs to be told
				if msg.get("code") != "rate_limited":
					remember({"token": null})
			elif _probing and msg.get("code") == "bad_request":  # an older server: no chats, no read
				_probing = false
				has_chats = false
				return
		"chats":
			_probing = false
			has_chats = true
		"logged_out":
			token = ""
	if msg.t in ["state", "act_error", "emote", "intent", "game_over"]:
		var id := str(msg.get("game", ""))
		var s = _games.get(id)
		if s != null and not is_instance_valid(s):
			_games.erase(id)
		elif s != null:
			s.on_message(msg)
		if msg.t != "game_over":
			return
	message.emit(msg)
