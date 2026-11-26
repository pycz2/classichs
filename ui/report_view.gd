class_name ReportView
extends Control
## "Report a problem" (docs/superpowers/specs/2026-11-26-roles-subservers-design.md §3): what happened in
## words, the screenshot taken before the window opened (removable) and a voice message. It goes to the
## server the player is logged in to (POST /reports), else waits in user:// till the next login
## (ServerLink.queue_report).

const MAX_TEXT := 4000
const MAX_VOICE := 60.0  # seconds
## The voice goes as a WAV, 16-bit PCM, mono, 16 kHz (the server makes it Ogg Opus).
const VOICE_RATE := 16000
const BUS := "Record"  # the microphone's bus: recorded, not heard

var screen := PackedByteArray()  # the screenshot (PNG); empty: removed
var game := ""  # the match it is sent from
var link: ServerLink  # the connection it goes through (null or logged out: it waits)
var voice: AudioStreamWAV  # the recording as recorded (any rate, mono or stereo)
var _recording := -1.0  # seconds recorded so far; -1: not recording
var _mic: AudioStreamPlayer
var _player: AudioStreamPlayer
var _text: TextEdit
var _pic: TextureRect
var _status: Label
var _voice_label: Label
var _send: Button


func _init(png := PackedByteArray(), game_id := "", l: ServerLink = null) -> void:
	screen = png
	game = game_id
	link = l


## Opens the window over parent with a screenshot of what the player sees (taken after the frame that
## hid the menu which opened it; headless: at once). l: the match's connection (else a logged-in one).
static func open(parent: Node, game_id := "", l: ServerLink = null) -> void:
	if l == null:
		for x in parent.get_tree().get_nodes_in_group(ServerLink.GROUP):
			if x is ServerLink and x.logged_in():
				l = x
				break
	var show := func(): parent.add_child(ReportView.new(screenshot(parent.get_viewport()), game_id, l))
	if DisplayServer.get_name() == "headless":
		show.call()
	else:
		RenderingServer.frame_post_draw.connect(show, CONNECT_ONE_SHOT)


## The screen as a PNG (at most 1920 wide: a picture over 4 MB is refused); empty when there is none.
static func screenshot(vp: Viewport) -> PackedByteArray:
	if vp == null or DisplayServer.get_name() == "headless":  # (no picture there)
		return PackedByteArray()
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return PackedByteArray()
	if img.get_width() > 1920:
		img.resize(1920, img.get_height() * 1920 / img.get_width())
	return img.save_png_to_buffer()


## What the server keeps with a report: the client, the window, the language, the game played, the match.
static func context(game_id := "") -> Dictionary:
	var platform := OS.get_name()
	for f in ["web_android", "web_ios", "web_macos", "web_windows", "web_linuxbsd"]:  # the browser's system
		if OS.has_feature(f):
			platform += " " + f
	var w := DisplayServer.window_get_size()
	var p := Packs.active()
	return {"version": str(ProjectSettings.get_setting("application/config/version")), "platform": platform,
		"screen": "%dx%d" % [w.x, w.y], "language": TranslationServer.get_locale(),
		"pack": {"id": p.id(), "version": p.version(), "rules_hash": p.rules_hash()} if p else {}, "game": game_id}


## A recording as the server takes it: a WAV, 16-bit PCM, mono, 16 kHz, at most 60 s (the channels
## mixed, the rate changed by linear interpolation). The recording is 16-bit (AudioEffectRecord's).
static func wav16k(s: AudioStreamWAV) -> PackedByteArray:
	var ch := 2 if s.stereo else 1
	var frames := s.data.size() / (2 * ch)
	var step := float(s.mix_rate) / VOICE_RATE
	var n := mini(int(frames / step), int(MAX_VOICE) * VOICE_RATE)
	var out := PackedByteArray()
	out.resize(44 + n * 2)
	out.encode_u32(0, 0x46464952)  # "RIFF"
	out.encode_u32(4, 36 + n * 2)
	out.encode_u32(8, 0x45564157)  # "WAVE"
	out.encode_u32(12, 0x20746d66)  # "fmt "
	out.encode_u32(16, 16)
	out.encode_u16(20, 1)  # PCM
	out.encode_u16(22, 1)  # mono
	out.encode_u32(24, VOICE_RATE)
	out.encode_u32(28, VOICE_RATE * 2)
	out.encode_u16(32, 2)
	out.encode_u16(34, 16)
	out.encode_u32(36, 0x61746164)  # "data"
	out.encode_u32(40, n * 2)
	for i in n:
		var at := i * step
		var a := int(at)
		var b := mini(a + 1, frames - 1)
		var k := at - a
		var v := 0.0
		for c in ch:
			v += lerpf(s.data.decode_s16((a * ch + c) * 2), s.data.decode_s16((b * ch + c) * 2), k)
		out.encode_s16(44 + i * 2, clampi(roundi(v / ch), -32768, 32767))
	return out


## The report as POST /reports takes it.
func report() -> Dictionary:
	return {"text": _text.text.strip_edges(), "written_at": int(Time.get_unix_time_from_system()), "context": context(game),
		"screen": Marshalls.raw_to_base64(screen) if not screen.is_empty() else "", "voice": Marshalls.raw_to_base64(wav16k(voice)) if voice else ""}


