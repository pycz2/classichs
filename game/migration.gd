class_name Migration
extends RefCounted
## The player's files from before 0.40 move to their places, once at start-up (Settings
## "layout" below LAYOUT; main runs it before anything else). The user data folder stays; nothing
## the player made is lost:
## - the art and music sets of Classic (settings "art", "music_set", from before packs) become
##   Classic's choices per game (pack_sets; a choice made there already wins); card backs chosen
##   per pack go (a pack with its own back shows it, the others the neutral back of the settings;
##   an old back that is not a neutral one becomes the default: Settings reads it so);
## - the game servers become the connections (Settings reads each with its address as its id,
##   so its saved login stays; nothing to move);
## - the player's name stays in profile.json: it is the name offered before code play;
## - decks: each file is a pack's (DeckStore.file); a deck whose cards are not of that pack moves
##   to the installed pack whose cards it uses (Classic ids: Classic); an unchanged ready-made
##   deck (a template's champion, cards and name, as the game put it into the list) goes: the
##   templates offer it. A damaged file is left as it is.

const LAYOUT := 1


## Runs the migration if the files are older (true when it ran).
static func run() -> bool:
	if int(Settings.data.get("layout", 0)) >= LAYOUT:
		return false
	var old := Settings.old
	var sets: Dictionary = Settings.data.pack_sets
	for id in sets:
		if sets[id] is Dictionary:
			sets[id].erase("back")
	var classic: Dictionary = sets.get(Packs.CLASSIC, {}) if sets.get(Packs.CLASSIC) is Dictionary else {}
	for pair in [["art", "art"], ["music_set", "music"]]:
		if old.get(pair[0]) is String and old[pair[0]] != "" and not classic.has(pair[1]):
			classic[pair[1]] = old[pair[0]]
	if not classic.is_empty():
		sets[Packs.CLASSIC] = classic
	move_decks()
	Settings.data.layout = LAYOUT
	Settings.save()
	return true


## Every pack id's decks file: misfiled decks to their pack, unchanged ready-made decks out.
static func move_decks() -> void:
	var cards := {}  # pack id -> {card id: true} (champions too)
	var made := {}  # pack id -> [[champion, sorted cards, [names]]] of its templates
	for p: Pack in Packs.all():
		if cards.has(p.id()):
			continue
		var ids := {}
		for c in p.cards():
			if c is Dictionary:
				ids[str(c.get("id", ""))] = true
		cards[p.id()] = ids
		made[p.id()] = _templates(p)
	var files := {}  # pack id -> [deck dict]; a missing file is an empty one, a damaged one is left out
	for id in cards:
		var at := DeckStore.file(id)
		if not FileAccess.file_exists(at):
			files[id] = []
			continue
		var j = JSON.parse_string(FileAccess.get_file_as_string(at))
		if j is Dictionary and j.get("decks") is Array and j.decks.all(func(d): return d is Dictionary):
			files[id] = j.decks.duplicate()
	var changed := {}
	for id in files.keys():
		var keep := []
		for d: Dictionary in files[id]:
			if _ready_made(d, made[id]):
				changed[id] = true
				continue
			var home: String = id if _fits(d, cards[id]) else ""
			if home == "":
				for other in files:
					if other != id and _fits(d, cards[other]):
						home = other
						break
			if home == "" or home == id:
				keep.append(d)
			else:
				files[home].append(d)
				changed[home] = true
				changed[id] = true
		files[id] = keep
	for id in changed:
		DeckStore.write(DeckStore.file(id), files[id])


## [champion, sorted cards, names] of each of a pack's decks/*.json (names: the file's `name`
## and the pack's `decks` term of it in every language).
static func _templates(p: Pack) -> Array:
	var out := []
	for f in p.files():
		if not (f.begins_with("decks/") and f.ends_with(".json")):
			continue
		var d = p.json(f)
		if not d is Dictionary or not d.get("cards") is Array:
			continue
		var key: String = f.get_file().get_basename()
		var names := [str(d.get("name", ""))]
		for lang in p.manifest.get("locales", []):
			var terms = p.locale(str(lang)).get("decks", {})
			if terms is Dictionary and terms.has(key):
				names.append(str(terms[key]))
		var c: Array = d.cards.map(func(x): return str(x))
		c.sort()
		out.append([str(d.get("champion", "")), c, names])
	return out


static func _ready_made(d: Dictionary, templates: Array) -> bool:
	if not d.get("cards") is Array:
		return false
	var c: Array = d.cards.map(func(x): return str(x))
	c.sort()
	return templates.any(func(t): return t[0] == str(d.get("hero", "")) and t[1] == c and t[2].has(str(d.get("name", ""))))


static func _fits(d: Dictionary, ids: Dictionary) -> bool:
	return ids.has(str(d.get("hero", ""))) and d.get("cards") is Array and d.cards.all(func(x): return ids.has(str(x)))
