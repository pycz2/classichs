class_name Packs
extends RefCounted
## The game packs the player has (decision D9 of docs/superpowers/plans/2026-10-16-game-packs.md):
## built-in ones in res://packs/*.cardpack (tools/build_packs.sh), and downloaded,
## imported or received ones in user://packs/<content_hash>.cardpack with an index
## (user://packs/index.json). One pack is active: the interface shows its cards,
## texts, art, sounds and music, and its games are played. Of a pack with versions (docs/packs/format.md §13)
## the chosen version is active: active() is its view (Pack.version_view), a pack of its own to the rest of the client.

const BUILTIN_DIR := "res://packs"
## Classic 2014, the old Classic pack (the rules the engine has built in; the player's decks of before the megapack).
## Not in the game's builds any more: tests and tools read it from build/packs (builtin_files).
const CLASSIC := "classic-2014"
## The game the client starts with: Classic, the megapack (packs/eras, its versions). Tests start with CLASSIC.
static var default_id := "hs-eras"
## Pack files read as built-in besides res://packs (tests and tools: build/packs/classic.cardpack …).
static var builtin_files: Array = []
## Tests point it at their own folder.
static var user_dir := "user://packs"

static var _list: Array = []  # Pack, built-in first
static var _active: Pack  # one of _list (a whole pack, never a version view)
static var _view: Pack  # the chosen version of _active when it has versions
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


## Every pack there is: built-in first (the default game at the top), then the others by when they came.
static func all() -> Array:
	if _list.is_empty():
		_scan()
	return _list.duplicate()


static func _scan() -> void:
	var idx := _index()
	var builtin := []
	var files: Array = Array(DirAccess.get_files_at(BUILTIN_DIR) if DirAccess.dir_exists_absolute(BUILTIN_DIR) else []).map(
		func(f: String): return BUILTIN_DIR + "/" + f) + builtin_files
	for path: String in files:
		var f := path.get_file()
		if f.ends_with(".cardpack"):
			var p := Pack.open(path, "builtin")
			if p:
				var known: Dictionary = idx.builtin.get(f, {})
				if known.get("size") == float(p.size) and known.get("rules_hash") == p.rules_hash() and known.get("version") == p.version():
					p.set_content_hash(str(known.get("content_hash", "")))
				builtin.append(p)
	builtin.sort_custom(func(a: Pack, b: Pack): return a.id() == default_id or (b.id() != default_id and a.id() < b.id()))
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
	p = p.whole()  # (a version view: its pack's)
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
	_view = null
	active()
	if _active != was:
		_changed()


## The active pack: the one in the settings (by content hash, else by id), else the default game; of a pack with
## versions, the view of its chosen version (version()).
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
			if classic == null and p.id() == default_id:
				classic = p
		if _active == null:
			_active = by_id if by_id else (classic if classic else (all()[0] if not all().is_empty() else null))
	if _active == null or _active.versions().is_empty():
		return _active
	if _view == null or _view.whole() != _active:  # (set_version, set_active and rescan drop it)
		_view = _active.version_view(version(_active))
	return _view if _view else _active


## The version of a pack with versions the player plays: the one chosen (set_version), else its default ("" for a
## one-version pack).
static func version(p: Pack) -> String:
	p = p.whole()
	var mine := ""
	if Settings.data.get("pack_versions") is Dictionary:
		mine = str(Settings.data.pack_versions.get(p.id(), ""))
	for v in p.versions():
		if v is Dictionary and mine != "" and str(v.get("id", "")) == mine:
			return mine
	return p.default_version()


## Chooses the version of a pack with versions (kept per pack id); the active pack switches to it at once.
static func set_version(p: Pack, vid: String) -> void:
	p = p.whole()
	if version(p) == vid:
		return
	if not Settings.data.get("pack_versions") is Dictionary:
		Settings.data.pack_versions = {}
	Settings.data.pack_versions[p.id()] = vid
	Settings.save()
	if p == _active:
		_view = null
		_changed()


## Whether p is the active pack (a pack with versions: itself or the view of its chosen version).
static func is_active(p: Pack) -> bool:
	return p != null and active() != null and p.whole() == _active and (p.version_id == "" or p.version_id == version(_active))


## p becomes the active pack (a version view: its pack, at that version).
static func set_active(p: Pack) -> void:
	if p.version_id != "" and p.whole() == _active:
		set_version(p, p.version_id)
		return
	if p.version_id != "" and version(p) != p.version_id:
		if not Settings.data.get("pack_versions") is Dictionary:
			Settings.data.pack_versions = {}
		Settings.data.pack_versions[p.id()] = p.version_id  # (saved with the pack below)
	p = p.whole()
	if p == _active:
		return
	server_sets = {}  # (another game: its own choices)
	Settings.data.pack = {"id": p.id(), "hash": content_hash(p)}
	Settings.save()
	_active = p
	_view = null
	_changed()


## The client shows its own screens (the main menu, the settings, the game library, the
## connections): no pack styles them (look() is null; main sets it). Inside a game the active
## pack gives the look, the menu music and pictures.
static var shell := false
## A game played through a server: the art and music choice the server keeps for it ({art, music}).
static var server_sets := {}


