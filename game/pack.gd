class_name Pack
extends RefCounted
## One game pack (a .cardpack zip, docs/packs/format.md), read straight from the
## zip with ZIPReader (nothing is unpacked). Packs (game/packs.gd) keeps the list.

## Where it came from: "builtin" (res://packs), "imported" (a file), "downloaded" (a server), "p2p".
var origin := "builtin"
var path := ""
var manifest := {}
## Bytes of the .cardpack file.
var size := 0
## The server a downloaded pack came from ("" for others).
var server := ""
var _zip: ZIPReader
var _files := {}  # path -> true (no directory entries)
var _json := {}  # path -> parsed value (cached)
var _content_hash := ""
var _rules_hash := ""
var _twice := false  # a file is in the zip twice

const MIB := 1024 * 1024
## docs/packs/format.md, "Size limits".
const LIMITS := {"pack": 128 * MIB, "unpacked": 256 * MIB, "files": 10000, "file": 16 * MIB, "image": 2 * MIB}
const TOP_FILES := ["manifest.json", "rules.json", "cards.json", "README.md", "CREDITS.md", "LICENSE.txt"]
const DIRS := ["scripts", "locales", "layout", "decks", "missions", "ui", "art", "sounds", "music", "voice"]
const PRESENTATION := ["fx", "sounds", "voice"]
const IMAGE_EXT := ["png", "jpg", "jpeg", "webp"]
const AUDIO_EXT := ["ogg", "wav", "mp3"]

static var _segment := RegEx.create_from_string("^[A-Za-z0-9_][A-Za-z0-9_.-]*$")
static var _id_re := RegEx.create_from_string("^[a-z0-9][a-z0-9._-]{0,63}$")


## The pack in a file, or null when it is not a readable zip with a manifest.
static func open(p_path: String, p_origin := "builtin") -> Pack:
	var z := ZIPReader.new()
	if z.open(p_path) != OK:
		return null
	var p := Pack.new()
	p.path = p_path
	p.origin = p_origin
	p._zip = z
	for f in z.get_files():
		if not f.ends_with("/"):
			p._twice = p._twice or p._files.has(f)
			p._files[f] = true
	var f := FileAccess.open(p_path, FileAccess.READ)
	p.size = f.get_length() if f else 0
	var m = p.json("manifest.json")
	if not m is Dictionary:
		z.close()
		return null
	p.manifest = m
	return p


func close() -> void:
	if _zip:
		_zip.close()
		_zip = null


func id() -> String:
	return str(manifest.get("id", ""))


func version() -> String:
	return str(manifest.get("version", ""))


## The rules hash the manifest gives (the build writes it; problems() checks it).
func rules_hash() -> String:
	return str(manifest.get("rules_hash", ""))


func builtin() -> bool:
	return origin == "builtin"


func has(file: String) -> bool:
	return _files.has(file)


func files() -> Array:
	var out := _files.keys()
	out.sort()  # code point order = UTF-8 byte order (format.md, "Hashes")
	return out


func read(file: String) -> PackedByteArray:
	if _zip == null or not _files.has(file):
		return PackedByteArray()
	return _zip.read_file(file)


## A JSON file of the pack (parsed once; null when missing or broken).
func json(file: String) -> Variant:
	if not _json.has(file):
		var j := JSON.new()
		var bytes := read(file)
		_json[file] = j.data if not bytes.is_empty() and j.parse(bytes.get_string_from_utf8()) == OK else null
	return _json[file]


func rules() -> Dictionary:
	var r = json("rules.json")
	return r if r is Dictionary else {}


func cards() -> Array:
	var c = json("cards.json")
	return c if c is Array else []


## locales/<lang>.json ({} when the pack has no such language).
func locale(lang: String) -> Dictionary:
	var l = json("locales/%s.json" % lang)
	return l if l is Dictionary else {}


func default_locale() -> String:
	return str(manifest.get("default_locale", "en"))


## The pack's language for an interface language: itself, its base ("pt_BR" -> "pt"), else the default.
func lang_for(lang: String) -> String:
	var have: Array = manifest.get("locales", [])
	if have.has(lang):
		return lang
	for l in have:
		if str(l).get_slice("_", 0) == lang.get_slice("_", 0):
			return l
	return default_locale()


## A {lang: text} of the manifest in a language (the default language, then any).
func text_of(by_lang: Variant, lang := "") -> String:
	if not by_lang is Dictionary or by_lang.is_empty():
		return str(by_lang) if by_lang is String else ""
	var l := lang if lang != "" else TranslationServer.get_locale()
	for k in [l, l.get_slice("_", 0), default_locale(), "en"]:
		if by_lang.has(k):
			return str(by_lang[k])
	return str(by_lang.values()[0])


## The pack's name in a language.
func title(lang := "") -> String:
	var t := text_of(manifest.get("name", {}), lang)
	return t if t != "" else id()


func description(lang := "") -> String:
	return text_of(manifest.get("description", {}), lang)


## The art, sound or music sets ("art", "sound", "music"): [{id, name?, default?, local?}].
func sets(kind: String) -> Array:
	var s = manifest.get(kind + "_sets", [])
	return s if s is Array else []


func default_set(kind: String) -> String:
	var all := sets(kind)
	for s in all:
		if s.get("default", false):
			return str(s.id)
	return str(all[0].id) if not all.is_empty() else ""


## A picture of the pack as a texture (null when missing or not a picture).
func texture(file: String) -> Texture2D:
	var img := image(file)
	return ImageTexture.create_from_image(img) if img else null


func image(file: String) -> Image:
	var bytes := read(file)
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err: int
	match file.get_extension().to_lower():
		"png": err = img.load_png_from_buffer(bytes)
		"webp": err = img.load_webp_from_buffer(bytes)
		_: err = img.load_jpg_from_buffer(bytes)
	return img if err == OK else null


