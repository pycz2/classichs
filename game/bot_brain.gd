class_name BotBrain
extends RefCounted
## The game's own bot at a level (rust/brain, classichs_brain::think, the same thinking as the game
## server's bots): it sees only its player's view. It thinks off the main thread so the game does not
## stop: a thread of the GDExtension class RulesBrain on desktop and Android, a Web Worker in the
## browser (web/rules.js). `think_now` waits for the answer (tests, instant games).

const LEVELS := ["easy", "medium", "hard"]

var _native: Object
var _web_id := -1
var _reply = null


## Whether this build has the bot (the native library or the browser's worker).
static func available() -> bool:
	if ClassDB.class_exists("RulesBrain"):
		return true
	if OS.has_feature("web"):
		var api = JavaScriptBridge.get_interface("ClassicRules")
		return api != null and bool(api.ready) and bool(api.has_worker())
	return false


## The bot's request for player p of a local game: its view, its own 30 cards, the level.
static func request(game_id: String, p: int, deck: Array, level: String) -> Dictionary:
	var view: Dictionary = Rules.request({"op": "snapshot", "game": game_id, "view": p}).get("state", {})
	return {"view": view, "seat": p, "deck": deck, "level": level, "seed": randi()}


## The answer at once: {ok, action (null: nothing to do), label} (native only: the browser's bot
## lives in a worker).
static func think_now(req: Dictionary) -> Dictionary:
	if not ClassDB.class_exists("RulesBrain"):
		return {"ok": false, "error": "no RulesBrain"}
	return _parse(ClassDB.instantiate("RulesBrain").think_json(JSON.stringify(req)))


static func _parse(s: Variant) -> Dictionary:
	var out = JSON.parse_string(str(s))
	return Rules.ints(out) if out is Dictionary else {"ok": false, "error": "bad reply from the bot"}


## Starts thinking; `done()` says when the answer is there.
func start(req: Dictionary) -> void:
	_reply = null
	var text := JSON.stringify(req)
	if ClassDB.class_exists("RulesBrain"):
		_native = ClassDB.instantiate("RulesBrain")
		_native.start(text)
	elif OS.has_feature("web"):
		_web_id = int(JavaScriptBridge.get_interface("ClassicRules").think_start(text))
	else:
		_reply = {"ok": false, "error": "no bot in this build"}


func done() -> bool:
	if _reply != null:
		return true
	if _native != null:
		var s := str(_native.poll())
		if s == "":
			return false
		_reply = _parse(s)
		_native = null
		return true
	if _web_id >= 0:
		var s := str(JavaScriptBridge.get_interface("ClassicRules").think_result(_web_id))
		if s == "":
			return false
		_reply = _parse(s)
		_web_id = -1
		return true
	return true


## The answer ({ok, action, label}) once done.
func reply() -> Dictionary:
	return _reply if _reply is Dictionary else {"ok": false, "error": "still thinking"}


## The game was left while the bot thought (its thread ends by itself; the answer is dropped).
func abandon() -> void:
	_native = null
	_web_id = -1