## The pack whose look the screens have now: the active one inside a game, none in the shell.
static func look() -> Pack:
	return null if shell else active()


static func set_shell(on: bool) -> void:
	if on == shell:
		return
	shell = on
	_pictures = {}
	Fonts.restyle()


## Opens a game: p becomes the active pack (sets: the server's art and music choice for it, {}
## on this device) and styles the screens from now on.
static func enter(p: Pack, sets := {}) -> void:
	shell = false
	if p.whole() != _active or (p.version_id != "" and p.version_id != version(_active)):
		set_active(p)  # (its caches start again; server_sets {})
	else:
		Fonts.restyle()
	var was := server_sets
	server_sets = sets
	for kind in ["art", "music"]:
		if str(was.get(kind, "")) != str(sets.get(kind, "")):
			_set_changed(kind)


## rules_hash: the pack's, when known: only packs of those rules can be it (no others get hashed).
static func find(content_hash_: String, rules_hash := "") -> Pack:
	for p: Pack in all():
		if (rules_hash == "" or p.rules_hash() == rules_hash) and content_hash(p) == content_hash_:
			return p
	return null


## The pack whose rules have this hash: a pack, or the view of a pack's version.
static func find_rules(rules_hash: String) -> Pack:
	for p: Pack in all():
		if p.rules_hash() == rules_hash and p.versions().is_empty():
			return p
		for v in p.versions():
			if v is Dictionary and str(v.get("rules_hash", "")) == rules_hash:
				return p.version_view(str(v.get("id", "")))
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


## The set the player chose for a pack ("art", "sound", "music"); the pack's default otherwise.
## In a game played through a server the server keeps the art and music choice (server_sets).
static func choice(p: Pack, kind: String) -> String:
	p = p.whole()
	if p == _active and server_sets.has(kind):
		return str(server_sets[kind])
	var mine: Dictionary = Settings.data.get("pack_sets", {}).get(p.id(), {}) if Settings.data.get("pack_sets") is Dictionary else {}
	if mine.has(kind):
		return str(mine[kind])
	if kind == "sound" and not p.builtin():  # the pack's own local sound set (card sounds, legendaries' music) unless one is picked
		for s in p.sets(kind):
			if s.get("local", false) and p.set_usable(kind, s):
				return str(s.id)
	return p.default_set(kind)


## Keeps a set choice on this device (a server game's are kept on the server: ServerLink.set_game_setting).
static func set_choice(p: Pack, kind: String, value: String) -> void:
	if not Settings.data.get("pack_sets") is Dictionary:
		Settings.data.pack_sets = {}
	var mine: Dictionary = Settings.data.pack_sets.get(p.id(), {})
	mine[kind] = value
	Settings.data.pack_sets[p.id()] = mine
	Settings.save()
	if p.whole() == _active and not server_sets.has(kind):
		_set_changed(kind)


static func _set_changed(kind: String) -> void:
	match kind:
		"art": Art.reset()
		"sound", "music": Sound.reset()


## Why a pack can't be installed (English keys, translated where shown; i18n_keys.gd reads them).
const ERRORS := ["The game pack is bigger than 1 GiB", "Cannot write the game pack", "This is not a game pack",
	"The game pack is damaged", "Cannot read the file"]


## Installs a pack from its bytes (a download, a file, a P2P transfer) into user://packs, waiting
## for the check (PackInstall.of_bytes(…).start() does it in the background).
## {pack: Pack} or {error: why (one of ERRORS), detail?}. A pack already there is returned as it is.
## want_hash: the content hash the sender promised ("" = any).
static func install(bytes: PackedByteArray, origin: String, extra := {}, want_hash := "") -> Dictionary:
	return PackInstall.of_bytes(bytes, "", origin, extra, want_hash).run_now()


## The last step of an install (PackInstall): the file tmp, checked by the rules engine (check:
## {content_hash, rules_hash} or {error}), goes into place under its content hash.
static func store(tmp: String, check: Dictionary, origin: String, extra := {}, want_hash := "") -> Dictionary:
	var p := Pack.open(tmp, origin)
	if p == null:
		DirAccess.remove_absolute(tmp)
		return {"error": ERRORS[2]}
	var bad := [str(check.error)] if check.has("error") else p.problems(false)
	var h := str(check.get("content_hash", ""))
	if bad.is_empty() and str(check.get("rules_hash", "")) != p.rules_hash():
		bad.append("rules_hash does not match the files")
	if bad.is_empty() and want_hash != "" and h != want_hash:
		bad.append("the pack differs from the one offered")
	if not bad.is_empty():
		p.close()
		DirAccess.remove_absolute(tmp)
		return {"error": ERRORS[3], "detail": bad[0]}
	var have := find(h, p.rules_hash())
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
		"size": p.size, "origin": origin, "added": int(Time.get_unix_time_from_system())}
	e.merge(extra)
	idx.packs.append(e)
	_save_index(idx)
	var out := Pack.open(user_dir + "/" + file, origin)
	out.set_content_hash(h)
	out.server = str(extra.get("server", ""))
	if not _list.is_empty():
		_list.append(out)
	return {"pack": out}


