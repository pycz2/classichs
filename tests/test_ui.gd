extends TestCase
## UI smoke tests: scenes build headless and the main flows run without errors.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _main() -> Node:
	var m: Node = load("res://ui/main.tscn").instantiate()
	root().add_child(m)
	return m


## The buttons of the menu shown now, by name.
static func _items(m: Node) -> Array:
	return m.screen.find_children("*", "Button", true, false).filter(func(b): return b.name != "Version").map(func(b): return str(b.name))


func _press(m: Node, button: String) -> void:
	(m.screen.find_child(button, true, false) as Button).pressed.emit()


## The whole tree: main menu → Play → Direct → the library → a game's menu → back up again.
func test_the_menu_tree() -> void:
	var m := _main()
	check(m.screen is MainMenu and m.screen.pack == null, "the client's main menu first")
	eq(_items(m), ["Play", "Settings", "Exit"] if not OS.has_feature("web") else ["Play", "Settings"], "Play, Settings, Exit")
	check(Packs.shell and Packs.look() == null, "no game styles it")
	_press(m, "Play")
	eq(_items(m), ["Direct", "Server", "Back"], "without a server or through one")
	_press(m, "Back")
	eq(_items(m), ["Play", "Settings", "Exit"] if not OS.has_feature("web") else ["Play", "Settings"], "back to the first level")
	_press(m, "Play")
	_press(m, "Direct")
	check(m.screen is GamesView, "the game library")
	(m.screen as GamesView).activate(Packs.active())
	check(m.screen is MainMenu and m.screen.pack == Packs.active(), "the game's menu")
	check(not Packs.shell and Packs.look() == Packs.active(), "in the game's look")
	var items := _items(m)
	for n in ["Collection", "Training", "CodePlay", "Tutorial", "Settings", "LeaveTheGame"]:
		check(items.has(n), n + " in the game's menu")
	check(not items.has("Play"), "no server Play without a server")
	check(not (m.screen.find_child("Collection", true, false) as Button).disabled, "collection enabled")
	_press(m, "Training")
	check(m.screen is TrainingSetup, "training")
	(m.screen as TrainingSetup).back.emit()
	check(m.screen is MainMenu and m.screen.pack != null, "back to the game's menu")
	_press(m, "LeaveTheGame")
	check(m.screen is GamesView, "leaving the game: the library")
	(m.screen as GamesView).back.emit()
	check(m.screen is MainMenu and m.screen.find_child("Direct", true, false) != null, "back: the Play submenu")
	m.free()


## A pack without missions has no Tutorial in its menu.
func test_tutorial_only_when_the_pack_has_one() -> void:
	var menu := MainMenu.new()
	menu.pack = Packs.active()
	root().add_child(menu)
	check(menu.find_child("Tutorial", true, false) != null, "Classic has a tutorial")
	menu.free()
	for p: Pack in Packs.all():
		if not p.has_tutorial():
			menu = MainMenu.new()
			menu.pack = p
			root().add_child(menu)
			check(menu.find_child("Tutorial", true, false) == null, p.id() + ": no tutorial")
			menu.free()


func test_menu_to_training_setup_and_back() -> void:
	var m := _main()
	m.show_training_setup()
	check(m.screen is TrainingSetup, "setup screen")
	m.show_menu()
	check(m.screen is MainMenu, "back to menu")
	m.free()


func _view(m: Match, debug := false) -> MatchView:
	var v := MatchView.new()
	v.debug_mode = debug
	root().add_child(v)
	v.bind(m)
	return v


func test_bot_vs_bot_through_view_ends_with_overlay() -> void:
	var m := H.decks("MAGE", "PRIEST", 3, 0, [true, true])
	var g := m.game
	var v := _view(m)
	check(g.game_over, "finished")
	check(v.find_child("GameOver", true, false) != null, "game over overlay")
	v.free()


func test_mulligan_overlay_confirm() -> void:
	var m := H.decks("MAGE", "WARRIOR", 5, 0, [false, true])
	var g := m.game
	var v := _view(m)
	var ov := v.find_child("Mulligan", true, false)
	check(ov != null, "mulligan overlay")
	(v.find_child("Confirm", true, false) as Button).pressed.emit()
	eq(g.phase, "PLAY", "game started")
	check(v.find_child("Mulligan", true, false) == null, "overlay closed")
	v.free()


func test_play_minion_by_clicks() -> void:
	var m := H.scene({"hero": "HERO_08", "hand": [H.WISP], "board": ["VAN_CS2_120", "VAN_CS2_120"]}, {"hero": "HERO_01"}, 0, [false, true])
	var g := m.game
	var v := _view(m)
	var w: GameView.Ent = g.players[0].hand[0]
	v.click_entity(w.id)
	eq(v._sel.get("stage", ""), "position", "asks for a position")
	v.click_board(1)
	eq(g.players[0].board[1], w, "wisp placed in the middle")
	v.free()


