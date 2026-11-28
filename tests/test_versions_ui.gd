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
	# (only its markup: bold and italics, non-breaking spaces, no final period)
	var archer: String = en.cards["VAN_CS2_189"].text
	en.cards["VAN_CS2_189"].text = "<i>" + archer.replace("<b>", "").replace("</b>", "").replace(" ", "\u00a0").trim_suffix(".").replace("Deal", "<b>Deal</b>") + "</i>"
	b._json["locales/en.json"] = en
	return b


func test_the_diff_of_6024_and_6485_is_leeroy_jenkins_and_starving_buzzard() -> void:
	var p := _eras()
	if p == null:
		return
	var d := Versions.diff(p.version_view("6024"), p.version_view("6485"), "en")
	var stats: Array = d.changed.filter(func(c): return c.fields != ["text"])
	eq(stats.map(func(c): return [c.id, c.fields]), [["VAN_EX1_116", ["cost"]],
		["VAN_CS2_237", ["cost", "attack", "health"]]], "Leeroy Jenkins and Starving Buzzard; the rest only the build's texts")
	# the texts are the player's language: the English one of Starving Buzzard stayed, the Italian one changed
	var it: Array = Versions.diff(p.version_view("6024"), p.version_view("6485"), "it").changed
	eq(it.filter(func(c): return c.id == "VAN_CS2_237").map(func(c): return c.fields),
		[["cost", "attack", "health", "text"]], "in Italian Starving Buzzard's text changed too")
	var leeroy: Dictionary = stats[0]
	eq([leeroy.a.cost, leeroy.b.cost], [4.0, 5.0], "Leeroy Jenkins: cost 4 -> 5")
	eq([d.added, d.removed], [[], []], "no card added or removed")
	eq(Versions.diff(p.version_view("6485"), p.version_view("6485")).changed, [], "a version is itself")
	eq(Versions.label(p, "6485"), "Leeroy Jenkins and Starving Buzzard nerfed, 2014-09-22", "a version's name and date")
	var eras := Versions.eras(p)
	eq(eras.filter(func(e): return e.id == "naxx").map(func(e): return [e.id, e.name, e.from, e.to, e.versions.size()]),
		[["naxx", "Curse of Naxxramas", "2014-07-22", "2014-09-22", 2]], "the versions by era (the other eras' versions come and go)")
	p.close()


func test_texts_are_compared_without_their_markup() -> void:
	var t := "<b>Battlecry:</b> Deal 1 damage."
	for same in ["Battlecry: Deal 1 damage", "[x]<b>Battlecry:</b>\nDeal\u00a01\u202fdamage.", "<i>Battlecry:  Deal 1 damage.</i> ",
			"Battlecry:\u2009Deal 1\u2007damage."]:
		eq(Versions.plain(same), Versions.plain(t), "the same text: " + same.c_escape())
	eq(Versions.plain(t), "Battlecry: Deal 1 damage", "as plain text")
	check(Versions.plain("Deal 2 damage.") != Versions.plain(t), "another text differs")
	eq(Versions.plain("Costs $3 (#2)."), "Costs $3 (#2)", "numbers kept")


func test_added_and_removed_cards() -> void:
	var p := _eras()
	if p == null:
		return
	var d := Versions.diff(p.version_view("6485"), _test_version(p), "en")
	eq(d.added.map(func(c): return c.id), ["TEST_NEW"], "the new card")
	eq(d.removed.map(func(c): return c.id), ["VAN_EX1_009"], "the card taken out")
	eq(d.changed, [], "nothing else (new line breaks or markup of a text are no change)")
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


func _press(parent: Node, button_name: String) -> void:
	var b := parent.find_child(button_name, true, false) as Button
	check(b != null and b.is_visible_in_tree() and not b.disabled, button_name + " shown")
	if b:
		b.pressed.emit()


