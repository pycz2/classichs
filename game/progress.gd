class_name Progress
extends RefCounted
## Completed tutorial missions (user://tutorial.json): {"completed": [Classic's], "<pack id>": [another pack's]}.

const DEFAULT_PATH := "user://tutorial.json"

static var path := DEFAULT_PATH


## The active pack's list in the file ("completed" for Classic, as before packs).
static func _key() -> String:
	var p := Packs.active()
	return "completed" if p == null or p.id() == Packs.CLASSIC else p.id()


static func _read() -> Dictionary:
	var j := JSON.new()
	if not FileAccess.file_exists(path) or j.parse(FileAccess.get_file_as_string(path)) != OK or not j.data is Dictionary:
		return {}
	return j.data


static func completed() -> Array:
	var got = _read().get(_key())
	var ids := Missions.ids()
	var out := []
	for n in (got if got is Array else []):
		if (n is float or n is int) and ids.has(int(n)) and not out.has(int(n)):
			out.append(int(n))
	out.sort()
	return out


## The tutorial's unlock rule: "all" opens every mission; "in_order" (the default) opens the first
## one, and each next one after the previous win.
static func unlocked(n: int) -> bool:
	var ids := Missions.ids()
	var i := ids.find(n)
	return i == 0 or (i > 0 and (str(Missions.tutorial().get("unlock", "in_order")) == "all" or completed().has(ids[i - 1])))


static func complete(n: int) -> void:
	var done := completed()
	if not done.has(n):
		done.append(n)
		done.sort()
	var all := _read()
	all[_key()] = done
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all))
