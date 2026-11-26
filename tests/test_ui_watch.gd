extends TestCase
## The UI watch debug mode (tools/ui_watch.gd, docs/ui-watch.md): the state it writes, its commands, a changed
## screen script reloaded and the screen built again, a broken one kept out.

const WATCH := preload("res://tools/ui_watch.gd")
const PROBE := "extends Control\nfunc _ready() -> void:\n\tvar l := Label.new()\n\tl.name = \"Probe\"\n\tl.text = \"%s\"\n\tadd_child(l)\n"


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## A main of one screen: the probe script's.
class FakeMain:
	extends Control
	var screen: Control
	var mode := ""
	var ui_watch: Node
	var path := ""

	func show_probe() -> void:
		if screen:
			remove_child(screen)
			screen.free()
		screen = load(path).new()
		add_child(screen)
		ui_watch.screen_set(screen, "show_probe", [])


func _dir(sub := "") -> String:
	var d := OS.get_user_data_dir().path_join("uiwatch_test").path_join(sub)
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))
	return d


func _watch(m: Node) -> Node:
	var w: Node = WATCH.new(m)
	w.dir = _dir()
	m.ui_watch = w
	m.add_child(w)
	return w


func _state(w: Node) -> Dictionary:
	w.write_state(true)
	return JSON.parse_string(FileAccess.get_file_as_string(w.dir.path_join("state.json")))


func _cmd(w: Node, c: Dictionary) -> void:
	var f := FileAccess.open(w.dir.path_join("cmd.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(c))
	f.close()
	w.poll_commands()


func _save(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_the_state_names_the_screen_its_call_and_its_controls() -> void:
	var m: Node = load("res://ui/main.tscn").instantiate()
	root().add_child(m)
	var w := _watch(m)
	m.show_library()
	var s := _state(w)
	eq([s.screen.type, s.screen.call], ["GamesView", "show_library"], "the screen and the call that opened it")
	check(s.seq >= 1, "a seq")
	eq(s.lang, "en")
	check(s.controls.any(func(c): return c.type == "Button" and c.get("text", "") != "" and c.rect.size() == 4),
		"its buttons with their texts and places")
	check(s.events.any(func(e): return e.t == "screen" and e.call == "show_library"), "the screen change is an event")
	var before := int(s.seq)
	eq(int(_state(w).seq), before + 1, "seq grows")
	var b: Button = m.screen.find_children("*", "Button", true, false).filter(func(x): return x.visible and x.text != "")[0]
	b.pressed.emit()
	check(_state(w).events.any(func(e): return e.t == "press" and e.text == b.text.strip_edges().left(80)), "a press is an event, with the button's text")
	m.free()


func test_commands_open_screens_switch_the_language_and_rebuild() -> void:
	var m: Node = load("res://ui/main.tscn").instantiate()
	root().add_child(m)
	var w := _watch(m)
	_cmd(w, {"goto": "show_settings"})
	check(m.screen is SettingsView, "goto opens the screen")
	check(not FileAccess.file_exists(w.dir.path_join("cmd.json")), "the command is taken")
	_cmd(w, {"goto": "enter_game", "args": [Packs.CLASSIC]})
	check(m.screen is MainMenu and not Packs.shell, "a game by its id")
	eq(_state(w).screen.call, "show_game_menu")
	var was: Control = m.screen
	_cmd(w, {"reload": true})
	check(m.screen is MainMenu and m.screen != was, "reload builds the screen again")
	was = m.screen
	_cmd(w, {"lang": "ru"})
	eq(TranslationServer.get_locale(), "ru")
	check(m.screen != was, "the screen again, in the language")
	eq(Settings.data.language, "en", "the settings stay")
	Locale.set_language("en")
	_cmd(w, {"shot": "x"})
	check(w.events.any(func(e): return e.t in ["shot", "shot_skipped"]), "a shot (skipped without a window)")
	_cmd(w, {"goto": "no_such_call"})
	check(w.events.back().t == "error", "an unknown call is told")
	m.show_menu(true)
	var ret: Dictionary = JSON.parse_string(w.restart_args()[-1])
	eq([ret.call, ret.args, ret.mode], ["show_menu", [true], ""], "a restart comes back by the same call")
	check("--ui-watch-return" in w.restart_args(), "and says so")
	eq([w.kind("res://ui/games_view.gd"), w.kind("res://ui/main.gd"), w.kind("res://game/settings.gd"), w.kind("res://data/i18n/ru.json")],
		["hot", "restart", "restart", "text"], "what a change needs")
	m.free()


func test_a_changed_screen_script_is_reloaded_and_a_broken_one_kept_out() -> void:
	allowed_errors = 1  # (the broken script's parse error)
	var d := _dir("probe")
	var core := _dir("core")
	var path := d.path_join("probe_view.gd")
	_save(path, PROBE % "one")
	_save(core.path_join("core.gd"), "extends RefCounted\n")
	var m := FakeMain.new()
	m.path = path
	root().add_child(m)
	var w: Node = WATCH.new(m)
	w.dir = _dir()
	w.hot_dirs = [d]
	w.dirs = [[d, ".gd"], [core, ".gd"]]
	w.files = []
	w.dry = true
	m.ui_watch = w
	m.add_child(w)
	m.show_probe()
	eq(m.screen.get_node("Probe").text, "one")
	_save(path, PROBE % "second")
	w.poll_files()
	eq(m.screen.get_node("Probe").text, "second", "the screen built again from the changed script")
	check(w.events.back().t == "reloaded" and w.events.back().rebuilt, "told, with the time")
	var was: Control = m.screen
	_save(path, "extends Control\nfunc _ready(:\n")
	w.poll_files()
	check(m.screen == was and m.screen.get_node("Probe").text == "second", "a broken script: the old screen stays")
	check(w.error.contains("probe_view.gd:2"), "the error says where: " + w.error)
	check(_state(w).error.contains("probe_view.gd:2"), "in the state too")
	check(w.find_child("UiWatchError", true, false) != null, "shown in red")
	_save(path, PROBE % "third")
	w.poll_files()
	eq([m.screen.get_node("Probe").text, w.error], ["third", ""], "fixed: reloaded, the error gone")
	check(w.find_child("UiWatchError", true, false) == null, "the red note gone")
	_save(core.path_join("core.gd"), "extends RefCounted\nvar x := 1\n")
	w.poll_files()
	check(w.events.back().t == "restart" and w.events.back().why.contains("core.gd"), "a core file starts the game again")
	m.free()
