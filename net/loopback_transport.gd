class_name LoopbackTransport
extends Transport
## Two transports connected in memory (tests). Messages go through JSON like a
## real network and wait in an inbox until pump() delivers them.

var peer: LoopbackTransport
var inbox: Array = []
var _closed := false


static func pair() -> Array:
	var a := LoopbackTransport.new()
	var b := LoopbackTransport.new()
	a.peer = b
	b.peer = a
	return [a, b]


func send(msg: Dictionary) -> void:
	if not _closed and peer and not peer._closed:
		peer.inbox.append(JSON.stringify(msg))


func close(reason := "") -> void:
	if _closed:
		return
	_closed = true
	if peer and not peer._closed:
		peer.inbox.append({"__closed": reason})


## Delivers queued messages on both sides until nothing is left. Returns the count.
static func pump(transports: Array) -> int:
	var n := 0
	var busy := true
	while busy:
		busy = false
		for t: LoopbackTransport in transports:
			while not t.inbox.is_empty():
				var m = t.inbox.pop_front()
				busy = true
				n += 1
				if m is Dictionary:
					t._closed = true
					t.closed.emit(m.__closed)
				else:
					t.received.emit(JSON.parse_string(m))
	return n
