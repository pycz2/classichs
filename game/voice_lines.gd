class_name VoiceLines
extends RefCounted
## What minions and heroes say: the active pack's locales/<lang>.json `voice` (card id ->
## kind -> text; kinds: play, attack, death; heroes: greetings, well_played, thanks, wow,
## oops, threaten, start, concede, attack). Heroes' emotes show these words. A card's
## `voice` field names whose lines it speaks.


static func reset() -> void:
	pass  # the pack caches its locale files


## The line in the language ("" = the interface language), the pack's default language when it
## has none, "" when none at all.
static func text(card_id: String, kind: String, lang := "") -> String:
	var p := Packs.active()
	if p == null:
		return ""
	var who: String = CardDb.card(card_id).get("voice", card_id) if CardDb.has(card_id) else card_id
	var l := lang if lang != "" else TranslationServer.get_locale()
	for code in [p.lang_for(l), p.default_locale()]:
		var line = p.locale(code).get("voice", {}).get(who, {}).get(kind)
		if line is String:
			return line
	return ""
