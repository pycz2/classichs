class_name CardDb
extends RefCounted
## The cards of the active pack (Packs.active(): cards.json and locales/<lang>.json)
## for drawing and texts, in the shape the client reads (HearthstoneJSON fields: name and
## text by Hearthstone locale, cardClass, mechanics, dbfId…): the Classic pack is built
## from that data (tools/pack.py `hsjson`), so this turns it back. Mechanic names are the
## client's (Packs.client_name). The rules engine has its own copy of the rules.

## Pack language -> the Hearthstone locale key the client keeps texts under.
const HS := {"en": "enUS", "ru": "ruRU", "de": "deDE", "fr": "frFR", "es": "esES", "pt_BR": "ptBR", "it": "itIT", "pl": "plPL"}
## Pack field -> client field (docs/packs/cards.md §4, the other way round).
const FIELDS := {"class": "cardClass", "rarity": "rarity", "set": "set", "collectible": "collectible", "cost": "cost",
	"attack": "attack", "health": "health", "durability": "durability", "race": "race", "keywords": "mechanics",
	"refs": "referencedTags", "spell_power": "spellDamage", "mana_lock": "overload", "unique": "elite",
	"code_id": "dbfId", "legacy_code_id": "legacyDbfId", "fx": "fx", "sounds": "sounds", "voice": "voice", "power": "power",
	"classes": "classes", "armor": "armor"}
const TYPES := {"CHAMPION": "HERO", "POWER": "HERO_POWER"}
const INT_FIELDS := ["dbfId", "legacyDbfId", "cost", "attack", "health", "durability", "overload", "spellDamage", "armor"]

static var _cards: Dictionary = {}
static var _by_dbf: Dictionary = {}
static var _related = null  # card id -> the cards it can bring (related()), null until asked

## related(): at most this many cards (the big card shows more than six on a turning wheel, KeywordTips).
const RELATED_MAX := 24
## A top-level line of a script that starts a card block (1) or a named helper: a local
## function or value (2, 3) or a lib function (4, 5).
static var _start := RegEx.create_from_string("^(?:cards\\.(\\w+)\\s*=|local\\s+function\\s+(\\w+)|local\\s+(\\w+)\\s*=|function\\s+(lib\\.\\w+)|(lib\\.\\w+)\\s*=)")
static var _quoted := RegEx.create_from_string("\"([^\"\\\\]*)\"")
static var _word := RegEx.create_from_string("[A-Za-z_]\\w*(?:\\.[A-Za-z_]\\w*)?")
## A line of a table keyed by a card id ("  LOOT_286 = { ... }"): a helper's table of every card's own ids
## (the Unidentified items' variants); only the card's own line counts.
static var _keyed := RegEx.create_from_string("(?m)^\\s*(\\w+)\\s*=\\s*\\{[^\\n]*")


static func reset() -> void:
	_cards = {}
	_by_dbf = {}
	_related = null
	_others = {}


static var _other: Pack  # begin(): the pack read instead of the active one
static var _others := {}  # Pack -> its caches (_state()) while another pack is read
static var _was: Array  # the active pack's caches during begin() … end()


## The pack whose cards are read: the active one, or the one between begin() and end().
static func pack() -> Pack:
	return _other if _other else Packs.active()


## Reads another pack's cards (a version of the active game: the version diff draws each card as in its version)
## until end(): card(), CardText, CardLayout and the card pictures (Art) see that pack. Each pack keeps its own caches.
static func begin(p: Pack) -> void:
	assert(_other == null, "CardDb.begin twice")
	_was = _state()
	_other = p
	_set_state(_others.get(p, [{}, {}, null, {}, {}, {}, {}, {}, []]))


static func end() -> void:
	_others[_other] = _state()
	_other = null
	_set_state(_was)


## Drops the caches of a pack begin() read (a screen that compared versions closes).
static func forget(p: Pack) -> void:
	_others.erase(p)


static func _state() -> Array:
	return [_cards, _by_dbf, _related, CardLayout._data, CardLayout._fitted, Art._textures, Art._framing, Art._designs, Art._sets]


static func _set_state(s: Array) -> void:
	_cards = s[0]
	_by_dbf = s[1]
	_related = s[2]
	CardLayout._data = s[3]
	CardLayout._fitted = s[4]
	Art._textures = s[5]
	Art._framing = s[6]
	Art._designs = s[7]
	Art._sets = s[8]