func _ready() -> void:
	name = "ReportView"
	z_index = 200  # (over the match's menus and cards)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	var style := Palette.box(Palette.TABLE, 12)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 200
	panel.offset_right = -200
	panel.offset_top = 50
	panel.offset_bottom = -50
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(Palette.label(tr("Report a problem"), 26, Palette.ATTACK))
	_text = TextEdit.new()
	_text.name = "Text"
	_text.placeholder_text = tr("What happened? What did you expect?")
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.text_changed.connect(_on_text)
	box.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	var shot := VBoxContainer.new()
	shot.name = "ScreenshotBox"
	row.add_child(shot)
	_pic = TextureRect.new()
	_pic.name = "Screenshot"
	_pic.custom_minimum_size = Vector2(192, 108)
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var img := Image.new()
	if not screen.is_empty() and img.load_png_from_buffer(screen) == OK:
		_pic.texture = ImageTexture.create_from_image(img)
	shot.add_child(_pic)
	var remove := _button("Remove", "RemoveScreenshot", func():
		screen = PackedByteArray()
		shot.visible = false)
	shot.add_child(remove)
	shot.visible = not screen.is_empty()
	var vbox := VBoxContainer.new()
	row.add_child(vbox)
	_voice_label = Palette.label("", 18)
	_voice_label.name = "VoiceTime"
	vbox.add_child(_voice_label)
	var vrow := HBoxContainer.new()
	vbox.add_child(vrow)
	vrow.add_child(_button("Record", "Record", _on_record))
	vrow.add_child(_button("Play", "PlayVoice", func():
		if voice:
			_player.stream = voice
			_player.play()))
	vrow.add_child(_button("Remove", "RemoveVoice", func():
		_player.stop()
		voice = null
		_refresh_voice()))
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_status = Palette.label("", 17)
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	_send = Palette.button(tr("Send"), "Send")
	_send.pressed.connect(_on_send)
	_send.disabled = true
	buttons.add_child(_send)
	var cancel := Palette.button(tr("Cancel"), "Cancel")
	cancel.pressed.connect(queue_free)
	buttons.add_child(cancel)
	_refresh_voice()


func _button(text: String, node_name: String, fn: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = tr(text)
	b.pressed.connect(fn)
	return b


func _on_text() -> void:
	if _text.text.length() > MAX_TEXT:
		_text.text = _text.text.left(MAX_TEXT)
		_text.set_caret_line(_text.get_line_count() - 1)
		_text.set_caret_column(_text.get_line(_text.get_line_count() - 1).length())
	if _send.text != tr("Sending…"):
		_send.disabled = _text.text.strip_edges() == ""


# --- the voice message ---------------------------------------------------------------------

func _on_record() -> void:
	if _recording >= 0.0:
		_stop_recording()
		return
	_player.stop()
	if OS.get_name() == "Android":
		OS.request_permission("RECORD_AUDIO")
	var bus := AudioServer.get_bus_index(BUS)
	if bus == -1:
		bus = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(bus, BUS)
		AudioServer.set_bus_mute(bus, true)  # (the player does not hear himself)
		AudioServer.add_bus_effect(bus, AudioEffectRecord.new())
	if _mic == null:
		_mic = AudioStreamPlayer.new()
		_mic.stream = AudioStreamMicrophone.new()  # (the browser asks for the microphone here)
		_mic.bus = BUS
		add_child(_mic)
	_mic.play()
	(AudioServer.get_bus_effect(bus, 0) as AudioEffectRecord).set_recording_active(true)
	voice = null
	_recording = 0.0
	_refresh_voice()


func _stop_recording() -> void:
	var rec := AudioServer.get_bus_effect(AudioServer.get_bus_index(BUS), 0) as AudioEffectRecord
	rec.set_recording_active(false)
	voice = rec.get_recording()
	_mic.stop()
	_recording = -1.0
	_refresh_voice()


func _process(delta: float) -> void:
	if _recording < 0.0:
		return
	_recording += delta
	if _recording >= MAX_VOICE:
		_stop_recording()
	else:
		_refresh_voice()


func _exit_tree() -> void:
	if _recording >= 0.0:
		_stop_recording()


static func _clock(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


func _refresh_voice() -> void:
	var rec := find_child("Record", true, false) as Button
	if _recording >= 0.0:
		rec.text = tr("Stop")
		_voice_label.text = tr("Recording: %s of %s") % [_clock(_recording), _clock(MAX_VOICE)]
	elif voice:
		rec.text = tr("Record again")
		_voice_label.text = tr("Voice message: %s") % _clock(voice.get_length())
	else:
		rec.text = tr("Record")
		_voice_label.text = tr("A voice message (up to a minute)")
	(find_child("PlayVoice", true, false) as Button).visible = voice != null
	(find_child("RemoveVoice", true, false) as Button).visible = voice != null


# --- sending -------------------------------------------------------------------------------

func _on_send() -> void:
	if _recording >= 0.0:
		_stop_recording()
	var r := report()
	_send.disabled = true
	if link and link.logged_in():
		_send.text = tr("Sending…")
		_status.text = tr("Sending…")
		link.send_report(r, _on_sent)
	else:
		ServerLink.queue_report(r)
		_done(tr("You are not logged in to a server: the report is saved and will be sent after the next login"))


func _on_sent(res: Dictionary) -> void:
	_send.text = tr("Send")
	if res.has("id"):
		_done(tr("The report is sent. Thank you!"))
	elif res.get("kept", false):
		_done(str(res.error) + "\n" + tr("The report is saved and will be sent after the next login"))
	else:
		_status.text = str(res.error)
		_send.disabled = false  # (the player may fix it: a shorter text, no screenshot)


## Sent or saved: the window can only be closed.
func _done(text: String) -> void:
	_status.text = text
	_send.disabled = true
	(find_child("Cancel", true, false) as Button).text = tr("Close")
