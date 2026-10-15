class_name Rules
extends RefCounted
## The rules engine (rust/engine, JSON API in its README): the only place where
## the game's rules run. Desktop and Android reach it through the GDExtension
## class RulesEngine (rules/classichs.gdextension), the browser through
## web/rules.js (window.ClassicRules) via JavaScriptBridge. One engine per
## process keeps many games by id.

## The engine's English messages a player may see (translated by tr_error).
const MESSAGES := ["This card can't be put in a deck", "This card belongs to another class",
	"The deck already has 30 cards", "No more copies of this card are allowed", "Unknown hero",
	"A deck needs exactly 30 cards. Cards now: %d", "Not yet! You have more cards to play!",
	"Not yet! You can still attack."]

static var _engine: Object
static var _hooks := {}
static var _ids := 0


## "" when the engine can be used, else why not (the web build loads it a moment after start).
static func missing() -> String:
	if _engine != null:
		return ""
	if ClassDB.class_exists("RulesEngine"):
		_engine = ClassDB.instantiate("RulesEngine")
		return ""
	if OS.has_feature("web"):
		var api = JavaScriptBridge.get_interface("ClassicRules")
		if api == null:
			return "rules.js is not loaded"
		if not api.ready:
			return "loading" if str(api.error) == "" else "rules.wasm: " + str(api.error)
		_engine = api
		return ""
	return "The rules engine is missing (rules/bin): build it with tools/build_rules.sh"


static func ready() -> bool:
	return missing() == ""


## One request to the engine; numbers in the reply are ints where whole.
static func request(req: Dictionary) -> Dictionary:
	var why := missing()
	if why != "":
		push_error("rules engine: " + why)
		return {"ok": false, "error": why}
	var out = JSON.parse_string(str(_engine.call_json(JSON.stringify(req))))
	return ints(out) if out is Dictionary else {"ok": false, "error": "bad reply from the rules engine"}


## JSON gives floats: whole numbers become ints (ids are dictionary keys and are compared).
static func ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if v == floorf(v) and absf(v) < 9.0e15 else v
		TYPE_ARRAY:
			for i in v.size():
				v[i] = ints(v[i])
		TYPE_DICTIONARY:
			for k in v:
				v[k] = ints(v[k])
	return v


## A fresh game id for this process.
static func new_id(prefix := "g") -> String:
	_ids += 1
	return "%s%d" % [prefix, _ids]


## What hooks a card has in the engine (on, aura, deathrattle, combo, choose_one, secret, …).
static func hooks(card_id: String) -> Dictionary:
	if _hooks.is_empty():
		_hooks = request({"op": "hooks"}).get("hooks", {})
	return _hooks.get(card_id, {})


## SHA-256 of the engine's card data (both online players must have the same).
static func data_hash() -> String:
	return str(request({"op": "data_hash"}).get("hash", ""))


## Why a deck can't be played ("" = it can), translated.
static func validate(deck: Dictionary) -> String:
	return tr_error(deck_error(deck))


## The same in the engine's English ("" = it can be played).
static func deck_error(deck: Dictionary) -> String:
	var r := request({"op": "validate", "deck": deck})
	return "" if r.ok else str(r.get("error", ""))


## An engine message in the interface language (its English text is the key).
static func tr_error(e: String) -> String:
	if e == "":
		return ""
	var cards := "A deck needs exactly 30 cards. Cards now: "
	if e.begins_with(cards):
		return TranslationServer.translate(cards + "%d") % int(e.substr(cards.length()))
	return TranslationServer.translate(e)


## Why a Debug Table scene (scenario) can't be built ("" = it can).
static func scenario_error(scene: Dictionary) -> String:
	var id := new_id("check")
	var r := request({"op": "new", "game": id, "scenario": scene})
	request({"op": "drop", "game": id})
	return "" if r.ok else str(r.get("error", "?")).trim_prefix("scenario: ")
