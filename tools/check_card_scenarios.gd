extends SceneTree
## Builds every generic scenario (game/card_scenarios.gd) of every card of every pack (res://packs and
## build/packs, or the packs named: classic dal …) and lists the scenes the engine refuses. With --play it also
## plays each scenario's steps and counts the ones that stop, by kind (a step not legal there).
## Usage: godot --headless --path . --script res://tools/check_card_scenarios.gd [-- [--play] [pack file names]]
## TEST_USER_DIR (a folder under the data dir, as tests/run.gd takes it) keeps user:// apart from the game's.


func _init() -> void:
	var own := OS.get_environment("TEST_USER_DIR")
	if own != "":
		ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
		ProjectSettings.set_setting("application/config/custom_user_dir_name", own)
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())


func _process(_d: float) -> bool:
	var args := OS.get_cmdline_user_args()
	var play := args.has("--play")
	var bad := 0
	for f in pack_files():
		if args.size() > int(play) and not args.has(f.get_file().get_basename()):
			continue
		var p := Pack.open(f, "imported")
		if p == null:
			print("%s: cannot open" % f)
			bad += 1
			continue
		Packs._active = p
		Packs._changed()
		var n := 0
		var stops := {}
		var t0 := Time.get_ticks_msec()
		for id in CardDb.all_ids():
			for t in CardScenarios.generic(id):
				n += 1
				var why := Rules.scenario_error(t.scene)
				if why != "":
					print("%s %s %s: %s" % [p.id(), id, t.key, why])
					bad += 1
				elif play:
					var r := CardTests.run(t)
					if r.match:
						r.match.free()
					if r.error != "":
						stops[t.kind] = stops.get(t.kind, []) + ["%s (%s)" % [id, r.error.left(80)]]
		print("%s: %d cards, %d scenarios, %d ms" % [p.id(), CardDb.all_ids().size(), n, Time.get_ticks_msec() - t0])
		for k in stops:
			print("  %s: %d stop, e.g. %s" % [k, stops[k].size(), ", ".join(stops[k].slice(0, 3))])
	print("%d problems" % bad)
	quit(1 if bad > 0 else 0)
	return true


## Every pack file: the built-in ones and the expansions tools/build_packs.sh puts into build/packs.
static func pack_files() -> Array:
	var out := []
	for dir in ["res://packs", ProjectSettings.globalize_path("res://build/packs")]:
		for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else []:
			if f.ends_with(".cardpack"):
				out.append(dir.path_join(f))
	return out
