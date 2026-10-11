class_name OnlineView
extends Control
## Online game setup, one step at a time: your name, your deck, then either
## "Create game" (invite code -> paste the answer) or "Join game" (paste the
## invite -> send back the answer code).

signal back
signal edit_decks
signal play(session: NetSession, m: Match)

## Seconds to wait for the connection after the codes are exchanged.
const CONNECT_TIMEOUT := 25.0
## Seconds the guest waits after showing its answer code: the host pastes it by hand.
const GUEST_WAIT := 240.0
## The steps in order; Back goes to the one before ("host" and "join" go back to "mode").
const STAGES := ["name", "deck", "mode", "host", "join"]

## Makes the transport; tests replace it with an in-memory fake.
var transport_factory: Callable = func() -> Transport: return WebRtcTransport.new()
var name_edit := LineEdit.new()
var chooser := DeckChooser.new()
var status: Label
var code_out := TextEdit.new()
var code_in := TextEdit.new()
var state := "idle"
var stage := "name"
var deck: Deck
var transport: Transport
var session: NetSession
var _stages := {}
var _subtitle: Label
var _exchange := VBoxContainer.new()
var _out_row := HBoxContainer.new()
var _out_hint: Label
var _in_label: Label
var _in_row := HBoxContainer.new()
var _connect_button: Button
var _join_button: Button
var _js_refs: Array = []
var _connect_wait := -1.0
var _wait_limit := CONNECT_TIMEOUT


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self)
	var title := Palette.label(tr("Online Game"), 40, Palette.ATTACK)
	title.position = Vector2(140, 24)
	add_child(title)
	_subtitle = Palette.label("", 22)
	_subtitle.position = Vector2(142, 80)
	add_child(_subtitle)
	for s in STAGES:
		var c := Control.new()
		c.name = "Stage_" + s
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(c)
		_stages[s] = c
	# your name
	var row := HBoxContainer.new()
	row.position = Vector2(140, 140)
	row.add_theme_constant_override("separation", 16)
	_stages.name.add_child(row)
	name_edit.name = "NameEdit"
	name_edit.text = Profile.load_name()
	name_edit.max_length = Profile.NAME_MAX
	name_edit.custom_minimum_size = Vector2(480, 52)
	name_edit.add_theme_font_size_override("font_size", 24)
	name_edit.text_submitted.connect(func(_t): show_stage("deck"))
	row.add_child(name_edit)
	var next := Palette.button(tr("Next"), "Next")
	next.custom_minimum_size = Vector2(200, 52)
	next.pressed.connect(show_stage.bind("deck"))
	row.add_child(next)
	# your deck
	chooser.name = "DeckChooser"
	chooser.position = Vector2(140, 130)
	chooser.size = Vector2(1000, 560)
	chooser.chosen.connect(choose_deck)
	chooser.edit_decks.connect(func(): edit_decks.emit())
	chooser.back.connect(step_back)
	_stages.deck.add_child(chooser)
	deck = _first_playable()
	# create or join
	var modes := HBoxContainer.new()
	modes.position = Vector2(140, 150)
	modes.add_theme_constant_override("separation", 40)
	_stages.mode.add_child(modes)
	for spec in [[tr("Create Game"), "Host", host_game], [tr("Join Game"), "Join", show_stage.bind("join")]]:
		var b := Palette.button(spec[0], spec[1])
		b.custom_minimum_size = Vector2(480, 200)
		b.add_theme_font_size_override("font_size", 34)
		b.pressed.connect(spec[2])
		modes.add_child(b)
	# the code exchange: one panel, its rows ordered and shown by stage
	_exchange.name = "Exchange"
	_exchange.position = Vector2(140, 130)
	_exchange.custom_minimum_size.x = 1000
	_exchange.add_theme_constant_override("separation", 10)
	add_child(_exchange)
	_out_row.name = "CodeOutRow"
	_out_row.add_theme_constant_override("separation", 12)
	code_out.name = "CodeOut"
	code_out.editable = false
	code_out.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_out.custom_minimum_size = Vector2(840, 110)
	code_out.add_theme_color_override("font_readonly_color", Palette.TEXT)
	_out_row.add_child(code_out)
	_out_row.add_child(_side_button(tr("Copy"), "Copy", func(): DisplayServer.clipboard_set(code_out.text)))
	_out_hint = Palette.label("", 22, Palette.SELECTED)
	_in_label = Palette.label("", 22)
	for l in [_out_hint, _in_label]:  # a little air above each field
		l.custom_minimum_size.y = 40
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_in_row.name = "CodeInRow"
	_in_row.add_theme_constant_override("separation", 12)
	code_in.name = "CodeIn"
	code_in.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	code_in.custom_minimum_size = Vector2(840, 110)
	_in_row.add_child(code_in)
	_connect_button = _side_button(tr("Connect"), "Finish", func(): finish(code_in.text))
	_join_button = _side_button(tr("Join"), "JoinCode", func(): join_game(code_in.text))
	_in_row.add_child(_connect_button)
	_in_row.add_child(_join_button)
	status = Palette.label("", 20, Palette.SELECTED)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(1000, 30)
	for c in [_out_hint, _out_row, _in_label, _in_row, status]:
		_exchange.add_child(c)
	# Back for every stage but the deck one (the chooser has its own)
	for s in ["name", "mode", "host", "join"]:
		var bk := Palette.button(tr("Back"), "Back")
		bk.position = Vector2(140, 642)
		bk.pressed.connect(step_back)
		_stages[s].add_child(bk)
	show_stage("name")
	_expose_js()


