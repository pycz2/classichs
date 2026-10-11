extends TestCase
## The debug tools (from the settings): Scene, Interaction test, Card test, Effects test.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _main() -> Node:
	var m: Node = load("res://ui/main.tscn").instantiate()
	root().add_child(m)
	return m


func _debug() -> DebugTable:
	DebugTable.last_scene = ""
	var d := DebugTable.new()
	root().add_child(d)
	return d


func _json(d: DebugTable) -> Dictionary:
	return JSON.parse_string(d.editor.text)


func test_example_position_builds() -> void:
	var j := JSON.new()
	eq(j.parse(FileAccess.get_file_as_string("res://data/debug_example.json")), OK, "valid JSON")
	var r := Scenario.build(j.data)
	eq(r.error, "", "the example builds")


func test_settings_open_the_debug_tools_and_back() -> void:
	var m := _main()
	m.show_settings()
	var b := m.screen.find_child("DebugTools", true, false) as Button
	check(b != null, "a Debug tools button in the settings")
	b.pressed.emit()
	check(m.screen is DebugTable, "the debug screen")
	(m.screen.find_child("Back", true, false) as Button).pressed.emit()
	check(m.screen is SettingsView, "back to the settings")
	m.free()
	var overlay := SettingsView.new()  # the settings over a match: no debug tools
	root().add_child(overlay)
	check(overlay.find_child("DebugTools", true, false) == null, "not in the overlay")
	overlay.free()


func test_four_tabs_switch_in_place() -> void:
	var d := _debug()
	for i in 4:
		(d.find_child("Tab%d" % i, true, false) as Button).pressed.emit()
		eq(d.tab, i, "tab %d open" % i)
		for j in 4:
			eq(d.find_child("Page%d" % j, true, false).visible, i == j, "page %d shown only with its tab (%d)" % [j, i])
	check(d.find_child("Page2", true, false).get_child(0) is CardLab, "the card lab in its tab")
	check(d.find_child("Page3", true, false).get_child(0) is EffectsLab, "the effects lab in its tab")
	for p in ["Page2", "Page3"]:
		check(not d.find_child(p, true, false).find_child("Back", true, false).visible, "no second Back in " + p)
	d.free()


func test_scene_editor_adds_and_removes_cards_and_the_json_follows() -> void:
	var d := _debug()
	var p1 := d.find_child("Player1", true, false)
	(p1.find_child("Zone_board", true, false) as Button).pressed.emit()
	eq(d.target, [1, "board"], "the board of player 2 is marked")
	(d.find_child("SceneCards", true, false) as CollectionView).click_card("VAN_CS2_182")
	check((_json(d).players[1].board as Array).has("VAN_CS2_182"), "the JSON has the Yeti")
	p1 = d.find_child("Player1", true, false)
	var tiles := p1.find_child("Tiles_board", true, false)
	var yeti := tiles.get_child(tiles.get_child_count() - 1) as DeckTiles.DeckTile
	eq(yeti.card_id, "VAN_CS2_182", "a tile for it")
	yeti.pressed.emit()
	check(not (_json(d).players[1].board as Array).has("VAN_CS2_182"), "a click on the tile takes it out")
	d.add_card(1, "board", "VAN_CS2_029")  # Fireball is no minion
	check(not (_json(d).players[1].board as Array).has("VAN_CS2_029"), "refused")
	check(d.error.text.contains("not a minion"), "and why: " + d.error.text)
	var mana := d.find_child("Player0", true, false).find_child("Stat_mana", true, false) as SpinBox
	mana.value = 3
	eq(int(_json(d).players[0].mana), 3, "numbers go to the JSON")
	d.free()


func test_applied_json_shows_in_the_editor() -> void:
	var d := _debug()
	d.editor.text = '{"players": [{"hero": "HERO_01", "mana": 7, "hand": ["VAN_CS2_029", "VAN_CS2_231"]}, {"hero": "HERO_08"}]}'
	(d.find_child("ApplyJson", true, false) as Button).pressed.emit()
	var p0 := d.find_child("Player0", true, false)
	eq((p0.find_child("Hero", true, false) as OptionButton).text, CardText.name("HERO_01"), "the hero")
	eq(int((p0.find_child("Stat_mana", true, false) as SpinBox).value), 7, "the mana")
	eq(p0.find_child("Tiles_hand", true, false).get_child_count(), 2, "two cards in hand")
	eq(d.error.text, "", "no problem")
	d.editor.text = "{ broken"
	d.apply_json()
	check(d.error.text.begins_with("Invalid JSON"), "a broken JSON is reported")
	d.free()


func test_radio_buttons_choose_the_mode() -> void:
	var d := _debug()
	var got := []
	d.start.connect(func(_g, bots): got.append(bots))
	check(d.bot_mode.button_pressed, "against the bot by default")
	d.hot_seat.button_pressed = true
	check(not d.bot_mode.button_pressed, "one mode at a time")
	d.start_game()
	d.bot_mode.button_pressed = true
	d.start_game()
	eq(got, [[false, false], [false, true]], "hot seat, then the bot")
	d.free()
	DebugTable.last_scene = ""


func test_interaction_test_lists_the_example_and_plays_it() -> void:
	DebugTable.last_test = ["", 0]
	var m := _main()
	m.show_debug_table(DebugTable.TESTS)
	var d := m.screen as DebugTable
	check(d.find_child("Page1", true, false).visible, "opens at the Interaction test tab")
	d.pick_test_card("VAN_CS2_189")
	check(d.test_list.item_count >= 1, "Elven Archer has tests")
	var i := -1
	for k in d.test_list.item_count:
		if d.test_list.get_item_text(k).begins_with("battlecry — Elven Archer"):
			i = k
	check(i >= 0, "the example is listed with its kind and title")
	d.test_list.select(i)
	d.run_selected()
	var v := m.screen as MatchView
	check(v != null, "a match")
	eq(v.controller.bots, [false, false], "nobody moves by itself")
	var status := v.find_child("RunStatus", true, false) as Label
	check(status.text.begins_with("Done"), "all steps played: " + status.text)
	eq(v.g.players[0].board[0].card_id, "VAN_CS2_189", "the archer is on the board")
	eq(v.g.players[1].board.size(), 0, "its battlecry killed the Wisp")
	(v.find_child("RunAgain", true, false) as Button).pressed.emit()
	var again := m.screen as MatchView
	check(again != v and again.g.players[1].board.is_empty(), "played again from the start")
	(again.find_child("RunBack", true, false) as Button).pressed.emit()
	check(m.screen is DebugTable and (m.screen as DebugTable).tab == DebugTable.TESTS, "back at the tab")
	m.free()


func test_an_illegal_step_is_shown_not_crashed() -> void:
	var m := _main()
	var v: MatchView = m.start_card_test({"title": "broken", "scene": {"players": [{"hero": "HERO_08", "deck": [H.WISP]}, {"hero": "HERO_01", "deck": [H.WISP]}]},
		"steps": [{"do": "end_turn"}, {"do": "play", "card": {"side": 0, "zone": "hand", "index": 3}}]})
	var status := v.find_child("RunStatus", true, false) as Label
	check(status.text.contains("Step 2 of 2") and status.text.contains("not legal"), status.text)
	m.free()
