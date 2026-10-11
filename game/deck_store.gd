class_name DeckStore
extends RefCounted
## Saved decks in user:// (IndexedDB in the browser). A broken file is kept
## aside as *.bad.json instead of being lost.

const DEFAULT_PATH := "user://decks.json"
const VERSION := 1

static var path := DEFAULT_PATH


static func load_all() -> Array[Deck]:
	var out: Array[Deck] = []
	if not FileAccess.file_exists(path):
		return out
	var text := FileAccess.get_file_as_string(path)
	var j := JSON.new()
	var ok := j.parse(text) == OK and j.data is Dictionary and j.data.get("decks") is Array
	if ok:
		for d in j.data.decks:
			var deck := Deck.from_dict(d)
			if deck == null:
				ok = false
			else:
				out.append(deck)
	if not ok:
		var bad := FileAccess.open(path.get_basename() + ".bad.json", FileAccess.WRITE)
		if bad:
			bad.store_string(text)
	return out


static func save_all(decks: Array) -> bool:
	var data := {"version": VERSION, "decks": decks.map(func(d: Deck): return d.to_dict())}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return DirAccess.rename_absolute(tmp, path) == OK
