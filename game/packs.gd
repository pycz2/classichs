class_name Packs
extends RefCounted
## The game packs the player has (decision D9 of docs/superpowers/plans/2026-10-16-game-packs.md):
## built-in ones in res://packs/*.cardpack (tools/build_packs.sh), and downloaded,
## imported or received ones in user://packs/<content_hash>.cardpack with an index
## (user://packs/index.json). One pack is active: the interface shows its cards,
## texts, art, sounds and music, and its games are played.

const BUILTIN_DIR := "res://packs"
## The pack the game falls back to (and the rules the engine has built in).
const CLASSIC := "classic-2014"
## Tests point it at their own folder.
static var user_dir := "user://packs"

static var _list: Array = []  # Pack, built-in first
static var _active: Pack
## Called after the active pack (or its art, sound or music set) changed: caches reset.
static var _listeners: Array[Callable] = []


static func _index_path() -> String:
	return user_dir + "/index.json"


## {packs: [{file, content_hash, rules_hash, id, version, size, origin, server?, added}], builtin: {file: {...}}}
static func _index() -> Dictionary:
	var j := JSON.new()
	var p := _index_path()
	if FileAccess.file_exists(p) and j.parse(FileAccess.get_file_as_string(p)) == OK and j.data is Dictionary:
		var d: Dictionary = j.data
		if d.get("packs") is Array and d.get("builtin") is Dictionary:
			return d
	return {"packs": [], "builtin": {}}


static func _save_index(d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(user_dir)
	var f := FileAccess.open(_index_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, " "))


## Every pack there is: built-in first (Classic at the top), then the others by when they came.
static func all() -> Array:
	if _list.is_empty():
		_scan()
	return _list.duplicate()


static func _scan() -> void:
	var idx := _index()
	var builtin := []
	for f in DirAccess.get_files_at(BUILTIN_DIR) if DirAccess.dir_exists_absolute(BUILTIN_DIR) else []:
		if f.ends_with(".cardpack"):
			var p := Pack.open(BUILTIN_DIR + "/" + f, "builtin")
			if p:
				var known: Dictionary = idx.builtin.get(f, {})
				if known.get("size") == float(p.size) and known.get("rules_hash") == p.rules_hash() and known.get("version") == p.version():
					p.set_content_hash(str(known.get("content_hash", "")))
				builtin.append(p)
	builtin.sort_custom(func(a: Pack, b: Pack): return a.id() == CLASSIC or (b.id() != CLASSIC and a.id() < b.id()))
	var others := []
	for e in idx.packs:
		if not e is Dictionary:
			continue
		var p := Pack.open(user_dir + "/" + str(e.get("file", "")), str(e.get("origin", "imported")))
		if p:
			p.set_content_hash(str(e.get("content_hash", "")))
			p.server = str(e.get("server", ""))
			others.append(p)
	_list = builtin + others


## The content hash of a built-in pack, remembered in the index (it is costly to compute).
static func content_hash(p: Pack) -> String:
	var known := p._content_hash != ""
	var h := p.content_hash()
	if p.builtin() and not known:
		var idx := _index()
		idx.builtin[p.path.get_file()] = {"size": p.size, "rules_hash": p.rules_hash(), "version": p.version(), "content_hash": h}
		_save_index(idx)
	return h


## Forgets the list (after files changed); the active pack is picked again.
static func rescan() -> void:
	for p: Pack in _list:
		if p != _active:
			p.close()
	_list = []
	var was := _active
	_active = null
	if active() != was:
		_changed()


## The active pack: the one in the settings (by content hash, else by id), else Classic.
static func active() -> Pack:
	if _active == null:
		var want: Dictionary = Settings.data.get("pack", {}) if Settings.data.get("pack") is Dictionary else {}
		var by_id: Pack = null
		var classic: Pack = null
		for p: Pack in all():
			if want.get("hash", "") != "" and p._content_hash == want.hash:
				_active = p
				break
			if by_id == null and p.id() == want.get("id", ""):
				by_id = p
			if classic == null and p.id() == CLASSIC:
				classic = p
		if _active == null:
			_active = by_id if by_id else (classic if classic else (all()[0] if not all().is_empty() else null))
	return _active


