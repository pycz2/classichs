class_name StudioProject
extends RefCounted
## A game made in ClassicHS Studio. A project is a folder user://studio/<id>/: pack/ is the game pack's source
## (docs/packs/format.md: manifest.json, rules.json, cards.json, locales/, scripts/, art/, sounds/, decks/), which
## PackCheck builds, checks and plays as the game's pack tools do; project.json keeps what only the editor needs
## (each card's effect: its building blocks or its raw Lua, studio/studio_effects.gd). The texts, rules and cards
## live here in memory and save() writes them; pictures and sounds are written into pack/ as they come.

const FORMAT := "classichs-studio/1"
const LANGS := ["en", "ru", "de", "fr", "es", "pt_BR", "it", "pl"]
const TYPES := ["MINION", "SPELL", "WEAPON", "CHAMPION", "POWER"]
## The art and sound sets a project's own pictures and sounds go into.
const ART_SET := "main"
const SOUND_SET := "main"
const MUSIC_SET := "main"
## The game's own music and event sounds (docs/packs/format.md §7): music/<set>/<name>, sounds/<set>/<name>.
const MUSIC := ["menu", "battle_1", "battle_2", "battle_3", "mulligan", "victory", "defeat", "arena"]
const GAME_SOUNDS := ["play_card", "attack", "damage", "death", "hero_power", "turn_start", "heal", "armor", "equip",
	"secret", "freeze", "shield", "spell", "trigger", "hit_big", "draw", "summon", "victory", "defeat", "click"]
## The file the effects' Lua goes into (StudioEffects.script()).
const SCRIPT := "scripts/studio.lua"
## A card's own sounds (docs/packs/format.md §7): sounds/<set>/<card id>_<slot>.<ext>.
const SOUND_SLOTS := ["play", "attack", "death", "trigger", "aim", "missile", "hit", "reveal", "choose", "music"]
const IMAGE_EXT := ["png", "jpg", "jpeg", "webp"]
const AUDIO_EXT := ["opus", "ogg", "wav", "mp3"]
## A picture's longer side is made at most this (docs/packs/format.md §7: 512 px recommended).
const ART_SIDE := 512
## What a new game starts with: the Classic pack's mechanics, races and rarities in 8 languages.
const TEMPLATE := "res://studio/template.json"

static var root := "user://studio"
static var _id_re := RegEx.create_from_string("^[a-z0-9][a-z0-9._-]{0,63}$")
static var _card_re := RegEx.create_from_string("^[A-Za-z0-9_]{1,64}$")

var id := ""
var dir := ""
var manifest := {}
var rules := {}
var cards: Array = []
## lang -> the locale file's dictionary.
var locales := {}
## Deck file name (without .json) -> {name, champion, cards}.
var decks := {}
## Card id -> {blocks: [...], lua: ""} (StudioEffects).
var effects := {}
var _previews := 0


# --- projects ------------------------------------------------------------------------------------

## Every project there is: [{id, name, dir}], by id.
static func list() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(root):
		return out
	var ids := Array(DirAccess.get_directories_at(root))
	ids.sort()
	for pid: String in ids:
		var m = JSON.parse_string(FileAccess.get_file_as_string("%s/%s/pack/manifest.json" % [root, pid]))
		if m is Dictionary:
			var names: Dictionary = m.get("name", {}) if m.get("name") is Dictionary else {}
			out.append({"id": pid, "name": str(names.get("en", pid)), "dir": root + "/" + pid})
	return out


## Why an id can't be a new project's ("" = it can).
static func id_problem(pid: String) -> String:
	if _id_re.search(pid) == null:
		return "Use small Latin letters, digits, dots, dashes and underscores"
	if DirAccess.dir_exists_absolute(root + "/" + pid):
		return "A project with this id exists"
	return ""


