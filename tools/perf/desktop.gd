extends SceneTree
## The performance harness on desktop: the game (ui/main.tscn) in a user:// of its own (PERF_USER_DIR, a
## folder under the data dir; default classichs-perf/desktop), so the player's own files are never touched,
## with the game's arguments after "--": --perf (the log, written to that user://perf/) and --drive
## --server=ws://127.0.0.1:PORT --user=NAME (tools/perf_drive.gd plays tournaments).
## godot --path . --script res://tools/perf/desktop.gd -- --perf --drive --server=… --user=…

var _started := false


func _init() -> void:
	var own := OS.get_environment("PERF_USER_DIR")
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", own if own != "" else "classichs-perf/desktop")
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	print("user dir: ", OS.get_user_data_dir())


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		root.add_child(load("res://ui/main.tscn").instantiate())
	return false