## The library -> the game's Versions (by era) -> Play this version: a game of its own (its menu, its look, no other
## version to switch to); Leave the game: the Versions again (Compare versions there); Back: the library.
func test_a_version_is_entered_from_the_versions_screen() -> void:
	var p := _installed()
	if p == null:
		return
	var m: Node = load("res://ui/main.tscn").instantiate()
	root().add_child(m)
	var g: GamesView = m.show_library()
	g.select(p)
	for n in ["VersionName", "ChooseVersion", "CompareVersions", "FormatSlot"]:
		check(g.find_child(n, true, false) == null, "no version line or choice in the library: " + n)
	_press(g, "Activate")
	var v := m.screen as VersionsView
	check(v != null, "the game opens its versions")
	if v == null:
		m.free()
		return
	eq([v.page, (v.find_child("Title", true, false) as Label).text], ["choose", "Versions"], "the Versions screen")
	eq((v.find_child("Era_naxx", true, false) as Label).text, "Curse of Naxxramas", "versions by era")
	check(Packs.shell, "the client's own look until a version is entered")
	check(v.find_child("Version_" + p.default_version(), true, false).chosen, "the last played one chosen (none yet: the default)")
	_press(v, "Version_6024")
	check(v.find_child("Version_6024", true, false).chosen and not v.find_child("Version_" + p.default_version(), true, false).chosen,
		"the one pressed is chosen")
	eq(Packs.version(p), p.default_version(), "nothing played before Play")
	_press(v, "PlayVersion")
	var menu := m.screen as MainMenu
	check(menu != null and not Packs.shell, "Play this version: its menu, in its look")
	eq([Packs.active().whole(), Packs.active().version_id, Packs.look()], [p, "6024", Packs.active()], "the version is the active game")
	eq(Settings.data.pack_versions.get(p.id()), "6024", "remembered")
	if menu:
		eq((menu.find_child("GameVersion", true, false) as Label).text, "Curse of Naxxramas, 2014-07-22", "the menu names it")
		for b in menu.find_children("*", "Button", true, false):
			check(not str(b.name).contains("Version") or b.name == "Version", "no version to switch to inside: " + b.name)
		_press(menu, "LeaveTheGame")
	v = m.screen as VersionsView
	check(v != null and v.find_child("Version_6024", true, false).chosen, "leaving the version: the Versions, it chosen")
	_press(v, "Compare")
	eq([v.page, v.b.version_id], ["compare", "6024"], "Compare versions: the one before the chosen one and it")
	_press(v, "From")
	_press(v, "Version_" + p.default_version())
	eq(v.a.version_id, p.default_version(), "any two versions")
	_press(v, "Back")
	eq([m.screen, v.page], [v, "choose"], "Back: the Versions")
	_press(v, "Back")
	check(m.screen is GamesView, "Back: the library")
	m.free()
	Packs.set_active(Packs.all()[0])
	Settings.data.pack_versions.erase(p.id())


## Decks are kept per version (decks.<pack id>.<version>.json); the old Classic decks (decks.json) are copied once
## into 5314, the old file kept.
func test_decks_per_version_and_the_old_classic_decks() -> void:
	var p := _installed()
	if p == null:
		return
	var before := FileAccess.get_file_as_string(DeckStore.path)  # (the other tests' Classic decks)
	DeckStore.write(DeckStore.path, [{"name": "My old Classic deck", "hero": "HERO_08", "cards": []}])
	var v5314 := p.version_view("5314")
	var v6024 := p.version_view("6024")
	eq(DeckStore.key(v5314), p.id() + ".5314", "a version's key")
	eq(DeckStore.file(DeckStore.key(v6024)), "%s.%s.6024.json" % [DeckStore.path.get_basename(), p.id()], "its own file")
	DirAccess.remove_absolute(DeckStore.file(DeckStore.key(v5314)))
	DirAccess.remove_absolute(DeckStore.file(DeckStore.key(v6024)))
	Packs.set_active(v5314)
	eq(DeckStore.load_all().map(func(d): return d.name), ["My old Classic deck"], "5314 starts with the old Classic decks")
	check(FileAccess.file_exists(DeckStore.path), "the old file stays")
	DeckStore.save_all([])
	eq(DeckStore.load_all().size(), 0, "deleted there: not copied again")
	Packs.set_active(v6024)
	eq(DeckStore.load_all().size(), 0, "another version: its own decks")
	var d := Deck.new()
	d.name = "Naxx deck"
	d.hero = "HERO_08"
	DeckStore.save_all([d])
	eq([DeckStore.count_local(DeckStore.key(v6024)), DeckStore.count_local(DeckStore.key(v5314))], [1, 0], "kept apart")
	eq(DeckStore.load_local().map(func(x): return x.name), ["Naxx deck"], "the active version's")
	Packs.set_active(Packs.all()[0])
	eq(DeckStore.load_all().map(func(x): return x.name), ["My old Classic deck"], "the old Classic pack keeps its file")
	for k in [DeckStore.key(v5314), DeckStore.key(v6024)]:
		DirAccess.remove_absolute(DeckStore.file(k))
	var f := FileAccess.open(DeckStore.path, FileAccess.WRITE)
	f.store_string(before)
	f.close()
	Settings.data.pack_versions.erase(p.id())


## A deck code brings only the cards of the version played (a Naxxramas card is not in 5314).
func test_a_deck_code_is_read_with_the_versions_cards() -> void:
	var p := _installed()
	if p == null:
		return
	Packs.set_active(p.version_view("6024"))
	var d := Deck.new()
	d.hero = "HERO_08"
	for id in ["FP1_001", "FP1_001", "VAN_CS2_182", "VAN_CS2_182"]:  # Zombie Chow (Naxxramas), Chillwind Yeti
		d.cards.append(id)
	for id in Decks.basic("MAGE").slice(0, 26):
		d.cards.append(id)
	var code := DeckCode.encode(d)
	eq(DeckCode.decode(code).error, "", "6024 has Zombie Chow")
	Packs.set_active(p.version_view("5314"))
	check(DeckCode.decode(code).error != "", "5314 has not: " + str(DeckCode.decode(code).error))
	Packs.set_active(Packs.all()[0])
	Settings.data.pack_versions.erase(p.id())