## A sound or music file of the pack (null when missing).
func stream(file: String) -> AudioStream:
	var bytes := read(file)
	if bytes.is_empty():
		return null
	match file.get_extension().to_lower():
		"ogg": return AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav": return AudioStreamWAV.load_from_buffer(bytes)
		"mp3":
			var s := AudioStreamMP3.new()
			s.data = bytes
			return s
	return null


## The first file of a folder named name.<one of the extensions> ("" when none).
func find(folder: String, name: String, exts: Array) -> String:
	for e in exts:
		var f := "%s/%s.%s" % [folder, name, e]
		if _files.has(f):
			return f
	return ""


## content_hash (format.md, "Hashes"): every file, path + SHA-256 of its bytes.
func content_hash() -> String:
	if _content_hash == "":
		var items := []
		for f in files():
			items.append([f, read(f)])
		_content_hash = Pack.digest("cardpack-content/1", items)
	return _content_hash


## Known from the pack index: saves hashing the whole zip again.
func set_content_hash(h: String) -> void:
	_content_hash = h


## rules_hash computed from the files (format.md, "Hashes").
func computed_rules_hash() -> String:
	if _rules_hash == "":
		var items := []
		for f in files():
			if Pack.is_rules_file(f):
				items.append([f, Pack.normalized(f, read(f))])
		_rules_hash = Pack.digest("cardpack-rules/1", items)
	return _rules_hash


static func is_rules_file(f: String) -> bool:
	return f in ["rules.json", "cards.json"] or (f.begins_with("missions/") and f.ends_with(".json")) \
		or (f.begins_with("scripts/") and f.ends_with(".lua"))


## The bytes rules_hash covers: canonical JSON (cards without fx, sounds, voice), Lua with plain \n.
static func normalized(f: String, bytes: PackedByteArray) -> PackedByteArray:
	if f.ends_with(".lua"):
		var s := bytes.get_string_from_utf8().trim_prefix("﻿")
		return s.replace("\r\n", "\n").replace("\r", "\n").to_utf8_buffer()
	var j := JSON.new()
	if j.parse(bytes.get_string_from_utf8()) != OK:
		return bytes  # broken: its hash will not match the manifest's
	var v = j.data
	if f == "cards.json" and v is Array:
		for c in v:
			if c is Dictionary:
				for k in PRESENTATION:
					c.erase(k)
	return canonical(v).to_utf8_buffer()


## Canonical JSON (format.md, "Hashes"): keys sorted by code point, no spaces, whole numbers,
## only " \ and control characters escaped.
static func canonical(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var keys: Array = v.keys()
			keys.sort()
			var parts := []
			for k in keys:
				parts.append(_quote(str(k)) + ":" + canonical(v[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			return "[" + ",".join(v.map(canonical)) + "]"
		TYPE_STRING, TYPE_STRING_NAME:
			return _quote(str(v))
		TYPE_FLOAT, TYPE_INT:
			return str(int(v))
		TYPE_BOOL:
			return "true" if v else "false"
	return "null"


static func _quote(s: String) -> String:
	var out := "\""
	for i in s.length():
		var c := s.unicode_at(i)
		match c:
			0x22: out += "\\\""
			0x5c: out += "\\\\"
			0x08: out += "\\b"
			0x0c: out += "\\f"
			0x0a: out += "\\n"
			0x0d: out += "\\r"
			0x09: out += "\\t"
			_:
				out += ("\\u%04x" % c) if c < 0x20 else String.chr(c)
	return out + "\""


## SHA-256(tag + "\n" + Σ path + ":" + hex(SHA-256(bytes)) + "\n"), items [[path, bytes]] sorted by path.
static func digest(tag: String, items: Array) -> String:
	items.sort_custom(func(a, b): return a[0] < b[0])
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update((tag + "\n").to_utf8_buffer())
	for it in items:
		h.update(("%s:%s\n" % [it[0], sha256(it[1])]).to_utf8_buffer())
	return h.finish().hex_encode()


static func sha256(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():
		h.update(bytes)
	return h.finish().hex_encode()


## What makes this file no pack the game may use ([] = fine): the paths and sizes of
## format.md, a manifest of format 1 with an id, and a rules_hash that matches the files.
func problems() -> Array:
	var out := []
	if size > LIMITS.pack:
		out.append("the file is bigger than 128 MiB")
	if _twice:
		out.append("a file is in it twice")
	if _files.size() > LIMITS.files:
		out.append("more than %d files" % LIMITS.files)
	var total := 0
	for f: String in _files:
		var parts := f.split("/")
		if f.length() > 200 or Array(parts).any(func(s): return _segment.search(s) == null):
			out.append("bad path: " + f.left(80))
			continue
		if parts.size() == 1 and not TOP_FILES.has(f):
			out.append("not allowed at the top: " + f)
		elif parts.size() > 1 and not DIRS.has(parts[0]):
			out.append("unknown folder: " + parts[0])
		var n := read(f).size() if not f.get_extension().to_lower() in IMAGE_EXT + AUDIO_EXT else 0
		total += n
		if n > LIMITS.file:
			out.append("too big: " + f)
	if total > LIMITS.unpacked:
		out.append("too big unpacked")
	if int(manifest.get("format", 0)) != 1:
		out.append("unknown format %s" % str(manifest.get("format", "?")))
	if _id_re.search(id()) == null:
		out.append("bad id")
	for need in ["rules.json", "cards.json"]:
		if not has(need):
			out.append(need + " is missing")
	if out.is_empty() and computed_rules_hash() != rules_hash():
		out.append("rules_hash does not match the files")
	return out
