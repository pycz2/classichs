class_name ReplayApp
extends Control
## The admin panel's replay player: the main scene of the "Replay viewer" web build
## (ui/replay_app.tscn), which the game server serves at /admin/replay/ (server/src/admin_extra.rs)
## and the panel opens in a frame as index.html?game=<id>. It fetches that game's replay
## (/admin/api/games/<id>/replay, the admin's cookie: same origin) and, unless it is here
## already, its game pack (/admin/api/pack_files/<rules hash>), then shows ReplayView. Back asks
## the panel to close the player.

## The player's Back (outside a browser: nothing else to do).
signal closed

## Gets a URL: func(url) -> {code (0: no answer), body: PackedByteArray} (may await). Tests set it.
var fetch: Callable = _http_get
## The game to show; the web build reads ?game= from its address.
var game_id := ""
## Where the API is (the web build: the page's origin).
var base := ""
var view: ReplayView
var status: Label
var _http: HTTPRequest
var _what := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if get_tree().current_scene == self:  # the build's main scene (tests add it themselves)
		Locale.load_all()
		Sprites.load_all()
		Settings.load_settings()
		Settings.apply()
		add_child(Sound.new())
	theme = Fonts.theme()
	var bg := ColorRect.new()
	bg.color = Color("0d0a07")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	status = Palette.label("", 22)
	status.name = "Status"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(status)
	if OS.has_feature("web"):
		var loc = JavaScriptBridge.get_interface("location")
		if game_id == "":
			game_id = _query_game(str(loc.search))
		if base == "":
			base = str(loc.origin)  # (HTTPRequest wants a whole URL)
	load_replay()


## "?game=abc&x=1" -> "abc".
static func _query_game(search: String) -> String:
	for kv in search.trim_prefix("?").split("&"):
		if kv.begins_with("game="):
			return kv.substr(5).uri_decode()
	return ""


func _say(text: String) -> void:
	status.text = text
	status.visible = true


## The replay, its pack, the view; on a failure the reason stays on the screen. True when shown.
func load_replay() -> bool:
	if game_id == "":
		_say(tr("No game to show: open a replay from the admin panel"))
		return false
	_say(tr("Loading the replay…"))
	var t0 := Time.get_ticks_msec()
	while Rules.missing() == "loading" and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	if not Rules.ready():
		_say(tr("The game cannot start: its rules engine is missing.") + "\n" + Rules.missing())
		return false
	_what = tr("Loading the replay…")
	var got: Dictionary = await fetch.call(base + "/admin/api/games/%s/replay" % game_id.uri_encode())
	var r := Replay.from_text(got.body.get_string_from_utf8()) if got.code == 200 else null
	if r == null:
		_say(tr("Cannot load the replay of this game (%s)") % _why(got.code))
		return false
	var p := r.pack()
	if p == null:
		_what = tr("Loading the game %s…") % str(r.data.get("pack_name", r.data.get("pack_id", "")))
		_say(_what)
		got = await fetch.call(base + "/admin/api/pack_files/" + str(r.data.pack))
		var put: Dictionary = Packs.install(got.body, "server") if got.code == 200 else {"error": _why(got.code)}
		p = put.get("pack")
		if p == null or p.rules_hash() != str(r.data.pack):
			_say(r.missing() + "\n" + tr(str(put.get("error", "This is not a game pack"))))
			return false
	_what = ""
	Packs.enter(p)
	status.visible = false
	view = ReplayView.new()
	view.replay = r
	view.back.connect(_close)
	add_child(view)
	return true


func _why(code: int) -> String:
	match code:
		0: return tr("no answer from the server")
		401: return tr("log in to the admin panel again")
		404: return tr("not on the server")
	return "HTTP %d" % code


## Back: the panel closes the frame.
func _close() -> void:
	closed.emit()
	if OS.has_feature("web"):
		var parent = JavaScriptBridge.get_interface("parent")
		if parent:
			parent.postMessage("chs-replay-close", str(JavaScriptBridge.get_interface("location").origin))


func _http_get(url: String) -> Dictionary:
	_http = HTTPRequest.new()
	add_child(_http)
	if _http.request(url) != OK:
		_http.queue_free()
		_http = null
		return {"code": 0, "body": PackedByteArray()}
	var res: Array = await _http.request_completed
	_http.queue_free()
	_http = null
	return {"code": res[1] if res[0] == HTTPRequest.RESULT_SUCCESS else 0, "body": res[3]}


func _process(_delta: float) -> void:
	if _http and _what != "" and _http.get_downloaded_bytes() > 0:
		var n := _http.get_downloaded_bytes()
		var of := _http.get_body_size()
		status.text = _what + "\n" + (Packs.size_text(n) + " / " + Packs.size_text(of) if of > 0 else Packs.size_text(n))
