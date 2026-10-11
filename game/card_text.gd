class_name CardText
extends RefCounted
## Localized card names and texts from cards.json.

const LOCALES := {"en": "enUS", "ru": "ruRU", "de": "deDE", "fr": "frFR", "es": "esES", "es_MX": "esMX",
	"it": "itIT", "pt": "ptBR", "pl": "plPL", "ja": "jaJP", "ko": "koKR", "zh_CN": "zhCN", "zh_TW": "zhTW",
	"zh": "zhCN", "th": "thTH"}

static var _tags := RegEx.create_from_string("<[^>]+>|\\[x\\]|\\{\\d+\\}\\s*")
static var _numbers := RegEx.create_from_string("[$#](\\d+)")


## Godot locale ("ru_RU", "pt") to the Hearthstone key ("ruRU", "ptBR"); English by default.
static func hs_locale(locale: String) -> String:
	if locale in LOCALES.values():
		return locale  # already a Hearthstone key ("ruRU")
	if LOCALES.has(locale):
		return LOCALES[locale]
	return LOCALES.get(locale.get_slice("_", 0), "enUS")


static func _loc(locale: String) -> String:
	return hs_locale(locale if locale != "" else TranslationServer.get_locale())


static func name(id: String, locale := "") -> String:
	var n: Dictionary = CardDb.card(id).get("name", {})
	return n.get(_loc(locale), n.get("enUS", id))


static var _spaces := RegEx.create_from_string("[ \\t]+")
static var _bb := RegEx.create_from_string("\\[/?(b|i|center|color[^\\]]*)\\]")


## Card text as BBCode: keywords (<b>) bold, <i> italic, spaces collapsed.
static func rich(id: String, locale := "", spellpower := 0) -> String:
	var t: Dictionary = CardDb.card(id).get("text", {})
	var s: String = t.get(_loc(locale), t.get("enUS", ""))
	s = s.replace("[x]", "").replace("[", "[lb]")
	s = s.replace("<b>", "[b]").replace("</b>", "[/b]").replace("<i>", "[i]").replace("</i>", "[/i]")
	s = _tags.sub(s, "", true)
	var out := ""
	var last := 0
	for m in _numbers.search_all(s):
		out += s.substr(last, m.get_start() - last)
		var n := int(m.get_string(1))
		out += ("[b]%d[/b]" % (n + spellpower)) if s[m.get_start()] == "$" and spellpower > 0 else str(n)
		last = m.get_end()
	out = _spaces.sub(out + s.substr(last), " ", true).replace(" \n", "\n").replace("\n ", "\n")
	return out.strip_edges()


## The visible characters of rich() (to measure them).
static func plain_rich(r: String) -> String:
	return _bb.sub(r, "", true).replace("[lb]", "[")


## Card text without markup. spellpower > 0 shows boosted "$n" values as *n*.
static func text(id: String, locale := "", spellpower := 0) -> String:
	var t: Dictionary = CardDb.card(id).get("text", {})
	var s: String = t.get(_loc(locale), t.get("enUS", ""))
	s = _tags.sub(s, "", true)
	var out := ""
	var last := 0
	for m in _numbers.search_all(s):
		out += s.substr(last, m.get_start() - last)
		var n := int(m.get_string(1))
		out += ("*%d*" % (n + spellpower)) if s[m.get_start()] == "$" and spellpower > 0 else str(n)
		last = m.get_end()
	return (out + s.substr(last)).strip_edges()