## A new game: one class with its hero and Hero Power, neutral cards, the sets core and token, Classic's
## rarities, tribes and mechanics, The Coin. Saved. Null when the id can't be used (id_problem()).
static func create(pid: String, title := "") -> StudioProject:
	if id_problem(pid) != "":
		return null
	var t: Dictionary = _template()
	var p := StudioProject.new()
	p.id = pid
	p.dir = root + "/" + pid
	p.manifest = {"format": 1, "id": pid, "version": "0.1.0", "engine": str(ProjectSettings.get_setting("application/config/version", "0.75.0")),
		"name": {"en": title if title != "" else pid}, "description": {"en": ""}, "authors": [], "license": "",
		"redistributable": true, "default_locale": "en", "locales": LANGS.duplicate(),
		"art_sets": [], "sound_sets": [], "music_sets": [], "colors": {"classes": {"NEUTRAL": "868e96"}, "rarities": {}}}
	var mechanics := {}
	for k in t.mechanics:
		mechanics[k] = {"engine": t.mechanics[k].engine}
	p.rules = {"format": 1,
		"limits": {"champion_health": 30, "max_mana": 10, "hand": 10, "board": 7, "deck_size": 30, "copies": 2,
			"copies_by_rarity": {"LEGENDARY": 1}},
		"start": {"first_player": "random", "hand": [3, 4], "coin": "coin", "mulligan": true},
		"bot": {"trap": 2},
		"fatigue": {"enabled": true, "first": 1, "step": 1},
		"timers": {"turn": 75, "fuse": 15, "mulligan": 45},
		"default_power": "",
		"classes": [{"id": "NEUTRAL", "neutral": true}],
		"races": t.races.keys(),
		"rarities": t.rarities.keys().map(func(r): return {"id": r, "tier": t.rarities[r].tier}),
		"no_rarity_tier": t.no_rarity_tier,
		"sets": ["core", "token"],
		"mechanics": mechanics,
		"modes": {"constructed": {"sets": ["core"], "class_cards": "own_and_neutral"}}}
	for lang in LANGS:
		var l := {"cards": {}, "classes": {}, "races": {}, "rarities": {}, "sets": {}, "mechanics": {}}
		for k in t.mechanics:
			if t.mechanics[k].has("name") and t.mechanics[k].name.has(lang):
				l.mechanics[k] = {"name": t.mechanics[k].name[lang], "tip": t.mechanics[k].tip.get(lang, "")}
		for r in t.races:
			l.races[r] = t.races[r][lang]
		for r in t.rarities:
			l.rarities[r] = t.rarities[r].name[lang]
		for k in WORDS:
			if WORDS[k].has(lang):
				_put(l, k, WORDS[k][lang])
		p.locales[lang] = l
	var colors := {"FREE": "e0e0e0", "COMMON": "e0e0e0", "RARE": "3d8bff", "EPIC": "b44cff", "LEGENDARY": "ff9b1a"}
	for r in t.rarities:
		p.manifest.colors.rarities[r] = colors.get(r, "e0e0e0")
	p.cards.append({"id": "coin", "type": "SPELL", "class": "NEUTRAL", "set": "token", "cost": 0})
	p.effects["coin"] = {"blocks": [], "lua": "spell = function(g, me) g.add_mana(g.ctrl(me), 1) end,"}
	p.add_class("KNIGHT", "c0392b")
	for lang in LANGS:
		for k in ["cards.knight_hero.name", "cards.knight_power.name", "cards.knight_power.text", "classes.KNIGHT"]:
			if WORDS.has(k) and WORDS[k].has(lang):
				_put(p.locales[lang], k, WORDS[k][lang])
	p.effects["knight_power"] = {"blocks": [], "lua": "hero_power = function(g, me) g.gain_armor(g.ctrl(me), 2) end,"}
	p.save()
	return p


## The texts of the template's own cards, classes and sets (path in a locale file -> lang -> text).
const WORDS := {
	"classes.NEUTRAL": {"en": "Neutral", "ru": "Нейтральные", "de": "Neutral", "fr": "Neutre", "es": "Neutral",
		"pt_BR": "Neutro", "it": "Neutrale", "pl": "Neutralne"},
	"sets.core": {"en": "Core", "ru": "Основной", "de": "Kern", "fr": "Base", "es": "Básico", "pt_BR": "Básico",
		"it": "Base", "pl": "Podstawowy"},
	"sets.token": {"en": "Tokens", "ru": "Жетоны", "de": "Spielsteine", "fr": "Jetons", "es": "Fichas",
		"pt_BR": "Fichas", "it": "Segnalini", "pl": "Żetony"},
	"cards.coin.name": {"en": "The Coin", "ru": "Монетка", "de": "Die Münze", "fr": "La pièce", "es": "La moneda",
		"pt_BR": "A Moeda", "it": "La Moneta", "pl": "Moneta"},
	"cards.coin.text": {"en": "Gain 1 Mana Crystal this turn only.", "ru": "Вы получаете 1 кристалл маны до конца хода.",
		"de": "Erhaltet 1 Manakristall nur für diesen Zug.", "fr": "Vous gagnez 1 cristal de mana pendant ce tour uniquement.",
		"es": "Obtienes 1 cristal de maná solo este turno.", "pt_BR": "Ganhe 1 Cristal de Mana somente neste turno.",
		"it": "Ottieni 1 Cristallo di Mana solo per questo turno.", "pl": "Zyskujesz 1 kryształ many tylko w tej turze."},
	"classes.KNIGHT": {"en": "Knight", "ru": "Рыцарь", "de": "Ritter", "fr": "Chevalier", "es": "Caballero",
		"pt_BR": "Cavaleiro", "it": "Cavaliere", "pl": "Rycerz"},
	"cards.knight_hero.name": {"en": "Knight", "ru": "Рыцарь", "de": "Ritter", "fr": "Chevalier", "es": "Caballero",
		"pt_BR": "Cavaleiro", "it": "Cavaliere", "pl": "Rycerz"},
	"cards.knight_power.name": {"en": "Raise Shield", "ru": "Поднять щит", "de": "Schild heben", "fr": "Lever le bouclier",
		"es": "Alzar escudo", "pt_BR": "Erguer escudo", "it": "Alzare lo scudo", "pl": "Unieś tarczę"},
	"cards.knight_power.text": {"en": "Gain 2 Armor.", "ru": "Вы получаете 2 ед. брони.", "de": "Erhaltet 2 Rüstung.",
		"fr": "Vous gagnez 2 points d’armure.", "es": "Obtienes 2 de armadura.", "pt_BR": "Ganhe 2 de Armadura.",
		"it": "Ottieni 2 Armatura.", "pl": "Zyskujesz 2 pkt. pancerza."},
}


