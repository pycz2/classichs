class_name ReplaysView
extends Control
## The game menu's Replays: the last games kept on this device (Replay.kept()) and, through a
## server, the player's games there (`replays {}`), one row each — both heroes, the names, the
## result, mode, game, date and turns — with Watch and Export (a .chsreplay file: a download on
## the web, the system's save dialog elsewhere, Android's too), and Import a .chsreplay (its game
## must be on this device with the same rules).

signal back
signal watch(r: Replay)

## The game modes as the rows name them (English keys).
const MODES := {"training": "Training", "code": "Code play", "hotseat": "Hot seat", "arena": "Arena",
	"casual": "Casual", "ranked": "Ranked", "friendly": "Friendly game", "tournament": "Tournament"}

## The tabs through a server (English keys).
const TABS := [["device", "On this device"], ["server", "On this server"]]
## The server (a ServerLink; null without one): its tab lists the player's games there.
var link: Object
var tab := "device"
var _scroll := ScrollContainer.new()
var _list := VBoxContainer.new()
var _note: Label
var _tabs := {}
var _server_list = null  # the server's `replays` list (null: not here yet)
var _want := {}  # game id -> "watch" | "export": waiting for its `replay`
var _web_callback: JavaScriptObject


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self, "library")
	var t := Palette.label(tr("Replays"), 40, Palette.ATTACK)
	t.position = Vector2(120, 22)
	add_child(t)
	var sub := Palette.label(tr("Watch your last games again, turn by turn"), 20)
	sub.position = Vector2(122, 78)
	add_child(sub)
	var imp := _button(tr("Import a replay"), "ImportReplay", "import", import_replay, Vector2(280, 56))
	imp.position = Vector2(880, 28)
	add_child(imp)
	if link:
		var row := HBoxContainer.new()
		row.position = Vector2(120, 116)
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		for spec in TABS:
			var b := _button(tr(spec[1]), "Tab_" + spec[0], "", show_tab.bind(spec[0]), Vector2(240, 46))
			row.add_child(b)
			_tabs[spec[0]] = b
		link.message.connect(_on_message)
	_scroll.name = "List"
	_scroll.position = Vector2(120, 174 if link else 126)
	_scroll.size = Vector2(1040, 470 if link else 518)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list.add_theme_constant_override("separation", 10)
	_list.custom_minimum_size.x = 1020
	_scroll.add_child(_list)
	var bk := _button(tr("Back"), "Back", "", func(): back.emit(), Vector2(200, 52))
	bk.position = Vector2(120, 656)
	add_child(bk)
	_note = Palette.label("", 18)
	_note.name = "Note"
	_note.position = Vector2(340, 664)
	_note.size = Vector2(820, 40)
	_note.clip_text = true
	add_child(_note)
	show_tab("device")


func show_tab(which: String) -> void:
	tab = which
	for k in _tabs:
		var on: bool = k == which
		_tabs[k].modulate = Color.WHITE if on else Color(0.65, 0.65, 0.65)
		if on:
			_tabs[k].add_theme_color_override("font_color", Palette.ATTACK)
		else:
			_tabs[k].remove_theme_color_override("font_color")
	if which == "server" and link:
		_server_list = null
		link.send({"t": "replays"})
	refresh()


func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if tab == "device":
		var kept := Replay.kept()
		for r in kept:
			_list.add_child(_row(_summary(r), func(): _watch(r), func(): export_replay(r)))
		if kept.is_empty():
			_empty(tr("No replays yet"), tr("Your finished games appear here: the last %d on this device.") % Replay.KEEP
				+ "\n" + tr("A replay file from a friend comes in with Import."), true)
		return
	if _server_list == null:
		_empty(tr("Loading…"), "", false)
		return
	for e in _server_list:
		var game := str(e.get("game", ""))
		_list.add_child(_row(_server_summary(e), _fetch.bind(game, "watch"), _fetch.bind(game, "export")))
	if _server_list.is_empty():
		_empty(tr("No games on this server yet"), tr("Your games played here appear in this list."), false)


## What a row shows: {names, heroes, me, winner, mode, pack, ended, turns}.
static func _summary(r: Replay) -> Dictionary:
	return {"names": [r.name(0), r.name(1)], "heroes": [r.hero(0), r.hero(1)], "me": r.me(), "winner": r.winner(),
		"mode": str(r.data.get("mode", "")), "pack": str(r.data.get("pack_name", "")), "ended": int(r.data.get("ended", 0)),
		"turns": int(r.data.get("result", {}).get("turns", 0))}


