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
	"code_id": "dbfId", "legacy_code_id": "legacyDbfId", "fx": "fx", "sounds": "sounds", "voice": "voice", "power": "power"}
const TYPES := {"CHAMPION": "HERO", "POWER": "HERO_POWER"}
const INT_FIELDS := ["dbfId", "legacyDbfId", "cost", "attack", "health", "durability", "overload", "spellDamage"]

static var _cards: Dictionary = {}
static var _by_dbf: Dictionary = {}


static func reset() -> void:
	_cards = {}
	_by_dbf = {}


static func _ensure_loaded() -> void:
	if not _cards.is_empty():
		return
	var p := Packs.active()
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
		if c.get("collectible", false) and sets.has(c.get("set", "")) and c.type != "HERO":
			out.append(id)
	out.sort()
	return out


static func all_ids() -> Array:
	_ensure_loaded()
	return _cards.keys()