static func _put(d: Dictionary, path: String, v: Variant) -> void:
	var parts := path.split(".")
	for i in parts.size() - 1:
		if not d.get(parts[i]) is Dictionary:
			d[parts[i]] = {}
		d = d[parts[i]]
	d[parts[-1]] = v


static func _template() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(TEMPLATE))


static func open(pid: String) -> StudioProject:
	var p := StudioProject.new()
	p.id = pid
	p.dir = root + "/" + pid
	if not p._read():
		return null
	return p


## A copy of a game pack to edit: its files (of a pack with versions, its default version's) with a new id and
## "(copy)" after its names. Its scripts stay as they are; cards given effects here get scripts/studio.lua.
## Null when the id can't be used.
static func from_pack(pack: Pack, pid: String) -> StudioProject:
	if id_problem(pid) != "":
		return null
	if pack.version_id == "" and not pack.versions().is_empty():
		pack = pack.version_view(pack.default_version())
	var to := root + "/" + pid + "/pack/"
	var keep := {}  # art/sounds/music: only the default set of each (a copy stays small enough to work with)
	for kind in ["art", "sound", "music"]:
		keep[kind] = pack.default_set(kind)
	for f: String in pack.files():
		var top := f.get_slice("/", 0)
		var set_kind: String = {"art": "art", "sounds": "sound", "music": "music"}.get(top, "")
		if f == "manifest.json" or (set_kind != "" and f.get_slice("/", 1) != keep[set_kind]) or top == "voice":
			continue
		DirAccess.make_dir_recursive_absolute((to + f).get_base_dir())
		var out := FileAccess.open(to + f, FileAccess.WRITE)
		out.store_buffer(pack.read(f))
		out.close()
	var m: Dictionary = Rules.ints(pack.manifest.duplicate(true))
	for k in ["rules_hash", "fx", "versions", "default_version"]:
		m.erase(k)
	m.id = pid
	for kind in ["art", "sound", "music"]:
		m[kind + "_sets"] = m.get(kind + "_sets", []).filter(func(s): return s is Dictionary and s.get("id") == keep[kind] and not s.get("local", false))
	for lang in m.get("name", {}):
		m.name[lang] = str(m.name[lang]) + " (copy)"
	var f := FileAccess.open(to + "manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(m, " ", false))
	f.close()
	var p := open(pid)
	if p:
		p.save()
	return p


func pack_dir() -> String:
	return dir + "/pack"


func _json(rel: String) -> Variant:
	var path := pack_dir() + "/" + rel
	return Rules.ints(JSON.parse_string(FileAccess.get_file_as_string(path))) if FileAccess.file_exists(path) else null


func _read() -> bool:
	var m = _json("manifest.json")
	var r = _json("rules.json")
	var c = _json("cards.json")
	if not (m is Dictionary and r is Dictionary and c is Array):
		return false
	manifest = m
	rules = r
	cards = c
	for lang in manifest.get("locales", []):
		var l = _json("locales/%s.json" % lang)
		locales[lang] = l if l is Dictionary else {}
	if DirAccess.dir_exists_absolute(pack_dir() + "/decks"):
		for f in DirAccess.get_files_at(pack_dir() + "/decks"):
			var d = _json("decks/" + f)
			if f.ends_with(".json") and d is Dictionary:
				decks[f.get_basename()] = d
	var s = JSON.parse_string(FileAccess.get_file_as_string(dir + "/project.json")) if FileAccess.file_exists(dir + "/project.json") else null
	effects = Rules.ints(s.get("effects", {})) if s is Dictionary and s.get("effects") is Dictionary else {}
	return true


## Writes everything into the folder: the pack's JSON files, the effects' script, project.json; the manifest's
## art and sound sets follow the folders that have files.
func save() -> void:
	DirAccess.make_dir_recursive_absolute(pack_dir() + "/locales")
	for kind in [["art", ART_SET], ["sound", SOUND_SET], ["music", MUSIC_SET]]:
		var folder := "%s/%s/%s" % [pack_dir(), {"art": "art", "sound": "sounds", "music": "music"}[kind[0]], kind[1]]
		var sets: Array = manifest.get(kind[0] + "_sets", [])
		var listed := sets.any(func(s): return s is Dictionary and s.get("id") == kind[1])
		var has_files := DirAccess.dir_exists_absolute(folder) and not DirAccess.get_files_at(folder).is_empty()
		if has_files and not listed:
			sets.append({"id": kind[1], "default": not sets.any(func(s): return s is Dictionary and s.get("default", false))})
		elif listed and not has_files:
			sets = sets.filter(func(s): return not (s is Dictionary and s.get("id") == kind[1]))
		manifest[kind[0] + "_sets"] = sets
	var script: String = StudioEffects.script(cards, effects)
	for c: Dictionary in cards:
		var e: Dictionary = effects.get(c.id, {})
		if not e.get("blocks", []).is_empty() or str(e.get("lua", "")).strip_edges() != "":
			c.script = SCRIPT + "#" + c.id
		elif str(c.get("script", "")).begins_with(SCRIPT + "#"):
			c.erase("script")
	_write("manifest.json", manifest)
	_write("rules.json", rules)
	_write("cards.json", cards)
	for lang in locales:
		_write("locales/%s.json" % lang, locales[lang])
	if DirAccess.dir_exists_absolute(pack_dir() + "/decks"):
		for f in DirAccess.get_files_at(pack_dir() + "/decks"):
			if not decks.has(f.get_basename()):
				DirAccess.remove_absolute(pack_dir() + "/decks/" + f)
	for d in decks:
		_write("decks/%s.json" % d, decks[d])
	if script.strip_edges() != "":
		_write_text(SCRIPT, script)
	elif FileAccess.file_exists(pack_dir() + "/" + SCRIPT):
		DirAccess.remove_absolute(pack_dir() + "/" + SCRIPT)
	var f := FileAccess.open(dir + "/project.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": FORMAT, "effects": effects}, " ", false))
	f.close()


