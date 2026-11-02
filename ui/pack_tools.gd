class_name PackTools
extends Control
## Pack tools (from the game library): choose a pack's source folder (docs/packs/format.md) or a
## .cardpack / .zip file; it is built, checked, loaded into the rules engine and played by bots
## (PackCheck, game/pack_check.gd); the findings in a list, errors red, warnings yellow, OK green,
## each with its file and line. Then: Save .cardpack, Install (into the library, like an import),
## Play a test game (Training with it). On the web and Android there is no folder to choose: a
## .cardpack, or the source folder zipped.

signal back
## A test game with this pack (main opens its Training).
signal play(p: Pack)

const LIST := Rect2(Vector2(40, 196), Vector2(1200, 446))
const COLORS := {PackCheck.ERROR: Color("ff6b5a"), PackCheck.WARNING: Color("ffc83d"), PackCheck.PASS: Color("5fd35a")}
## Level -> its word (English keys; i18n_keys.gd reads this table).
const LEVELS := {PackCheck.ERROR: "Error", PackCheck.WARNING: "Warning", PackCheck.PASS: "OK"}

## The last run (null before a source is chosen).
var result: PackCheck
var games := 4
var _source := {}  # {folder} or {name, bytes, path?}
var _installed: Pack
var _list: VBoxContainer
var _summary: Label
var _where: Label
var _message: Label
var _buttons := {}
var _web_callback: JavaScriptObject  # kept alive while the browser's file picker is open


static func can_pick_folder() -> bool:
	return not OS.has_feature("web") and not OS.has_feature("android") and not OS.has_feature("ios")


func _ready() -> void:
	name = "PackTools"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self, "library_bg")
	var title := Palette.label(tr("Pack tools"), 34, Palette.ATTACK)
	title.position = Vector2(LIST.position.x, 18)
	add_child(title)
	var back_b := _button(tr("Back"), "Back", Vector2(LIST.end.x - 150, 20), 150)
	back_b.pressed.connect(func(): back.emit())
	var x := LIST.position.x
	if can_pick_folder():
		_button(tr("Choose a folder"), "ChooseFolder", Vector2(x, 84), 230).pressed.connect(choose_folder)
		x += 246
	_button(tr("Choose a file"), "ChooseFile", Vector2(x, 84), 230).pressed.connect(choose_file)
	x += 246
	var again := _button(tr("Build and check"), "Run", Vector2(x, 84), 250)
	again.pressed.connect(func(): _later(rerun))
	x += 270
	var n := Palette.label(tr("Trial games"), 17)
	n.position = Vector2(x, 96)
	add_child(n)
	var spin := SpinBox.new()
	spin.name = "Games"
	spin.min_value = 0
	spin.max_value = 20
	spin.value = games
	spin.position = Vector2(x + n.get_minimum_size().x + 12, 88)
	spin.value_changed.connect(func(v): games = int(v))
	add_child(spin)
	_where = Palette.label("", 16, Palette.MUTED)
	_where.position = Vector2(LIST.position.x, 140)
	_where.size = Vector2(LIST.size.x, 22)
	_where.clip_text = true
	add_child(_where)
	_summary = Palette.label("", 19)
	_summary.name = "Summary"
	_summary.position = Vector2(LIST.position.x, 164)
	add_child(_summary)
	var panel := PanelContainer.new()
	panel.position = LIST.position
	panel.size = LIST.size
	panel.add_theme_stylebox_override("panel", Palette.frame())
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	var y := LIST.end.y + 14
	_button(tr("Save .cardpack"), "Save", Vector2(LIST.position.x, y), 230).pressed.connect(save)
	_button(tr("Install"), "Install", Vector2(LIST.position.x + 246, y), 200).pressed.connect(install)
	_button(tr("Play a test game"), "PlayTest", Vector2(LIST.position.x + 462, y), 290).pressed.connect(play_test)
	_message = Palette.label("", 16)
	_message.name = "Message"
	_message.position = Vector2(LIST.position.x + 770, y + 12)
	_message.size = Vector2(LIST.end.x - LIST.position.x - 770, 22)
	_message.clip_text = true
	add_child(_message)
	_show()


func _button(text: String, id: String, at: Vector2, width: int) -> Button:
	var b := Palette.button(text, id)
	b.custom_minimum_size = Vector2(width, 46)
	b.position = at
	add_child(b)
	_buttons[id] = b
	return b


# --- running --------------------------------------------------------------------------------

## Builds, checks, loads and plays a source folder.
func open_folder(dir: String) -> void:
	_source = {"folder": dir}
	rerun()


## The same for a file's bytes (.cardpack: checked as it is; .zip: a source folder zipped).
func open_bytes(bytes: PackedByteArray, file_name: String, path := "") -> void:
	_source = {"name": file_name, "bytes": bytes, "path": path}
	rerun()


## The chosen source again (a folder or a file on disk is read again: edit, then Build and check).
func rerun() -> void:
	if _source.is_empty():
		return
	if _source.has("folder"):
		result = PackCheck.open_folder(_source.folder)
	else:
		if _source.path != "" and FileAccess.file_exists(_source.path):
			_source.bytes = FileAccess.get_file_as_bytes(_source.path)
		result = PackCheck.open_file(_source.bytes, _source.name)
	result.check()
	if ["manifest.json", "rules.json", "cards.json"].all(func(f): return result.files.has(f)) and result.load_engine():
		for i in games:
			result.trial(i)
	_installed = null
	_message.text = ""
	_show()


## Runs f a moment later, once "Checking…" is on the screen (a big pack takes a while).
func _later(f: Callable) -> void:
	if _source.is_empty():
		return
	_summary.text = tr("Checking…")
	_summary.add_theme_color_override("font_color", Palette.TEXT)
	for i in 2:
		await get_tree().process_frame
	f.call()


