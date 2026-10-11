extends TestCase


static func _placeholders(s: String) -> Array:
	var re := RegEx.create_from_string("%[+]?[sd]")
	var out := []
	for m in re.search_all(s):
		out.append(m.get_string())
	out.sort()
	return out


func test_every_language_translates_every_key() -> void:
	var keys := I18nKeys.collect()
	eq(keys.size() > 200, true, "collector found the keys")
	for code in Locale.LANGS:
		if code == "en":
			continue
		var path := "%s/%s.json" % [Locale.DEFAULT_DIR, code]
		var j := JSON.new()
		var parsed := j.parse(FileAccess.get_file_as_string(path)) == OK and j.data is Dictionary
		eq(parsed, true, path + " parses")
		if not parsed:
			continue
		var missing := []
		var broken := []
		for k in keys:
			var v = j.data.get(k, "")
			if not v is String or v.strip_edges() == "":
				missing.append(k)
			elif _placeholders(k) != _placeholders(v):
				broken.append(k)
		eq(missing, [], code + ": no missing keys")
		eq(broken, [], code + ": placeholders match")


func test_language_switch_changes_interface_strings() -> void:
	Locale.set_language("ru")
	eq(str(TranslationServer.translate("End Turn")), "Конец хода", "ru")
	Locale.set_language("de")
	eq(str(TranslationServer.translate("End Turn")) != "End Turn", true, "de")
	Locale.set_language("en")
	eq(str(TranslationServer.translate("End Turn")), "End Turn", "en")


func test_font_has_every_character_the_interface_uses() -> void:
	var font := ThemeDB.fallback_font
	var texts := []
	for dir in ["res://ui", "res://game"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				texts.append([f, FileAccess.get_file_as_string(dir + "/" + f)])
	for code in Locale.LANGS:
		if code != "en":
			texts.append([code, FileAccess.get_file_as_string("%s/%s.json" % [Locale.DEFAULT_DIR, code])])
	var missing := {}
	for t in texts:
		for ch in t[1]:
			if ch.unicode_at(0) > 127 and not font.has_char(ch.unicode_at(0)):
				missing[ch] = t[0]
	eq(missing, {}, "characters the font lacks (shown as boxes)")
