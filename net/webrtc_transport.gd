class_name WebRtcTransport
extends Transport
## WebRTC data channel (browser build). Signaling is manual: the host makes an
## invite code, the guest answers with an answer code. All ICE candidates are
## gathered before a code is shown, so each side sends exactly one code. Without a
## server two messages are always needed (offer there, answer back).

signal code_ready(code: String)
signal error(text: String)

## STUN finds our outside address; TURN relays the traffic when no direct path works
## (symmetric NAT, blocked UDP). The browser uses TURN only when it has to; the data
## stays encrypted (DTLS). ExpressTURN free plan: a public test login, UDP and TCP 3478
## (its port 443 does not answer). A product needs short-lived logins from a backend.
const ICE := {"iceServers": [
	{"urls": ["stun:stun.l.google.com:19302"]},
	{"urls": ["turn:free.expressturn.com:3478", "turn:free.expressturn.com:3478?transport=tcp"],
		"username": "000000002107107828", "credential": "5mXEP7ZkQ9DzSgm/B5EfRGEWH/k="},
]}
const GATHER_QUIET := 1.0  # seconds without a new candidate = gathering done
const GATHER_MAX := 10.0  # the relay (TURN) candidates can take a few seconds
## The guest feeds the host's candidates again and again until the connection opens:
## a browser (Firefox) gives up its checks ~10 s after making the answer, and the host
## pastes that answer by hand much later.
const RETRY_EVERY := 5.0
const RETRY_FOR := 300.0

var pc: WebRTCPeerConnection
var channel: WebRTCDataChannel
var _sdp := {}
var _ice: Array = []
var _gather_quiet := -1.0
var _gather_total := 0.0
var _open := false
var _closed := false
var _remote_ice: Array = []  # guest: the host's candidates [mid, index, "candidate:..."]
var _retry_at := -1.0
var _retry_t := 0.0
var _round := 0


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


## The SDP without its a=candidate lines, and those candidates [mid, m-line index,
## "candidate:..."] (the guest adds them itself, see RETRY_EVERY).
static func split_candidates(sdp: String) -> Dictionary:
	var lines := []
	var ice := []
	var m := -1
	var mid := "0"
	for l in sdp.replace("\r\n", "\n").split("\n"):
		if l.begins_with("m="):
			m += 1
			mid = str(m)
		elif l.begins_with("a=mid:"):
			mid = l.substr(6).strip_edges()
		if l.begins_with("a=candidate:"):
			ice.append([mid, maxi(m, 0), l.substr(2).strip_edges()])
			continue
		if l.begins_with("a=end-of-candidates") or l.strip_edges() == "":
			continue
		lines.append(l)
	return {"sdp": "\r\n".join(lines) + "\r\n", "ice": ice}


## The same candidate with a new foundation, so the browser does not drop it as a
## candidate it already has.
static func refounded(candidate: String, round: int, i: int) -> String:
	var rest := candidate.substr(candidate.find(" "))
	return "candidate:r%dx%d%s" % [round, i, rest]


static func _relay_only() -> bool:
	if not OS.has_feature("web"):
		return false
	var q = JavaScriptBridge.eval("location.search", true)
	return q is String and (q as String).contains("relay=1")


func _setup_peer() -> bool:
	pc = WebRTCPeerConnection.new()
	var config := ICE.duplicate(true)
	if _relay_only():  # ?relay=1: only through TURN, to test the relay
		config["iceTransportPolicy"] = "relay"
	if pc.initialize(config) != OK:
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
	var parts := split_candidates(r.sdp)
	_remote_ice = parts.ice
	pc.set_remote_description("offer", parts.sdp)  # the answer comes via session_description_created
	_retry_at = 1.0  # the first candidates once the browser has the offer, then every RETRY_EVERY
	_retry_t = 0.0


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
	if _retry_at >= 0.0 and not _open:
		_retry_t += minf(delta, 0.5)
		if _retry_t >= _retry_at and _retry_t <= RETRY_FOR:
			_round += 1
			for i in _remote_ice.size():
				var c: Array = _remote_ice[i]
				pc.add_ice_candidate(c[0], c[1], refounded(c[2], _round, i))
			_retry_at = _retry_t + RETRY_EVERY
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
