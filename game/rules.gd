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
## Whether the engine loads packs (its `load_pack` op): -1 not asked yet, 0 no (it knows only
## its built-in Classic rules), 1 yes.
static var pack_ops := -1
## The rules hash of the pack the engine plays now ("": its built-in rules), and those it loaded
## (pack rules_hash -> the engine's).
static var _pack := ""
static var _pack_ready := false
static var _loaded := {}
## Requests that play by a pack's rules: they get `pack` (the rules hash) when the engine loaded one.
const PACK_OPS := ["new", "validate", "draft", "hooks", "data_hash"]


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
	if PACK_OPS.has(req.get("op")) and not req.has("pack"):
		if not _pack_ready:
			_pack_ready = true
			var bad := load_pack(Packs.active())
			if bad != "":
				push_warning("rules engine: " + bad)
		if _pack != "":
			req["pack"] = _pack
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


## The one place where the engine learns a pack's rules (its `load_pack` op with the pack's
## manifest, rules files and texts as a zip in base64, rust/engine README); its games then
## run on them. "" when the engine can play
## the pack, else why not. An engine without packs (it answers "unknown op") plays its
## built-in Classic rules only.
static func load_pack(p: Pack) -> String:
	var why := can_play(p)
	_pack = str(_loaded[p.rules_hash()]) if why == "" and _loaded.has(p.rules_hash()) else ""
	return why


## Whether this engine can play a pack's games ("" = it can, else why not); loads its rules
## into the engine (once) without making them the ones played.
static func can_play(p: Pack = null) -> String:
	p = p if p else Packs.active()
	if p == null:
		return "no game pack"
	var rh := p.rules_hash()
	if _loaded.has(rh):
		return ""
	if pack_ops != 0 and missing() == "":
		var r := request({"op": "load_pack", "data": Marshalls.raw_to_base64(_rules_zip(p))})
		if r.ok:
			pack_ops = 1
			_loaded[rh] = str(r.get("pack", rh))  # the engine's name for these rules (the same hash)
			return ""
		if str(r.get("error", "")) != "unknown op":
			return str(r.get("error", "?"))
		pack_ops = 0
	return "" if p.id() == Packs.CLASSIC else NEEDS_ENGINE


## The pack without its pictures, sounds and music (what the engine reads: the manifest,
## the rules files and the texts), as zip bytes.
static func _rules_zip(p: Pack) -> PackedByteArray:
	var tmp := Packs.user_dir + "/engine.tmp.zip"
	DirAccess.make_dir_recursive_absolute(Packs.user_dir)
	var z := ZIPPacker.new()
	if z.open(tmp) != OK:
		return Packs.bytes_of(p)
	for f in p.files():
		if Pack.is_rules_file(f) or f == "manifest.json" or f.begins_with("locales/"):
			z.start_file(f)
			z.write_file(p.read(f))
			z.close_file()
	z.close()
	var bytes := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(tmp)
	return bytes


## Shown when a pack's games can't be played by this engine yet.
const NEEDS_ENGINE := "This game needs a newer rules engine"


## The active pack changed: its rules are loaded on the next request.
static func pack_changed() -> void:
	_hooks = {}
	_pack = ""
	_pack_ready = false


## A fresh game id for this process.
static func new_id(prefix := "g") -> String:
	_ids += 1
	return "%s%d" % [prefix, _ids]


## What hooks a card has in the engine (on, aura, deathrattle, combo, choose_one, secret, …).
static func hooks(card_id: String) -> Dictionary:
	if _hooks.is_empty():
		_hooks = request({"op": "hooks"}).get("hooks", {})
	return _hooks.get(card_id, {})


## SHA-256 of the engine's card data (both online players must have the same) of a pack's
## rules (default: the active pack's).
static func data_hash(p: Pack = null) -> String:
	var req := {"op": "data_hash"}
	if p and can_play(p) == "" and _loaded.has(p.rules_hash()):
		req.pack = _loaded[p.rules_hash()]
	return str(request(req).get("hash", ""))


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
