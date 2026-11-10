extends SceneTree
## Plays every card test (data/card_tests) and lists those that fail, then how many
## cards have tests. Usage: godot --headless --path . --script res://tools/check_card_tests.gd [-- <pack id>]
## A built-in pack's id (naxx-2014) plays the tests of that pack's cards (this run only: not saved).


func _process(_d: float) -> bool:
	var want := OS.get_cmdline_user_args()
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
