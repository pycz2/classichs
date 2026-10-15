class_name FakeLink
extends ServerLink
## A ServerLink without a socket: "connected" at once, what it sends is kept in
## `sent`, and tests deliver the server's messages with dispatch().

var sent: Array = []
var up := true


func open(address: String) -> Error:
	url = address
	resuming = false
	token = ""
	return OK


func is_open() -> bool:
	return up


func send(msg: Dictionary) -> void:
	sent.append(msg)


## The messages of one type sent so far.
func of(t: String) -> Array:
	return sent.filter(func(m): return m.get("t") == t)


func close() -> void:
	super()
	up = false
