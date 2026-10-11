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


func test_generated_illustrations_load_when_present() -> void:
	check(Art.texture("HERO_08") != null, "Jaina has an illustration")
	eq(Art.texture("NO_SUCH_CARD"), null, "missing: drawn art instead")
	eq(Art.outline("oval", Rect2(0, 0, 100, 50)).size(), 32, "oval outline")


func test_art_sets_are_folders_and_switch_pictures() -> void:
	var root := "user://test_art_root"
	for d in ["cards", "original", "my_set"]:
		DirAccess.make_dir_recursive_absolute(root + "/" + d)
	var jpg := FileAccess.get_file_as_bytes("res://art/cards/HERO_08.jpg")
	for path in ["/cards/HERO_01.jpg", "/original/HERO_08.jpg", "/my_set/HERO_09.jpg"]:
		var f := FileAccess.open(root + path, FileAccess.WRITE)
		f.store_buffer(jpg)
		f.close()
	var was := Art.root
	Art.root = root
	Art.reset()
	eq(Art.sets(), ["generated", "original", "my_set"], "built-in sets first, then the player's folders")
	Settings.data.art = "original"
	Art.reset()
	check(Art.texture("HERO_08") != null, "original picture used")
	eq(Art.texture("HERO_01"), null, "no picture in this set: drawn placeholder")
	Settings.data.art = "my_set"
	Art.reset()
	check(Art.texture("HERO_09") != null, "the player's own set")
	Settings.data.art = "no_such_set"
	Art.reset()
	check(Art.texture("HERO_01") != null, "an unknown set falls back to the generated pictures")
	Settings.data.art = "generated"
	Art.root = was
	Art.reset()
	for path in ["/cards/HERO_01.jpg", "/original/HERO_08.jpg", "/my_set/HERO_09.jpg", "/cards", "/original", "/my_set", ""]:
		DirAccess.remove_absolute(root + path)


func test_settings_screen_offers_art_sets() -> void:
	var s := SettingsView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	var pick := s.find_child("ArtSet", true, false) as OptionButton
	eq(pick.item_count, Art.sets().size(), "every picture set")
	pick.item_selected.emit(1)
	eq(Settings.data.art, "original", "stored")
	pick.item_selected.emit(0)
	eq(Settings.data.art, "generated", "back")
	s.free()
