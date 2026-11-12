class_name PackCheck
extends RefCounted
## The pack tools of the client (ui/pack_tools.gd): make a .cardpack from a pack's source folder
## (or that folder zipped) the way tools/pack.py build does, without its recipe.json steps; check it
## the way tools/pack.py check does, as far as a client can (what it can't: site/dev/en/testing.md);
## load it into the rules engine (the rules and every card script compile); play bot-vs-bot trial
## games with its ready decks, as tools/pack_try.gd does. Every finding is an item
## {level: "error" | "warning" | "ok", text, file, line} (file "" and line 0 when not known);
## the texts are in English, like the tools' and the engine's.

const ERROR := "error"
const WARNING := "warning"
const PASS := "ok"
## docs/packs/schema, copied here by tools/build_packs.sh (docs/ is not in the game's files).
const SCHEMAS := "res://packs/schema"
const MAX_ACTIONS := 2000
const MIB := 1024 * 1024
const LIMITS := {"pack": 1024 * MIB, "unpacked": 2048 * MIB, "files": 50000, "file": 16 * MIB, "image": 2 * MIB,
	"rules": 8 * MIB, "text": 32 * MIB}
const IMAGES := ["png", "jpg", "jpeg", "webp"]
const AUDIO := ["opus", "ogg", "wav", "mp3"]
## Folder -> [extensions, depth below it: 1 = files right in it, 2 = in a sub-folder (a set), 0 = any].
const DIRS := {"scripts": [["lua", "md"], 0], "locales": [["json"], 1], "layout": [["json"], 1],
	"decks": [["json"], 1], "missions": [["json"], 1], "ui": [["png", "jpg", "jpeg", "webp", "json"], 1],
	"art": [["png", "jpg", "jpeg", "webp", "md"], 2], "sounds": [["opus", "ogg", "wav", "mp3", "md"], 2],
	"music": [["opus", "ogg", "wav", "mp3", "md"], 2], "voice": [["opus", "ogg", "wav", "mp3", "md"], 0]}
const FONT_FILES := ["ttf", "otf", "txt", "md"]

static var _path_re := RegEx.create_from_string("^[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)*$")
static var _where_re := RegEx.create_from_string(
	"((?:scripts/[A-Za-z0-9_./-]+?\\.lua)|(?:missions|decks|locales)/[A-Za-z0-9_.-]+?\\.json|rules\\.json|cards\\.json|manifest\\.json|tutorial\\.json)(?::(\\d+))?")
static var _regex := {}
static var _schemas := {}

## path -> bytes: the pack's files (built: the manifest has its fx and rules_hash).
var files := {}
## What was opened: a folder or a file name.
var source := ""
## Made from a source (a folder, a .zip), not a ready .cardpack.
var from_source := false
var items: Array = []
## The engine's name of the pack's rules once it loaded them ("" before).
var rules_hash := ""
var _parsed := {}  # path -> parsed JSON (null: broken)
var _texts := {}  # path -> text (for line numbers)
var _bytes := PackedByteArray()
var _cards := {}  # id -> card, while checking


# --- opening a source ------------------------------------------------------------------------

## A pack's source folder (docs/packs/format.md §1): every file in it, built.
static func open_folder(dir: String) -> PackCheck:
	var c := PackCheck.new()
	c.source = dir
	c.from_source = true
	if not DirAccess.dir_exists_absolute(dir):
		c._item(ERROR, "cannot read the folder " + dir)
		return c
	c._walk(dir.trim_suffix("/"), "")
	c._build()
	return c


## A file's bytes: a .cardpack is checked as it is; a .zip is a pack's source folder zipped, built.
static func open_file(bytes: PackedByteArray, file_name: String) -> PackCheck:
	var c := PackCheck.new()
	c.source = file_name
	c.from_source = not file_name.to_lower().ends_with(".cardpack")
	if bytes.size() > LIMITS.pack:
		c._item(ERROR, "the file is bigger than 1 GiB")
		return c
	var tmp := _tmp()
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		c._item(ERROR, "cannot write " + tmp)
		return c
	f.store_buffer(bytes)
	f.close()
	var z := ZIPReader.new()
	if z.open(tmp) != OK:
		DirAccess.remove_absolute(tmp)
		c._item(ERROR, "this is not a zip file")
		return c
	var all := {}
	for p in z.get_files():
		if p.ends_with("/"):
			continue
		if all.has(p):
			c._item(ERROR, "twice in the zip", p)
		all[p] = z.read_file(p)
	z.close()
	DirAccess.remove_absolute(tmp)
	if not c.from_source:
		c.files = all
		c._bytes = bytes
		return c
	# a zipped folder: maybe one folder at the top (the source's own); macOS adds __MACOSX/
	var top := ""
	if not all.has("manifest.json"):
		var tops := {}
		for p: String in all:
			if not p.begins_with("__MACOSX/"):
				tops[p.get_slice("/", 0) + "/" if p.contains("/") else ""] = true
		if tops.size() == 1 and tops.keys()[0] != "":
			top = tops.keys()[0]
	for p: String in all:
		if p.begins_with("__MACOSX/") or not p.begins_with(top):
			continue
		c._add(p.trim_prefix(top), all[p])
	c._build()
	return c