static func _server_summary(e: Dictionary) -> Dictionary:
	var names = e.get("players", ["", ""])
	var heroes = e.get("heroes", ["", ""])
	return {"names": names if names is Array and names.size() == 2 else ["", str(e.get("opponent", ""))],
		"heroes": heroes if heroes is Array and heroes.size() == 2 else ["", ""], "me": int(e.get("you", 0)),
		"winner": int(e.get("winner", int(e.get("you", 0)) if e.get("won", false) else -2)), "mode": str(e.get("mode", "")),
		"pack": str(e.get("pack_name", "")), "ended": int(e.get("ended", 0)), "turns": int(e.get("turns", 0))}


## One game: both heroes, "A vs B", the mode, game, date and turns, the result badge, Watch, Export.
func _row(s: Dictionary, on_watch: Callable, on_export: Callable) -> Control:
	var row := PanelContainer.new()
	row.name = "Replay%d" % _list.get_child_count()
	var st := Palette.box(Color(0.09, 0.06, 0.04, 0.92), 14, Color("6b5320"), 2)
	st.set_content_margin_all(12)
	row.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)
	var faces := Control.new()
	faces.custom_minimum_size = Vector2(160, 72)
	for p in 2:
		var face := Portrait.new()
		face.hero = str(s.heroes[p])
		face.position = Vector2(0 if p == s.me else 88, 0)
		face.size = Vector2(72, 72)
		face.won = s.winner == p
		faces.add_child(face)
	var vs := IconView.new()  # crossed swords between the two
	vs.kind = "swords"
	vs.position = Vector2(66, 22)
	vs.size = Vector2(28, 28)
	vs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	faces.add_child(vs)
	h.add_child(faces)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	var me: int = s.me
	var title := Palette.label("%s  vs  %s" % [_name(s.names[me]), _name(s.names[1 - me])], 22)
	title.clip_text = true
	text.add_child(title)
	var bits := [tr(MODES.get(s.mode, s.mode)) if s.mode != "" else "", tr("%d turns") % s.turns if s.turns > 0 else "",
		_date(s.ended), s.pack]
	var info := Palette.label("  ·  ".join(bits.filter(func(b): return b != "")), 17, Palette.MUTED)
	info.clip_text = true
	text.add_child(info)
	h.add_child(text)
	h.add_child(_badge(s.winner, me))
	var w := _button(tr("Watch"), "Watch", "play", on_watch, Vector2(170, 56))
	h.add_child(w)
	var x := _button("", "Export", "export", on_export, Vector2(56, 56))
	x.tooltip_text = tr("Export a replay file")
	h.add_child(x)
	return row


static func _name(n: String) -> String:
	return TranslationServer.translate("Player") if n == Profile.DEFAULT_NAME else n


