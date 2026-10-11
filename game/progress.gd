class_name Progress
extends RefCounted
## Completed tutorial missions (user://tutorial.json).

const DEFAULT_PATH := "user://tutorial.json"

static var path := DEFAULT_PATH


static func completed() -> Array:
	var j := JSON.new()
	if not FileAccess.file_exists(path) or j.parse(FileAccess.get_file_as_string(path)) != OK \
			or not j.data is Dictionary or not j.data.get("completed") is Array:
		return []
	var out := []
	for n in j.data.completed:
		if (n is float or n is int) and int(n) >= 1 and int(n) <= Missions.count() and not out.has(int(n)):
			out.append(int(n))
	out.sort()
	return out


## Mission 1 is always open; each next one opens after the previous win.
static func unlocked(n: int) -> bool:
	return n == 1 or completed().has(n - 1)


static func complete(n: int) -> void:
	var done := completed()
	if not done.has(n):
		done.append(n)
		done.sort()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"completed": done}))
