class_name VoiceLines
extends RefCounted
## What minions and heroes say (data/voice_lines.json: card id -> kind -> language ->
## text; kinds: play, attack, death; heroes: greetings, well_played, thanks, wow, oops,
## threaten, start, concede, attack). Heroes' emotes show these words.

const PATH := "res://data/voice_lines.json"

static var _data := {}


static func _lines() -> Dictionary:
	if _data.is_empty():
		var j := JSON.new()
		if FileAccess.file_exists(PATH) and j.parse(FileAccess.get_file_as_string(PATH)) == OK and j.data is Dictionary:
			_data = j.data
	return _data


## The line in the language ("" = the interface language), English when it has none, "" when none at all.
static func text(card_id: String, kind: String, lang := "") -> String:
	var by_lang = _lines().get(card_id, {}).get(kind)
	if not by_lang is Dictionary:
		return ""
	var l := lang if lang != "" else TranslationServer.get_locale()
	return by_lang.get(l, by_lang.get(l.get_slice("_", 0), by_lang.get("en", "")))