func _show() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var good := result != null and result.errors() == 0 and not result.files.is_empty()
	for id in ["Save", "Install", "PlayTest"]:
		_buttons[id].disabled = not good
	_buttons.Run.disabled = _source.is_empty()
	if result == null:
		_where.text = ""
		_summary.text = ""
		var hint := tr("Choose a pack's source folder (manifest.json, rules.json, cards.json, …) or a .cardpack file.") \
			if can_pick_folder() else \
			tr("This device can't open a folder: choose a .cardpack file, or the pack's source folder zipped into a .zip file.")
		var l := Palette.label(hint + "\n" + tr("It is built as tools/pack.py build does (without recipe.json steps), checked, loaded into the rules engine and played by bots."), 17)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(LIST.size.x - 40, 0)
		_list.add_child(l)
		return
	_where.text = "%s: %s" % [tr("Source") if result.from_source else tr("Game file"), result.source]
	var e := result.errors()
	var w := result.count(PackCheck.WARNING)
	_summary.text = tr("%d errors, %d warnings") % [e, w]
	_summary.add_theme_color_override("font_color", COLORS[PackCheck.ERROR if e else (PackCheck.WARNING if w else PackCheck.PASS)])
	var order := {PackCheck.ERROR: 0, PackCheck.WARNING: 1, PackCheck.PASS: 2}
	var sorted := result.items.duplicate()
	sorted.sort_custom(func(a, b): return order[a.level] < order[b.level])  # (stable: in the order found)
	for i in sorted.size():
		_list.add_child(_row(sorted[i], i))


func _row(it: Dictionary, i: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "Item%d" % i
	row.add_theme_constant_override("separation", 12)
	var c: Color = COLORS[it.level]
	var tag := Palette.label(tr(LEVELS[it.level]), 16, c)
	tag.custom_minimum_size = Vector2(96, 0)
	row.add_child(tag)
	var at := Palette.label(it.file + (":%d" % it.line if it.line > 0 else ""), 16, Palette.MUTED)
	at.custom_minimum_size = Vector2(230, 0)
	at.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	row.add_child(at)
	var text := Palette.label(it.text, 16, c.lerp(Palette.TEXT, 0.45))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(LIST.size.x - 400, 0)
	row.add_child(text)
	return row


func _say(text: String, good := true) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", COLORS[PackCheck.PASS] if good else COLORS[PackCheck.ERROR])


# --- after a good check -----------------------------------------------------------------------

## Adds the pack to the game library, like an import. The pack, or null (the reason is shown).
func install() -> Pack:
	if result == null or result.errors() > 0:
		return null
	if _installed == null:
		var r := Packs.install(result.pack_bytes(), "imported")
		if r.has("error"):
			_say(tr(str(r.error)) + (": " + str(r.detail) if r.has("detail") else ""), false)
			return null
		_installed = r.pack
	_say(tr("Added: %s") % _installed.title())
	return _installed


## Installs the pack and opens a training game with it.
func play_test() -> void:
	var p := install()
	if p:
		play.emit(p)


## Saves the .cardpack: the system's save dialog, a download on the web.
func save() -> void:
	if result == null or result.errors() > 0:
		return
	var bytes := result.pack_bytes()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, result.file_name(), "application/zip")
		return
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.current_file = result.file_name()
	d.filters = PackedStringArray(["*.cardpack ; " + tr("Game packs")])
	d.file_selected.connect(func(path: String):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_buffer(bytes)
			f.close()
			_say(tr("Saved: %s") % path.get_file())
		else:
			_say(tr("Cannot write the game pack"), false)
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(900, 600))


# --- choosing a source ------------------------------------------------------------------------

func choose_folder() -> void:
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.dir_selected.connect(func(dir: String):
		d.queue_free()
		_source = {"folder": dir}
		_later(rerun))
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(900, 600))


## A .cardpack or a zipped source folder: the system's file dialog, the browser's file picker on the web.
func choose_file() -> void:
	if OS.has_feature("web"):
		_choose_web()
		return
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.filters = PackedStringArray(["*.cardpack, *.zip ; " + tr("Game packs")])
	d.file_selected.connect(func(path: String):
		d.queue_free()
		_source = {"name": path.get_file(), "bytes": PackedByteArray(), "path": path}
		_later(rerun))
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(900, 600))


## The browser: a hidden <input type=file> reads the file and hands it over as base64.
func _choose_web() -> void:
	_web_callback = JavaScriptBridge.create_callback(func(args: Array):
		_source = {"name": str(args[0]), "bytes": Marshalls.base64_to_raw(str(args[1])), "path": ""}
		_later(rerun))
	JavaScriptBridge.get_interface("window").classichsPackToolsPicked = _web_callback
	JavaScriptBridge.eval("""(function () {
		var i = document.getElementById('classichs-packtools-input');
		if (!i) {
			i = document.createElement('input');
			i.type = 'file'; i.accept = '.cardpack,.zip'; i.id = 'classichs-packtools-input'; i.style.display = 'none';
			document.body.appendChild(i);
			i.addEventListener('change', function () {
				var f = i.files[0];
				if (!f) return;
				var r = new FileReader();
				r.onload = function () {
					var b = new Uint8Array(r.result), s = '';
					for (var k = 0; k < b.length; k += 32768) s += String.fromCharCode.apply(null, b.subarray(k, k + 32768));
					i.value = '';
					window.classichsPackToolsPicked(f.name, btoa(s));
				};
				r.readAsArrayBuffer(f);
			});
		}
		i.click();
	})();""", true)
