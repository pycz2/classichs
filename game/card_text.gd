class_name CardText
extends RefCounted
## Localized card names and texts of the active pack (CardDb), and its other names (term()).

const LOCALES := {"en": "enUS", "ru": "ruRU", "de": "deDE", "fr": "frFR", "es": "esES", "es_MX": "esMX",
	"it": "itIT", "pt": "ptBR", "pl": "plPL", "ja": "jaJP", "ko": "koKR", "zh_CN": "zhCN", "zh_TW": "zhTW",
	"zh": "zhCN", "th": "thTH"}

static var _tags := RegEx.create_from_string("<[^>]+>|\\[x\\]|\\{\\d+\\}\\s*")
static var _numbers := RegEx.create_from_string("[$#](\\d+)")
## "2 |4(point,points)": the word form for the number before it.
static var _plural := RegEx.create_from_string("(\\d+)(\\[/b\\]|\\*)?([ \\x{a0}]*)\\|4\\(([^,)]*),([^)]*)\\)")


static func _plurals(s: String) -> String:
	var out := ""
	var last := 0
	for m in _plural.search_all(s):
		var word := m.get_string(4) if int(m.get_string(1)) <= 1 else m.get_string(5)
		out += s.substr(last, m.get_start() - last) + m.get_string(1) + m.get_string(2) + m.get_string(3) + word
		last = m.get_end()
	return out + s.substr(last)


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
	if id == "":
		return "?"  # a card the view hides
	var n: Dictionary = CardDb.card(id).get("name", {})
	return n.get(_loc(locale), n.get("enUS", id))


static var _spaces := RegEx.create_from_string("[ \\t]+")
static var _bb := RegEx.create_from_string("\\[/?(b|i|center|color[^\\]]*)\\]")


## The pack language of a Hearthstone locale key ("ruRU" -> "ru").
static func pack_lang(hs: String) -> String:
	var l = CardDb.HS.find_key(hs)
	return l if l != null else hs


## A name from the active pack's locales (section "races", "classes", "rarities"…): the language,
## the pack's default language, else "".
static func term(section: String, key: String, locale := "") -> String:
	var p := Packs.active()
	if p == null:
		return ""
	for lang in [p.lang_for(pack_lang(_loc(locale))), p.default_locale()]:
		var names = p.locale(lang).get(section, {})
		if names is Dictionary and names.has(key):
			return str(names[key])
	return ""


## The card's race in a language ("" for none).
static func race(id: String, locale := "") -> String:
	var r: String = CardDb.card(id).get("race", "")
	if r == "":
		return ""
	var t := term("races", r, locale)
	return t if t != "" else r.capitalize()


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
	out = _spaces.sub(_plurals(out + s.substr(last)), " ", true).replace(" \n", "\n").replace("\n ", "\n")
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
	return _plurals(out + s.substr(last)).strip_edges()
