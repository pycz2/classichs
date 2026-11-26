extends Node
## UI watch, a debug mode (docs/ui-watch.md): the owner plays in a normal window, someone else reads what is on the
## screen and edits the screens' scripts, and the window shows the change at once. main adds it only under
## `-- --ui-watch` (its own user://, never the player's) or `-- --ui-watch-real` (the player's own profile).
## Into DIR (~/ClassicHS-local/uiwatch, or UI_WATCH_DIR): state.json (the screen, its visible controls, popups, the last
## events and errors; written when something changed, at most every 0.3 s), pid, godot.log, the shots. It takes
## commands from DIR/cmd.json (tools/ui_watch.py writes them). A changed screen script (ui/) is reloaded and the
## screen built again by the same call of main that opened it; a translation file is read again; any other change
## (game/, main.gd, this file, the fonts, project.godot) starts the game again on the same screen.

const PROFILE := "classichs-uiwatch"  # the watch's own user:// (a folder in the OS's data folder)
const EVERY := 0.3  # the state and the files
const CMD_EVERY := 0.2
const KEEP_EVENTS := 50
const MAX_CONTROLS := 400
## Where a change is reloaded in place (else: a restart), and what is watched.
var hot_dirs := ["res://ui/"]
var dirs := [["res://ui", ".gd"], ["res://game", ".gd"], ["res://data/i18n", ".json"], ["res://fonts", ".ttf"],
	["res://fonts", ".otf"]]
var files := ["res://project.godot", "res://tools/ui_watch.gd"]
var dry := false  # tests: a restart is only told, never done

var main: Node
var dir := ""
var seq := 0
## The call of main that opened the screen now: {call, args, node} (main._set_screen tells).
var nav := {}
var history: Array = []
var events: Array = []
var error := ""  # a changed script that does not compile (the old screen stays)
var shots := {}
var last_shot := ""
var _log := WatchLog.new()
var _mtimes := {}
var _last := ""
var _t_state := 0.0
var _t_cmd := 0.0
var _t_files := 0.0
var _windows: Array[Window] = []
var _overlays := ""
var _error_layer: CanvasLayer
var _ret := {}  # where a restart asked to go back to
var _class_name := RegEx.create_from_string("(?m)^class_name\\s+\\w+")


## The engine's errors and warnings (push_error, script errors), from any thread.
class WatchLog:
	extends Logger
	var lines: Array = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		_lock.lock()
		lines.append({"t": "warning" if error_type == ERROR_TYPE_WARNING else "error", "fn": function,
			"text": "%s (%s:%d)" % [rationale if rationale != "" else code, file, line], "code": code, "file": file, "line": line})
		_lock.unlock()

	func take() -> Array:
		_lock.lock()
		var out := lines
		lines = []
		_lock.unlock()
		return out


