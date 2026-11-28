class_name DeckStore
extends RefCounted
## A player's decks, per game (a deck belongs to the pack it was made in; in a pack with versions, to the version):
## on this device in user:// (IndexedDB in the browser), one file per game (key(): the old Classic pack's is
## decks.json, another pack's decks.<pack id>.json, a version's decks.<pack id>.<version>.json); in a game played
## through a server (link) the server's decks of that game. The old Classic pack's decks start Classic's version 5314
## (its time, May 2014) once: copied there, the old file kept. There are no ready-made decks in the list: a new deck may start from a
## template (Decks.templates). A broken file is kept aside as *.bad.json instead of being lost.

const DEFAULT_PATH := "user://decks.json"
const VERSION := 2
## The version the old Classic pack's decks are copied into (key()).
const OLD_CLASSIC_INTO := "hs-eras.5314"

static var path := DEFAULT_PATH
## A game played through a server: its decks are this connection's (null = this device's).
static var link: ServerLink
## Set by load_all when the file was damaged (a copy is kept); shown to the player.
static var last_load_error := ""


## A game's decks key: its pack id, with the version for a version of a pack ("hs-eras.5314").
static func key(p: Pack) -> String:
	return p.id() + ("." + p.version_id if p.version_id != "" else "")


## The decks file of a game's key (key(); a pack id; the active game's by default).
static func file(pack_id := "") -> String:
	if pack_id == "":
		pack_id = key(Packs.active()) if Packs.active() else Packs.CLASSIC
	return path if pack_id == Packs.CLASSIC else "%s.%s.json" % [path.get_basename(), pack_id]


## The old Classic pack's decks (decks.json) become version 5314's the first time its file is read (none there yet).
static func _copy_old_classic(at: String) -> void:
	if at == file(OLD_CLASSIC_INTO) and at != path and not FileAccess.file_exists(at) and FileAccess.file_exists(path):
		DirAccess.copy_absolute(path, at)


## The decks of the active game: the server's in a server game, else this device's.
static func load_all() -> Array[Deck]:
	if link:
		last_load_error = ""
		return link.decks_of(Packs.active())
	return load_local()


## The decks kept on this device for a pack id (the active pack's by default; the cards are read
## with the active pack's: a pack of the same rules).
static func load_local(pack_id := "") -> Array[Deck]:
	var out: Array[Deck] = []
	var at := file(pack_id)
	last_load_error = ""
	_copy_old_classic(at)
	if not FileAccess.file_exists(at):
		return out
	var text := FileAccess.get_file_as_string(at)
	var j := JSON.new()
	var ok := j.parse(text) == OK and j.data is Dictionary and j.data.get("decks") is Array
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
		var backup := _free_backup_path(at)
		var bad := FileAccess.open(backup, FileAccess.WRITE)
		if bad:
			bad.store_string(text)
		last_load_error = TranslationServer.translate("The saved decks file was damaged; a copy was kept as %s") % backup.get_file()
	return out


## decks.bad.json, then decks.bad1.json, … — never overwrite an earlier copy.
static func _free_backup_path(at: String) -> String:
	var base := at.get_basename() + ".bad"
	var p := base + ".json"
	var n := 1
	while FileAccess.file_exists(p):
		p = "%s%d.json" % [base, n]
		n += 1
	return p


## Saves the active game's decks on this device (a server game's go to the server: DeckListView).
static func save_all(decks: Array) -> bool:
	if link:
		return true
	return write(file(), decks.map(func(d: Deck): return d.to_dict()))


## Writes a decks file (the decks as dictionaries) through a temporary file.
static func write(at: String, decks: Array) -> bool:
	var tmp := at + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version": VERSION, "decks": decks}, "  "))
	f.close()
	return DirAccess.rename_absolute(tmp, at) == OK


## How many decks a game's key has on this device (read as they are: no pack needs to be active).
static func count_local(pack_id: String) -> int:
	_copy_old_classic(file(pack_id))
	var j = JSON.parse_string(FileAccess.get_file_as_string(file(pack_id))) if FileAccess.file_exists(file(pack_id)) else null
	return j.decks.size() if j is Dictionary and j.get("decks") is Array else 0


## Deletes a pack id's decks on this device (the pack was deleted; versions: each one's too).
static func delete_for(pack_id: String, versions := []) -> void:
	DirAccess.remove_absolute(file(pack_id))
	for v in versions:
		if v is Dictionary:
			DirAccess.remove_absolute(file(pack_id + "." + str(v.get("id", ""))))
