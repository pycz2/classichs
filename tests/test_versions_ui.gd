extends TestCase
## A pack with versions in the games library (game/versions.gd, ui/versions_view.gd): the version shown and chosen,
## the versions by era, and Compare versions: every card that differs between two versions, drawn as in each.

const ERAS := "res://build/packs/eras.cardpack"  # tools/build_packs.sh (./run_tests.sh builds it)


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## Hearthstone 2014–2019 straight from its file (not installed).
func _eras() -> Pack:
	var p := Pack.open(ProjectSettings.globalize_path(ERAS), "imported")
	check(p != null, ERAS + " (tools/build_packs.sh)")
	return p


## Hearthstone 2014–2019 installed (the library lists it).
func _installed() -> Pack:
	var r := Packs.install(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(ERAS)), "imported")
	check(r.has("pack"), "installed: " + str(r))
	return r.get("pack")


## A version of the test: 6485 with one card taken out and a new collectible one.
func _test_version(p: Pack) -> Pack:
	var b := p.version_view("6485")
	var cards: Array = b.cards().duplicate(true).filter(func(c): return c.id != "VAN_EX1_009")  # Angry Chicken
	var yeti: Dictionary = cards.filter(func(c): return c.id == "VAN_CS2_182")[0].duplicate()
	yeti.id = "TEST_NEW"
	cards.append(yeti)
	b._json["cards.json"] = cards
	var en: Dictionary = b.locale("en").duplicate(true)
	en.cards["TEST_NEW"] = {"name": "Test Yeti", "text": ""}
	en.cards["VAN_EX1_116"].text = "[x]" + en.cards["VAN_EX1_116"].text.replace(". ", ".\n  ")  # (only its line breaks)
	b._json["locales/en.json"] = en
	return b


func test_the_diff_of_6024_and_6485_is_leeroy_jenkins_and_starving_buzzard() -> void:
	var p := _eras()
	if p == null:
		return
	var d := Versions.diff(p.version_view("6024"), p.version_view("6485"), "en")
	eq(d.changed.map(func(c): return [c.id, c.fields]), [["VAN_EX1_116", ["cost"]],
		["VAN_CS2_237", ["cost", "attack", "health"]]], "Leeroy Jenkins and Starving Buzzard, nothing else")
	# the texts are the player's language: the English one of Starving Buzzard stayed, the Italian one changed
	eq(Versions.diff(p.version_view("6024"), p.version_view("6485"), "it").changed.map(func(c): return [c.id, c.fields]),
		[["VAN_CS2_237", ["cost", "attack", "health", "text"]], ["VAN_EX1_116", ["cost"]]], "in Italian (by name: Condor Affamato)")
	eq([d.changed[0].a.cost, d.changed[0].b.cost], [4.0, 5.0], "Leeroy Jenkins: cost 4 -> 5")
	eq([d.added, d.removed], [[], []], "no card added or removed")
	eq(Versions.diff(p.version_view("6485"), p.version_view("6485")).changed, [], "a version is itself")
	eq(Versions.label(p, "6485"), "Leeroy Jenkins and Starving Buzzard nerfed, 2014-09-22", "a version's name and date")
	var eras := Versions.eras(p)
	eq(eras.map(func(e): return [e.id, e.name, e.from, e.to, e.versions.size()]),
		[["naxx", "Curse of Naxxramas", "2014-07-22", "2014-09-22", 2]], "the versions by era")
	p.close()


