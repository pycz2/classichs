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
	eq(Art.sets(), ["generated", "cartoon", "simple", "photo", "original", "my_set"], "the pack's sets first, then the player's folders")
	Packs.set_choice(Packs.active(), "art", "original")
	check(Art.texture("HERO_08") != null, "original picture used")
	check(Art.texture("HERO_01") != null, "no picture in this set: the pack's default set's (docs/packs/format.md §7)")
	Packs.set_choice(Packs.active(), "art", "my_set")
	check(Art.texture("HERO_09") != null, "the player's own set")
	Packs.set_choice(Packs.active(), "art", "no_such_set")
	check(Art.texture("HERO_01") != null, "an unknown set falls back to the generated pictures")
	Packs.set_choice(Packs.active(), "art", "generated")
	Art.root = was
	Art.reset()
	for path in ["/cards/HERO_01.jpg", "/original/HERO_08.jpg", "/my_set/HERO_09.jpg", "/cards", "/original", "/my_set", ""]:
		DirAccess.remove_absolute(root + path)


## framing.json (docs/packs/format.md §7) moves and zooms a picture in every window: Art.paint_in draws it
## on Art.square; a picture without framing covers the window, centred, as before.
func test_framing_moves_and_zooms_the_picture() -> void:
	var root := "user://test_art_framing"
	DirAccess.make_dir_recursive_absolute(root + "/my_set")
	var jpg := FileAccess.get_file_as_bytes("res://art/cards/HERO_08.jpg")
	for path in ["/my_set/HERO_08.jpg", "/my_set/HERO_09.jpg"]:
		var f := FileAccess.open(root + path, FileAccess.WRITE)
		f.store_buffer(jpg)
		f.close()
	var f := FileAccess.open(root + "/my_set/framing.json", FileAccess.WRITE)
	f.store_string('{"HERO_08": {"x": 0.1, "y": -0.05, "zoom": 1.5}}')
	f.close()
	var was := Art.root
	Art.root = root
	Art.reset()
	Packs.set_choice(Packs.active(), "art", "my_set")
	var hand := Rect2(10, 20, 100, 50)
	var side := maxf(hand.size.x, hand.size.y)
	var before := Rect2(hand.get_center() - Vector2(side, side) / 2.0, Vector2(side, side))  # paint_in's square until 0.73.0
	check(Art.texture("HERO_09") != null and Art.texture("HERO_08") != null, "both pictures from the player's folder")
	eq(Art.square(hand, "HERO_09"), before, "no framing: exactly as before")
	check(Art.square(hand, "HERO_08").is_equal_approx(Rect2(60 + 10 - 75, 45 - 5 - 75, 150, 150)), "moved right and up, zoomed: %s" % Art.square(hand, "HERO_08"))
	check(Art.square(Rect2(0, 0, 40, 40), "HERO_08").is_equal_approx(Rect2(20 + 4 - 30, 20 - 2 - 30, 60, 60)), "the same numbers in the board's oval")
	Packs.set_choice(Packs.active(), "art", "generated")
	Art.texture("HERO_08")
	eq(Art.square(hand, "HERO_08"), before, "the generated set has no framing of it")
	Art.root = was
	Art.reset()
	for path in ["/my_set/HERO_08.jpg", "/my_set/HERO_09.jpg", "/my_set/framing.json", "/my_set", ""]:
		DirAccess.remove_absolute(root + path)


## A pack's set: art/<set>/framing.json in the pack (tools/pack.py takes it along with the pictures).
func test_framing_of_a_packs_set() -> void:
	var classic: Pack = Packs.all().filter(func(p): return p.id() == Packs.CLASSIC and p.builtin())[0]
	var src := "user://test_framing_src.zip"
	var out := "user://test_framing_out.zip"
	var f := FileAccess.open(src, FileAccess.WRITE)
	f.store_buffer(FileAccess.get_file_as_bytes(classic.path))
	f.close()
	var r := ZIPReader.new()
	r.open(src)
	var w := ZIPPacker.new()
	w.open(out)
	for name in r.get_files():
		w.start_file(name)
		w.write_file(r.read_file(name))
		w.close_file()
	w.start_file("art/generated/framing.json")
	w.write_file('{"HERO_08": {"zoom": 2}}'.to_utf8_buffer())
	w.close_file()
	w.close()
	r.close()
	var p: Pack = Packs.install(FileAccess.get_file_as_bytes(out), "imported").get("pack")
	DirAccess.remove_absolute(src)
	DirAccess.remove_absolute(out)
	Packs.set_active(p)
	check(Art.texture("HERO_08") != null, "the pack's picture")
	eq(Art.square(Rect2(0, 0, 100, 50), "HERO_08"), Rect2(-50, -75, 200, 200), "zoomed twice")
	Packs.set_active(classic)
	Packs.remove(p)
	Art.texture("HERO_08")
	eq(Art.square(Rect2(0, 0, 100, 50), "HERO_08"), Rect2(0, -25, 100, 100), "the bundled pack frames none")


## The art set is chosen per game in the library (no longer in the settings).
func test_library_offers_art_sets() -> void:
	var root := "user://test_art_root2"
	for d in ["cards", "original"]:
		DirAccess.make_dir_recursive_absolute(root + "/" + d)
	var f := FileAccess.open(root + "/original/HERO_08.jpg", FileAccess.WRITE)  # a folder with the pack's cards
	f.store_buffer(FileAccess.get_file_as_bytes("res://art/cards/HERO_08.jpg"))
	f.close()
	var was := Art.root
	Art.root = root
	Art.reset()
	var s := SettingsView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	check(s.find_child("ArtSet", true, false) == null and s.find_child("MusicSet", true, false) == null, "not in the settings")
	s.free()
	var g := GamesView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	var pick := g.find_child("ArtSet", true, false) as OptionButton
	eq(pick.item_count, Art.sets().size(), "every picture set")
	pick.item_selected.emit(4)  # generated, cartoon, simple, photo (the pack's sets), then the player's folder
	eq(Packs.choice(Packs.active(), "art"), "original", "stored for this game")
	pick.item_selected.emit(0)
	eq(Settings.data.pack_sets[Packs.CLASSIC].art, "generated", "back")
	g.free()
	Art.root = was
	Art.reset()
	for d in ["/original/HERO_08.jpg", "/cards", "/original", ""]:
		DirAccess.remove_absolute(root + d)


func test_card_backs_are_chosen_in_the_settings() -> void:
	eq(Settings.data.card_back, CardBacks.DEFAULT, "default back")
	var s := SettingsView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	var pick := s.find_child("CardBack", true, false) as OptionButton
	eq(pick.item_count, CardBacks.NAMES.size(), "every back offered")
	check(CardBacks.NAMES.size() >= 3, "several neutral backs")
	for n in ["classic", "horde", "druid"]:
		check(not CardBacks.NAMES.has(n), n + ": a game's back, not offered")
	pick.item_selected.emit(2)
	eq(Settings.data.card_back, CardBacks.NAMES[2], "stored")
	Settings.load_settings()
	eq(Settings.data.card_back, CardBacks.NAMES[2], "kept after loading")
	pick.item_selected.emit(0)
	s.free()


func test_unknown_card_back_falls_back_to_the_default() -> void:
	var f := FileAccess.open(Settings.path, FileAccess.WRITE)
	f.store_string('{"card_back": "no_such_back"}')
	f.close()
	Settings.load_settings()
	eq(Settings.data.card_back, CardBacks.DEFAULT, "unknown back ignored")
