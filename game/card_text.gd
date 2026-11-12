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


## The key of a card's set as players know it: "<set>:<rarity>" when the pack names or marks that
## (Classic's Basic cards: VANILLA:FREE), else its set ("" for none).
static func set_key(id: String) -> String:
	var c := CardDb.card(id)
	var s: String = c.get("set", "")
	var k := "%s:%s" % [s, c.get("rarity", "")]
	var marks = Packs.active().manifest.get("set_marks", {}) if Packs.active() else {}
	return k if s != "" and (term("sets", k) != "" or (marks is Dictionary and marks.has(k))) else s


## The name of a card's set (set_key) in a language ("" when the pack names none; not `set_name`: scripts have that).
static func card_set(id: String, locale := "") -> String:
	var k := set_key(id)
	return term("sets", k, locale) if k != "" else ""


## The card's race in a language ("" for none).
static func race(id: String, locale := "") -> String:
	var r: String = CardDb.card(id).get("race", "")
	if r == "":
		return ""
	var t := term("races", r, locale)
	return t if t != "" else r.capitalize()


static var _placeholder := RegEx.create_from_string("\\{(\\d+)\\}")
static var _before_stop := RegEx.create_from_string("[ \\x{a0}]+(?=[.,;])")
static var _double := RegEx.create_from_string("  +")


## The raw text of a card in a language, its "{0}", "{1}"… filled in with args (the engine's `text_args` of a card in a
## game: a Jade card's next Golem, a potion's two effects; an arg that is a card id stands for that card's text), or
## left out without them (in the collection: "Summon a Jade Golem.").
static func raw(id: String, locale := "", args := []) -> String:
	var t: Dictionary = CardDb.card(id).get("text", {})
	var s: String = t.get(_loc(locale), t.get("enUS", ""))
	if not s.contains("{"):
		return s
	var out := ""
	var last := 0
	for m in _placeholder.search_all(s):
		out += s.substr(last, m.get_start() - last)
		var i := int(m.get_string(1))
		var a := str(args[i]) if i < args.size() else ""
		if a != "" and a != id and CardDb.has(a):
			a = raw(a, locale).replace("[x]", "")
		out += a
		last = m.get_end()
	out += s.substr(last)
	if args.is_empty():  # the spaces and brackets around what was left out
		out = _double.sub(_before_stop.sub(out.replace("( )", "").replace("()", ""), "", true), " ", true)
	return out


## Card text as BBCode: keywords (<b>) bold, <i> italic, spaces collapsed; args: raw().
static func rich(id: String, locale := "", spellpower := 0, args := []) -> String:
	var s := raw(id, locale, args)
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
static func text(id: String, locale := "", spellpower := 0, args := []) -> String:
	var s := raw(id, locale, args)
	s = _tags.sub(s, "", true)
	var out := ""
	var last := 0
	for m in _numbers.search_all(s):
		out += s.substr(last, m.get_start() - last)
		var n := int(m.get_string(1))
		out += ("*%d*" % (n + spellpower)) if s[m.get_start()] == "$" and spellpower > 0 else str(n)
		last = m.get_end()
	return _plurals(out + s.substr(last)).strip_edges()