func test_added_and_removed_cards() -> void:
	var p := _eras()
	if p == null:
		return
	var d := Versions.diff(p.version_view("6485"), _test_version(p), "en")
	eq(d.added.map(func(c): return c.id), ["TEST_NEW"], "the new card")
	eq(d.removed.map(func(c): return c.id), ["VAN_EX1_009"], "the card taken out")
	eq(d.changed, [], "nothing else (new line breaks of a text are no change)")
	var back := Versions.diff(_test_version(p), p.version_view("6485"), "en")
	eq([back.added.map(func(c): return c.id), back.removed.map(func(c): return c.id)], [["VAN_EX1_009"], ["TEST_NEW"]],
		"the other way round")
	var v := VersionsView.new()
	v.pack = p
	root().add_child(v)
	v.compare(p.version_view("6485"), _test_version(p))
	eq((v.find_child("Summary", true, false) as Label).text, "0 changed, 1 added, 1 removed", "the summary")
	check(v.find_child("Added_TEST_NEW", true, false) != null and v.find_child("Removed_VAN_EX1_009", true, false) != null,
		"the sections show the cards")
	v.free()
	p.close()


func test_choosing_a_version_in_the_library() -> void:
	var p := _installed()
	if p == null:
		return
	var g := GamesView.new()
	root().add_child(g)
	g.select(p)
	eq((g.find_child("VersionName", true, false) as Label).text, "Version: Leeroy Jenkins and Starving Buzzard nerfed, 2014-09-22",
		"the version played")
	check(g.find_child("FormatSlot", true, false) != null, "a place for the mode (Standard, Wild)")
	(g.find_child("ChooseVersion", true, false) as Button).pressed.emit()
	var v: VersionsView = g.find_child("Versions", true, false)
	check(v != null, "the version choice opens")
	eq((v.find_child("Era_naxx", true, false) as Label).text, "Curse of Naxxramas", "versions by era")
	check(v.find_child("Version_6485", true, false).chosen and not v.find_child("Version_6024", true, false).chosen, "the chosen one marked")
	(v.find_child("Version_6024", true, false) as Button).pressed.emit()
	eq(Packs.version(p), "6024", "chosen")
	eq(Settings.data.pack_versions.get("hs-eras"), "6024", "remembered")
	check(v.find_child("Version_6024", true, false).chosen, "marked")
	(v.find_child("Back", true, false) as Button).pressed.emit()
	check(g.find_child("Versions", true, false) == null or g.find_child("Versions", true, false).is_queued_for_deletion(), "closed")
	eq((g.find_child("VersionName", true, false) as Label).text, "Version: Curse of Naxxramas, 2014-07-22", "the library shows it")
	Packs.set_active(p)
	eq(Packs.active().version_id, "6024", "the game plays it")
	var m := MainMenu.new()
	m.pack = Packs.active()
	root().add_child(m)
	eq((m.find_child("GameVersion", true, false) as Label).text, "Curse of Naxxramas, 2014-07-22", "the game's menu names it")
	m.free()
	g.free()
	Packs.set_active(Packs.all()[0])
	Settings.data.pack_versions.erase("hs-eras")


func test_compare_versions_lists_filters_and_goes_back() -> void:
	var p := _eras()
	if p == null:
		return
	Settings.data.pack_versions = {"hs-eras": "6485"}
	var v := VersionsView.new()
	v.pack = p
	root().add_child(v)
	(v.find_child("Compare", true, false) as Button).pressed.emit()
	eq([v.a.version_id, v.b.version_id], ["6024", "6485"], "the previous version and the chosen one")
	eq((v.find_child("Summary", true, false) as Label).text, "2 changed, 0 added, 0 removed", "the summary")
	var leeroy: Control = v.find_child("Change_VAN_EX1_116", true, false)
	check(leeroy != null, "Leeroy Jenkins' row")
	if leeroy:
		var old: CardView = leeroy.find_child("Old", true, false)
		var new: CardView = leeroy.find_child("New", true, false)
		eq([old.pack.version_id, new.pack.version_id], ["6024", "6485"], "each card as in its version")
		CardDb.begin(new.pack)
		eq(CardDb.card("VAN_EX1_116").cost, 5, "drawn from 6485")
		check(Art.texture("FP1_001") != null, "with its pack's pictures (a Naxxramas card)")
		CardDb.end()
		eq([CardDb.card("VAN_EX1_116").cost, CardDb.has("FP1_001")], [4, false], "the active pack's cards stay (Classic)")
		eq(old.get_child(0).fields, ["cost"], "its cost marked")
	var field: OptionButton = v.find_child("FieldFilter", true, false)
	field.select(Array(range(field.item_count)).map(field.get_item_text).find("Attack"))
	field.item_selected.emit(field.selected)
	eq(v.shown().changed.map(func(c): return c.id), ["VAN_CS2_237"], "only the Attack changes")
	field.select(0)
	field.item_selected.emit(0)
	var search: LineEdit = v.find_child("Search", true, false)
	search.text_changed.emit("leeroy")
	eq(v.shown().changed.map(func(c): return c.id), ["VAN_EX1_116"], "found by name")
	search.text_changed.emit("")
	var cls: OptionButton = v.find_child("ClassFilter", true, false)
	cls.select(Array(range(cls.item_count)).map(cls.get_item_text).find("Hunter"))
	cls.item_selected.emit(cls.selected)
	eq(v.shown().changed.map(func(c): return c.id), ["VAN_CS2_237"], "a class")
	(v.find_child("Back", true, false) as Button).pressed.emit()
	eq(v.page, "choose", "Back: the version choice")
	v.free()
	Settings.data.pack_versions.erase("hs-eras")
	p.close()


