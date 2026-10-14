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
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1 << 20
	socket.outbound_buffer_size = 1 << 20
	return socket.connect_to_url(address)


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
	_channels[game_id] = c
	c.tree_exited.connect(func(): _channels.erase(game_id))
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
		if not msg is Dictionary or not msg.get("t") is String:
			continue
		if msg.t == "game":
			var c: ServerChannel = _channels.get(str(msg.get("game", "")))
			if c and msg.get("m") is Dictionary:
				c.received.emit(msg.m)
			continue
		message.emit(msg)
	if st == WebSocketPeer.STATE_CLOSED and not _closed:
		_closed = true
		var why := socket.get_close_reason()
		for c in _channels.values():
			c.closed.emit("connection")
		closed.emit(why if why != "" else TranslationServer.translate("Connection lost"))


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
