extends TestCase


func test_motifs_follow_name_race_type_and_class() -> void:
	var want := {"VAN_CS2_029": "fire", "VAN_CS2_024": "ice", "VAN_CS2_022": "sheep", "VAN_CS2_182": "yeti",
		"VAN_CS2_168": "murloc", "VAN_CS2_112": "axe", "VAN_CS2_172": "paw", "VAN_HERO_08bp": "fire",
		"HERO_08": "arcane", "HERO_01": "shield", "VAN_EX1_298": "fire", "VAN_CS2_189": "bow"}
	for id in want:
		eq(Art.motif(id), want[id], id)


func test_every_card_draws_inside_its_rect() -> void:
	var rect := Rect2(10, 20, 100, 70)
	var bounds := rect.grow(1.0)
	var start := Time.get_ticks_msec()
	var motifs := {}
	for id in CardDb.all_ids():
		var shapes := Art.shapes(id, rect)
		motifs[Art.motif(id)] = true
		if shapes.size() < 3:
			check(false, "too few shapes for " + id)
			continue
		for s in shapes:
			for p in Art.points(s):
				if not bounds.has_point(p):
					check(false, "%s: %s outside (%s)" % [id, p, s[0]])
					break
	check(Time.get_ticks_msec() - start < 1500, "fast enough")
	check(motifs.size() >= 25, "varied motifs: %d" % motifs.size())


func test_same_card_same_art() -> void:
	eq(Art.shapes("VAN_CS2_182", Rect2(0, 0, 50, 50)), Art.shapes("VAN_CS2_182", Rect2(0, 0, 50, 50)), "deterministic")