## Hundreds of changes (every card's cost): only the rows in view are made; scrolling makes the others.
func test_a_long_diff_makes_only_the_rows_in_view() -> void:
	var p := _eras()
	if p == null:
		return
	var b := p.version_view("6485")
	var cards: Array = b.cards().duplicate(true)
	for c in cards:
		c.cost = int(c.get("cost", 0)) + 1
	b._json["cards.json"] = cards
	var v := VersionsView.new()
	v.pack = p
	root().add_child(v)
	v.compare(p.version_view("6485"), b)
	eq(v.shown().changed.size(), cards.size(), "every card changed")
	var rows: Control = v.find_child("Rows", true, false)
	check(rows.get_child_count() < 12, "only the rows in view: %d" % rows.get_child_count())
	var scroll: ScrollContainer = v.find_child("DiffList", true, false)
	for i in 2:  # (the list takes its size)
		await (Engine.get_main_loop() as SceneTree).process_frame
	scroll.scroll_vertical = int(rows.custom_minimum_size.y)
	v._fill_rows()
	var last: Dictionary = v.shown().changed[-1]
	check(v.find_child("Change_" + last.id, true, false) != null, "the last one after scrolling")
	check(rows.get_child_count() < 12, "and the first ones are gone")
	v.free()
	p.close()


## The screens at the game's size and a phone's (the whole game in view), with no errors.
func test_the_screens_at_desktop_and_phone_sizes() -> void:
	var p := _installed()
	if p == null:
		return
	var was := TouchInput.phone
	var size0 := root().size
	for phone in [false, true]:
		TouchInput.phone = phone
		var m: Node = load("res://ui/main.tscn").instantiate()
		root().add_child(m)
		for size in [Vector2i(1280, 720), Vector2i(2400, 1080), Vector2i(2484, 1116), Vector2i(2440, 2268)]:
			root().size = size
			var g: GamesView = m.show_library()
			g.select(p)
			(g.find_child("ChooseVersion", true, false) as Button).pressed.emit()
			var v: VersionsView = g.find_child("Versions", true, false)
			eq(v.size, Vector2(1280, 720), "the version choice fills the screen at %s" % size)
			(v.find_child("Compare", true, false) as Button).pressed.emit()
			check(v.find_child("Change_VAN_EX1_116", true, false) != null, "the comparison at %s" % size)
			(v.find_child("From", true, false) as Button).pressed.emit()
			eq(v.page, "from", "the first version's choice")
			(v.find_child("Version_6485", true, false) as Button).pressed.emit()
			eq([v.page, v.a.version_id], ["compare", "6485"], "picked")
			eq((v.find_child("Summary", true, false) as Label).text, "0 changed, 0 added, 0 removed", "the same version")
		m.free()
	root().size = size0
	TouchInput.phone = was
