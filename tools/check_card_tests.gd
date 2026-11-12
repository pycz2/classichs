extends SceneTree
## Plays every card test (data/card_tests) and lists those that fail, then how many
## cards have tests. Usage: godot --headless --path . --script res://tools/check_card_tests.gd [-- <pack id>]
## A built-in pack's id (naxx-2014) plays the tests of that pack's cards (this run only: not saved); a .cardpack file
## (build/packs/icc.cardpack: an expansion) is installed into the run's user dir and played (use TEST_USER_DIR).
## TEST_USER_DIR (a folder under the data dir, as tests/run.gd takes it) keeps user:// apart from the game's.


func _init() -> void:
	var own := OS.get_environment("TEST_USER_DIR")
	if own != "":
		ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
		ProjectSettings.set_setting("application/config/custom_user_dir_name", own)
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())


func _process(_d: float) -> bool:
	var want := OS.get_cmdline_user_args()
	for a in want:  # a .cardpack file (an expansion of build/packs) is installed into this run's user dir first
		if a.ends_with(".cardpack"):
			var r := Packs.install_file(a)
			if r.has("error"):
				print("%s: %s" % [a, r.error])
				quit(1)
				return true
			want.append(r.pack.id())
	for p in Packs.all():
		if want.has(p.id()):
			Packs._active = p
			Packs._changed()
	print("pack: %s" % Packs.active().id())
	var tests := CardTests.load_all()
	var bad := 0
	var n := 0
	for id in tests:
		if not CardDb.card(id):
			print("%s: unknown card" % id)
			bad += 1
			continue
		for t in tests[id]:
			n += 1
			for k in ["kind", "title", "scene", "steps"]:
				if not t.has(k):
					print("%s %s: no \"%s\"" % [id, t.get("kind", "?"), k])
					bad += 1
			var r := CardTests.run(t)
			if r.match:
				r.match.free()
			if r.error != "":
				print("%s %s: step %d: %s" % [id, t.get("kind", "?"), r.step, r.error])
				bad += 1
	var all := CardDb.all_ids()
	var covered := all.filter(func(id): return tests.has(id))
	print("%d tests for %d of %d cards; %d problems" % [n, covered.size(), all.size(), bad])
	quit()
	return true
