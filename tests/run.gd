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


func _init() -> void:
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
			t.call(name)
			if errors.count > before:
				t.failures.append("script error: " + errors.last)
			if t.failures.is_empty():
				continue
			failed += 1
			print("FAIL %s:%s" % [f, name])
			for msg in t.failures:
				print("    " + msg)
	print("%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 or total == 0 else 0)
