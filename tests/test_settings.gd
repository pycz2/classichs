extends TestCase


func test_system_default_language() -> void:
	eq(Locale.pick("ru_RU"), "ru", "ru")
	eq(Locale.pick("pt_BR"), "pt_BR", "pt_BR")
	eq(Locale.pick("pt_PT"), "pt_BR", "Portuguese falls back to pt_BR")
	eq(Locale.pick("de_AT"), "de", "de")
	eq(Locale.pick("ja_JP"), "en", "unsupported → English")


func test_translations_load_from_json() -> void:
	var dir := "user://test_i18n"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/ru.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"Training": "Тренировка"}))
	f.close()
	Locale.load_all(dir)
	Locale.set_language("ru")
	eq(str(TranslationServer.translate("Training")), "Тренировка", "translated")
	eq(str(TranslationServer.translate("Untranslated thing")), "Untranslated thing", "missing key stays English")
	Locale.set_language("en")
	eq(str(TranslationServer.translate("Training")), "Training", "English")
	DirAccess.remove_absolute(dir + "/ru.json")
	DirAccess.remove_absolute(dir)
	Locale.load_all()


func test_settings_roundtrip_and_apply() -> void:
	Settings.path = "user://test_settings.json"
	DirAccess.remove_absolute(Settings.path)
	Settings.load_settings()
	eq(Settings.data.shake, true, "default shake on")
	Settings.data.shake = false
	Settings.data.music = 0.25
	Settings.data.language = "de"
	Settings.save()
	Settings.data = Settings.DEFAULTS.duplicate(true)
	Settings.load_settings()
	eq([Settings.data.shake, Settings.data.music, Settings.data.language], [false, 0.25, "de"], "loaded")
	Settings.apply()
	eq(Match.shake_enabled, false, "shake applied")
	eq(TranslationServer.get_locale(), "de", "language applied")
	Settings.data = Settings.DEFAULTS.duplicate(true)
	Settings.data.language = "en"
	Settings.apply()
	DirAccess.remove_absolute(Settings.path)
	Settings.path = Settings.DEFAULT_PATH


func test_broken_settings_file_uses_defaults() -> void:
	Settings.path = "user://test_settings2.json"
	var f := FileAccess.open(Settings.path, FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	Settings.load_settings()
	eq(Settings.data.music, Settings.DEFAULTS.music, "defaults")
	f = FileAccess.open(Settings.path, FileAccess.WRITE)
	f.store_string('{"music": "loud", "shake": 7, "language": "xx"}')
	f.close()
	Settings.load_settings()
	eq([Settings.data.music, Settings.data.shake, Settings.data.language], [Settings.DEFAULTS.music, true, ""], "bad values ignored")
	DirAccess.remove_absolute(Settings.path)
	Settings.path = Settings.DEFAULT_PATH


func test_key_collector_finds_literals_and_tables() -> void:
	var keys := I18nKeys.collect()
	for k in ["Training", "End Turn", "You draw %s", "Greetings!", "Not yet! You have more cards to play!",
			"Play minions and use them to attack Hogger. Deal enough damage and you win!", "Oh yeah!", "Hand", "New Deck"]:
		check(keys.has(k), "collected: " + k)


func test_collector_finds_paired_history_strings() -> void:
	var keys := I18nKeys.collect()
	for k in ["You play %s", "Opponent plays %s", "You win", "Opponent wins"]:
		check(keys.has(k), "collected: " + k)


func test_history_turn_lines_marked_by_event() -> void:
	var m := H.game()
	H.end_turn(m)
	var rows := HistoryText.rows(m.game.history.back(), m.game, 0, "en")
	check(rows.any(func(r): return r.turn and r.text.begins_with("Turn")), "turn row marked")
	check(rows.any(func(r): return not r.turn), "other rows not marked")


func test_remote_refusal_reasons_are_translatable() -> void:
	var keys := I18nKeys.collect()
	for k in ["an action for the wrong player", "an illegal action", "the game states differ", "a broken action"]:
		check(keys.has(k), "collected: " + k)
