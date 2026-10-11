class_name VoiceLines
extends RefCounted
## What minions and heroes say (data/voice_lines.json: card id -> kind -> language ->
## text; kinds: play, attack, death; heroes: greetings, well_played, thanks, wow, oops,
## threaten, start, concede, attack) and the recorded clips of those lines
## (audio/voice/<Hearthstone locale>/<card id>_<kind>.ogg, made by tools/tts).

const PATH := "res://data/voice_lines.json"
const CLIPS := "res://audio/voice"

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


## The recorded clip of the line in the interface language, or null.
static func clip(card_id: String, kind: String) -> AudioStream:
	var path := "%s/%s/%s_%s.ogg" % [CLIPS, CardText.hs_locale(TranslationServer.get_locale()), card_id, kind]
	return load(path) if ResourceLoader.exists(path) else null
