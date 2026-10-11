extends TestCase


func test_profile_save_load_and_limit() -> void:
	Profile.path = "user://test_profile.json"
	DirAccess.remove_absolute(Profile.path)
	eq(Profile.load_name(), Profile.DEFAULT_NAME, "default")
	Profile.save_name("Джайна ✨ " + "x".repeat(40))
	eq(Profile.load_name().length(), Profile.NAME_MAX, "cut to the limit")
	check(Profile.load_name().begins_with("Джайна ✨"), "unicode kept")
	Profile.save_name("   ")
	eq(Profile.load_name(), Profile.DEFAULT_NAME, "blank falls back")
	DirAccess.remove_absolute(Profile.path)
	Profile.path = Profile.DEFAULT_PATH


func test_signal_code_roundtrip() -> void:
	var sdp := "v=0\r\no=- 46117 2 IN IP4 127.0.0.1\r\ns=-\r\n".repeat(10)
	var ice := [["0", 0, "candidate:1 1 udp 2122260223 192.168.1.5 50000 typ host"]]
	var code := SignalCode.pack("offer", sdp, ice)
	var r := SignalCode.unpack(code)
	eq(r.error, "", "unpacked")
	eq([r.type, r.sdp, r.ice], ["offer", sdp, ice], "same data")
	check(code.length() < sdp.length(), "compressed")


func test_signal_code_garbage() -> void:
	for bad in ["", "hello", "AAAA", Marshalls.utf8_to_base64("{\"v\": 1}"), SignalCode.pack("offer", "x", []).substr(0, 10)]:
		var r := SignalCode.unpack(bad)
		check(r.error != "", "rejected: " + bad)


func test_signal_code_wrong_kind() -> void:
	var code := SignalCode.pack("answer", "x", [])
	eq(SignalCode.unpack(code, "offer").error != "", true, "an answer is not an invite")


func test_loopback_pair_delivers_json() -> void:
	var pair := LoopbackTransport.pair()
	var got := []
	pair[1].received.connect(func(m): got.append(m))
	pair[0].send({"t": "x", "n": 5})
	eq(got, [], "not delivered until pumped")
	LoopbackTransport.pump(pair)
	eq(got.size(), 1, "delivered")
	eq(typeof(got[0].n), TYPE_FLOAT, "numbers arrive as float, like JSON over a network")
	pair[0].close("bye")
	var closed := []
	pair[1].closed.connect(func(r): closed.append(r))
	LoopbackTransport.pump(pair)
	eq(closed, ["bye"], "peer sees the close")
	for t in pair:
		t.free()


func test_candidates_are_embedded_in_sdp() -> void:
	var sdp := "v=0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\nc=IN IP4 0.0.0.0\r\n"
	var full := WebRtcTransport.with_candidates(sdp, [["0", 0, "candidate:1 1 udp 2113937151 192.168.1.3 52789 typ host"]])
	check(full.contains("\r\na=candidate:1 1 udp 2113937151 192.168.1.3 52789 typ host\r\n"), full)
	check(full.ends_with("a=end-of-candidates\r\n"), "end marker")