static func set_active(p: Pack) -> void:
	if p == _active:
		return
	Settings.data.pack = {"id": p.id(), "hash": content_hash(p)}
	Settings.save()
	_active = p
	_changed()


static func find(content_hash_: String) -> Pack:
	for p: Pack in all():
		if content_hash(p) == content_hash_:
			return p
	return null


static func find_rules(rules_hash: String) -> Pack:
	for p: Pack in all():
		if p.rules_hash() == rules_hash:
			return p
	return null


## Runs after the active pack or one of its sets changes (the screens' caches).
static func on_change(f: Callable) -> void:
	_listeners.append(f)


static func _changed() -> void:
	CardDb.reset()
	CardLayout.reset()
	Art.reset_all()
	KeywordTips.reset()
	VoiceLines.reset()
	Decks.reset()
	Rules.pack_changed()
	Sound.reset()
	for f in _listeners:
		if f.is_valid():
			f.call()


## The set the player chose for a pack ("art", "sound", "music", "back"); the pack's default otherwise.
## Classic keeps the choices made before packs (settings "art", "music_set").
static func choice(p: Pack, kind: String) -> String:
	var mine: Dictionary = Settings.data.get("pack_sets", {}).get(p.id(), {}) if Settings.data.get("pack_sets") is Dictionary else {}
	if mine.has(kind):
		return str(mine[kind])
	if p.id() == CLASSIC:
		match kind:
			"art": return str(Settings.data.get("art", p.default_set("art")))
			"music": return str(Settings.data.get("music_set", p.default_set("music")))
	return p.default_set(kind)


static func set_choice(p: Pack, kind: String, value: String) -> void:
	if not Settings.data.get("pack_sets") is Dictionary:
		Settings.data.pack_sets = {}
	var mine: Dictionary = Settings.data.pack_sets.get(p.id(), {})
	mine[kind] = value
	Settings.data.pack_sets[p.id()] = mine
	if p.id() == CLASSIC and kind == "art":
		Settings.data.art = value
	if p.id() == CLASSIC and kind == "music":
		Settings.data.music_set = value
	Settings.save()
	if p == _active:
		match kind:
			"art": Art.reset()
			"sound", "music": Sound.reset()


## Why a pack can't be installed (English keys, translated where shown; i18n_keys.gd reads them).
const ERRORS := ["The game pack is bigger than 128 MiB", "Cannot write the game pack", "This is not a game pack",
	"The game pack is damaged", "Cannot read the file"]


## Installs a pack from its bytes (a download, a file, a P2P transfer) into user://packs.
## {pack: Pack} or {error: why (one of ERRORS), detail?}. A pack already there is returned as it is.
## want_hash: the content hash the sender promised ("" = any).
static func install(bytes: PackedByteArray, origin: String, extra := {}, want_hash := "") -> Dictionary:
	if bytes.size() > Pack.LIMITS.pack:
		return {"error": ERRORS[0]}
	DirAccess.make_dir_recursive_absolute(user_dir)
	var tmp := user_dir + "/incoming.tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"error": ERRORS[1]}
	f.store_buffer(bytes)
	f.close()
	var p := Pack.open(tmp, origin)
	if p == null:
		DirAccess.remove_absolute(tmp)
		return {"error": ERRORS[2]}
	var bad := p.problems()
	var h := p.content_hash() if bad.is_empty() else ""
	if bad.is_empty() and want_hash != "" and h != want_hash:
		bad.append("the pack differs from the one offered")
	if not bad.is_empty():
		p.close()
		DirAccess.remove_absolute(tmp)
		return {"error": ERRORS[3], "detail": bad[0]}
	var have := find(h)
	if have:
		p.close()
		DirAccess.remove_absolute(tmp)
		return {"pack": have}
	p.close()
	var file := h + ".cardpack"
	DirAccess.remove_absolute(user_dir + "/" + file)
	if DirAccess.rename_absolute(tmp, user_dir + "/" + file) != OK:
		return {"error": ERRORS[1]}
	var idx := _index()
	var e := {"file": file, "content_hash": h, "rules_hash": p.rules_hash(), "id": p.id(), "version": p.version(),
		"size": bytes.size(), "origin": origin, "added": int(Time.get_unix_time_from_system())}
	e.merge(extra)
	idx.packs.append(e)
	_save_index(idx)
	var out := Pack.open(user_dir + "/" + file, origin)
	out.set_content_hash(h)
	out.server = str(extra.get("server", ""))
	if not _list.is_empty():
		_list.append(out)
	return {"pack": out}


