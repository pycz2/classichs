class_name Opus
extends RefCounted
## Ogg Opus files (.opus) as AudioStreamWAV (16-bit PCM, 48 kHz), decoded by rust/opus: through the
## GDExtension class OpusDecoder on desktop and Android, through web/rules.js (ClassicRules) in the
## browser. Godot itself plays no Opus. A 3-minute track takes a few hundred ms: music decodes in the
## background (`await Opus.stream_later(bytes)`), short sounds at once (`Opus.stream(bytes)`).


## null when the bytes are not an Ogg Opus file (the reason in the log) or no decoder is there.
static func stream(bytes: PackedByteArray) -> AudioStream:
	if bytes.is_empty():
		return null
	if ClassDB.class_exists("OpusDecoder"):
		return ClassDB.class_call_static("OpusDecoder", "decode", bytes)
	var api = _web()
	return _wav(api.decode_opus(Marshalls.raw_to_base64(bytes)), api) if api else null


## The same in a thread of its own (a Web Worker in the browser); the game goes on meanwhile.
static func stream_later(bytes: PackedByteArray) -> AudioStream:
	if bytes.is_empty() or DisplayServer.get_name() == "headless":  # (no screen to keep smooth: tests, tools)
		return stream(bytes)
	var tree := Engine.get_main_loop() as SceneTree
	if ClassDB.class_exists("OpusDecoder"):
		var d: Object = ClassDB.instantiate("OpusDecoder")
		d.start(bytes)
		while not d.done():
			await tree.process_frame
		return d.stream()
	var api = _web()
	if api == null:
		return null
	var id = api.opus_start(Marshalls.raw_to_base64(bytes))
	while not api.opus_done(id):
		await tree.process_frame
	return _wav(api.opus_take(id), api)


## A file of the game itself (res://), say the client's menu music.
static func load_file(path: String) -> AudioStream:
	return stream(FileAccess.get_file_as_bytes(path))


static func _web() -> Variant:
	if not OS.has_feature("web"):
		push_warning("opus: no decoder (rules/bin): build it with tools/build_rules.sh")
		return null
	return JavaScriptBridge.get_interface("ClassicRules")


static func _wav(r: Variant, api: Variant) -> AudioStream:
	if r == null:
		push_warning("opus: " + str(api.opus_error))
		return null
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = 48000
	s.stereo = int(r.channels) == 2
	s.data = JavaScriptBridge.js_buffer_to_packed_byte_array(r.pcm)
	return s
