extends TestCase


func test_designs_follow_the_card() -> void:
	var want := {
		"VAN_CS2_029": ["spell", "fire", "projectile"],  # Fireball
		"VAN_CS2_032": ["spell", "fire", "area"],  # Flamestrike
		"VAN_CS2_022": ["spell", "arcane", "transform"],  # Polymorph
		"VAN_CS2_023": ["spell", "arcane", "draw"],  # Arcane Intellect
		"VAN_CS2_182": ["motif", "yeti"],  # Chillwind Yeti
		"VAN_CS2_168": ["motif", "murloc"],  # Murloc Raider
		"VAN_CS2_172": ["beast", "raptor"],  # Bloodfen Raptor
		"VAN_CS2_189": ["humanoid", "elf", "hunter"],  # Elven Archer
		"VAN_CS2_112": ["weapon", "axe"],  # Arcanite Reaper
		"HERO_08": ["hero", "MAGE"],
		"VAN_HERO_08bp": ["spell", "fire", "projectile"],  # Fireblast
	}
	for id in want:
		var d := Art.design(id)
		eq([d.kind] + d.subject, want[id], id)


func test_every_card_has_its_own_picture() -> void:
	var keys := {}
	var pairs := {}
	var shapes := {}
	for id in CardDb.all_ids():
		var d := Art.design(id)
		var k := Art.key(d)
		check(not keys.has(k), "%s and %s share the design %s" % [id, keys.get(k), k])
		keys[k] = id
		var pair := "%s|%s|%s" % [d.subject, d.scene, d.look]
		check(not pairs.has(pair), "%s and %s share subject and scene %s" % [id, pairs.get(pair), pair])
		pairs[pair] = id
		var sig := str(Art.shapes(id, Rect2(0, 0, 100, 70))).sha256_text()
		check(not shapes.has(sig), "%s and %s draw the same shapes" % [id, shapes.get(sig)])
		shapes[sig] = id


func test_every_card_draws_inside_its_rect() -> void:
	for rect in [Rect2(10, 20, 100, 70), Rect2(0, 0, 80, 80)]:
		var bounds: Rect2 = rect.grow(1.0)
		var start := Time.get_ticks_msec()
		for id in CardDb.all_ids():
			var shapes := Art.shapes(id, rect)
			if shapes.size() < 8:
				check(false, "too few shapes for " + id)
				continue
			for s in shapes:
				for p in Art.points(s):
					if not bounds.has_point(p):
						check(false, "%s: %s outside %s (%s)" % [id, p, rect, s[0]])
						break
		check(Time.get_ticks_msec() - start < 3000, "fast enough")


func test_same_card_same_art() -> void:
	eq(Art.shapes("VAN_CS2_182", Rect2(0, 0, 50, 50)), Art.shapes("VAN_CS2_182", Rect2(0, 0, 50, 50)), "deterministic")