## m: main; own_profile: user:// becomes the watch's own (set at once, before main reads its settings).
func _init(m: Node = null, own_profile := false) -> void:
	main = m
	name = "UiWatch"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if own_profile:
		ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
		ProjectSettings.set_setting("application/config/custom_user_dir_name", PROFILE)
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	dir = OS.get_environment("UI_WATCH_DIR")
	if dir == "":
		dir = OS.get_environment("HOME").path_join("ClassicHS-local/uiwatch")
	var args := OS.get_cmdline_user_args()
	var i := args.find("--ui-watch-return")
	if i >= 0 and i + 1 < args.size():
		var r = JSON.parse_string(args[i + 1])
		_ret = r if r is Dictionary else {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	OS.add_logger(_log)
	var path := dir.path_join("state.json")
	var old = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if old is Dictionary:
		seq = int(old.get("seq", 0))  # (seq only grows, also over restarts)
		if not _ret.is_empty():  # a restart: its events and history go on
			events = old.get("events", [])
			history = old.get("history", [])
	_write(dir.path_join("pid"), str(OS.get_process_id()))
	get_tree().node_added.connect(_added)
	for n in main.find_children("*", "", true, false):
		_added(n)
	_scan()


func _exit_tree() -> void:
	OS.remove_logger(_log)


func _process(delta: float) -> void:
	if not _ret.is_empty() and main.screen != null:
		_go_back()
	_t_cmd -= delta
	if _t_cmd <= 0.0:
		_t_cmd = CMD_EVERY
		poll_commands()
	_t_files -= delta
	if _t_files <= 0.0:
		_t_files = EVERY
		poll_files()
	_t_state -= delta
	if _t_state <= 0.0:
		_t_state = EVERY
		write_state()


# --- what main tells -----------------------------------------------------------------------

## main._set_screen: s is the screen now, opened by main.by(args).
func screen_set(s: Control, by: String, args: Array) -> void:
	nav = {"call": by, "args": args, "node": s}
	history.append({"screen": _type(s), "call": by, "args": _plain(args)})
	history = history.slice(-30)
	event({"t": "screen", "screen": _type(s), "call": by, "args": _plain(args)})


func event(e: Dictionary) -> void:
	e.at = snappedf(Time.get_unix_time_from_system(), 0.001)
	events.append(e)
	events = events.slice(-KEEP_EVENTS)


func _added(n: Node) -> void:
	if n is BaseButton:
		n.pressed.connect(_pressed.bind(n))
	elif n is Window:
		_windows.append(n)
		n.visibility_changed.connect(_popup.bind(n))


func _pressed(b: BaseButton) -> void:
	event({"t": "press", "text": _text(b), "name": str(b.name), "path": _where(b)})


func _popup(w: Window) -> void:
	event({"t": "popup" if w.visible else "popup_closed", "name": str(w.name), "title": w.title})


# --- the state -----------------------------------------------------------------------------

## The engine's errors and warnings into the events.
func _drain(lines: Array) -> void:
	for l in lines:
		if str(l.file).begins_with("gdscript://"):
			continue  # (a changed script's check: told as `error`)
		event({"t": l.t, "text": l.text})


func current() -> Node:
	if main.get("watch_view") != null:
		return main.watch_view
	return main.screen


## The state now (without seq and the time).
func state() -> Dictionary:
	_drain(_log.take())
	var s := current()
	var d := {"pid": OS.get_process_id(), "profile": OS.get_user_data_dir(), "window": [get_window().size.x, get_window().size.y],
		"lang": TranslationServer.get_locale(), "history": history, "error": error, "shots": shots, "last_shot": last_shot}
	if s:
		var opened: bool = nav.get("node") == s
		d.screen = {"type": _type(s), "name": str(s.name), "call": nav["call"] if opened else "",
			"args": _plain(nav["args"]) if opened else []}
		var cs := []
		_controls(s, s, cs, MAX_CONTROLS, false)
		d.controls = cs
		d.controls_cut = cs.size() >= MAX_CONTROLS
	d.popups = _windows.filter(func(w): return is_instance_valid(w) and w.visible).map(func(w: Window):
		var cs := []
		_controls(w, w, cs, 60, true)
		return {"name": str(w.name), "title": w.title, "controls": cs})
	var over := []
	for c in main.get_children():
		if c == s or c == self or (c is CanvasLayer and not c.visible) or (c is CanvasItem and not c.visible):
			continue
		var cs := []
		_controls(c, c, cs, 60, true)
		if not cs.is_empty():
			over.append({"name": str(c.name), "controls": cs})
	d.overlays = over
	var sig := str(over.map(func(o): return [o.name, o.controls.map(func(x): return x.get("text", ""))]))
	if sig != _overlays:  # a toast, the friends panel, a dialog over the screen...
		if _overlays != "" or not over.is_empty():
			event({"t": "overlays", "shown": over.map(func(o): return "%s: %s" % [o.name, " | ".join(o.controls.map(func(x): return x.get("text", "")).filter(func(x): return x != "").slice(0, 4))])})
		_overlays = sig
	d.events = events
	return d


## Writes state.json when the state changed (temp file + rename: a reader never sees half of it).
func write_state(force := false) -> void:
	var d := state()
	var text := JSON.stringify(d)
	if text == _last and not force:
		return
	_last = text
	seq += 1
	d.seq = seq
	d.time = snappedf(Time.get_unix_time_from_system(), 0.001)
	_write(dir.path_join("state.json"), JSON.stringify(d, " "))


func _controls(n: Node, base: Node, out: Array, cap: int, texts_only: bool) -> void:
	for c in n.get_children():
		if out.size() >= cap:
			return
		if c is CanvasItem and not c.visible or c is CanvasLayer and not c.visible:
			continue
		if c is Control:
			var r: Rect2 = c.get_global_rect()
			var e := {"type": _type(c), "name": str(c.name), "path": str(base.get_path_to(c)),
				"rect": [roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y)]}
			var t := _text(c)
			if t != "":
				e.text = t
			if c is BaseButton and c.disabled:
				e.disabled = true
			if c.has_focus():
				e.focus = true
			if c.tooltip_text != "":
				e.tooltip = c.tooltip_text.left(80)
			if not texts_only or e.has("text") or c is BaseButton:
				out.append(e)
		if not c is Window:
			_controls(c, base, out, cap, texts_only)


func _text(c: Control) -> String:
	var t := ""
	if c is RichTextLabel:
		t = c.get_parsed_text()
	elif c is LineEdit:
		t = c.text if c.text != "" else c.placeholder_text
	elif "text" in c:
		t = str(c.text)
	return t.strip_edges().replace("\n", " ").left(80)


