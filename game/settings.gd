class_name Settings
extends RefCounted
## Player settings (user://settings.json). Bad or missing values fall back to defaults.

const DEFAULT_PATH := "user://settings.json"
const DEFAULTS := {"language": "", "music": 0.5, "sfx": 0.8, "voice": 0.8, "tts": true, "shake": true, "fullscreen": false,
	"tracker": false, "anim_speed": 1, "art": "generated", "tracker_deck": true, "tracker_left": true, "tracker_opp": true}
const BUSES := ["Music", "SFX"]

static var path := DEFAULT_PATH
static var data: Dictionary = DEFAULTS.duplicate()


static func load_settings() -> void:
	data = DEFAULTS.duplicate()
	var j := JSON.new()
	if not FileAccess.file_exists(path) or j.parse(FileAccess.get_file_as_string(path)) != OK or not j.data is Dictionary:
		return
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
				if v is float or v is int:
					data[k] = clampi(int(v), 1, 4)
			TYPE_STRING:
				if k == "art":
					if v is String and v != "":  # a folder in art/; a missing one falls back to "generated"
						data[k] = v
				elif v is String and (v == "" or Locale.LANGS.has(v)):
					data[k] = v


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
