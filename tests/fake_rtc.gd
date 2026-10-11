class_name FakeRtc
extends LoopbackTransport
## Test double for WebRtcTransport: real invite/answer codes, loopback delivery.

signal code_ready(code: String)
signal error(text: String)

var _open := false
## Simulates a connection that never opens (bad answer, blocked network).
var never_open := false


## Like a real data channel: nothing is sent before the connection opens.
func send(msg: Dictionary) -> void:
	if _open:
		super(msg)


func close(reason := "") -> void:
	if _open:
		super(reason)
	else:
		_closed = true  # never connected: the other side notices nothing


func host() -> void:
	code_ready.emit(SignalCode.pack("offer", "fake-offer", []))


func join(invite: String) -> void:
	var r := SignalCode.unpack(invite, "offer")
	if r.error != "":
		error.emit(r.error)
		return
	code_ready.emit(SignalCode.pack("answer", "fake-answer", []))


func finish(answer: String) -> void:
	var r := SignalCode.unpack(answer, "answer")
	if r.error != "":
		error.emit(r.error)
		return
	if never_open:
		return
	_open = true
	peer._open = true
	opened.emit()
	peer.opened.emit()


static func fake_pair() -> Array:
	var a := FakeRtc.new()
	var b := FakeRtc.new()
	a.peer = b
	b.peer = a
	return [a, b]