## Victory / Defeat / Draw from the player's side, as a coloured pill.
func _badge(winner: int, me: int) -> Control:
	var kind := "draw" if winner < 0 else ("win" if winner == me else "loss")
	var col: Color = {"win": Color("2f8f3a"), "loss": Color("9b2c22"), "draw": Color("6b6152")}[kind]
	var c := CenterContainer.new()
	var p := PanelContainer.new()
	p.name = "Badge"
	var st := Palette.raw_box(col, 18, col.lightened(0.35), 2)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", st)
	var l := Palette.label({"win": tr("Victory"), "loss": tr("Defeat"), "draw": tr("Draw")}[kind], 18, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 96
	p.add_child(l)
	c.add_child(p)
	return c


## An empty list: a big film frame, what goes here, and (on the device) Import.
func _empty(title: String, text: String, with_import: bool) -> void:
	var box := VBoxContainer.new()
	box.name = "Empty"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(1020, 420)
	box.add_theme_constant_override("separation", 14)
	var icon := IconView.new()
	icon.kind = "film"
	icon.custom_minimum_size = Vector2(96, 96)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.modulate = Color(1, 1, 1, 0.8)
	box.add_child(icon)
	var t := Palette.label(title, 30, Palette.ATTACK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	if text != "":
		var l := Palette.label(text, 18, Palette.MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	if with_import:
		var b := _button(tr("Import a replay"), "ImportEmpty", "import", import_replay, Vector2(280, 56))
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(b)
	_list.add_child(box)


func _button(text: String, id: String, icon: String, fn: Callable, min_size := Vector2(260, 48)) -> Button:
	var b := Palette.button(text, id)
	b.custom_minimum_size = min_size
	b.size = min_size  # (the icon is placed by the size)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(fn)
	if icon != "":
		Icons.attach(b, icon, 30)
		if text != "":
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.add_theme_constant_override("h_separation", 0)
			b.text = "      " + text  # room for the icon on the left
	return b


static func _date(unix: int) -> String:
	if unix <= 0:
		return ""
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_datetime_string_from_unix_time(unix + bias, true).left(16)


func say(text: String, ok := true) -> void:
	_note.text = text
	_note.add_theme_color_override("font_color", Palette.TEXT if ok else Color("ffb070"))


func _watch(r: Replay) -> void:
	var why := r.missing()
	if why != "":
		say(why, false)
		return
	watch.emit(r)


# --- the server's games --------------------------------------------------------------------

func _fetch(game: String, what: String) -> void:
	_want[game] = what
	say(tr("Loading…"))
	link.send({"t": "replay", "game": game})


func _on_message(msg: Dictionary) -> void:
	match msg.get("t"):
		"replays":
			_server_list = (msg.get("list") as Array).filter(func(e): return e is Dictionary) if msg.get("list") is Array else []
			if tab == "server":
				refresh()
		"replay":
			var game := str(msg.get("game", ""))
			if not _want.has(game):
				return
			var what: String = _want[game]
			_want.erase(game)
			var r := Replay.from_data(msg.get("data"))
			if r == null:
				say(tr("This is not a replay file"), false)
				return
			for e in _server_list if _server_list is Array else []:
				if str(e.get("game", "")) == game:
					r.data.me = int(e.get("you", 0))
			say("")
			if what == "watch":
				_watch(r)
			else:
				export_replay(r)
		"error":
			if not _want.is_empty() and msg.get("code") in ["not_found", "bad_request"]:
				_want.clear()
				say(tr("The server has no replay of this game"), false)


# --- export and import ---------------------------------------------------------------------

## Saves a .chsreplay: a download on the web, the system's save dialog elsewhere (Android's too).
func export_replay(r: Replay) -> void:
	var bytes := r.to_text().to_utf8_buffer()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, r.file_name(), "application/json")
		say(tr("Saved: %s") % r.file_name())
		return
	var d := FileDialog.new()
	d.name = "ExportDialog"
	d.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.current_file = r.file_name()
	d.filters = PackedStringArray(["*." + Replay.EXT + " ; " + tr("Replays")])
	d.file_selected.connect(func(path: String):
		d.queue_free()
		if r.to_file(path):
			say(tr("Saved: %s") % path.get_file())
		else:
			say(tr("Could not write the file"), false))
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(900, 600))


## Picks a .chsreplay: the system's file dialog natively, the browser's file picker on the web.
func import_replay() -> void:
	if OS.has_feature("web"):
		_import_web()
		return
	var d := FileDialog.new()
	d.name = "ImportDialog"
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.filters = PackedStringArray(["*." + Replay.EXT + " ; " + tr("Replays")])
	d.file_selected.connect(func(path: String):
		d.queue_free()
		import_text(FileAccess.get_file_as_string(path)))
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(900, 600))


## The browser: a hidden <input type=file> hands the file's text over.
func _import_web() -> void:
	_web_callback = JavaScriptBridge.create_callback(func(args: Array): import_text(str(args[0])))
	JavaScriptBridge.get_interface("window").classichsReplayPicked = _web_callback
	JavaScriptBridge.eval("""(function () {
		var i = document.getElementById('classichs-replay-input');
		if (!i) {
			i = document.createElement('input');
			i.type = 'file'; i.accept = '.chsreplay,application/json'; i.id = 'classichs-replay-input'; i.style.display = 'none';
			document.body.appendChild(i);
			i.addEventListener('change', function () {
				var f = i.files[0];
				if (!f) return;
				var r = new FileReader();
				r.onload = function () { i.value = ''; window.classichsReplayPicked(r.result); };
				r.readAsText(f);
			});
		}
		i.click();
	})();""", true)


## A replay file's text: kept among the last replays when its game is on this device.
func import_text(text: String) -> Replay:
	var r := Replay.from_text(text)
	if r == null:
		say(tr("This is not a replay file"), false)
		return null
	var why := r.missing()
	if why != "":
		say(why, false)
		return null
	Replay.keep(r, int(Time.get_unix_time_from_system()))
	show_tab("device")
	say(tr("Imported: %s vs %s") % [_name(r.name(0)), _name(r.name(1))])
	return r


## A hero's portrait in a gold ring (brighter for the winner).
class Portrait:
	extends Control
	var hero := ""
	var won := false

	func _draw() -> void:
		var c := size / 2.0
		var rad := minf(size.x, size.y) / 2.0
		draw_circle(c, rad, Color("f2c94c") if won else Color("8a7240"))
		draw_circle(c, rad - 3.0, Color("1b140f"))
		if hero != "":
			Art.paint_in(self, Rect2(c - Vector2(rad - 5, rad - 5), Vector2(rad - 5, rad - 5) * 2.0), hero, "circle")