func _type(n: Node) -> String:
	var s: Script = n.get_script()
	while s:
		if s.get_global_name() != &"":
			return str(s.get_global_name())
		s = s.get_base_script()
	return n.get_class()


## Where a node is: its path in the screen, else in main.
func _where(n: Node) -> String:
	var s := current()
	if s and s.is_ancestor_of(n):
		return str(s.get_path_to(n))
	return str(main.get_path_to(n)) if main.is_ancestor_of(n) else str(n.get_path())


## Arguments as JSON: a pack by its id, other objects as text.
func _plain(v: Variant) -> Variant:
	if v is Array:
		return v.map(_plain)
	if v is Pack:
		return v.id()
	if v is Object:
		return str(v)
	return v


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
	DirAccess.rename_absolute(path + ".tmp", path)


# --- commands ------------------------------------------------------------------------------

## DIR/cmd.json, one command: taken (and deleted) and done.
func poll_commands() -> void:
	var p := dir.path_join("cmd.json")
	if not FileAccess.file_exists(p):
		return
	var c = JSON.parse_string(FileAccess.get_file_as_string(p))
	DirAccess.remove_absolute(p)
	if not c is Dictionary:
		event({"t": "error", "text": "cmd.json is not a JSON object"})
		return
	run(c)


func run(c: Dictionary) -> void:
	event({"t": "cmd", "cmd": c})
	if c.has("goto"):
		var a = c.get("args", [])
		goto(str(c.goto), a if a is Array else [a])
	if c.has("size") and c["size"] is Array and c["size"].size() == 2:
		get_window().size = Vector2i(int(c["size"][0]), int(c["size"][1]))
	if c.has("lang"):
		Locale.set_language(str(c.lang))  # (the settings stay as they are: nothing is saved)
		rebuild()
	if c.get("reload", false):
		rebuild()
	if c.has("shot"):
		shot(str(c.shot))
	if c.get("restart", false):
		restart("asked")


## main.by(args), as a button would (enter_game takes the pack's id).
func goto(by: String, args: Array) -> void:
	if not main.has_method(by):
		event({"t": "error", "text": "main has no " + by})
		return
	if by == "enter_game":
		var p = Packs.all().filter(func(x: Pack): return x.id() == str(args[0] if args else ""))
		if p.is_empty():
			event({"t": "error", "text": "no game " + str(args)})
			return
		args = [p[0]]
	main.callv(by, args)


## The screen built again by the call that opened it.
func rebuild() -> bool:
	if nav.get("call", "") == "" or nav["node"] != current():
		event({"t": "error", "text": "this screen cannot be built again (no call of main opened it)"})
		return false
	main.callv(nav["call"], nav["args"])
	return true


func shot(name_: String) -> void:
	var n := name_.validate_filename() if name_ != "" else "shot"
	if DisplayServer.get_name() == "headless":
		event({"t": "shot_skipped", "name": n})
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(n + ".png")
	img.save_png(path + ".tmp.png")
	DirAccess.rename_absolute(path + ".tmp.png", path)
	shots[n] = path
	last_shot = path
	event({"t": "shot", "path": path})


# --- changed files -------------------------------------------------------------------------

func _watched() -> Array:
	var out := files.filter(func(f): return FileAccess.file_exists(f))
	for d in dirs:
		_find(d[0], d[1], out)
	return out


func _find(path: String, ext: String, out: Array) -> void:
	for f in DirAccess.get_files_at(path):
		if f.ends_with(ext):
			out.append(path.path_join(f))
	for sub in DirAccess.get_directories_at(path):
		_find(path.path_join(sub), ext, out)