func test_targeted_spell_by_clicks() -> void:
	var m := H.scene({"hero": "HERO_08", "hand": ["VAN_CS2_029"]}, {"hero": "HERO_01"}, 0, [false, true])
	var g := m.game
	var v := _view(m)
	v.click_entity(g.players[0].hand[0].id)
	eq(v._sel.get("stage", ""), "target", "asks for a target")
	v.click_entity(g.hero(1).id)
	eq(g.hero(1).health(), 24, "fireball hit")
	v.free()


func test_attack_by_clicks() -> void:
	var m := H.scene({"hero": "HERO_08", "board": ["VAN_CS2_120"]}, {"hero": "HERO_01"}, 0, [false, true])
	var g := m.game
	var v := _view(m)
	v.click_entity(g.players[0].board[0].id)
	v.click_entity(g.hero(1).id)
	eq(g.hero(1).health(), 28, "attacked")
	v.free()


func test_choose_one_by_clicks() -> void:
	var m := H.scene({"hero": "HERO_06", "hand": ["VAN_EX1_154"]}, {"hero": "HERO_01", "board": ["VAN_CS2_182"]}, 0, [false, true])
	var g := m.game
	var v := _view(m)
	v.click_entity(g.players[0].hand[0].id)
	var ov := v.find_child("ChooseOne", true, false)
	check(ov != null, "choose one overlay")
	var cards := ov.find_children("*", "CardView", true, false)
	eq(cards.size(), 2, "two options")
	cards[0].clicked.emit(cards[0])
	v.click_entity(g.players[1].board[0].id)
	eq(g.players[1].board[0].health(), 2, "3 damage option")
	v.free()


func test_unplayable_card_shows_hint() -> void:
	var m := H.scene({"hero": "HERO_08", "hand": ["VAN_CS2_029"], "mana": 1, "max_mana": 1}, {"hero": "HERO_01"}, 0, [false, true])
	var g := m.game
	var v := _view(m)
	v.click_entity(g.players[0].hand[0].id)
	check(v._sel.is_empty(), "nothing selected")
	check(v._hint.text != "", "hint shown")
	v.free()


func test_end_turn_button_hands_over_to_bot() -> void:
	var m := H.scene({"hero": "HERO_08", "deck": [H.WISP, H.WISP, H.WISP]}, {"hero": "HERO_01", "deck": [H.WISP, H.WISP]}, 0, [false, true])
	var g := m.game
	var v := _view(m)
	(v.find_child("EndTurn", true, false) as Button).pressed.emit()
	eq(g.current, 0, "bot played and passed back")
	check(g.turn >= 3, "turns advanced")
	v.free()


func test_history_panel_long_match() -> void:
	var deck: Array = []
	for i in 170:
		deck.append(H.WISP)
	var m := H.scene({"hero": "HERO_08", "deck": deck}, {"hero": "HERO_01", "deck": deck.duplicate()})
	for i in 320:
		H.end_turn(m)
	var v := _view(m)
	check(v._history.line_count() >= 320, "all lines: %d" % v._history.line_count())
	v.free()


func test_json_overlay_in_debug_mode() -> void:
	var m := H.scene({"hero": "HERO_08", "hand": [H.WISP]}, {"hero": "HERO_01"}, 0, [false, true])
	var g := m.game
	var v := _view(m, true)
	check(v.find_child("JsonButton", true, false) != null, "debug button")
	v.show_json()
	var ed := v.find_child("Json", true, false).find_children("*", "TextEdit", true, false)[0] as TextEdit
	eq(Rules.scenario_error(JSON.parse_string(ed.text)), "", "valid scenario text")
	v.free()


func test_debug_table_flow() -> void:
	var d := DebugTable.new()
	root().add_child(d)
	var started := []
	d.start.connect(func(game, bots): started.append([game, bots]))
	d.start_game()
	eq(started.size(), 1, "example starts")
	d.editor.text = "{ broken"
	d.start_game()
	check(d.error.text.begins_with("Invalid JSON"), "json error shown: " + d.error.text)
	d.editor.text = '{"players": [{"hero": "HERO_08", "hand": ["NOPE"]}, {"hero": "HERO_01"}]}'
	d.start_game()
	check(d.error.text.contains("unknown card NOPE"), "scenario error shown")
	d.load_example()
	eq(d.error.text, "", "the example builds")
	d.add_card(1, "board", "VAN_CS2_182")
	check(JSON.parse_string(d.editor.text).players[1].board.has("VAN_CS2_182"), "card added")
	eq(started.size(), 1, "errors did not start a game")
	d.free()


