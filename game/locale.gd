class_name Locale
extends RefCounted
## Interface languages. English strings are the keys; data/i18n/<code>.json maps
## them to translations. Card names and texts come from cards.json.

const DEFAULT_DIR := "res://data/i18n"
const LANGS := {"en": "English", "ru": "Русский", "de": "Deutsch", "fr": "Français", "es": "Español",
	"pt_BR": "Português (Brasil)", "it": "Italiano", "pl": "Polski"}

static var _loaded: Array[Translation] = []


static func load_all(dir := DEFAULT_DIR) -> void:
	for t in _loaded:
		TranslationServer.remove_translation(t)
	_loaded.clear()
	for code in LANGS:
		if code == "en":
			continue
		var path := "%s/%s.json" % [dir, code]
		if not FileAccess.file_exists(path):
			continue
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(path)) != OK or not j.data is Dictionary:
			push_warning("broken translation file " + path)
			continue
		var t := Translation.new()
		t.locale = code
		for k in j.data:
			if j.data[k] is String and j.data[k] != "":
				t.add_message(k, j.data[k])
		TranslationServer.add_translation(t)
		_loaded.append(t)


## A supported language for an OS locale ("ru_RU" → "ru"); English otherwise.
static func pick(os_locale: String) -> String:
	if LANGS.has(os_locale):
		return os_locale
	var lang := os_locale.get_slice("_", 0)
	if lang == "pt":
		return "pt_BR"
	return lang if LANGS.has(lang) else "en"


static func set_language(code: String) -> void:
	TranslationServer.set_locale(code if LANGS.has(code) else "en")
