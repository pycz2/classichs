extends TestCase

const LANGS := ["en", "ru", "de", "fr", "es", "pt_BR", "it", "pl"]


func test_voice_lines_parse_and_match_cards() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/voice_lines.json"))
	check(data is Dictionary and not (data as Dictionary).is_empty(), "voice_lines.json parses")
	for id: String in data:
		check(CardDb.has(id), "known card " + id)
		var entry: Dictionary = data[id]
		check(entry.get("source", "") != "", id + " has a source")
		for key: String in entry:
			if key == "source" or key == "translated":
				continue
			var lines: Dictionary = entry[key]
			check(lines.get("en", "") != "", "%s %s has English" % [id, key])
			for lang: String in lines:
				check(lang in LANGS, "%s %s: language %s" % [id, key, lang])
				check(str(lines[lang]).strip_edges() != "", "%s %s %s not empty" % [id, key, lang])
		for lang: Variant in entry.get("translated", []):
			check(lang in LANGS and lang != "en", "%s translated: %s" % [id, lang])


func test_heroes_say_emotes_in_their_own_words() -> void:
	eq(VoiceLines.text("HERO_08", "threaten", "en"), "My magic will tear you apart!", "Jaina")
	check(VoiceLines.text("HERO_08", "greetings", "ru") != "", "in Russian too")
	eq(VoiceLines.text("VAN_CS2_182", "play", "en"), "", "no line: empty")
