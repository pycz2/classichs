extends SceneTree


class ErrorCounter extends Logger:
	var count := 0
	var last := ""

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		count += 1
		last = "%s (%s:%d) %s" % [rationale if rationale != "" else code, file, line, function]


var _started := false
var _progress := OS.get_environment("TEST_PROGRESS")


## tools/run_tests.py runs several of these at once, each with its own user:// (TEST_USER_DIR: a folder
## under OS.get_data_dir()), set here before any test touches user://.
func _init() -> void:
	var own := OS.get_environment("TEST_USER_DIR")
	if own != "":
		ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
		ProjectSettings.set_setting("application/config/custom_user_dir_name", own)
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())


## TEST_PROGRESS: a file that holds this process's user:// and the test running now (a hung run names it).
func _report(now: String) -> void:
	if _progress != "":
		var f := FileAccess.open(_progress, FileAccess.WRITE)
		f.store_string(OS.get_user_data_dir() + "\n" + now + "\n")
		f.close()


## Tests run in the first frame: only then is root inside the tree, so UI tests
## can add nodes and get _ready() calls.
func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_all()
	return false


## Every test starts on test files, even if an earlier test pointed a path at the player's real file.
func _use_test_files() -> void:
	Settings.path = "user://test_runner_settings.json"
	Profile.path = "user://test_runner_profile.json"
	DeckStore.path = "user://test_runner_decks.json"
	Progress.path = "user://test_runner_tutorial.json"
	ServerLink.session_path = "user://test_runner_server_session.json"
	Replay.dir = "user://test_runner_replays"
	DirAccess.remove_absolute(ServerLink.session_path)  # no saved session: main never connects by itself
	Packs.set_shell(false)  # (main shows its own screens in the client's look; tests see the active pack's)
	Packs.server_sets = {}
	DeckStore.link = null
	if Packs.user_dir != "user://test_runner_packs" or Packs.active() == null or Packs.active().id() != Packs.CLASSIC:
		Packs.user_dir = "user://test_runner_packs"  # downloaded and imported packs of the tests; Classic active
		Settings.data.erase("pack")
		Packs.rescan()
	# Every test starts with the built-in packs only: a pack an earlier test of this process left installed
	# changed what the next one saw (which tests share a process depends on the run's balance).
	for p in Packs.all():
		if p.origin != "builtin":
			Packs.remove(p)
	_player_decks()


## The tests' player has saved Classic's ten template decks (no game puts ready decks into a
## list any more: a test of an empty list deletes the file).
func _player_decks() -> void:
	DirAccess.remove_absolute("user://test_runner_decks.neon.json")
	DeckStore.write(DeckStore.file(), Decks.templates().map(func(t):
		var d: Dictionary = t.deck.to_dict()
		d.name = t.name
		return d))


func _fresh_settings() -> void:
	Settings.path = "user://test_runner_settings.json"
	var sf := FileAccess.open(Settings.path, FileAccess.WRITE)
	sf.store_string(JSON.stringify({"language": "en", "music": 0.0, "sfx": 0.0, "layout": Migration.LAYOUT}))
	sf.close()


## TEST_LIST (run_tests.py's first process): every test as "file:method" into that file, one a line
## ("file" alone for a file that does not load: whoever runs it says why).
func _list(files: Array, path: String) -> void:
	var out := PackedStringArray()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			out.append(f)
			continue
		for m in script.get_script_method_list():
			if m.name.begins_with("test_"):
				out.append(f + ":" + m.name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(out) + "\n")
	file.close()


func _run_all() -> void:
	Anim.instant = true  # tests never wait for animations
	# Tests never read the player's real settings and always run in English.
	_fresh_settings()
	Locale.load_all()
	var args := OS.get_cmdline_user_args()
	var filter: String = args[0] if args.size() > 0 else ""
	var files := Array(DirAccess.get_files_at("res://tests")).filter(
		func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	if OS.get_environment("TEST_LIST") != "":
		_list(files, OS.get_environment("TEST_LIST"))
	# run_tests.py: this process's share, "file" (all its tests) or "file:method", space-separated
	var only := OS.get_environment("TEST_ONLY").split(" ", false)
	if not only.is_empty():
		files = files.filter(func(f: String) -> bool: return f in only or Array(only).any(func(x): return x.begins_with(f + ":")))
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var total := 0
	var failed := 0
	for f in files:
		_report(f + " (loading)")
		var load_errors := errors.count
		var script: GDScript = load("res://tests/" + f)
		if script == null or errors.count > load_errors or not script.can_instantiate():
			total += 1
			failed += 1
			print("FAIL %s: cannot load (%s)" % [f, errors.last])
			continue
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (f + ":" + name).contains(filter):
				continue
			if not only.is_empty() and not (f in only or (f + ":" + name) in only):
				continue
			var started := Time.get_ticks_msec()
			total += 1
			_report(f + ":" + name)
			var before := errors.count
			var t: TestCase = script.new()
			_use_test_files()
			_fresh_settings()  # (a test may have saved its own)
			Settings.load_settings()
			Locale.set_language("en")
			t.call(name)
			H.cleanup()
			if errors.count > before + t.allowed_errors:
				t.failures.append("script error: " + errors.last)
			if _progress != "":
				print("TIME %s:%s %d" % [f, name, Time.get_ticks_msec() - started])  # (run_tests.py shares the tests by these)
			if t.failures.is_empty():
				continue
			failed += 1
			print("FAIL %s:%s" % [f, name])
			for msg in t.failures:
				print("    " + msg)
	_report("(done)")
	print("%d tests, %d failed" % [total, failed])
	_use_test_files()
	for path in [Settings.path, Profile.path, DeckStore.path, Progress.path]:
		DirAccess.remove_absolute(path)
	OS.remove_logger(errors)
	quit(1 if failed > 0 or total == 0 else 0)
