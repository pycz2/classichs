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
	DirAccess.remove_absolute(ServerLink.session_path)  # no saved session: main never connects by itself


func _run_all() -> void:
	Anim.instant = true  # tests never wait for animations
	# Tests never read the player's real settings and always run in English.
	Settings.path = "user://test_runner_settings.json"
	var sf := FileAccess.open(Settings.path, FileAccess.WRITE)
	sf.store_string(JSON.stringify({"language": "en", "music": 0.0, "sfx": 0.0}))
	sf.close()
	Locale.load_all()
	var args := OS.get_cmdline_user_args()
	var filter: String = args[0] if args.size() > 0 else ""
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var files := Array(DirAccess.get_files_at("res://tests")).filter(
		func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	var total := 0
	var failed := 0
	for f in files:
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
			total += 1
			var before := errors.count
			var t: TestCase = script.new()
			_use_test_files()
			Settings.load_settings()
			Locale.set_language("en")
			t.call(name)
			H.cleanup()
			if errors.count > before:
				t.failures.append("script error: " + errors.last)
			if t.failures.is_empty():
				continue
			failed += 1
			print("FAIL %s:%s" % [f, name])
			for msg in t.failures:
				print("    " + msg)
	print("%d tests, %d failed" % [total, failed])
	_use_test_files()
	for path in [Settings.path, Profile.path, DeckStore.path, Progress.path]:
		DirAccess.remove_absolute(path)
	OS.remove_logger(errors)
	quit(1 if failed > 0 or total == 0 else 0)
