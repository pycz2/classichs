extends TestCase
## ClassicHS Studio's shell (studio/studio.gd) and its tabs Game, Classes, Sets & rarities, Decks, Check &
## export; a test match from the editor.

const ROOT := "user://test_studio"


func _studio() -> Studio:
	StudioProject.root = ROOT
	Studio.remove_dir(ROOT)
	var s := Studio.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	return s


func _find(n: Node, id: String) -> Node:
	var x := n.find_child(id, true, false)
	check(x != null, "a " + id)
	return x


func _type(e: LineEdit, t: String) -> void:
	e.text = t
	e.text_changed.emit(t)


## A project with two collectible minions and a legal 4-card deck (deck size 4), open in the editor.
func _ready_game(s: Studio) -> StudioProject:
	var p := StudioProject.create("gamma", "Gamma")
	p.rules.limits.deck_size = 4
	p.add_card("MINION", "KNIGHT")
	p.add_card("MINION")
	p.save()
	s.open_project(p)
	return p


func test_the_start_screen_lists_the_projects() -> void:
	StudioProject.root = ROOT
	Studio.remove_dir(ROOT)
	StudioProject.create("alpha", "Alpha")
	var s := Studio.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	check(s.screen.find_child("Project_alpha", true, false) != null, "the project is listed")
	(_find(s.screen, "Delete_alpha") as Button).pressed.emit()
	(_find(s, "Confirm") as ConfirmationDialog).confirmed.emit()
	check(not DirAccess.dir_exists_absolute(ROOT + "/alpha"), "deleted after the question")
	check(s.screen.find_child("Project_alpha", true, false) == null, "not listed")
	s.free()
	StudioProject.root = "user://studio"


func test_a_new_game_through_the_start_screen() -> void:
	var s := _studio()
	_type(_find(s.screen, "NewId"), "Bad Id")
	check((_find(s.screen, "NewProblem") as Label).text != "", "a bad id says why")
	_type(_find(s.screen, "NewId"), "beta")
	_type(_find(s.screen, "NewName"), "Beta")
	(_find(s.screen, "Create") as Button).pressed.emit()
	check(s.project != null and s.project.id == "beta", "the new project is open")
	eq(str(s.screen.name), "Editor", "the editor shows")
	check(DirAccess.dir_exists_absolute(ROOT + "/beta/pack"), "its folder")
	eq(StudioProject.list().size(), 1, "it is listed")
	s.free()
	StudioProject.root = "user://studio"


func test_the_game_tab_changes_names_and_rules() -> void:
	var s := _studio()
	s.new_project("delta", "Delta")
	var g: StudioGame = s.tab("Game")
	g.lang = "ru"
	g.refresh()
	_type(_find(g, "Name"), "Дельта")
	(_find(g, "limits_deck_size") as SpinBox).value = 20
	(_find(g, "Fatigue") as CheckBox).button_pressed = false
	s.save()
	var p := StudioProject.open("delta")
	eq(p.manifest.name.get("ru"), "Дельта", "the name in Russian")
	eq(p.manifest.name.get("en"), "Delta", "the English one stays")
	eq(p.rules.limits.deck_size, 20, "the deck size")
	eq(p.rules.fatigue.enabled, false, "no fatigue")
	var img := Image.create(1000, 500, false, Image.FORMAT_RGB8)
	eq(g.set_picture("tile", img), "", "a tile picture")
	eq(Image.load_from_file(g.picture_path("tile")).get_size(), Vector2i(750, 300), "cut to 750x300")
	s.free()
	StudioProject.root = "user://studio"


func test_classes_and_sets_are_added() -> void:
	var s := _studio()
	s.new_project("epsilon", "Epsilon")
	var c: StudioClasses = s.tab("Classes")
	_type(_find(c, "NewClass"), "MAGE")
	(_find(c, "AddClass") as Button).pressed.emit()
	check(s.project.rules.classes.any(func(x): return x.id == "MAGE"), "the class")
	check(not s.project.card("mage_hero").is_empty() and not s.project.card("mage_power").is_empty(), "its hero and Hero Power")
	check(c.find_child("Class_MAGE", true, false) != null, "shown")
	(_find(c.find_child("Class_MAGE", true, false), "HeroName") as LineEdit).text_changed.emit("Archmage")
	eq(s.project.text("mage_hero", "en").get("name"), "Archmage", "the hero's name")
	eq(c.add_class("MAGE"), "A class with this id exists", "not twice")
	var t: StudioSets = s.tab("Sets")
	_type(_find(t, "NewSet"), "expert")
	(_find(t, "AddSet") as Button).pressed.emit()
	check(s.project.rules.sets.has("expert"), "the set")
	check(s.project.rules.modes.constructed.sets.has("expert"), "playable in constructed")
	eq(t.add_race("golem"), "", "a tribe")
	check(s.project.rules.races.has("GOLEM"), "its id upper-case")
	s.free()
	StudioProject.root = "user://studio"


func test_a_legal_deck_then_check_and_export() -> void:
	var s := _studio()
	var p := _ready_game(s)
	var d: StudioDecks = s.tab("Decks")
	_type(_find(d, "NewDeckName"), "First")
	(_find(d, "CreateDeck") as Button).pressed.emit()
	eq(d.chosen, "first", "the deck's file")
	check((_find(d, "DeckProblem") as Label).text != tr("The deck is legal"), "empty: not legal")
	for cid in p.deck_pool(p.decks.first.champion):
		for i in 2:
			(_find(d.find_child("Card_" + cid, true, false), "More") as Button).pressed.emit()
	eq(p.decks.first.cards.size(), 4, "four cards")
	eq(p.deck_problem("first"), "", "the deck is legal")
	var k: StudioCheck = s.tab("Check")
	var c := k.run()
	eq(c.errors(), 0, "no errors: " + str(c.items.filter(func(it): return it.level == PackCheck.ERROR)))
	check(k.find_child("Item0", true, false) != null, "the findings are listed")
	var path := ROOT + "/out.cardpack"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(c.pack_bytes())
	f.close()
	var pack := Pack.open(path, "test")
	check(pack != null and pack.id() == "gamma", "the export opens as the game's pack")
	if pack:
		pack.close()
	var servers: Array = Settings.data.servers
	Settings.data.servers = [{"id": "nowhere", "url": "ws://127.0.0.1:9"}]
	check(k.upload(0) == null, "no upload without a session")
	eq((_find(k, "Message") as Label).text, tr("Log in to a server in the game first"), "it says why")
	Settings.data.servers = servers
	s.free()
	StudioProject.root = "user://studio"


func test_try_a_card_in_a_match_and_come_back() -> void:
	var s := _studio()
	var p := _ready_game(s)
	var was := Packs.active()
	var cid: String = p.cards.filter(func(x): return x.type == "MINION")[0].id
	var v := s.try_card(cid)
	check(v != null and s.screen == v, "a match shows")
	if v:
		eq(Packs.active().id(), "gamma", "with the game's pack")
		var hand: Array = v.controller.game.players[0].hand.map(func(e): return e.card_id)
		eq(hand, [cid, cid], "the card twice in hand")
		v.leave.emit()
	eq(str(s.screen.name), "Editor", "back in the editor")
	eq(s.tabs.current_tab, 3, "on the Cards tab")
	eq(Packs.active(), was, "the game active before is again")
	check(not Packs.all().any(func(x: Pack): return x.id() == "gamma"), "the match's pack is gone")
	s.free()
	StudioProject.root = "user://studio"
