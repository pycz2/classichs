class_name Settings
extends RefCounted
## Player settings (user://settings.json). Bad or missing values fall back to defaults.
## "pack" is the active game pack ({id, hash}), "pack_sets" the art, sound and music set
## chosen per pack id (game/packs.gd). "servers" the connections to game servers: [{id, url,
## name}] (D14; the same address may be there twice with other logins: the id tells them apart,
## the first one's id is its address; an old single "server" becomes the list). "layout": the
## version of the player's files (Migration; 0 = before 0.40).

const DEFAULT_PATH := "user://settings.json"
const DEFAULTS := {"language": "", "music": 0.5, "sfx": 0.8, "shake": true, "fullscreen": false,
	"tracker": false, "anim_speed": 1, "card_back": CardBacks.DEFAULT, "tracker_deck": true, "tracker_opp": true,
	"servers": [], "bot_level": "medium", "pack": {}, "pack_sets": {}, "layout": 0}
const BUSES := ["Music", "SFX"]

static var path := DEFAULT_PATH
static var data: Dictionary = DEFAULTS.duplicate(true)


## True when there was no settings file yet (the first run: the language is asked).
static var first_run := false
## The settings file as it was read (Migration takes what older versions kept there).
static var old: Dictionary = {}


static func load_settings() -> void:
	data = DEFAULTS.duplicate(true)
	old = {}
	first_run = not FileAccess.file_exists(path)
	var j := JSON.new()
	if not FileAccess.file_exists(path) or j.parse(FileAccess.get_file_as_string(path)) != OK or not j.data is Dictionary:
		return
	old = j.data
	for k in DEFAULTS:
		var v = j.data.get(k)
		match typeof(DEFAULTS[k]):
			TYPE_FLOAT:
				if v is float or v is int:
					data[k] = clampf(float(v), 0.0, 1.0)
			TYPE_BOOL:
				if v is bool:
					data[k] = v
			TYPE_INT:
				if k == "layout":
					if v is float or v is int:
						data[k] = maxi(0, int(v))
				elif v is float or v is int:
					data[k] = clampi(int(v), 1, 4)
			TYPE_ARRAY:
				if k == "servers" and v is Array:
					var list := []
					for e in v:
						var id := str(e.get("id", e.get("url", ""))) if e is Dictionary else ""
						if e is Dictionary and server_ok(str(e.get("url", ""))) and id != "" and not list.any(func(x): return x.id == id):
							list.append({"id": id, "url": str(e.url), "name": server_label(str(e.url), e.get("name"))})
					data[k] = list
				elif k == "servers" and server_ok(str(j.data.get("server", ""))):  # the old single address
					data[k] = [{"id": str(j.data.server), "url": str(j.data.server), "name": server_label(str(j.data.server))}]
			TYPE_DICTIONARY:
				if v is Dictionary:
					data[k] = v
			TYPE_STRING:
				if k == "card_back":
					if v is String and CardBacks.NAMES.has(v):
						data[k] = v
				elif k == "bot_level":
					if v is String and BotBrain.LEVELS.has(v):
						data[k] = v
				elif v is String and (v == "" or Locale.LANGS.has(v)):
					data[k] = v


## A game server address the client may use: ws:// or wss://, a host, no spaces.
static func server_ok(address: String) -> bool:
	return address.length() <= 200 and (address.begins_with("ws://") or address.begins_with("wss://")) \
		and address.split("://")[1] != "" and not address.contains(" ")


## A server's name: the one given (trimmed, 40 letters at most), else its host.
static func server_label(address: String, given: Variant = null) -> String:
	var n := str(given).strip_edges().left(40) if given is String else ""
	return n if n != "" else address.split("://")[-1].get_slice("/", 0).get_slice(":", 0)


## The name of a connection (by its id), else of the first one to that address, else the host.
static func server_name(id: String) -> String:
	for e in data.servers:
		if e.id == id:
			return e.name
	for e in data.servers:
		if e.url == id:
			return e.name
	return server_label(id)


## A new connection's id: the address the first time, then "<address>#2", "#3"...
static func new_server_id(address: String) -> String:
	var id := address
	var n := 1
	while data.servers.any(func(x): return x.id == id):
		n += 1
		id = "%s#%d" % [address, n]
	return id


static func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


static func language() -> String:
	return data.language if data.language != "" else Locale.pick(OS.get_locale())


static func apply() -> void:
	Locale.set_language(language())
	Match.shake_enabled = data.shake
	for i in BUSES.size():
		var bus := AudioServer.get_bus_index(BUSES[i])
		if bus < 0:
			AudioServer.add_bus()
			bus = AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus, BUSES[i])
		var v: float = data.music if BUSES[i] == "Music" else data.sfx
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(bus, v <= 0.0)


## Fullscreen must follow a user action in the browser (the settings toggle does that).
static func set_fullscreen(on: bool) -> void:
	data.fullscreen = on
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
