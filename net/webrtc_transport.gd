class_name WebRtcTransport
extends Transport
## WebRTC data channel (browser build). Signaling is manual: the host makes an
## invite code, the guest answers with an answer code. All ICE candidates are
## gathered before a code is shown, so each side sends exactly one code.

signal code_ready(code: String)
signal error(text: String)

const ICE := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
const GATHER_QUIET := 1.0  # seconds without a new candidate = gathering done
const GATHER_MAX := 8.0

var pc: WebRTCPeerConnection
var channel: WebRTCDataChannel
var _sdp := {}
var _ice: Array = []
var _gather_quiet := -1.0
var _gather_total := 0.0
var _open := false
var _closed := false


static func available() -> bool:
	return OS.has_feature("web")


## The SDP with the gathered candidates written in as a=candidate lines. Browsers
## apply a remote description asynchronously and may drop candidates added right
## after it; candidates inside the SDP always arrive together with it.
static func with_candidates(sdp: String, ice: Array) -> String:
	var out := sdp.strip_edges() + "\r\n"
	for c in ice:
		if str(c[2]) != "":  # Firefox signals the end of gathering with an empty candidate
			out += "a=" + str(c[2]) + "\r\n"
	return out + "a=end-of-candidates\r\n"


func _setup_peer() -> bool:
	pc = WebRTCPeerConnection.new()
	if pc.initialize(ICE) != OK:
		error.emit(tr("Online play needs the browser version of the game"))
		return false
	channel = pc.create_data_channel("game", {"negotiated": true, "id": 1})
	pc.session_description_created.connect(func(type: String, sdp: String):
		pc.set_local_description(type, sdp)
		_sdp = {"type": type, "sdp": sdp}
		_gather_quiet = 0.0
		_gather_total = 0.0)
	pc.ice_candidate_created.connect(func(media: String, index: int, name: String):
		_ice.append([media, index, name])
		_gather_quiet = 0.0)
	return true


func host() -> void:
	if _setup_peer():
		pc.create_offer()


func join(invite: String) -> void:
	var r := SignalCode.unpack(invite, "offer")
	if r.error != "":
		error.emit(r.error)
		return
	if not _setup_peer():
		return
	pc.set_remote_description("offer", r.sdp)  # the answer comes via session_description_created


func finish(answer: String) -> void:
	var r := SignalCode.unpack(answer, "answer")
	if r.error != "":
		error.emit(r.error)
		return
	if pc == null:
		error.emit(tr("Create an invite first"))
		return
	pc.set_remote_description("answer", r.sdp)


func _process(delta: float) -> void:
	if pc == null or _closed:
		return
	pc.poll()
	if _gather_quiet >= 0.0:
		_gather_quiet += delta
		_gather_total += delta
		# Wait for the browser to finish gathering: the STUN (srflx) candidate can come
		# seconds after the local ones, and it is the one that works across networks.
		var complete: bool = pc.has_method("get_gathering_state") and pc.call("get_gathering_state") == 2
		var quiet_fallback: bool = not pc.has_method("get_gathering_state") and _gather_quiet >= GATHER_QUIET and not _ice.is_empty()
		if complete or quiet_fallback or _gather_total >= GATHER_MAX:
			_gather_quiet = -1.0
			if _ice.is_empty():
				error.emit(tr("Could not find a network address: check the internet connection"))
			else:
				code_ready.emit(SignalCode.pack(_sdp.type, with_candidates(_sdp.sdp, _ice), []))
	var ready := channel.get_ready_state()
	if ready == WebRTCDataChannel.STATE_OPEN and not _open:
		_open = true
		opened.emit()
	while channel.get_available_packet_count() > 0:
		var j := JSON.new()
		var text := channel.get_packet().get_string_from_utf8()
		received.emit(j.data if j.parse(text) == OK else null)
	var state := pc.get_connection_state()
	if state == WebRTCPeerConnection.STATE_FAILED and not _open:
		_closed = true
		error.emit(tr("Could not connect: the networks may block direct connections"))
	elif _open and (ready == WebRTCDataChannel.STATE_CLOSED or state in [WebRTCPeerConnection.STATE_FAILED, WebRTCPeerConnection.STATE_CLOSED]):
		_closed = true
		closed.emit("connection")


func send(msg: Dictionary) -> void:
	if _open and not _closed:
		channel.put_packet(JSON.stringify(msg).to_utf8_buffer())


func close(_reason := "") -> void:
	if pc and not _closed:
		_closed = true
		channel.close()
		pc.close()
