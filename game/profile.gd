class_name Profile
extends RefCounted
## The local player's profile: the name the opponent sees.

const DEFAULT_PATH := "user://profile.json"
## The longest name (a server account's too: 16 at registration).
const NAME_MAX := 16
const DEFAULT_NAME := "Player"

static var path := DEFAULT_PATH


static func load_name() -> String:
	var j := JSON.new()
	if not FileAccess.file_exists(path) or j.parse(FileAccess.get_file_as_string(path)) != OK or not j.data is Dictionary:
		return DEFAULT_NAME
	return clean(str(j.data.get("name", "")), NAME_MAX)


static func save_name(n: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"name": clean(n, NAME_MAX)}))


## Trimmed, at most `most` characters, never empty. Another player's name (from the network) keeps up
## to 24 (an older one; a server account's has up to 20): `short` shows it with "…".
static func clean(n: String, most := 24) -> String:
	n = n.strip_edges().left(most).strip_edges()
	return n if n != "" else DEFAULT_NAME


## A name to show: one longer than NAME_MAX characters (an older one, a server account's of up
## to 20) ends in "…" after its first NAME_MAX - 1.
static func short(n: String) -> String:
	return n if n.length() <= NAME_MAX else n.left(NAME_MAX - 1).strip_edges() + "…"