## Through a server: its game -> the Versions -> Play this version -> its menu and lobby (Standard and Wild where it
## has both, no version to choose); leaving it: the Versions; Back: the server's home.
func test_a_version_through_a_server() -> void:
	var p := _installed()
	if p == null:
		return
	var two := ""
	for x in p.versions():
		if x.get("formats", []).size() > 1:
			two = str(x.id)
	Settings.data.servers = [{"id": "ws://a.test:7377", "url": "ws://a.test:7377", "name": "Alpha"}]
	Settings.save()
	var m: Node = load("res://ui/main.tscn").instantiate()
	var l := FakeLink.new()
	l.url = "ws://a.test:7377"
	m.server_links.append(l)
	root().add_child(m)
	m.show_connections()
	m.open_connection("ws://a.test:7377")
	l.dispatch({"t": "auth", "ok": true, "token": "tok", "me": {"user": "anna", "tag": null, "arena": null, "season": "2026-10",
		"rank": {"rank": 25.0, "stars": 1.0, "streak": 1.0, "legend": null}}})
	var entry := {"id": p.id(), "name": p.manifest.name, "version": p.version(), "rules_hash": p.rules_hash(),
		"content_hash": Packs.content_hash(p), "size": p.size,
		"versions": p.versions().map(func(x): return {"id": x.id, "rules_hash": x.rules_hash})}
	for msg in [{"t": "chats", "list": []}, {"t": "packs", "server": [entry], "mine": []}, {"t": "decks", "list": []}]:
		l.dispatch(msg)
	check(m.screen is ServerHome, "the server's home")
	var row: Node = m.screen.find_child("Game_" + p.id(), true, false)
	check(row != null, "the game on the server")
	if row == null:
		m.free()
		return
	_press(row, "Play")
	var v := m.screen as VersionsView
	check(v != null, "its Versions")
	if v == null:
		m.free()
		return
	_press(v, "Version_" + two)
	_press(v, "PlayVersion")
	check(m.screen is MainMenu and m.screen.through_server, "the version's menu, through the server")
	eq(Packs.active().version_id, two, "that version")
	eq(DeckStore.link, l, "its decks are the server's")
	_press(m.screen, "Play")
	var s := m.screen as ServerView
	check(s != null and s.stage == "lobby", "its lobby")
	if s:
		check(s.find_child("Version", true, false) == null, "no version to choose there")
		check(s.find_child("Format_standard", true, false) != null and s.find_child("Format_wild", true, false) != null, "Standard and Wild")
		_press(s, "Back")
	_press(m.screen, "LeaveTheGame")
	check(m.screen is VersionsView, "leaving: the Versions")
	_press(m.screen, "Back")
	check(m.screen is ServerHome, "Back: the server's home")
	m.free()
	Packs.set_active(Packs.all()[0])
	Settings.data.pack_versions.erase(p.id())
	Settings.data.servers = []
	Settings.save()


## The server's decks of a game with versions: each version shows its own (the deck's `version`).
func test_server_decks_per_version() -> void:
	var p := _installed()
	if p == null:
		return
	var l := FakeLink.new()
	l.url = "ws://a.test:7377"
	l.decks = [{"id": 1, "pack": p.id(), "version": "5314", "name": "Old", "hero": "HERO_08", "cards": [], "updated": 1},
		{"id": 2, "pack": p.id(), "version": "6024", "name": "Naxx", "hero": "HERO_08", "cards": [], "updated": 1}]
	eq(l.decks_of(p.version_view("6024")).map(func(d): return d.name), ["Naxx"], "6024's")
	eq(l.decks_of(p.version_view("5314")).map(func(d): return d.name), ["Old"], "5314's")
	l.free()


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
	var n: int = Versions.diff(p.version_view("6024"), p.version_view("6485"), "en").changed.size()
	eq((v.find_child("Summary", true, false) as Label).text, "%d changed, 0 added, 0 removed" % n, "the summary")
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
			var v: VersionsView = m.show_versions(p)
			eq(v.size, Vector2(1280, 720), "the Versions fill the screen at %s" % size)
			var play := v.find_child("PlayVersion", true, false) as Button
			check(play != null and Rect2(Vector2.ZERO, v.size).encloses(play.get_rect()), "Play this version in view at %s" % size)
			(v.find_child("Compare", true, false) as Button).pressed.emit()
			check((v.find_child("Summary", true, false) as Label).text.contains(" changed, "), "the comparison at %s" % size)
			(v.find_child("From", true, false) as Button).pressed.emit()
			eq(v.page, "from", "the first version's choice")
			(v.find_child("Version_" + p.default_version(), true, false) as Button).pressed.emit()
			eq([v.page, v.a.version_id], ["compare", p.default_version()], "picked")
			eq((v.find_child("Summary", true, false) as Label).text, "0 changed, 0 added, 0 removed", "the same version")
		m.free()
	root().size = size0
	TouchInput.phone = was