func test_place_minion_by_clicking_an_existing_minion() -> void:
	var m := H.scene({"hero": "HERO_08", "hand": [H.WISP], "board": ["VAN_CS2_120", "VAN_CS2_120"]}, {"hero": "HERO_01"}, 0, [false, true])
	var g := m.game
	var v := _view(m)
	var w: GameView.Ent = g.players[0].hand[0]
	v.click_entity(w.id)
	v.click_entity(g.players[0].board[1].id)  # a click on the minion picks a slot next to it
	eq(w.zone, "PLAY", "placed, not switched to an attack")
	v.free()


func test_invalid_click_mid_selection_clears_highlights() -> void:
	var m := H.scene({"hero": "HERO_08", "hand": ["VAN_CS2_029", "VAN_EX1_279"], "mana": 4, "max_mana": 4}, {"hero": "HERO_01"}, 0, [false, true])
	var g := m.game
	var v := _view(m)
	v.click_entity(g.players[0].hand[0].id)  # Fireball: targeting
	v.click_entity(g.players[0].hand[1].id)  # Pyroblast: too expensive
	eq(v._views[g.hero(1).id].glow, Color.TRANSPARENT, "target glow cleared")
	v.free()


func test_concede_asks_for_confirmation() -> void:
	var m := H.scene({"hero": "HERO_08"}, {"hero": "HERO_01"}, 0, [false, true])
	var g := m.game
	var v := _view(m)
	(v.find_child("Concede", true, false) as Button).pressed.emit()
	check(not g.game_over, "not conceded on the first click")
	(v.find_child("ConfirmConcede", true, false) as Button).pressed.emit()
	check(g.game_over and g.winner == 1, "conceded after confirmation")
	v.free()


func test_debug_add_card_with_broken_players() -> void:
	var d := DebugTable.new()
	root().add_child(d)
	d.editor.text = '{"players": [1, 2]}'
	check(d.apply_json(), "valid JSON is read")
	check(d.error.text.contains("hero is required"), "the scene's problem shown: " + d.error.text)
	d.add_card(0, "hand", H.WISP)
	check(d.error.text.contains("two objects"), "no player to add to: " + d.error.text)
	d.free()


func test_long_card_text_uses_smaller_font() -> void:
	var short := CardLayout.of("VAN_CS2_029", "en")  # Fireball
	var long := CardLayout.of("VAN_EX1_295", "en")  # Ice Block
	check(int(long.text) < int(short.text), "long text is smaller: %s %s" % [short, long])

func test_hidden_history_follows_new_moves() -> void:
	var h := HistoryPanel.new()
	h.visible = false
	root().add_child(h)
	check(h.following(), "a hidden panel follows the newest line")
	h.visible = true
	h.free()


func test_ticked_buttons_keep_their_plank_under_the_mouse() -> void:
	var t := Fonts.theme()
	check(t.has_stylebox("hover_pressed", "Button") and not t.get_stylebox("hover_pressed", "Button") is StyleBoxEmpty, "a pressed button under the mouse still has its background")


func test_first_run_asks_for_the_language() -> void:
	var was := Settings.path
	Settings.path = "user://test_first_run_settings.json"
	DirAccess.remove_absolute(Settings.path)
	var m := _main()
	check(m.screen is LanguagePicker, "the language comes first")
	eq(m.screen.find_children("Lang_*", "Button", true, false).size(), 8, "all 8 languages")
	(m.screen.find_child("Lang_de", true, false) as Button).pressed.emit()
	check(m.screen is MainMenu, "then the menu")
	eq(TranslationServer.get_locale(), "de", "in German")
	Settings.load_settings()
	eq([Settings.first_run, Settings.data.language], [false, "de"], "kept for the next run")
	m.free()
	DirAccess.remove_absolute(Settings.path)
	Settings.path = was
	Settings.load_settings()
	Locale.set_language("en")


## Codes need WebRTC (the browser, or the webrtc-native plugin in the other builds); the server works everywhere.
func test_online_without_webrtc_offers_the_server() -> void:
	var m := _main()
	_press(m, "Play")
	check(not (m.screen.find_child("Server", true, false) as Button).disabled, "through a server everywhere")
	m.enter_game(Packs.active())
	var codes := m.screen.find_child("CodePlay", true, false) as Button
	eq(codes.disabled, not WebRtcTransport.available(), "code play needs WebRTC (the browser)")
	m.free()
