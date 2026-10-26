extends TestCase
## A real WebRTC connection inside this process: two WebRtcTransports exchange the invite and the answer
## codes and open the data channel (the webrtc-native plugin on Windows, macOS, Linux and Android).


func _pump(a: WebRtcTransport, b: WebRtcTransport, done: Callable, secs := 20.0) -> bool:
	var t := 0.0
	while t < secs and not done.call():
		a._process(0.05)
		b._process(0.05)
		OS.delay_msec(50)
		t += 0.05
	return done.call()


func test_two_players_connect_with_codes() -> void:
	if OS.has_feature("web"):
		return
	check(WebRtcTransport.available(), "the webrtc-native plugin is loaded (tools/fetch_webrtc.sh)")
	if not WebRtcTransport.available():
		return
	var host := WebRtcTransport.new()
	var guest := WebRtcTransport.new()
	var got := []
	var opened := [0]
	host.code_ready.connect(func(c: String): guest.join(c))
	guest.code_ready.connect(func(c: String): host.finish(c))
	host.opened.connect(func(): opened[0] += 1; host.send({"t": "hello", "from": "host"}))
	guest.opened.connect(func(): opened[0] += 1; guest.send({"t": "hello", "from": "guest"}))
	host.received.connect(func(m): got.append(m))
	guest.received.connect(func(m): got.append(m))
	host.host()
	check(_pump(host, guest, func(): return got.size() >= 2), "both sides get a message")
	eq(opened[0], 2, "the channel opens on both sides")
	eq(got.map(func(m): return m.get("from")).filter(func(x): return x != null).size(), 2, "the messages arrive whole")
	host.close()
	guest.close()
	host.free()
	guest.free()


func test_native_ice_has_no_tcp_turn() -> void:
	if OS.has_feature("web"):
		return
	var urls := []
	for s in WebRtcTransport.ice_config().iceServers:
		urls.append_array(s.urls)
	check(urls.any(func(u: String): return u.begins_with("turn:")), "a TURN server is still set")
	check(not urls.any(func(u: String): return u.contains("transport=tcp")), "libjuice has no TURN over TCP")