## Imports a .cardpack file (a path the player picked), waiting; install_file_later in the background.
static func install_file(file: String) -> Dictionary:
	return install_file_later(file).run_now()


## The same as a PackInstall: the file is copied in ("receiving"), then checked in turn. Not started.
static func install_file_later(file: String) -> PackInstall:
	var j := PackInstall.receiving(file.get_file(), "imported")
	if not FileAccess.file_exists(file):
		j.finish({"error": ERRORS[4]})
	elif DirAccess.copy_absolute(file, j.file) != OK:
		j.finish({"error": ERRORS[1]})
	else:
		j.received()
	return j


## Deletes a downloaded, imported or received pack (never a built-in one), and the decks made in
## it on this device when no other pack of that id stays.
static func remove(p: Pack) -> bool:
	p = p.whole()
	if p.builtin():
		return false
	var h := content_hash(p)
	var idx := _index()
	idx.packs = idx.packs.filter(func(e): return not e is Dictionary or e.get("content_hash") != h)
	_save_index(idx)
	p.close()
	DirAccess.remove_absolute(p.path)
	_list.erase(p)
	if not all().any(func(x: Pack): return x.id() == p.id()):  # its decks on this device go with it
		DeckStore.delete_for(p.id(), p.versions())
	if p == _active:
		_active = null
		_view = null
		Settings.data.erase("pack")
		Settings.save()
		active()
		_changed()
	return true


## The active pack's raw bytes (to send to another player or a server).
static func bytes_of(p: Pack) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(p.path)


## A size for people in the interface's language: "34.3 MB", "34,3 МБ".
static func size_text(n: int) -> String:
	if n < 104858:
		return TranslationServer.translate("%d KB") % maxi(1, n / 1024)
	var mb := "%.1f" % (n / 1048576.0)
	if not TranslationServer.get_locale().begins_with("en"):  # (every other language writes a decimal comma)
		mb = mb.replace(".", ",")
	return TranslationServer.translate("%s MB") % mb


## The client speaks the Classic pack's mechanic names (TAUNT, DIVINE_SHIELD, SECRET…); a
## pack's own names reach it through the engine vocabulary (rules.json `mechanics`).
const ENGINE_TO_CLIENT := {"GUARD": "TAUNT", "HASTE": "CHARGE", "BARRIER": "DIVINE_SHIELD",
	"DOUBLE_ATTACK": "WINDFURY", "SPELLPROOF": "ELUSIVE", "SPELL_POWER": "SPELLPOWER", "MANA_LOCK": "OVERLOAD",
	"TRAP": "SECRET", "ON_PLAY": "BATTLECRY", "ON_DEATH": "DEATHRATTLE", "CHOICE": "CHOOSE_ONE",
	"WOUNDED": "ENRAGED", "TRIGGER": "TRIGGER_VISUAL", "ADJACENT": "ADJACENT_BUFF",
	"SPELL_SCALED": "AFFECTED_BY_SPELL_POWER", "NO_SPELL_POWER": "ImmuneToSpellpower",
	"POWER_MULTIPLIER": "DOUBLE_HEAL_DAMAGE", "TASK": "QUEST", "TASK_PROGRESS": "QUEST_PROGRESS",
	"TASK_GOAL": "QUEST_PROGRESS_TOTAL", "DORMANT": "UNTOUCHABLE", "QUICK": "RUSH", "REPEATABLE": "ECHO",
	"AT_GAME_START": "START_OF_GAME", "FUSE": "MODULAR"}
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


## The icon of a set mark (CardText.set_key) of the active pack: manifest `set_marks.<key>.icon`. Null
## when it has none: Classic shows no marks, the packs after it mark each card with its set.
static func set_mark(key: String) -> Texture2D:
	var p := CardDb.pack()
	var marks = p.manifest.get("set_marks", {}) if p else {}
	var icon = marks.get(key, {}).get("icon") if marks is Dictionary and marks.get(key) is Dictionary else null
	if not icon is String or icon == "":
		return null
	var cache: String = p.path + "|mark|" + str(icon)
	if not _pictures.has(cache):
		_pictures[cache] = p.texture(icon)
	return _pictures[cache]


static var _pictures := {}  # "<pack path>|<name>" -> Texture2D or null


## A picture of the styling pack's (look()) ui/ folder by name (ui/menu.jpg, ui/board.jpg, ui/library.jpg…),
## or the manifest's logo / card_back ("logo", "card_back"); null when it has none.
static func picture(name: String) -> Texture2D:
	var p := look()
	if p == null:
		return null
	var key := p.path + "|" + name
	if not _pictures.has(key):
		var f = p.manifest.get(name) if name in ["logo", "card_back"] else p.find("ui", name, Pack.IMAGE_EXT)
		_pictures[key] = p.texture(f) if f is String and f != "" else null
	return _pictures[key]