static func _tmp() -> String:
	DirAccess.make_dir_recursive_absolute(Packs.user_dir)
	return Packs.user_dir + "/pack_tools.tmp"


func _walk(dir: String, rel: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		_item(ERROR, "cannot read the folder " + dir)
		return
	d.include_hidden = false
	for f in d.get_files():
		_add(rel + f, FileAccess.get_file_as_bytes(dir + "/" + f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_walk(dir + "/" + sub, rel + sub + "/")


## A source file, as tools/pack.py build takes it: no hidden files, no Godot .import files, no
## recipe.json or *.patch.json (they are for the build, not the pack).
func _add(p: String, data: PackedByteArray) -> void:
	if Array(p.split("/")).any(func(s: String): return s.begins_with(".")) or p.ends_with(".import"):
		return
	if p == "recipe.json":
		_item(WARNING, "recipe.json: its steps are not run here (they need tools/pack.py build); the files are packed as they are", p)
		return
	if p.ends_with(".patch.json"):
		return
	files[p] = data


## What tools/pack.py build adds: the manifest's fx (every effect the cards name) and rules_hash.
func _build() -> void:
	var man = _parse("manifest.json") if files.has("manifest.json") else null
	if not man is Dictionary:
		return
	var fx := {}
	var cards = _parse("cards.json") if files.has("cards.json") else null
	for c in cards if cards is Array else []:
		if c is Dictionary and c.get("fx") is Dictionary:
			for v in c.fx.values():
				fx[str(v)] = true
	var names := fx.keys()
	names.sort()
	man = Rules.ints(man.duplicate(true))
	man.fx = names
	man.rules_hash = computed_rules_hash()
	_texts["manifest.json"] = files["manifest.json"].get_string_from_utf8()  # lines: the source's
	files["manifest.json"] = (JSON.stringify(man, " ", false) + "\n").to_utf8_buffer()
	_parsed.erase("manifest.json")


## rules_hash of the files (docs/packs/format.md §3).
func computed_rules_hash() -> String:
	var list := []
	for p: String in files:
		if Pack.is_rules_file(p):
			list.append([p, Pack.normalized(p, files[p])])
	return Pack.digest("cardpack-rules/1", list)


## The .cardpack: a zip of the files, sorted (a ready .cardpack: its own bytes).
func pack_bytes() -> PackedByteArray:
	if _bytes.is_empty():
		_bytes = PackCheck.zip(files)
	return _bytes


## A zip of the files (those only() keeps), sorted by path.
static func zip(of: Dictionary, only := Callable()) -> PackedByteArray:
	var tmp := _tmp()
	var z := ZIPPacker.new()
	if z.open(tmp) != OK:
		return PackedByteArray()
	var paths := of.keys()
	paths.sort()
	for p: String in paths:
		if only.is_null() or only.call(p):
			z.start_file(p)
			z.write_file(of[p])
			z.close_file()
	z.close()
	var out := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(tmp)
	return out


## The pack's id and version for a file name ("tiny-duel-0.1.0.cardpack").
func file_name() -> String:
	var m = _parse("manifest.json") if files.has("manifest.json") else null
	if m is Dictionary and m.get("id") is String:
		return "%s-%s.cardpack" % [m.id, str(m.get("version", "0"))]
	return "pack.cardpack"


# --- findings ----------------------------------------------------------------------------------

func _item(level: String, text: String, file := "", line := 0) -> void:
	items.append({"level": level, "text": text, "file": file, "line": line})


## An error or warning about something named in a file: its line is where the name first stands.
func _at(level: String, text: String, file: String, name := "") -> void:
	_item(level, text, file, _line(file, name) if name != "" else 0)


func _line(file: String, name: String) -> int:
	if not files.has(file):
		return 0
	if not _texts.has(file):
		_texts[file] = (files[file] as PackedByteArray).get_string_from_utf8()
	var i: int = _texts[file].find("\"" + name + "\"")
	return _texts[file].substr(0, i).count("\n") + 1 if i >= 0 else 0


func count(level: String) -> int:
	return items.filter(func(it): return it.level == level).size()


func errors() -> int:
	return count(ERROR)


# --- the file checks (tools/pack.py check) ------------------------------------------------------

func _parse(p: String) -> Variant:
	if not _parsed.has(p):
		var b: PackedByteArray = files[p]
		var v: Variant = null
		if b.size() >= 3 and b[0] == 0xEF and b[1] == 0xBB and b[2] == 0xBF:
			_item(ERROR, "UTF-8 BOM", p, 1)
		else:
			var j := JSON.new()
			if j.parse(b.get_string_from_utf8()) != OK:
				_item(ERROR, "not JSON: " + j.get_error_message(), p, j.get_error_line() + 1)  # (0 = the first line)
			else:
				v = j.data
		_parsed[p] = v
	return _parsed[p]


## A JSON file, checked against its schema (null when broken).
func _json(p: String, schema_name := "") -> Variant:
	var v = _parse(p)
	if v == null or schema_name == "":
		return v
	var errs := PackCheck.validate(v, PackCheck.schema(schema_name))
	for e: String in errs.slice(0, 20):
		_item(ERROR, e.trim_prefix("$.").trim_prefix("$"), p, _schema_line(p, v, e))
	if errs.size() > 20:
		_item(ERROR, "… and %d more schema errors" % (errs.size() - 20), p)
	return null if not errs.is_empty() else v


## The line of a schema error "$[3].power_level: unknown field …": the card's (cards.json), else its key's.
func _schema_line(p: String, v: Variant, e: String) -> int:
	var at := e.get_slice(": ", 0)
	var m := _re("^\\$\\[(\\d+)\\]").search(at)
	if m and v is Array and int(m.get_string(1)) < v.size() and v[int(m.get_string(1))] is Dictionary:
		var line := _line(p, str(v[int(m.get_string(1))].get("id", "")))
		if line > 0:
			return line
	var field := _re("unknown field '([^']+)'").search(e)
	if field:
		return _line(p, field.get_string(1))
	var keys := Array(at.split(".")).filter(func(s: String): return s != "$" and not s.begins_with("$["))
	return _line(p, keys[-1].get_slice("[", 0)) if not keys.is_empty() else 0


static func _re(pattern: String) -> RegEx:
	if not _regex.has(pattern):
		_regex[pattern] = RegEx.create_from_string(pattern)
	return _regex[pattern]


static func schema(name: String) -> Dictionary:
	if not _schemas.has(name):
		var v = JSON.parse_string(FileAccess.get_file_as_string(SCHEMAS + "/" + name)) \
			if FileAccess.file_exists(SCHEMAS + "/" + name) else null
		_schemas[name] = v if v is Dictionary else {}
		if not v is Dictionary:
			push_warning("pack check: no schema " + name + " (tools/build_packs.sh copies them)")
	return _schemas[name]


static func _is(v: Variant, t: String) -> bool:
	match t:
		"integer": return v is int or (v is float and v == floorf(v))
		"number": return v is int or v is float
		"object": return v is Dictionary
		"array": return v is Array
		"string": return v is String
		"boolean": return v is bool
		"null": return v == null
	return false


static func _same(a: Variant, b: Variant) -> bool:
	return (typeof(a) == typeof(b) or (_is(a, "number") and _is(b, "number"))) and a == b


## Errors of v against a schema: the JSON Schema subset tools/pack.py validate knows (type, enum,
## const, pattern, min/max(Length|Items|imum), uniqueItems, properties, required,
## additionalProperties, propertyNames, items, anyOf, local $ref).
static func validate(v: Variant, s: Dictionary, root: Variant = null, at := "$") -> Array:
	var top: Dictionary = root if root is Dictionary else s
	if s.has("$ref"):
		var node: Variant = top
		for part in str(s["$ref"]).trim_prefix("#/").split("/"):
			node = node.get(part, {}) if node is Dictionary else {}
		return validate(v, node, top, at)
	if s.has("anyOf"):
		for x in s.anyOf:
			if validate(v, x, top, at).is_empty():
				return []
		return ["%s: matches none of the allowed forms" % at]
	var errs := []
	if s.has("type"):
		var types: Array = s.type if s.type is Array else [s.type]
		if not types.any(func(t): return _is(v, t)):
			return ["%s: expected %s, got %s" % [at, "/".join(types), _kind(v)]]
	if s.has("const") and not _same(v, s.const):
		errs.append("%s: must be %s" % [at, JSON.stringify(s.const)])
	if s.has("enum") and not s.enum.any(func(x): return _same(v, x)):
		errs.append("%s: %s is not one of %s" % [at, JSON.stringify(v), JSON.stringify(s.enum)])
	if v is String:
		if s.has("pattern") and _re(s.pattern).search(v) == null:
			errs.append("%s: %s does not match %s" % [at, JSON.stringify(v), s.pattern])
		if v.length() > s.get("maxLength", v.length()) or v.length() < s.get("minLength", 0):
			errs.append("%s: length %d out of range" % [at, v.length()])
	if _is(v, "number") and (v < s.get("minimum", v) or v > s.get("maximum", v)):
		errs.append("%s: %s out of range" % [at, Rules.ints(v)])
	if v is Array:
		if v.size() > s.get("maxItems", v.size()) or v.size() < s.get("minItems", 0):
			errs.append("%s: %d items, out of range" % [at, v.size()])
		if s.get("uniqueItems", false):
			var seen := {}
			for x in v:
				seen[JSON.stringify(x, "", true)] = true
			if seen.size() != v.size():
				errs.append("%s: items repeat" % at)
		if s.has("items"):
			for i in v.size():
				errs.append_array(validate(v[i], s.items, top, "%s[%d]" % [at, i]))
	if v is Dictionary:
		var props: Dictionary = s.get("properties", {})
		for k in s.get("required", []):
			if not v.has(k):
				errs.append("%s: missing '%s'" % [at, k])
		for k in v:
			if s.has("propertyNames"):
				errs.append_array(validate(k, s.propertyNames, top, "%s.%s (key)" % [at, k]))
			if props.has(k):
				errs.append_array(validate(v[k], props[k], top, "%s.%s" % [at, k]))
			elif s.get("additionalProperties") is bool and s.additionalProperties == false:
				errs.append("%s: unknown field '%s'" % [at, k])
			elif s.get("additionalProperties") is Dictionary:
				errs.append_array(validate(v[k], s.additionalProperties, top, "%s.%s" % [at, k]))
	return errs


static func _kind(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY: return "object"
		TYPE_ARRAY: return "array"
		TYPE_STRING: return "string"
		TYPE_BOOL: return "boolean"
		TYPE_NIL: return "null"
	return "number"


static func _fraction(v: Variant) -> bool:
	if v is float:
		return v != floorf(v)
	if v is Dictionary:
		return v.values().any(_fraction)
	if v is Array:
		return v.any(_fraction)
	return false


## The paths, folders, extensions and sizes of docs/packs/format.md §1.
func _check_paths() -> void:
	var total := 0
	var text := 0
	var rules := 0
	for p: String in files:
		var size: int = files[p].size()
		total += size
		if _path_re.search(p) == null or p.length() > 200:
			_item(ERROR, "bad path (letters, digits, _ . - and /, no leading dot, at most 200 characters)", p)
			continue
		if size > LIMITS.file:
			_item(ERROR, "%d bytes, more than %d" % [size, LIMITS.file], p)
		var parts := p.split("/")
		if parts.size() == 1:
			if not Pack.TOP_FILES.has(p):
				_item(ERROR, "not allowed at the top (allowed: %s)" % ", ".join(Pack.TOP_FILES), p)
			continue
		var top := parts[0]
		if not DIRS.has(top):
			_item(ERROR, "unknown folder %s/" % top, p)
			continue
		var exts: Array = DIRS[top][0]
		var depth: int = DIRS[top][1]
		var ext := p.get_extension().to_lower()
		if top == "ui" and parts.size() == 3 and parts[1] == "fonts":
			exts = FONT_FILES
			depth = 2
		elif top == "ui" and ext == "json" and p != "ui/theme.json":
			_item(ERROR, "the only JSON file in ui/ is theme.json", p)
		if not exts.has(ext):
			_item(ERROR, "%s/ holds only %s" % [top, " ".join(exts.map(func(e): return "." + e))], p)
		if depth != 0 and parts.size() - 1 != depth:
			_item(ERROR, "%s/ files go %s" % [top, "right in it" if depth == 1 else "in a sub-folder (a set)"], p)
		if IMAGES.has(ext) and size > LIMITS.image:
			_item(ERROR, "picture of %d bytes, more than %d" % [size, LIMITS.image], p)
		if top in ["locales", "layout"]:
			text += size
		if Pack.is_rules_file(p):
			rules += size
	if files.size() > LIMITS.files:
		_item(ERROR, "%d files, more than %d" % [files.size(), LIMITS.files])
	for row in [["unpacked", total], ["rules", rules], ["text", text]]:
		if row[1] > LIMITS[row[0]]:
			_item(ERROR, "%s size %d is more than %d" % [row[0], row[1], LIMITS[row[0]]])


## Every check of tools/pack.py check_files the client can make.
func check() -> void:
	var before := errors()
	_check_paths()
	for need in ["manifest.json", "rules.json", "cards.json"]:
		if not files.has(need):
			_item(ERROR, need + " is missing")
	if errors() > before:
		return
	var man = _json("manifest.json", "manifest.schema.json")
	var rules = _json("rules.json", "rules.schema.json")
	var card_list = _json("cards.json", "cards.schema.json")
	if man == null or rules == null or card_list == null:
		return
	for p: String in files:
		if Pack.is_rules_file(p) and p.ends_with(".json") and _fraction(_parse(p)):
			_item(ERROR, "fractions are not allowed (whole numbers only)", p)
	var voc: Dictionary = schema("keywords.json")
	var engine_ids := {}
	var kinds := {}
	for k in voc.get("keywords", []):
		engine_ids[k.id] = true
		kinds[k.id] = k.kind
	var cards := {}
	for c in card_list:
		if cards.has(c.id):
			_at(ERROR, "card %s twice" % c.id, "cards.json", c.id)
		cards[c.id] = c
	_cards = cards
	var card := _card

	# rules
	for name in rules.mechanics:
		if not engine_ids.has(rules.mechanics[name].engine):
			_at(ERROR, "mechanic %s maps to %s, not an engine keyword (docs/packs/schema/keywords.json)" % [name, rules.mechanics[name].engine], "rules.json", name)
	var classes := {}
	for c in rules.classes:
		classes[c.id] = true
	if not rules.classes.any(func(c): return c.get("neutral", false)):
		_item(WARNING, "no class is neutral", "rules.json")
	for c in rules.classes:
		if c.has("champion"):
			var champ = card.call(c.champion, "class " + c.id, "rules.json", "CHAMPION")
			if champ and champ.class != c.id:
				_at(ERROR, "champion %s of %s is of class %s" % [c.champion, c.id, champ.class], "rules.json", c.champion)
	var rarities := {}
	for x in rules.rarities:
		rarities[x.id] = true
	for rid in rules.limits.get("copies_by_rarity", {}):
		if not rarities.has(rid):
			_at(ERROR, "copies_by_rarity names unknown rarity " + rid, "rules.json", rid)
	var sets := {}
	for s in rules.get("sets", []):
		sets[s] = true
	var races := {}
	for s in rules.get("races", []):
		races[s] = true
	if rules.start.get("coin"):
		card.call(rules.start.coin, "start.coin", "rules.json", "SPELL")
	if rules.has("default_power"):
		card.call(rules.default_power, "default_power", "rules.json", "POWER")
	elif card_list.any(func(c): return c.type == "CHAMPION"):
		_item(ERROR, "default_power is missing (the engine needs it whenever the pack has champions)", "rules.json")
	var modes: Dictionary = rules.modes
	for mname in modes:
		for s in modes[mname].sets:
			if not sets.has(s):
				_at(ERROR, "modes.%s uses unknown set %s" % [mname, s], "rules.json", s)
	for rid in modes.constructed.get("starter_rarities", []):
		if not rarities.has(rid):
			_at(ERROR, "starter_rarities names unknown rarity " + rid, "rules.json", rid)
	for cid in modes.constructed.get("starter_core", []):
		var c = card.call(cid, "starter_core", "rules.json")
		if c and not c.get("collectible", false):
			_at(ERROR, "starter_core card %s is not collectible" % cid, "rules.json", cid)
	if modes.has("arena"):
		var a: Dictionary = modes.arena
		for cls in a.classes:
			if not classes.has(cls):
				_at(ERROR, "arena class %s unknown" % cls, "rules.json", cls)
		if a.tier_weights.values().reduce(func(x, y): return x + y, 0) <= 0:
			_at(ERROR, "arena tier_weights add up to 0", "rules.json", "tier_weights")
		for n in a.get("special_picks", []):
			if n > a.picks:
				_at(ERROR, "arena special pick %d is after the last pick" % n, "rules.json", "special_picks")
	var ranked = rules.get("ranked")
	if ranked:
		var nums: Array = ranked.ranks.map(func(x): return int(x.rank))
		var down := nums.duplicate()
		down.sort()
		down.reverse()
		var unique := {}
		for n in nums:
			unique[n] = true
		if nums.is_empty() or nums != down or unique.size() != nums.size() or nums[-1] != 1 or nums[0] != nums.size():
			_at(ERROR, "ranked.ranks must run from the lowest rank (N) down to 1, one each", "rules.json", "ranks")
		for x in ranked.ranks + ([ranked.legend] if ranked.get("legend") else []):
			var em = x.get("emblem")
			if em and em.has("card"):
				card.call(em.card, "rank %s emblem" % str(Rules.ints(x.get("rank", "legend"))), "rules.json")
			if em and em.has("image") and not files.has(em.image):
				_at(ERROR, "emblem %s is not in the pack" % em.image, "rules.json", em.image)

	# cards
	var fxc: Dictionary = schema("fx.json")
	var fx_names := {"element": fxc.get("elements", [])}
	for slot in ["cast", "hit", "play", "death"]:
		fx_names[slot] = fxc.get(slot, [])
	for c in card_list:
		var at: String = c.id
		if not classes.has(c.class):
			_at(ERROR, "%s: unknown class %s" % [at, c.class], "cards.json", at)
		if c.has("rarity") and not rarities.has(c.rarity):
			_at(ERROR, "%s: unknown rarity %s" % [at, c.rarity], "cards.json", at)
		if c.has("set") and not sets.is_empty() and not sets.has(c.set):
			_at(ERROR, "%s: unknown set %s" % [at, c.set], "cards.json", at)
		if c.has("race") and not races.has(c.race):
			_at(ERROR, "%s: unknown race %s" % [at, c.race], "cards.json", at)
		for k in c.get("keywords", []) + c.get("refs", []):
			if not rules.mechanics.has(k):
				_at(ERROR, "%s: mechanic %s is not in rules.json mechanics" % [at, k], "cards.json", at)
		if c.type == "CHAMPION":
			if c.has("power"):
				card.call(c.power, at + " power", "cards.json", "POWER")
			elif not rules.has("default_power"):
				_at(ERROR, "%s: a champion needs a power (or rules.json default_power)" % at, "cards.json", at)
		elif c.has("power"):
			_at(ERROR, "%s: only a CHAMPION has a power" % at, "cards.json", at)
		if c.has("script") and not files.has(c.script.get_slice("#", 0)):
			_at(ERROR, "%s: script %s is not in the pack" % [at, c.script.get_slice("#", 0)], "cards.json", at)
		for slot in c.get("fx", {}):
			if not c.fx[slot] in fx_names.get(slot, []):
				_at(WARNING, "%s: fx.%s '%s' is not in the catalog (the client shows its default)" % [at, slot, c.fx[slot]], "cards.json", at)
		for slot in c.get("sounds", {}):
			var name: String = c.sounds[slot]
			if not files.keys().any(func(p: String): return p.begins_with("sounds/") and p.get_file().get_basename() == name):
				_at(WARNING, "%s: sound %s is in no sound set" % [at, name], "cards.json", at)

	# the manifest and the files it names
	var langs: Array = man.locales
	if not langs.has(man.default_locale):
		_at(ERROR, "default_locale is not in locales", "manifest.json", "default_locale")
	if man.get("rules_hash") and man.rules_hash != computed_rules_hash():
		_at(ERROR, "rules_hash does not match the pack (build it again)", "manifest.json", "rules_hash")
	for key in ["card_back", "logo"]:
		if man.get(key) and not files.has(man[key]):
			_at(ERROR, "%s %s is not in the pack" % [key, man[key]], "manifest.json", key)
	var marks = man.get("set_marks", {})
	for key in marks if marks is Dictionary else {}:
		var icon = marks[key].get("icon") if marks[key] is Dictionary else null
		if icon and not files.has(icon):
			_at(ERROR, "set_marks.%s icon %s is not in the pack" % [key, icon], "manifest.json", "set_marks")
	if files.has("ui/theme.json"):
		var theme = _json("ui/theme.json", "theme.schema.json")
		if theme is Dictionary:
			for kf in [["fonts", "title"], ["fonts", "body"], ["button", "texture"], ["panel", "texture"]]:
				var f = theme.get(kf[0], {}).get(kf[1])
				if f and not files.has(f):
					_at(ERROR, "%s is not in the pack" % f, "ui/theme.json", f)
	for kt in [["art_sets", "art"], ["sound_sets", "sounds"], ["music_sets", "music"]]:
		var listed := {}
		for s in man.get(kt[0], []):
			listed[s.id] = true
		var present := {}
		for p: String in files:
			if p.begins_with(kt[1] + "/"):
				present[p.get_slice("/", 1)] = true
		for s in listed:
			if not present.has(s):
				_at(ERROR, "%s %s has no files in %s/%s/" % [kt[0], s, kt[1], s], "manifest.json", s)
		for s in present:
			if not listed.has(s):
				_item(ERROR, "%s/%s/ is not listed in manifest.json %s" % [kt[1], s, kt[0]], "manifest.json")
		if man.get(kt[0], []).filter(func(s): return s.get("default", false)).size() > 1:
			_at(ERROR, "more than one default in " + kt[0], "manifest.json", kt[0])
	for s in man.get("art_sets", []):
		var stems := {}
		for p: String in files:
			if p.begins_with("art/%s/" % s.id) and not p.ends_with(".md"):
				stems[p.get_file().get_basename()] = true
		var unknown := stems.keys().filter(func(x): return not cards.has(x))
		unknown.sort()
		if not unknown.is_empty():
			_item(WARNING, "art/%s/: %d pictures of no card (%s)" % [s.id, unknown.size(), ", ".join(unknown.slice(0, 5))])
		var missing := cards.keys().filter(func(x): return not stems.has(x))
		missing.sort()
		if not missing.is_empty() and s.get("default", false):
			_item(WARNING, "art/%s/: no picture for %d cards (%s)" % [s.id, missing.size(), ", ".join(missing.slice(0, 5))])

	# locales and layouts
	var texts := files.keys().filter(func(p: String): return p.begins_with("locales/") or p.begins_with("layout/"))
	texts.sort()
	for p: String in texts:
		if not langs.has(p.get_file().get_basename()):
			_item(ERROR, "%s is not in manifest.json locales" % p.get_file().get_basename(), p)
	for lang in langs:
		var p := "locales/%s.json" % lang
		if not files.has(p):
			_at(ERROR, "%s is missing (manifest.json lists %s)" % [p, lang], "manifest.json", "locales")
			continue
		var loc = _json(p, "locale.schema.json")
		if loc == null:
			continue
		var names: Dictionary = loc.get("cards", {})
		for cid in names:
			if not cards.has(cid):
				_at(WARNING, "text of unknown card " + cid, p, cid)
		var nameless := cards.keys().filter(func(cid): return not names.get(cid, {}).get("name"))
		if not nameless.is_empty():
			_item(ERROR if lang == man.default_locale else WARNING,
				"%d cards without a name (%s)" % [nameless.size(), ", ".join(nameless.slice(0, 5))], p)
		if lang == man.default_locale:
			var used := {}
			for c in card_list:
				for k in c.get("keywords", []):
					used[k] = true
			var list := used.keys()
			list.sort()
			for k in list:
				var engine = rules.mechanics.get(k, {}).get("engine")
				if kinds.get(engine) in ["keyword", "hook"] and not loc.get("mechanics", {}).has(k):
					_item(WARNING, "mechanic %s has no name or tip" % k, p)
	for p: String in texts:
		if p.begins_with("layout/"):
			var lay = _json(p, "layout.schema.json")
			if lay is Dictionary:
				var stray: Array = lay.keys().filter(func(cid): return not cards.has(cid))
				if not stray.is_empty():
					_at(WARNING, "layout of %d unknown cards" % stray.size(), p, stray[0])

	# decks and missions
	var paths := files.keys()
	paths.sort()
	for p: String in paths:
		if p.begins_with("decks/"):
			var d = _json(p, "deck.schema.json")
			if d != null:
				var why := deck_error(d, cards, rules)
				if why != "":
					_item(ERROR, "illegal deck: " + why, p)
	for p: String in paths:
		if not p.begins_with("missions/"):
			continue
		var m = _json(p, "mission.schema.json")
		if m == null:
			continue
		card.call(m.champion, "champion", p, "CHAMPION")
		card.call(m.boss, "boss", p, "CHAMPION")
		if m.has("boss_power"):
			card.call(m.boss_power, "boss_power", p, "POWER")
		for cid in m.player.hand + m.player.deck + m.boss_deck + ([m.reward] if m.has("reward") else []):
			card.call(cid, "a card", p)
		if m.get("script") and not files.has(str(m.script).get_slice("#", 0)):
			_at(ERROR, "script %s is not in the pack" % m.script, p, "script")
	_check_tutorial(man, rules, card)


## A card the pack names (an error when it has none, or it is not of that type).
func _card(cid: String, at: String, file: String, kind := "") -> Variant:
	var c = _cards.get(cid)
	if c == null:
		_at(ERROR, "%s: unknown card %s" % [at, cid], file, cid)
	elif kind != "" and c.type != kind:
		_at(ERROR, "%s: %s is a %s, not a %s" % [at, cid, c.type, kind], file, cid)
	return c


## Why a deck is illegal by the pack's rules ("" = legal): tools/pack.py deck_error.
static func deck_error(deck: Dictionary, cards: Dictionary, rules: Dictionary) -> String:
	var by_class := {}
	var champ_class := {}
	var neutral := {}
	for c in rules.classes:
		by_class[c.id] = c
		if c.has("champion"):
			champ_class[c.champion] = c.id
		if c.get("neutral", false):
			neutral[c.id] = true
	var limits: Dictionary = rules.limits
	var arena: bool = deck.get("arena", false)
	var mode: Dictionary = rules.modes.get("arena" if arena else "constructed", {})
	var cls = champ_class.get(deck.champion)
	if cls == null or by_class[cls].get("playable", true) == false:
		return "unknown champion " + deck.champion
	var counts := {}
	for cid in deck.cards:
		var c = cards.get(cid)
		if c == null or not c.get("collectible", false) or not c.get("set") in mode.get("sets", []) or c.type == "CHAMPION":
			return cid + " can't be put in a deck"
		if not neutral.has(c.class) and c.class != cls:
			return cid + " belongs to another class"
		counts[cid] = counts.get(cid, 0) + 1
		var most := int(mode.get("copies", 0) if arena else limits.get("copies_by_rarity", {}).get(c.get("rarity"), limits.get("copies", 2)))
		if most > 0 and counts[cid] > most:
			return "more than %d copies of %s" % [most, cid]
	if deck.cards.size() != int(limits.get("deck_size", 30)):
		return "a deck needs exactly %d cards, it has %d" % [int(limits.get("deck_size", 30)), deck.cards.size()]
	return ""


## tutorial.json (docs/packs/format.md §12): tools/pack.py check_tutorial.
func _check_tutorial(man: Dictionary, rules: Dictionary, card: Callable) -> void:
	var has_missions := files.keys().any(func(p: String): return p.begins_with("missions/"))
	if not files.has("tutorial.json"):
		if has_missions:
			_item(WARNING, "missions/ without tutorial.json: the game shows no tutorial")
		return
	var t = _json("tutorial.json", "tutorial.schema.json")
	if t == null:
		return
	var base: String = man.default_locale
	var locs := {}
	for lang in man.locales:
		var p := "locales/%s.json" % lang
		if files.has(p) and _parse(p) is Dictionary:
			locs[lang] = _parse(p)
	var text := func(path: Array, file: String, name: String, where: String, required: bool) -> void:
		for lang in locs:
			var v: Variant = locs[lang]
			for k in path:
				v = v.get(k) if v is Dictionary else null
			if not v is String or v.strip_edges() == "":
				_at(ERROR if lang == base and required else WARNING,
					"%s: no text %s in locales/%s.json" % [where, ".".join(path), lang], file, name)
	var seen := {}
	for i in t.missions.size():
		var ms: Dictionary = t.missions[i]
		var at := "missions[%d]" % i
		var n := int(ms.id)
		if seen.has(n):
			_item(ERROR, "%s: mission %d twice" % [at, n], "tutorial.json")
		seen[n] = true
		var p := "missions/%d.json" % n
		if not files.has(p):
			_item(ERROR, "%s: %s is not in the pack" % [at, p], "tutorial.json")
			continue
		var m = _parse(p)
		if not m is Dictionary:
			continue
		text.call(["missions", str(n), "intro"], "tutorial.json", "", at, true)
		for k in ["start", "hurt", "defeat"]:
			text.call(["missions", str(n), "lines", k], "tutorial.json", "", at, false)
		if m.get("reward"):
			text.call(["missions", str(n), "reward_line"], "tutorial.json", "", at, false)
		for h in m.get("hints", []):
			if not t.get("hints", {}).has(h):
				_at(ERROR, "hint %s has no rule in tutorial.json hints" % h, p, h)
			text.call(["hints", h], p, h, "hint " + h, true)
		for j in ms.get("intro", []).size():
			var page: Dictionary = ms.intro[j]
			var where := "%s.intro[%d]" % [at, j]
			text.call(["tutorial", page.title], "tutorial.json", page.title, where, true)
			text.call(["tutorial", page.text], "tutorial.json", page.text, where, true)
			var cards := 0
			for it in page.get("items", []):
				if it.has("card"):
					card.call(it.card, where, "tutorial.json")
					cards += 1
				elif it.has("hero"):
					card.call(it.hero, where, "tutorial.json", "CHAMPION")
				elif it.has("picture") and not files.has(it.picture):
					_at(ERROR, "%s: picture %s is not in the pack" % [where, it.picture], "tutorial.json", it.picture)
				elif it.has("note"):
					text.call(["tutorial", it.note], "tutorial.json", it.note, where, true)
					if it.get("to") is Dictionary and int(it.to.card) >= cards:
						_at(ERROR, "%s: note %s points at card %d, the page has %d before it" % [where, it.note, int(it.to.card), cards], "tutorial.json", it.note)
	for h in t.get("hints", {}):
		for c in t.hints[h]:
			for cid in c.get("cards", []):
				card.call(cid, "hints." + h, "tutorial.json")
			if c.get("keyword") and not rules.get("mechanics", {}).has(c.keyword):
				_at(WARNING, "hints.%s: keyword %s is not in rules.json mechanics" % [h, c.keyword], "tutorial.json", h)


# --- the engine ---------------------------------------------------------------------------------

## The file and line an engine message names ("scripts/sun.lua:16: …"): [file, line].
static func locate(message: String) -> Array:
	var m := _where_re.search(message)
	return [m.get_string(1), int(m.get_string(2))] if m else ["", 0]


## Loads the pack's rules into the rules engine (it compiles every card script). False when it refuses.
func load_engine() -> bool:
	var why := Rules.missing()
	if why != "":
		_item(ERROR, "the rules engine is missing: " + why)
		return false
	var data := PackCheck.zip(files, func(p: String): return Pack.is_rules_file(p) or p == "manifest.json" or p.begins_with("locales/"))
	var r := Rules.request({"op": "load_pack", "data": Marshalls.raw_to_base64(data)})
	if not r.get("ok", false):
		var e := str(r.get("error", "?")).trim_prefix("bad pack: ")
		var at := locate(e)
		_item(ERROR, "the engine refuses the pack: " + e, at[0], at[1])
		return false
	rules_hash = str(r.get("pack", ""))
	var scripts := files.keys().filter(func(p: String): return p.begins_with("scripts/") and p.ends_with(".lua")).size()
	_item(PASS, "the engine loads the pack: its rules and %d scripts compile" % scripts)
	return true


## The pack's ready decks: [{name, champion, cards}], by file name.
func decks() -> Array:
	var out := []
	var paths := files.keys().filter(func(p: String): return p.begins_with("decks/") and p.ends_with(".json"))
	paths.sort()
	for p in paths:
		var d = _parse(p)
		if d is Dictionary and d.get("champion") is String and d.get("cards") is Array:
			out.append({"name": str(d.get("name", p.get_file())), "champion": d.champion, "cards": d.cards})
	return out


## Trial game i of a bot-vs-bot run (after load_engine): deck i against the next one, as
## tools/pack_try.gd plays it; one item says how it went. True when it ended well.
func trial(i: int) -> bool:
	var list := decks()
	if list.is_empty():
		_item(WARNING, "no ready decks (decks/*.json): no trial games")
		return false
	var d0: Dictionary = list[i % list.size()]
	var d1: Dictionary = list[(i + 1) % list.size()]
	var game := Rules.new_id("pack_try")
	var vs := "game %d (%s vs %s)" % [i + 1, d0.name, d1.name]
	var r := Rules.request({"op": "new", "game": game, "pack": rules_hash, "seed": 1000 + i,
		"decks": [{"hero": d0.champion, "cards": d0.cards}, {"hero": d1.champion, "cards": d1.cards}]})
	if not r.get("ok", false):
		_item(ERROR, "%s does not start: %s" % [vs, r.get("error", "?")])
		return false
	var actions := 0
	while not r.get("over", false) and actions < MAX_ACTIONS:
		var moved := false
		for p in 2:  # in the mulligan both players act; then the current one
			var b := Rules.request({"op": "bot", "game": game, "player": p})
			if b.get("action") is Dictionary:
				r = Rules.request({"op": "act", "game": game, "action": b.action})
				moved = true
				actions += 1
				break
		if not moved or not r.get("ok", false):
			break
	Rules.request({"op": "drop", "game": game})
	var how := "turn %d, %d actions" % [int(r.get("turn", 0)), actions]
	if r.has("script_error"):
		var at := locate(str(r.script_error))
		_item(ERROR, "%s: a card script failed at %s: %s" % [vs, how, r.script_error], at[0], at[1])
		return false
	if not r.get("over", false):
		_item(ERROR, "%s got stuck at %s: %s" % [vs, how, r.get("error", "no move")])
		return false
	var w := int(r.get("winner", -1))
	_item(PASS, "%s: %s, %s" % [vs, how, "a draw" if w < 0 else "won by " + [d0.name, d1.name][w]])
	return true