func _side_button(text: String, id: String, action: Callable) -> Button:
	var b := Palette.button(text, id)
	b.custom_minimum_size = Vector2(148, 52)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(action)
	return b


func _first_playable() -> Deck:
	for d in chooser.decks:
		if d.validate() == "":
			return d
	return null


func show_stage(s: String) -> void:
	stage = s
	for k in _stages:
		_stages[k].visible = k == s
	_subtitle.text = {"name": tr("Your name"), "deck": tr("Choose your deck"),
		"mode": tr("Create a new game or join a friend's game"), "host": tr("Create Game"), "join": tr("Join Game")}[s]
	_exchange.visible = s == "host" or s == "join"
	if s == "host":
		_exchange.move_child(_out_hint, 0)
		_exchange.move_child(_out_row, 1)
		_out_hint.text = tr("Send this code to your friend")
		_in_label.text = tr("Paste your friend's answer code")
	elif s == "join":
		_exchange.move_child(_in_label, 0)
		_exchange.move_child(_in_row, 1)
		_exchange.move_child(_out_hint, 2)
		_out_hint.text = tr("Send this code back to your friend and wait")
		_in_label.text = tr("Paste your friend's invite code")
	_refresh()


## Shows the code fields only once they are needed.
func _refresh() -> void:
	var have_code := code_out.text != ""
	var hosting := stage == "host"
	_out_row.visible = have_code
	_out_hint.visible = have_code
	_in_label.visible = have_code or not hosting
	_in_row.visible = have_code or not hosting
	_connect_button.visible = hosting
	_join_button.visible = not hosting


func step_back() -> void:
	match stage:
		"name":
			_drop_session()
			back.emit()
		"deck":
			show_stage("name")
		"mode":
			show_stage("deck")
		_:
			_drop_session()
			state = "idle"
			status.text = ""
			code_out.text = ""
			code_in.text = ""
			show_stage("mode")


func choose_deck(d: Deck) -> void:
	deck = d
	show_stage("mode")


func _drop_session() -> void:
	_connect_wait = -1.0
	if session:
		session.leave()
		session.queue_free()
		transport.queue_free()
		session = null


func _begin(is_host: bool) -> bool:
	var why := tr("Choose your deck") if deck == null else deck.validate()
	if why != "":
		status.text = why
		return false
	_drop_session()
	code_out.text = ""
	Profile.save_name(name_edit.text)
	transport = transport_factory.call()
	add_child(transport)
	session = NetSession.new()
	add_child(session)
	session.setup(transport, is_host, Profile.load_name(), deck)
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
	show_stage("host")
	if not _begin(true):
		return
	state = "waiting"
	status.text = tr("Creating an invite code…")
	transport.host()
	_refresh()


func join_game(invite: String) -> void:
	show_stage("join")
	if invite.strip_edges() == "":
		status.text = tr("Paste the invite code first")
		return
	if not _begin(false):
		_refresh()
		return
	state = "waiting"
	status.text = tr("Creating an answer code…")
	transport.join(invite)
	_refresh()


func finish(answer: String) -> void:
	if session == null or not session.host:
		status.text = tr("Create a game first")
		return
	status.text = tr("Connecting…")
	_connect_wait = 0.0
	_wait_limit = CONNECT_TIMEOUT
	transport.finish(answer)


func _on_code(code: String) -> void:
	code_out.text = code
	state = "code"
	status.text = "" if session.host else tr("Waiting for your friend to connect…")
	_connect_wait = -1.0 if session.host else 0.0
	_wait_limit = GUEST_WAIT
	_refresh()


func _process(delta: float) -> void:
	if _connect_wait >= 0.0 and state != "playing" and state != "failed":
		_connect_wait += minf(delta, 0.5)  # a hidden tab sleeps: its time away does not count
		if _connect_wait >= _wait_limit:
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
