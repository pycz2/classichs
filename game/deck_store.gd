class_name DeckStore
extends RefCounted
## Saved decks in user:// (IndexedDB in the browser). A broken file is kept
## aside as *.bad.json instead of being lost.

const DEFAULT_PATH := "user://decks.json"
const VERSION := 1

static var path := DEFAULT_PATH
## Set by load_all when the file was damaged (a copy is kept); shown to the player.
static var last_load_error := ""


## A ready Basic deck for every hero (the first run starts with them).
static func starter() -> Array[Deck]:
	var out: Array[Deck] = []
	for cls in TrainingSetup.ORDER:
		var d := Deck.new()
		d.hero = Decks.hero(cls)
		d.name = TranslationServer.translate("Basic deck: %s") % CardText.name(d.hero)
		d.cards.assign(Decks.basic(cls))
		out.append(d)
	return out


static func load_all() -> Array[Deck]:
	var out: Array[Deck] = []
	if not FileAccess.file_exists(path):
		return starter()
	var text := FileAccess.get_file_as_string(path)
	var j := JSON.new()
	var ok := j.parse(text) == OK and j.data is Dictionary and j.data.get("decks") is Array
	last_load_error = ""
	if ok:
		for d in j.data.decks:
			var deck := Deck.from_dict(d)
			if deck == null:
				ok = false
			else:
				if deck.cards.size() != d.cards.size():
					ok = false  # some cards no longer exist
				out.append(deck)
	if not ok:
		var backup := _free_backup_path()
		var bad := FileAccess.open(backup, FileAccess.WRITE)
		if bad:
			bad.store_string(text)
		last_load_error = TranslationServer.translate("The saved decks file was damaged; a copy was kept as %s") % backup.get_file()
	return out


## decks.bad.json, then decks.bad1.json, … — never overwrite an earlier copy.
static func _free_backup_path() -> String:
	var base := path.get_basename() + ".bad"
	var p := base + ".json"
	var n := 1
	while FileAccess.file_exists(p):
		p = "%s%d.json" % [base, n]
		n += 1
	return p


static func save_all(decks: Array) -> bool:
	var data := {"version": VERSION, "decks": decks.map(func(d: Deck): return d.to_dict())}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return DirAccess.rename_absolute(tmp, path) == OK