## Imports a .cardpack file (a path the player picked).
static func install_file(file: String) -> Dictionary:
	if not FileAccess.file_exists(file):
		return {"error": ERRORS[4]}
	return install(FileAccess.get_file_as_bytes(file), "imported")


## Deletes a downloaded, imported or received pack (never a built-in one).
static func remove(p: Pack) -> bool:
	if p.builtin():
		return false
	var h := content_hash(p)
	var idx := _index()
	idx.packs = idx.packs.filter(func(e): return not e is Dictionary or e.get("content_hash") != h)
	_save_index(idx)
	p.close()
	DirAccess.remove_absolute(p.path)
	_list.erase(p)
	if p == _active:
		_active = null
		Settings.data.erase("pack")
		Settings.save()
		active()
		_changed()
	return true


## The active pack's raw bytes (to send to another player or a server).
static func bytes_of(p: Pack) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(p.path)


## A size for people: "34.3 MB".
static func size_text(n: int) -> String:
	return "%.1f MB" % (n / 1048576.0) if n >= 104858 else "%d KB" % maxi(1, n / 1024)


## The client speaks the Classic pack's mechanic names (TAUNT, DIVINE_SHIELD, SECRET…); a
## pack's own names reach it through the engine vocabulary (rules.json `mechanics`).
const ENGINE_TO_CLIENT := {"GUARD": "TAUNT", "HASTE": "CHARGE", "BARRIER": "DIVINE_SHIELD",
	"DOUBLE_ATTACK": "WINDFURY", "SPELLPROOF": "ELUSIVE", "SPELL_POWER": "SPELLPOWER", "MANA_LOCK": "OVERLOAD",
	"TRAP": "SECRET", "ON_PLAY": "BATTLECRY", "ON_DEATH": "DEATHRATTLE", "CHOICE": "CHOOSE_ONE",
	"WOUNDED": "ENRAGED", "TRIGGER": "TRIGGER_VISUAL", "ADJACENT": "ADJACENT_BUFF",
	"SPELL_SCALED": "AFFECTED_BY_SPELL_POWER", "NO_SPELL_POWER": "ImmuneToSpellpower",
	"POWER_MULTIPLIER": "DOUBLE_HEAL_DAMAGE"}
static var _to_client := {}  # pack name -> client name, only where they differ
static var _to_pack := {}  # client name -> pack name
static var _names_of: Pack


static func _names() -> void:
	if _names_of == active() and _names_of != null:
		return
	_names_of = active()
	_to_client = {}
	_to_pack = {}
	var mech = _names_of.rules().get("mechanics", {}) if _names_of else {}
	for name in mech if mech is Dictionary else {}:
		var engine := str(mech[name].get("engine", name)) if mech[name] is Dictionary else str(name)
		var client: String = ENGINE_TO_CLIENT.get(engine, engine)
		_to_pack[client] = name
		if client != name:
			_to_client[name] = client


## A mechanic, tag or zone name of the active pack (cards, snapshots) in the client's words.
static func client_name(name: String) -> String:
	_names()
	return _to_client.get(name, name)


## The active pack's name of a client mechanic name (its texts are under it).
static func pack_name(client: String) -> String:
	_names()
	return _to_pack.get(client, client)


## pack name -> client name for every name that differs ({} for Classic).
static func renames() -> Dictionary:
	_names()
	return _to_client


static var _pictures := {}  # "<pack path>|<name>" -> Texture2D or null


## A picture of the active pack's ui/ folder by name (ui/menu.jpg, ui/board.jpg, ui/library.jpg…),
## or the manifest's logo / card_back ("logo", "card_back"); null when it has none.
static func picture(name: String) -> Texture2D:
	var p := active()
	if p == null:
		return null
	var key := p.path + "|" + name
	if not _pictures.has(key):
		var f = p.manifest.get(name) if name in ["logo", "card_back"] else p.find("ui", name, Pack.IMAGE_EXT)
		_pictures[key] = p.texture(f) if f is String and f != "" else null
	return _pictures[key]
