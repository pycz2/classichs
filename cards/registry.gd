class_name Cards
extends RefCounted
## Card hooks by card id. Each file in FILES has `static func register(r: Dictionary)`.

const FILES := ["heroes", "neutral", "druid", "hunter", "mage", "paladin", "priest", "rogue",
	"shaman", "warlock", "warrior"]

static var _hooks: Dictionary = {}


static func _ensure_loaded() -> void:
	if not _hooks.is_empty():
		return
	for f in FILES:
		load("res://cards/%s.gd" % f).register(_hooks)


static func of(card_id: String) -> Dictionary:
	_ensure_loaded()
	return _hooks.get(card_id, {})


static func add(card_id: String, hooks: Dictionary) -> void:
	_ensure_loaded()
	_hooks[card_id] = hooks


static func all_ids() -> Array:
	_ensure_loaded()
	return _hooks.keys()
