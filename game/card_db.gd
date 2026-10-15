class_name CardDb
extends RefCounted
## The card data (data/cards.json) for drawing and texts. The rules engine has
## its own copy built in (rust/engine); Rules.data_hash() is the one that counts online.

const INT_FIELDS := ["dbfId", "legacyDbfId", "cost", "attack", "health", "durability", "overload", "spellDamage"]

static var _cards: Dictionary = {}
static var _by_dbf: Dictionary = {}


static func _ensure_loaded() -> void:
	if not _cards.is_empty():
		return
	var text := FileAccess.get_file_as_string("res://data/cards.json")
	var list: Array = JSON.parse_string(text)
	for c: Dictionary in list:
		for k in INT_FIELDS:
			if c.has(k):
				c[k] = int(c[k])
		_cards[c.id] = c
		_by_dbf[c.dbfId] = c.id
		if c.has("legacyDbfId") and not _by_dbf.has(c.legacyDbfId):
			_by_dbf[c.legacyDbfId] = c.id


## A card the view hides ("") is a blank one.
static func card(id: String) -> Dictionary:
	_ensure_loaded()
	if id == "":
		return HIDDEN
	assert(_cards.has(id), "unknown card " + id)
	return _cards[id]


const HIDDEN := {"id": "", "type": "", "name": {}, "text": {}, "mechanics": [], "cost": 0}


static func has(id: String) -> bool:
	_ensure_loaded()
	return _cards.has(id)


static func by_dbf(dbf: int) -> String:
	_ensure_loaded()
	return _by_dbf.get(dbf, "")


static func collectible() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for id: String in _cards:
		var c: Dictionary = _cards[id]
		if c.get("collectible", false) and c.get("set", "") == "VANILLA":
			out.append(id)
	out.sort()
	return out


static func all_ids() -> Array:
	_ensure_loaded()
	return _cards.keys()