## A file's time and size (ponytail: the time is in whole seconds; two saves in one second of the same size are one).
func _key(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "%d:%d" % [FileAccess.get_modified_time(path), f.get_length() if f else -1]


func _scan() -> Array:
	var changed := []
	for p in _watched():
		var k := _key(p)
		if _mtimes.has(p) and _mtimes[p] != k:
			changed.append(p)
		_mtimes[p] = k
	return changed


func poll_files() -> void:
	var changed := _scan()
	if not changed.is_empty():
		apply(changed)


## What a change needs: "hot" (a screen script: reload, build the screen again), "text" (a translation file) or
## "restart" (the rest: the core classes, main, the fonts, the project).
func kind(path: String) -> String:
	if path.ends_with(".json"):
		return "text"
	if path.ends_with(".gd") and path.get_file() != "main.gd" and hot_dirs.any(func(d): return path.begins_with(d)):
		return "hot"
	return "restart"


func apply(changed: Array) -> void:
	var t0 := Time.get_ticks_msec()
	var problems := []
	for p in changed:
		if p.ends_with(".gd"):
			var e := check(p)
			if e != "":
				problems.append(e)
	if not problems.is_empty():
		_show_error("\n".join(problems))
		event({"t": "reload_failed", "files": changed, "error": error})
		return
	_show_error("")
	if changed.any(func(p): return kind(p) == "restart"):
		restart("changed: " + ", ".join(changed))
		return
	for p in changed:
		if kind(p) == "text":
			Locale.load_all()
		else:
			var s: GDScript = load(p)
			s.source_code = FileAccess.get_file_as_string(p)
			var err := s.reload(true)
			if err != OK:
				event({"t": "error", "text": "%s: reload failed (%s)" % [p, error_string(err)]})
	var built := rebuild()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	event({"t": "reloaded", "files": changed, "rebuilt": built, "ms": Time.get_ticks_msec() - t0})


## "" when the script at path compiles as it is on disk now, else its first error (path:line: text). It is compiled
## apart (without its class_name, which the loaded one keeps), so a broken file never touches the running game.
func check(path: String) -> String:
	var s := GDScript.new()
	s.source_code = _class_name.sub(FileAccess.get_file_as_string(path), "", true)
	_drain(_log.take())
	var err := s.reload()
	var said := _log.take()
	_drain(said)
	said = said.filter(func(l): return str(l.file).begins_with("gdscript://"))
	if err == OK:
		return ""
	if said.is_empty():
		return "%s: %s" % [path, error_string(err)]
	return "%s:%d: %s" % [path, said[0].line, str(said[0].code).trim_prefix("Parse Error: ")]


## A red note over everything while a changed script does not compile ("" hides it).
func _show_error(text: String) -> void:
	error = text
	if _error_layer:
		_error_layer.free()
		_error_layer = null
	if text == "":
		return
	_error_layer = CanvasLayer.new()
	_error_layer.name = "UiWatchError"
	_error_layer.layer = 128
	var l := Label.new()
	l.name = "Text"
	l.text = "UI watch: a changed script does not compile; the screen stays as it was.\n" + text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color.WHITE)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.6, 0.05, 0.05, 0.92)
	box.set_content_margin_all(12)
	l.add_theme_stylebox_override("normal", box)
	l.position = Vector2(20, 20)
	l.size = Vector2(1240, 0)
	_error_layer.add_child(l)
	add_child(_error_layer)


# --- restart -------------------------------------------------------------------------------

## Where to come back after a restart: the call that opened the screen (when its arguments are plain values),
## the mode and the game.
func come_back() -> Dictionary:
	var r := {"mode": main.mode, "pack": Packs.active().id() if not Packs.shell and Packs.active() else "",
		"lang": TranslationServer.get_locale(), "at": Time.get_unix_time_from_system(), "call": "", "args": []}
	if nav.get("node") == current() and nav["call"] != "":
		var plain: bool = nav["args"].all(func(a): return a == null or a is bool or a is int or a is float or a is String)
		r["call"] = nav["call"] if plain else ""
		r.args = nav["args"] if plain else []
	return r


## The command line of the same game again, coming back to where it is now.
func restart_args() -> PackedStringArray:
	var w := get_window()
	var out := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--log-file", dir.path_join("godot.log"),
		"--position", "%d,%d" % [w.position.x, w.position.y], "--resolution", "%dx%d" % [w.size.x, w.size.y],
		"res://ui/main.tscn", "--"])
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--ui-watch-return":
			i += 2
			continue
		out.append(args[i])
		i += 1
	if not ("--ui-watch" in out or "--ui-watch-real" in out):
		out.append("--ui-watch")
	out.append_array(["--ui-watch-return", JSON.stringify(come_back())])
	return out


func restart(why: String) -> void:
	event({"t": "restart", "why": why})
	write_state(true)
	if dry:
		return
	OS.create_process(OS.get_executable_path(), restart_args())
	get_tree().quit()


## After a restart: back to the mode, the game and the screen of before.
func _go_back() -> void:
	var r := _ret
	_ret = {}
	if r.get("lang", "") != "":
		Locale.set_language(r.lang)
	if r.get("mode") == "server":
		main.show_connections()
		var until := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < until and not (main.server_link and main.server_link.logged_in()):
			await get_tree().process_frame
	elif r.get("mode") == "direct":
		main.show_library()
	if str(r.get("pack", "")) != "":
		goto("enter_game", [r.pack])
	if str(r.get("call", "")) != "" and r["call"] != "show_game_menu":
		goto(r["call"], r.get("args", []))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	event({"t": "returned", "call": r.get("call", ""), "ms": int((Time.get_unix_time_from_system() - float(r.get("at", 0))) * 1000)})
