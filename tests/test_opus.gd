extends TestCase
## Ogg Opus (game/opus.gd, rust/opus): rust/opus's fixtures (0.5 s tones, mono and stereo) decode to
## the right length and channels, also in the background; a broken file gives null; a pack's .opus
## sound and voice line play, and win over another format of the same name.

const FIXTURES := "res://rust/opus/tests/fixtures/"


func _fixture(name: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(FIXTURES + name)


func _is_tone(s: AudioStream, stereo: bool, what: String) -> void:
	check(s is AudioStreamWAV, what + ": a stream")
	if s is AudioStreamWAV:
		eq(s.stereo, stereo, what + ": stereo")
		eq(s.mix_rate, 48000, what + ": 48 kHz")
		check(absf(s.get_length() - 0.5) < 0.001, "%s: 0.5 s, not %f" % [what, s.get_length()])


func test_the_fixtures_decode() -> void:
	_is_tone(Opus.stream(_fixture("tone_mono.opus")), false, "mono")
	_is_tone(Opus.stream(_fixture("tone_stereo.opus")), true, "stereo")


func test_in_the_background() -> void:
	var d: Object = ClassDB.instantiate("OpusDecoder")
	d.start(_fixture("tone_stereo.opus"))
	var t0 := Time.get_ticks_msec()
	while not d.done() and Time.get_ticks_msec() - t0 < 5000:
		OS.delay_msec(2)
	_is_tone(d.stream(), true, "decoded in a thread")


func test_a_broken_file_is_null() -> void:
	allowed_errors = 2  # (the decoder says why)
	check(Opus.stream(PackedByteArray()) == null, "nothing")
	check(Opus.stream("not an ogg file".to_utf8_buffer()) == null, "not Ogg")
	var cut := _fixture("tone_stereo.opus").slice(0, 60)
	check(Opus.stream(cut) == null, "only the start of the header page")


func test_a_pack_plays_its_opus_sound_and_voice() -> void:
	var classic: Pack = Packs.all().filter(func(p): return p.id() == Packs.CLASSIC and p.builtin())[0]
	var tone := _fixture("tone_stereo.opus")
	var bytes := _repacked(FileAccess.get_file_as_bytes(classic.path), {
		"sounds/generated/attack.opus": tone, "voice/en/HERO_08_greetings.opus": _fixture("tone_mono.opus")})
	var p: Pack = Packs.install(bytes, "imported").get("pack")
	check(p != null, "the pack installs")
	if p == null:
		return
	Packs.set_active(p)
	var s := Sound.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	eq(Sound.path_for("attack"), "sounds/generated/attack.opus", "the .opus (first, also next to an older .wav)")
	Sound.play("attack")
	_is_tone(s.last_player().stream, true, "the sound")
	check(Sound.say("HERO_08", "greetings"), "the line is said")
	_is_tone(s._voice.stream, false, "the line")
	s.free()
	Packs.set_active(classic)
	Packs.remove(p)


## The pack's zip with files changed or added.
func _repacked(bytes: PackedByteArray, change: Dictionary) -> PackedByteArray:
	var src := "user://test_opus_src.zip"
	var out := "user://test_opus_out.zip"
	var f := FileAccess.open(src, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var r := ZIPReader.new()
	r.open(src)
	var w := ZIPPacker.new()
	w.open(out)
	for name in r.get_files():
		if not change.has(name):
			w.start_file(name)
			w.write_file(r.read_file(name))
			w.close_file()
	for name in change:
		w.start_file(name)
		w.write_file(change[name])
		w.close_file()
	w.close()
	r.close()
	var data := FileAccess.get_file_as_bytes(out)
	DirAccess.remove_absolute(src)
	DirAccess.remove_absolute(out)
	return data