func _write(rel: String, v: Variant) -> void:
	_write_text(rel, JSON.stringify(v, " ", false) + "\n")


func _write_text(rel: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute((pack_dir() + "/" + rel).get_base_dir())
	var f := FileAccess.open(pack_dir() + "/" + rel, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# --- building --------------------------------------------------------------------------------------

## Saves, then builds the pack and checks it as the game's pack tools do (PackCheck: errors and warnings in
## items). load: also load it into the rules engine (every script compiles); games: bot-vs-bot trial games
## with its decks.
func build(load := false, games := 0) -> PackCheck:
	save()
	var c := PackCheck.open_folder(pack_dir())
	c.check()
	if load and blocking(c) == 0 and c.load_engine():
		for i in games:
			if not c.trial(i) and c.decks().is_empty():
				break  # (no decks: said once)
	return c


## The errors that keep a pack from being played: all but those of its ready decks (a deck being made
## does not stop a test match; the export still needs none).
static func blocking(c: PackCheck) -> int:
	return c.items.filter(func(it): return it.level == PackCheck.ERROR and not str(it.file).begins_with("decks/")).size()


## A pack of the project as it is now, for drawing its cards (CardView.pack): its rules, cards and texts and
## the pictures of the cards asked for (all when none are named), without the sounds. Written into
## preview_dir(); null when it can't be.
func preview_pack(only_art: Array = []) -> Pack:
	var files := {"manifest.json": _bytes(manifest), "rules.json": _bytes(rules), "cards.json": _bytes(cards)}
	for lang in locales:
		files["locales/%s.json" % lang] = _bytes(locales[lang])
	var art := "%s/art/%s" % [pack_dir(), ART_SET]
	if DirAccess.dir_exists_absolute(art):
		for f in DirAccess.get_files_at(art):
			if f == "framing.json" or only_art.is_empty() or only_art.has(f.get_basename()):
				files["art/%s/%s" % [ART_SET, f]] = FileAccess.get_file_as_bytes(art + "/" + f)
	var m: Dictionary = manifest.duplicate(true)
	m.art_sets = [{"id": ART_SET, "default": true}] if files.keys().any(func(k): return k.begins_with("art/")) else []
	m.sound_sets = []
	files["manifest.json"] = _bytes(m)
	var where := preview_dir()
	DirAccess.make_dir_recursive_absolute(where)
	for old in DirAccess.get_files_at(where):  # (one a view still reads goes the next time, where a system keeps it)
		if old.begins_with(id + "-"):
			DirAccess.remove_absolute(where + "/" + old)
	_previews += 1
	var path := "%s/%s-%d.cardpack" % [where, id, _previews]  # a new file each time: the last preview may still be open
	var z := ZIPPacker.new()
	if z.open(path) != OK:
		return null
	for p: String in files:
		z.start_file(p)
		z.write_file(files[p])
		z.close_file()
	z.close()
	return Pack.open(path, "studio")


## Where previews are written: the system's cache, not user:// (in the browser every user:// file is saved
## into IndexedDB, and a preview made and removed at each change made those saves fail).
static func preview_dir() -> String:
	var cache := OS.get_cache_dir()
	return (cache if cache != "" else OS.get_user_data_dir()) + "/studio-preview"


static func _bytes(v: Variant) -> PackedByteArray:
	return JSON.stringify(v).to_utf8_buffer()


# --- cards -----------------------------------------------------------------------------------------

func card(cid: String) -> Dictionary:
	for c: Dictionary in cards:
		if c.id == cid:
			return c
	return {}


func _free_id(base: String) -> String:
	base = base.to_lower().replace(" ", "_").replace("-", "_")
	var n := 1
	var cid := base
	while not card(cid).is_empty():
		n += 1
		cid = "%s_%d" % [base, n]
	return cid


## A new card of a type with ordinary values (a collectible common of the core set; a token has none);
## its English name says what it is. Its id.
func add_card(type: String, cls := "NEUTRAL") -> String:
	var cid := _free_id("card_%d" % (cards.size() + 1))
	var c := {"id": cid, "type": type, "class": cls, "set": "core", "cost": 1}
	match type:
		"MINION":
			c.merge({"attack": 1, "health": 1})
		"WEAPON":
			c.merge({"attack": 1, "durability": 2})
		"CHAMPION":
			c.merge({"health": int(rules.get("limits", {}).get("champion_health", 30)), "power": str(rules.get("default_power", ""))})
	if type in ["MINION", "SPELL", "WEAPON"]:
		c.rarity = "COMMON" if rules.get("rarities", []).any(func(r): return r.id == "COMMON") else str(rules.rarities[0].id)
		c.collectible = true
	cards.append(c)
	set_text(cid, "en", "New " + type.to_lower(), "")
	return cid


func remove_card(cid: String) -> void:
	cards = cards.filter(func(c): return c.id != cid)
	effects.erase(cid)
	for lang in locales:
		for section in ["cards", "voice"]:
			if locales[lang].get(section) is Dictionary:
				locales[lang][section].erase(cid)
	for f in _media(cid):
		DirAccess.remove_absolute(f)
	set_framing(cid, 0, 0, 1)


## Renames a card everywhere (texts, voice lines, effect, pictures, sounds, decks, heroes' powers). "" or why it can't.
func rename_card(old: String, new: String) -> String:
	if _card_re.search(new) == null:
		return "Use Latin letters, digits and underscores"
	if not card(new).is_empty():
		return "A card with this id exists"
	var c := card(old)
	if c.is_empty():
		return "No such card"
	c.id = new
	if effects.has(old):
		effects[new] = effects[old]
		effects.erase(old)
	for lang in locales:
		for section in ["cards", "voice"]:
			var t: Dictionary = locales[lang].get(section, {})
			if t.has(old):
				t[new] = t[old]
				t.erase(old)
	for f in _media(old):
		DirAccess.rename_absolute(f, f.get_base_dir() + "/" + new + f.get_file().trim_prefix(old))
	var fr := framing_all()
	if fr.has(old):
		fr[new] = fr[old]
		fr.erase(old)
		_write("art/%s/framing.json" % ART_SET, fr)
	for x: Dictionary in cards:
		if x.get("power") == old:
			x.power = new
	for k in ["default_power"]:
		if rules.get(k) == old:
			rules[k] = new
	if rules.get("start", {}).get("coin") == old:
		rules.start.coin = new
	for cl in rules.get("classes", []):
		if cl.get("champion") == old:
			cl.champion = new
	for d in decks.values():
		if d.get("champion") == old:
			d.champion = new
		d.cards = d.get("cards", []).map(func(x): return new if x == old else x)
	return ""


## The files of a card's picture and sounds.
func _media(cid: String) -> Array:
	var out := []
	for folder in ["%s/art/%s" % [pack_dir(), ART_SET], "%s/sounds/%s" % [pack_dir(), SOUND_SET]]:
		if DirAccess.dir_exists_absolute(folder):
			for f in DirAccess.get_files_at(folder):
				if f.get_basename() == cid or f.get_basename().begins_with(cid + "_") and SOUND_SLOTS.has(f.get_basename().trim_prefix(cid + "_")):
					out.append(folder + "/" + f)
	return out


## A card's name and text in a language ({} when it has none there).
func text(cid: String, lang: String) -> Dictionary:
	return locales.get(lang, {}).get("cards", {}).get(cid, {})


func set_text(cid: String, lang: String, name: String, body: String) -> void:
	if not locales.has(lang):
		locales[lang] = {}
	var t: Dictionary = locales[lang].get_or_add("cards", {})
	var e := {}
	if name != "":
		e.name = name
	if body != "":
		e.text = body
	if e.is_empty():
		t.erase(cid)
	else:
		t[cid] = e


## The kinds of a card's voice lines (docs/packs/format.md §7): a hero's, a minion's or a weapon's.
const HERO_LINES := ["start", "greetings", "well_played", "thanks", "wow", "oops", "threaten"]
const CARD_LINES := ["play", "attack", "death", "trigger"]


## A card's voice line of a kind in a language ("" when none: locales' `voice`).
func voice_line(cid: String, lang: String, kind: String) -> String:
	return str(locales.get(lang, {}).get("voice", {}).get(cid, {}).get(kind, ""))


func set_voice_line(cid: String, lang: String, kind: String, line: String) -> void:
	var v: Dictionary = locales.get_or_add(lang, {}).get_or_add("voice", {})
	var mine: Dictionary = v.get_or_add(cid, {})
	if line.strip_edges() == "":
		mine.erase(kind)
	else:
		mine[kind] = line
	if mine.is_empty():
		v.erase(cid)
	if v.is_empty():
		locales[lang].erase("voice")


## Gives a card its effect (StudioEffects: {blocks, lua}): its script is made on save(), and the mechanics its
## blocks show (Battlecry, Deathrattle, Secret…) replace the ones its old blocks showed.
func set_effect(cid: String, effect: Dictionary) -> void:
	var c := card(cid)
	var old: Array = _block_keywords(c, effects.get(cid, {}))
	effects[cid] = effect
	var kw: Array = c.get("keywords", []).filter(func(k): return not old.has(k))
	for k in _block_keywords(c, effect):
		if not kw.has(k):
			kw.append(k)
	if kw.is_empty():
		c.erase("keywords")
	else:
		c.keywords = kw
	if effect.get("blocks", []).is_empty() and str(effect.get("lua", "")).strip_edges() == "":
		effects.erase(cid)


## The pack's names of the mechanics an effect's blocks show (added to rules.json when the pack lacks one).
func _block_keywords(c: Dictionary, effect: Dictionary) -> Array:
	if effect.get("blocks", []).is_empty() or str(effect.get("lua", "")).strip_edges() != "":
		return []
	return StudioEffects.keywords(effect, str(c.get("type", ""))).map(mechanic_name)


## The pack's name of an engine mechanic (rules.json mechanics); one is added (its names from the template)
## when the pack has none.
func mechanic_name(engine: String) -> String:
	var mech: Dictionary = rules.get_or_add("mechanics", {})
	for k in mech:
		if mech[k].get("engine") == engine:
			return k
	var t: Dictionary = _template().mechanics
	var name := engine
	for k in t:
		if t[k].engine == engine:
			name = k
	mech[name] = {"engine": engine}
	if t.has(name) and t[name].has("name"):
		for lang in locales:
			if t[name].name.has(lang):
				locales[lang].get_or_add("mechanics", {})[name] = {"name": t[name].name[lang], "tip": t[name].tip.get(lang, "")}
	return name


## The mechanics a person may give a card: [{id (the pack's name), engine, name, tip}] in a language, the
## keyword kind of docs/packs/schema/keywords.json (Taunt, Charge, Divine Shield…).
func keyword_choices(lang := "en") -> Array:
	var kinds := {}
	var vocab = JSON.parse_string(FileAccess.get_file_as_string(PackCheck.SCHEMAS + "/keywords.json"))
	for k in vocab.get("keywords", []) if vocab is Dictionary else []:
		kinds[k.id] = k.kind
	var out := []
	for k in rules.get("mechanics", {}):
		var engine := str(rules.mechanics[k].get("engine", ""))
		if kinds.get(engine) == "keyword" and engine != "TRAP":
			var t: Dictionary = locales.get(lang, {}).get("mechanics", {}).get(k, locales.get("en", {}).get("mechanics", {}).get(k, {}))
			out.append({"id": k, "engine": engine, "name": str(t.get("name", k)), "tip": str(t.get("tip", ""))})
	return out


# --- pictures and sounds ---------------------------------------------------------------------------

## The file of a card's picture ("" when it has none).
func art_path(cid: String) -> String:
	for ext in IMAGE_EXT:
		var f := "%s/art/%s/%s.%s" % [pack_dir(), ART_SET, cid, ext]
		if FileAccess.file_exists(f):
			return f
	return ""


## A card's picture: made square-ish at most ART_SIDE on its longer side and saved as PNG (WebP when that is
## over 2 MiB). "" or why not.
func set_art(cid: String, img: Image) -> String:
	if img == null or img.is_empty():
		return "Not a picture"
	img = img.duplicate()
	var side := maxi(img.get_width(), img.get_height())
	if side > ART_SIDE:
		img.resize(img.get_width() * ART_SIDE / side, img.get_height() * ART_SIDE / side, Image.INTERPOLATE_LANCZOS)
	var old := art_path(cid)
	if old != "":
		DirAccess.remove_absolute(old)
	var folder := "%s/art/%s" % [pack_dir(), ART_SET]
	DirAccess.make_dir_recursive_absolute(folder)
	var bytes := img.save_png_to_buffer()
	var ext := "png"
	if bytes.size() > PackCheck.LIMITS.image:
		bytes = img.save_webp_to_buffer(true, 0.85)
		ext = "webp"
	var f := FileAccess.open("%s/%s.%s" % [folder, cid, ext], FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return ""


func remove_art(cid: String) -> void:
	if art_path(cid) != "":
		DirAccess.remove_absolute(art_path(cid))
	set_framing(cid, 0, 0, 1)


## art/main/framing.json (docs/packs/format.md §7, classichs-art-framing/1's values): card id -> {x, y, zoom}.
func framing_all() -> Dictionary:
	var j = _json("art/%s/framing.json" % ART_SET)
	return j if j is Dictionary else {}


## Where a card's picture sits: (x, y, zoom), (0, 0, 1) by default.
func framing(cid: String) -> Vector3:
	var e: Dictionary = framing_all().get(cid, {})
	return Vector3(float(e.get("x", 0)), float(e.get("y", 0)), float(e.get("zoom", 1)))


## Moves and zooms a card's picture (x, y: -1…1, zoom: 0.5…3, as the framing tool keeps them).
func set_framing(cid: String, x: float, y: float, zoom: float) -> void:
	var all := framing_all()
	x = snappedf(clampf(x, -1, 1), 0.001)
	y = snappedf(clampf(y, -1, 1), 0.001)
	zoom = snappedf(clampf(zoom, 0.5, 3), 0.001)
	if is_zero_approx(x) and is_zero_approx(y) and is_equal_approx(zoom, 1):
		if not all.has(cid):
			return
		all.erase(cid)
	else:
		all[cid] = {"x": x, "y": y, "zoom": zoom}
	if all.is_empty():
		DirAccess.remove_absolute("%s/art/%s/framing.json" % [pack_dir(), ART_SET])
	else:
		_write("art/%s/framing.json" % ART_SET, all)


## The file of a card's sound for a slot ("" when it has none).
func sound_path(cid: String, slot: String) -> String:
	for ext in AUDIO_EXT:
		var f := "%s/sounds/%s/%s_%s.%s" % [pack_dir(), SOUND_SET, cid, slot, ext]
		if FileAccess.file_exists(f):
			return f
	return ""


## The file of the game's music or event sound (folder "music" or "sounds", a name of MUSIC or GAME_SOUNDS);
## "" when it has none.
func audio_path(folder: String, name: String) -> String:
	for ext in AUDIO_EXT:
		var f := "%s/%s/%s/%s.%s" % [pack_dir(), folder, MUSIC_SET if folder == "music" else SOUND_SET, name, ext]
		if FileAccess.file_exists(f):
			return f
	return ""


## The game's music or event sound from a file's bytes. "" or why not.
func set_audio(folder: String, name: String, bytes: PackedByteArray, ext: String) -> String:
	ext = ext.to_lower()
	if not AUDIO_EXT.has(ext):
		return "Use an .opus, .ogg, .wav or .mp3 file"
	if bytes.size() > PackCheck.LIMITS.file:
		return "The file is bigger than 16 MiB"
	remove_audio(folder, name)
	var dir_ := "%s/%s/%s" % [pack_dir(), folder, MUSIC_SET if folder == "music" else SOUND_SET]
	DirAccess.make_dir_recursive_absolute(dir_)
	var f := FileAccess.open("%s/%s.%s" % [dir_, name, ext], FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return ""


func remove_audio(folder: String, name: String) -> void:
	while audio_path(folder, name) != "":
		DirAccess.remove_absolute(audio_path(folder, name))


## A card's sound for a slot from a file's bytes (ext: opus, ogg, wav, mp3). "" or why not.
func set_sound(cid: String, slot: String, bytes: PackedByteArray, ext: String) -> String:
	ext = ext.to_lower()
	if not AUDIO_EXT.has(ext):
		return "Use an .opus, .ogg, .wav or .mp3 file"
	if bytes.size() > PackCheck.LIMITS.file:
		return "The file is bigger than 16 MiB"
	remove_sound(cid, slot)
	var folder := "%s/sounds/%s" % [pack_dir(), SOUND_SET]
	DirAccess.make_dir_recursive_absolute(folder)
	var f := FileAccess.open("%s/%s_%s.%s" % [folder, cid, slot, ext], FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return ""


func remove_sound(cid: String, slot: String) -> void:
	if sound_path(cid, slot) != "":
		DirAccess.remove_absolute(sound_path(cid, slot))


# --- classes, sets, rarities -----------------------------------------------------------------------

## A new playable class with its hero (a CHAMPION card <id>_hero) and Hero Power (a POWER card <id>_power that
## deals 1 damage); the first one's power serves as the default. "" or why not.
func add_class(cls: String, color := "c0392b") -> String:
	cls = cls.to_upper()
	if _card_re.search(cls) == null:
		return "Use Latin letters, digits and underscores"
	if rules.classes.any(func(c): return c.id == cls):
		return "A class with this id exists"
	var low := cls.to_lower()
	var hero := _free_id(low + "_hero")
	var power := _free_id(low + "_power")
	rules.classes.insert(rules.classes.size() - 1 if rules.classes.size() > 0 and rules.classes[-1].get("neutral", false) else rules.classes.size(),
		{"id": cls, "champion": hero})
	cards.append({"id": hero, "type": "CHAMPION", "class": cls, "set": "core", "health": int(rules.limits.get("champion_health", 30)), "power": power})
	cards.append({"id": power, "type": "POWER", "class": cls, "set": "core", "cost": 2})
	effects[power] = {"blocks": [], "lua": "target = \"any\",\nhero_power = function(g, me, t) g.damage(me, t, g.hp_dmg(me, 1)) end,"}
	if str(rules.get("default_power", "")) == "":
		rules.default_power = power
	manifest.get_or_add("colors", {}).get_or_add("classes", {})[cls] = color
	set_text(hero, "en", cls.capitalize(), "")
	set_text(power, "en", "Strike", "Deal 1 damage.")
	locales.get_or_add("en", {}).get_or_add("classes", {})[cls] = cls.capitalize()
	return ""


## Removes a class, its hero and Hero Power; its other cards become neutral.
func remove_class(cls: String) -> void:
	var c: Dictionary = {}
	for x in rules.classes:
		if x.id == cls:
			c = x
	if c.is_empty() or c.get("neutral", false):
		return
	rules.classes.erase(c)
	var neutral := ""
	for x in rules.classes:
		if x.get("neutral", false):
			neutral = x.id
	var hero := card(str(c.get("champion", "")))
	if not hero.is_empty():
		var power := str(hero.get("power", ""))
		remove_card(hero.id)
		if power != "" and not cards.any(func(x): return x.get("power") == power):
			remove_card(power)
			if rules.get("default_power") == power:
				var others := cards.filter(func(x): return x.type == "POWER")
				rules.default_power = others[0].id if not others.is_empty() else ""
	for x: Dictionary in cards:
		if x.get("class") == cls:
			x["class"] = neutral
	manifest.get("colors", {}).get("classes", {}).erase(cls)
	for lang in locales:
		locales[lang].get("classes", {}).erase(cls)
	for d in decks.keys():
		if card(str(decks[d].get("champion", ""))).is_empty():
			decks.erase(d)


## A term of a locale section (classes, sets, rarities, races) in a language, else English, else its id.
func term(section: String, key: String, lang := "en") -> String:
	var v = locales.get(lang, {}).get(section, {}).get(key, locales.get("en", {}).get(section, {}).get(key, key))
	return str(v)


func set_term(section: String, key: String, lang: String, value: String) -> void:
	var s: Dictionary = locales.get_or_add(lang, {}).get_or_add(section, {})
	if value == "":
		s.erase(key)
	else:
		s[key] = value


## Adds a set (playable in constructed when collectible is true). "" or why not.
func add_set(set_id: String, playable := true) -> String:
	if _card_re.search(set_id) == null:
		return "Use Latin letters, digits and underscores"
	if rules.sets.has(set_id):
		return "A set with this id exists"
	rules.sets.append(set_id)
	if playable:
		rules.get_or_add("modes", {}).get_or_add("constructed", {"class_cards": "own_and_neutral"}).get_or_add("sets", []).append(set_id)
	return ""


## Removes a set no card is in. "" or why not.
func remove_set(set_id: String) -> String:
	if cards.any(func(c): return c.get("set") == set_id):
		return "Cards are in this set"
	rules.sets.erase(set_id)
	for m in rules.get("modes", {}).values():
		if m is Dictionary and m.get("sets") is Array:
			m.sets.erase(set_id)
	for lang in locales:
		locales[lang].get("sets", {}).erase(set_id)
	return ""


## Adds a rarity of a tier (common, rare, epic, legendary). "" or why not.
func add_rarity(rid: String, tier: String, color := "e0e0e0") -> String:
	if _card_re.search(rid) == null:
		return "Use Latin letters, digits and underscores"
	if rules.rarities.any(func(r): return r.id == rid):
		return "A rarity with this id exists"
	rules.rarities.append({"id": rid, "tier": tier})
	manifest.get_or_add("colors", {}).get_or_add("rarities", {})[rid] = color
	return ""


## Removes a rarity no card has. "" or why not.
func remove_rarity(rid: String) -> String:
	if cards.any(func(c): return c.get("rarity") == rid):
		return "Cards have this rarity"
	rules.rarities = rules.rarities.filter(func(r): return r.id != rid)
	manifest.get("colors", {}).get("rarities", {}).erase(rid)
	for lang in locales:
		locales[lang].get("rarities", {}).erase(rid)
	return ""


# --- decks -----------------------------------------------------------------------------------------

## The cards a deck of a hero may hold (collectible, of the constructed sets, its class or neutral), by cost.
func deck_pool(hero: String) -> Array:
	var cls := str(card(hero).get("class", ""))
	var neutral: Array = rules.classes.filter(func(c): return c.get("neutral", false)).map(func(c): return c.id)
	var sets: Array = rules.get("modes", {}).get("constructed", {}).get("sets", rules.sets)
	var out := []
	for c: Dictionary in cards:
		var of_class: bool = c.get("classes").has(cls) if c.get("classes") is Array else (c.get("class") == cls or neutral.has(c.get("class")))
		if c.get("collectible", false) and c.type != "CHAMPION" and sets.has(c.get("set")) and of_class:
			out.append(c)
	out.sort_custom(func(a, b): return [int(a.get("cost", 0)), str(a.id)] < [int(b.get("cost", 0)), str(b.id)])
	return out.map(func(c): return c.id)


## Why a deck is not legal by the pack's rules ("" = it is): PackCheck's own check.
func deck_problem(name: String) -> String:
	var by_id := {}
	for c in cards:
		by_id[c.id] = c
	return PackCheck.deck_error(decks.get(name, {}), by_id, rules)
