class_name ChannelTransport
extends Transport
## One game of an Arena series over the Arena's connection: its messages travel
## inside {"t": "game", "g": n, "m": …}; ArenaSession delivers the replies.
## Closing it ends only this game, not the connection.

var parent: Transport
var game := 0
var _closed := false


func send(msg: Dictionary) -> void:
	if not _closed:
		parent.send({"t": "game", "g": game, "m": msg})


func close(_reason := "") -> void:
	_closed = true
