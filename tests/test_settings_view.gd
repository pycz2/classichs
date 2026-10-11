extends TestCase


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _setup() -> void:
	Settings.path = "user://test_settings_view.json"
	Profile.path = "user://test_profile_settings.json"
	Settings.load_settings()


func _teardown() -> void:
	Locale.set_language("en")
	for p in [Settings.path, Profile.path]:
		DirAccess.remove_absolute(p)
	Settings.path = "user://test_runner_settings.json"
	Profile.path = Profile.DEFAULT_PATH
	Settings.load_settings()
	Settings.data.language = "en"
	Settings.apply()


func _settings() -> SettingsView:
	var s := SettingsView.new()
	root().add_child(s)
	return s


func test_menu_opens_settings_and_back() -> void:
	_setup()
	var m: Node = load("res://ui/main.tscn").instantiate()
	root().add_child(m)
	(m.screen.find_child("Settings", true, false) as Button).pressed.emit()
	check(m.screen is SettingsView, "settings screen")
	(m.screen.find_child("Back", true, false) as Button).pressed.emit()
	check(m.screen is MainMenu, "back to menu")
	m.free()
	_teardown()


func test_language_switch_saves_and_rebuilds() -> void:
	_setup()
	var s := _settings()
	s.set_language("ru")
	eq(Settings.data.language, "ru", "stored")
	eq(TranslationServer.get_locale(), "ru", "applied")
	var title := s.find_child("Title", true, false) as Label
	eq(title.text, "Настройки", "own texts rebuilt in Russian")
	Settings.load_settings()
	eq(Settings.data.language, "ru", "saved to file")
	s.free()
	_teardown()


func test_volume_shake_and_tts() -> void:
	_setup()
	var s := _settings()
	(s.find_child("Music", true, false) as HSlider).value = 0.0
	eq(Settings.data.music, 0.0, "music 0")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music bus muted")
	(s.find_child("Shake", true, false) as CheckButton).button_pressed = false
	eq(Match.shake_enabled, false, "shake off")
	check(s.find_child("Tts", true, false) == null and s.find_child("voice", true, false) == null, "no speech settings any more")
	Settings.load_settings()
	eq(Settings.data.shake, false, "saved")
	s.free()
	_teardown()


func test_name_is_saved() -> void:
	_setup()
	var s := _settings()
	var ed := s.find_child("Name", true, false) as LineEdit
	ed.text = "  Jaina  "
	ed.text_changed.emit(ed.text)
	eq(Profile.load_name(), "Jaina", "profile name")
	s.free()
	_teardown()


func test_match_settings_relabels_static_buttons() -> void:
	_setup()
	var v := MatchView.new()
	root().add_child(v)
	var m := Match.new()
	m.bot_delay = 0.0
	m.setup(H.scene({"hero": "HERO_08"}), [false, true])
	v.bind(m)
	(v.find_child("SettingsButton", true, false) as Button).pressed.emit()
	var s := v.find_child("SettingsView", true, false) as SettingsView
	check(s != null, "settings overlay")
	s.set_language("ru")
	eq((v.find_child("EndTurn", true, false) as Button).text, "Конец хода", "end turn relabeled")
	var texts := func() -> Array:
		return v.find_children("*", "Label", true, false).map(func(l): return l.text) + \
			v.find_children("*", "Button", true, false).map(func(b): return b.text)
	check(texts.call().has("– Ваша колода"), "tracker header relabeled")
	eq((v.find_child("HistoryTitle", true, false) as Label).text, "История", "history title relabeled")
	check(texts.call().has("Бот"), "bot name relabeled")
	s.set_language("en")
	check(texts.call().has("Bot"), "bot name back in English")
	(s.find_child("Back", true, false) as Button).pressed.emit()
	check(not is_instance_valid(s) or s.is_queued_for_deletion(), "overlay closed")
	v.free()
	_teardown()


func test_concede_button_becomes_menu_after_game_over() -> void:
	var v := MatchView.new()
	root().add_child(v)
	var m := Match.new()
	m.bot_delay = 0.0
	m.setup(H.scene({"hero": "HERO_08"}), [false, false])
	v.bind(m)
	m.submit({"type": "concede", "player": 1})
	v.refresh()
	eq((v.find_child("Concede", true, false) as Button).text, "Menu", "menu after game over")
	v.free()
