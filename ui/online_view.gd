class_name OnlineView
extends Control
## Online game setup: name, deck, then either "Create game" (invite code ->
## paste answer) or "Join game" (paste invite -> send back the answer code).

signal back
signal play(session: NetSession, m: Match)

## Seconds to wait for the connection after the codes are exchanged.
const CONNECT_TIMEOUT := 25.0

## Makes the transport; tests replace it with an in-memory fake.
var transport_factory: Callable = func() -> Transport: return WebRtcTransport.new()
var name_edit := LineEdit.new()
var deck_picker := OptionButton.new()
var status: Label
var code_out := TextEdit.new()
var code_in := TextEdit.new()
var state := "idle"
var transport: Transport
var session: NetSession
var _decks: Array[Deck] = []
var _js_refs: Array = []
var _connect_wait := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self)
	var box := VBoxContainer.new()
	box.position = Vector2(80, 30)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(Palette.label(tr("Online Game"), 36, Palette.ATTACK))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(Palette.label(tr("Your name"), 20))
	name_edit.name = "NameEdit"
	name_edit.text = Profile.load_name()
	name_edit.max_length = Profile.NAME_MAX
	name_edit.custom_minimum_size = Vector2(300, 38)
	row.add_child(name_edit)
	row.add_child(Palette.label(tr("Deck"), 20))
	deck_picker.name = "DeckPicker"
	deck_picker.custom_minimum_size = Vector2(420, 38)
	_decks = TrainingSetup.available_decks()
	for d in _decks:
		deck_picker.add_item(d.name + ("" if d.validate() == "" else "  (%d/30)" % d.cards.size()))
	deck_picker.selected = 2
	row.add_child(deck_picker)
	box.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	for spec in [[tr("Create Game"), "Host", host_game], [tr("Join Game"), "Join", func(): join_game(code_in.text)],
			[tr("Connect"), "Finish", func(): finish(code_in.text)], [tr("Copy Code"), "Copy", func(): DisplayServer.clipboard_set(code_out.text)],
			[tr("Back"), "Back", _on_back]]:
		var b := Palette.button(spec[0], spec[1])
		b.custom_minimum_size = Vector2(200, 44)
		b.pressed.connect(spec[2])
		buttons.add_child(b)
	box.add_child(buttons)
	status = Palette.label(tr("Create a game and send the invite code to a friend, or paste a friend's invite code and press \"Join Game\"."), 18, Palette.SELECTED)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(1100, 50)
	box.add_child(status)
	box.add_child(Palette.label(tr("Your code (send it to your friend)"), 18))
	code_out.name = "CodeOut"
	code_out.editable = false
	code_out.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_out.custom_minimum_size = Vector2(1100, 150)
	box.add_child(code_out)
	box.add_child(Palette.label(tr("Paste your friend's code here"), 18))
	code_in.name = "CodeIn"
	code_in.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_in.custom_minimum_size = Vector2(1100, 150)
	box.add_child(code_in)
	_expose_js()


func _deck() -> Deck:
	return _decks[deck_picker.selected]


func _begin(is_host: bool) -> bool:
	var d := _deck()
	var why := d.validate()
	if why != "":
		status.text = why
		return false
	if session:
		session.leave()
		session.queue_free()
		transport.queue_free()
	Profile.save_name(name_edit.text)
	transport = transport_factory.call()
	add_child(transport)
	session = NetSession.new()
	add_child(session)
	session.setup(transport, is_host, Profile.load_name(), d)
	session.started.connect(func(m):
		state = "playing"
		status.text = tr("Connected")
		_sync_js()  # the screen changes right after this
		play.emit(session, m))
	session.failed.connect(func(reason):
		state = "failed"
		status.text = reason)
	if transport.has_signal("code_ready"):
		transport.code_ready.connect(_on_code)
		transport.error.connect(func(text):
			state = "failed"
			status.text = text)
	return true


func host_game() -> void:
	if not _begin(true):
		return
	state = "waiting"
	status.text = tr("Creating an invite code…")
	transport.host()


func join_game(invite: String) -> void:
	if invite.strip_edges() == "":
		status.text = tr("Paste the invite code first")
		return
	if not _begin(false):
		return
	state = "waiting"
	status.text = tr("Creating an answer code…")
	transport.join(invite)


func finish(answer: String) -> void:
	if session == null or not session.host:
		status.text = tr("Create a game first")
		return
	status.text = tr("Connecting…")
	_connect_wait = 0.0
	transport.finish(answer)


func _on_code(code: String) -> void:
	code_out.text = code
	state = "code"
	status.text = tr("Send this invite code to your friend, then paste their answer code and press \"Connect\".") if session.host \
		else tr("Send this answer code back to your friend and wait for the game to start.")
	_connect_wait = -1.0 if session.host else 0.0


func _on_back() -> void:
	if session:
		session.leave()
	back.emit()


func _process(delta: float) -> void:
	if _connect_wait >= 0.0 and state != "playing" and state != "failed":
		_connect_wait += minf(delta, 0.5)  # a hidden tab sleeps: its time away does not count
		if _connect_wait >= CONNECT_TIMEOUT:
			_connect_wait = -1.0
			state = "failed"
			status.text = tr("Could not connect. Create a new invite and try again (the networks may block direct connections).")
	_sync_js()


## Browser callbacks can't return values: the code and state are mirrored into
## window.chs_code and window.chs_state for automated tests.
func _sync_js() -> void:
	if OS.has_feature("web"):
		var w := JavaScriptBridge.get_interface("window")
		w.chs_code = code_out.text
		w.chs_state = state + ":" + status.text
		if transport is WebRtcTransport and transport.pc:
			w.chs_net = "pc=%d ch=%d" % [transport.pc.get_connection_state(), transport.channel.get_ready_state()]


## Browser-only hooks for automated two-tab tests: window.chs.host(), .join(code),
## .finish(code); read window.chs_code and window.chs_state.
func _expose_js() -> void:
	if not OS.has_feature("web"):
		return
	var cb := func(fn: Callable) -> JavaScriptObject:
		var o := JavaScriptBridge.create_callback(func(args): return fn.call(args))
		_js_refs.append(o)
		return o
	var api: JavaScriptObject = JavaScriptBridge.create_object("Object")
	api.host = cb.call(func(_a): host_game())
	api.join = cb.call(func(a): join_game(str(a[0])))
	api.finish = cb.call(func(a): finish(str(a[0])))
	JavaScriptBridge.get_interface("window").chs = api
	_js_refs.append(api)
