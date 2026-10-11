class_name Profile
extends RefCounted
## The local player's profile: the name the opponent sees.

const DEFAULT_PATH := "user://profile.json"
const NAME_MAX := 24
const DEFAULT_NAME := "Player"

static var path := DEFAULT_PATH


static func load_name() -> String:
	var j := JSON.new()
	if not FileAccess.file_exists(path) or j.parse(FileAccess.get_file_as_string(path)) != OK or not j.data is Dictionary:
		return DEFAULT_NAME
	return clean(str(j.data.get("name", "")))


static func save_name(n: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"name": clean(n)}))


## Trimmed, at most NAME_MAX characters, never empty.
static func clean(n: String) -> String:
	n = n.strip_edges().left(NAME_MAX).strip_edges()
	return n if n != "" else DEFAULT_NAME