static func _ensure_loaded() -> void:
	if not _cards.is_empty():
		return
	var p := pack()
	if p == null:
		push_error("no game pack (res://packs: tools/build_packs.sh)")
		return
	var texts := {}  # lang key -> cards section
	for lang in p.manifest.get("locales", []):
		texts[HS.get(lang, lang)] = p.locale(lang).get("cards", {})
	for c: Dictionary in p.cards():
		var out := {"id": c.id, "type": TYPES.get(c.type, c.type), "name": {}}
		for k in c:
			if FIELDS.has(k):
				out[FIELDS[k]] = c[k]
		if not out.has("dbfId"):  # a pack without code numbers: a stable one from the id (deck codes)
			out.dbfId = c.id.hash()
		for k in INT_FIELDS:
			if out.has(k):
				out[k] = int(out[k])
		for k in ["mechanics", "referencedTags"]:
			if out.has(k):
				out[k] = out[k].map(Packs.client_name)
		for key in texts:
			var t: Dictionary = texts[key].get(c.id, {})
			if t.has("name"):
				out.name[key] = t.name
			if t.has("text"):
				if not out.has("text"):
					out.text = {}
				out.text[key] = t.text
		if not out.name.has("enUS"):  # the client falls back to English: the pack's default language is it
			var base: Dictionary = texts.get(HS.get(p.default_locale(), p.default_locale()), {}).get(c.id, {})
			out.name.enUS = base.get("name", c.id)
			if base.has("text"):
				out.get_or_add("text", {}).enUS = base.text
		_cards[c.id] = out
		if out.has("dbfId"):
			_by_dbf[out.dbfId] = c.id
	for id in _cards:  # the legacy numbers only where no card has the number itself
		var c: Dictionary = _cards[id]
		if c.has("legacyDbfId") and not _by_dbf.has(c.legacyDbfId):
			_by_dbf[c.legacyDbfId] = id


## A card the view hides ("") is a blank one.
static func card(id: String) -> Dictionary:
	_ensure_loaded()
	if id == "":
		return HIDDEN
	assert(_cards.has(id), "unknown card " + id)
	return _cards.get(id, HIDDEN)


const HIDDEN := {"id": "", "type": "", "name": {}, "text": {}, "mechanics": [], "cost": 0}


static func has(id: String) -> bool:
	_ensure_loaded()
	return _cards.has(id)


static func by_dbf(dbf: int) -> String:
	_ensure_loaded()
	return _by_dbf.get(dbf, "")


## The cards a deck may hold: collectible cards of the constructed mode's sets.
static func collectible() -> Array[String]:
	_ensure_loaded()
	var sets: Array = Packs.active().rules().get("modes", {}).get("constructed", {}).get("sets", ["VANILLA"])
	var out: Array[String] = []
	for id: String in _cards:
		var c: Dictionary = _cards[id]
		if c.get("collectible", false) and sets.has(c.get("set", "")):  # (a hero card too)
			out.append(id)
	out.sort()
	return out


static func all_ids() -> Array:
	_ensure_loaded()
	return _cards.keys()


## A Hero Power that works by itself and cannot be used (its text says so: Hagatha's Bewitch): it shows no cost.
static func passive_power(id: String) -> bool:
	var c := card(id)
	return c.get("type") == "HERO_POWER" and c.get("text") is Dictionary and str(c.text.get("enUS", "")).contains("Passive Hero Power")


## The cards a card can bring into the game, for its hover (summoned, made, transformed
## into, its Choose One cards, a champion's power), in a stable order, at most RELATED_MAX.
## Taken from the pack: card ids quoted in the card's script block (from `cards.<key> =` to
## the next top-level definition) and in the helpers it names (the file's local functions
## and values, lib.lua's lib.*, followed further), then the card's `power`.
static func related(id: String) -> Array:
	_ensure_loaded()
	if _related == null:
		_related = _find_related()
	return _related.get(id, [])


static func _find_related() -> Dictionary:
	var out := {}
	var p := pack()
	if p == null:
		return out
	var lib: Dictionary = _script_chunks(p, "scripts/lib.lua")[1]
	var files := {}  # script file -> [card blocks, named helpers]
	for c: Dictionary in p.cards():
		var found := []
		var s := str(c.get("script", ""))
		if s.contains("#"):
			var f := s.get_slice("#", 0)
			if not files.has(f):
				files[f] = _script_chunks(p, f)
			var named: Dictionary = lib.merged(files[f][1], true)
			var todo: Array = [files[f][0].get(s.get_slice("#", 1), "")]
			var seen := {}
			while not todo.is_empty():
				var text: String = todo.pop_front()
				for m in _keyed.search_all(text):
					if m.get_string(1) != c.id and _cards.has(m.get_string(1)):
						text = text.replace(m.get_string(), "")
				for m in _quoted.search_all(text):
					var x := m.get_string(1)
					if _cards.has(x) and x != c.id and not found.has(x):
						found.append(x)
				for m in _word.search_all(text):
					var w := m.get_string()
					if named.has(w) and not seen.has(w):
						seen[w] = true
						todo.append(named[w])
		var power := str(c.get("power", ""))
		if _cards.has(power) and power != c.id and not found.has(power):
			found.append(power)
		if not found.is_empty():
			out[c.id] = found.slice(0, RELATED_MAX)
	return out


## A script file cut at its top-level definitions: [{card key: text}, {helper name: text}],
## without comments.
static func _script_chunks(p: Pack, file: String) -> Array:
	var blocks := {}
	var named := {}
	var cur = null
	for line in p.read(file).get_string_from_utf8().split("\n"):
		var m := _start.search(line)
		if m:
			var key := m.get_string(1)
			if key != "":
				cur = blocks.get_or_add(key, [])
			else:
				for i in range(2, 6):
					if m.get_string(i) != "":
						cur = named.get_or_add(m.get_string(i), [])
		if cur != null:
			cur.append(line.get_slice("--", 0))
	for d in [blocks, named]:
		for k in d:
			d[k] = "\n".join(d[k])
	return [blocks, named]
