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


## Drops all hooks. Call before the engine quits: hook lambdas held in a
## static Dictionary crash Godot at shutdown otherwise.
static func unload() -> void:
	_hooks.clear()


static func remove(card_id: String) -> void:
	_hooks.erase(card_id)


## Secret hooks: fires on `event` during the opponent's turn when cond(g, me, ev) holds;
## the secret is revealed, then effect(g, me, ev) runs.
static func secret(event: String, cond: Callable, effect: Callable) -> Dictionary:
	return {"on": {event: func(g, me, ev):
		if g.secret_ready(me) and cond.call(g, me, ev):
			g.reveal(me)
			effect.call(g, me, ev)}}


static func all_ids() -> Array:
	_ensure_loaded()
	return _hooks.keys()
