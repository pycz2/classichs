class_name ServerLink
extends Node
## The connection to a game server (docs/superpowers/specs/2026-10-15-server-design.md):
## one WebSocket with JSON messages {"t": …}. It lives as long as the player stays
## on the server, across screens; a game runs over a ServerChannel on top of it.

signal opened
signal message(msg: Dictionary)
signal closed(reason: String)

var url := ""
var socket := WebSocketPeer.new()
var token := ""  # the session after login (kept in memory only)
var me := {}  # the player's profile from the server
var _was_open := false
var _closed := false
var _channels := {}  # game id -> ServerChannel


func open(address: String) -> Error:
	url = address
	_closed = false
	_was_open = false
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
	if not _closed:
		_closed = true
		socket.close()


## A channel for the game with this id (the NetSession of that game talks through it).
func channel(game_id: String) -> ServerChannel:
	var c := ServerChannel.new()
	c.link = self
	c.game = game_id
	_channels[game_id] = c  # a freed channel is dropped on its next message (MatchView reparents it)
	return c


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
		var why := socket.get_close_reason()
		for c in _channels.values():
			if is_instance_valid(c):
				c.closed.emit("connection")
		closed.emit(why if why != "" else TranslationServer.translate("Connection lost"))


## A message from the server: a game's message goes to its channel, the rest to `message`.
func dispatch(msg: Dictionary) -> void:
	if msg.t != "game":
		message.emit(msg)
		return
	var id := str(msg.get("game", ""))
	var c = _channels.get(id)
	if c != null and not is_instance_valid(c):
		_channels.erase(id)
	elif c != null and msg.get("m") is Dictionary:
		c.received.emit(msg.m)


## One game over the server: NetSession messages go inside {"t": "game", "game": id, "m": …}.
class ServerChannel:
	extends Transport
	var link: ServerLink
	var game := ""

	func send(msg: Dictionary) -> void:
		if link:
			link.send({"t": "game", "game": game, "m": msg})

	func close(_reason := "") -> void:
		pass  # the link stays: only this game ends
