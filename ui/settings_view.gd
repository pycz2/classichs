class_name SettingsView
extends Control
## The client's settings, the same everywhere (the main menu, a game's menu, over a match):
## language, music and sound volume, the card back (a neutral one; a pack with its own back
## shows that), animation speed, screen shake, fullscreen, the FPS counter. Inside a game a "Debug tools" button
## opens that game's debug table. Every change is applied and saved at once. Works as a screen
## and as an overlay.

signal back
## The debug tools were asked for (the button shows only when this is connected:
## not in the settings opened over a match).
signal debug
## The language changed; the owner relabels its own texts.
signal language_changed
## The card back changed; the owner redraws its cards.
signal art_changed

## Row labels (English keys); the translation tool reads these lists.
const SLIDERS := [["Music", "music"], ["Sounds", "sfx"]]
const TOGGLES := [["Screen shake", "Shake", "shake"], ["Fullscreen", "Fullscreen", "fullscreen"],
	["FPS counter", "Fps", "fps"], ["Performance log", "PerfLog", "perf"]]


func _ready() -> void:
	name = "SettingsView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(Palette.TABLE, 0.95)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var title := Palette.label(tr("Settings"), 40, Palette.ATTACK)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)

	var lang := OptionButton.new()
	lang.name = "Language"
	for code in Locale.LANGS:
		lang.add_item(Locale.LANGS[code])
		if code == Settings.language():
			lang.select(lang.item_count - 1)
	lang.item_selected.connect(func(i): set_language(Locale.LANGS.keys()[i]))
	_row(grid, tr("Language"), lang)

	for s in SLIDERS:
		var sl := HSlider.new()
		sl.name = s[0]
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = Settings.data[s[1]]
		sl.custom_minimum_size = Vector2(300, 32)
		var key: String = s[1]
		sl.value_changed.connect(func(v): _store(key, v))
		_row(grid, tr(s[0]), sl)

	var backs := HBoxContainer.new()
	backs.add_theme_constant_override("separation", 10)
	var back_pick := OptionButton.new()
	back_pick.name = "CardBack"
	back_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var preview := CardBacks.Preview.new()
	var back_names: Array = CardBacks.NAMES
	for n in back_names:
		back_pick.add_item(tr(CardBacks.LABELS[n]))
	back_pick.select(maxi(0, back_names.find(Settings.data.card_back)))
	preview.back = Settings.data.card_back
	back_pick.item_selected.connect(func(i):
		_store("card_back", back_names[i])
		preview.back = back_names[i]
		preview.queue_redraw()
		art_changed.emit())
	backs.add_child(back_pick)
	backs.add_child(preview)
	_row(grid, tr("Card back"), backs)

	var speed := HSlider.new()
	speed.name = "AnimSpeed"
	speed.min_value = 1
	speed.max_value = 4
	speed.step = 1
	speed.tick_count = 4
	speed.ticks_on_borders = true
	speed.value = Settings.data.anim_speed
	speed.custom_minimum_size = Vector2(300, 32)
	speed.value_changed.connect(func(v): _store("anim_speed", int(v)))
	_row(grid, tr("Animation speed"), speed)

	for t in TOGGLES:
		var cb := CheckButton.new()
		cb.name = t[1]
		cb.button_pressed = Settings.data[t[2]]
		if t[2] == "fullscreen":  # Esc in the browser leaves fullscreen without us
			cb.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		var key: String = t[2]
		cb.toggled.connect(func(on):
			if key == "fullscreen":
				Settings.set_fullscreen(on)  # runs inside the click: the browser allows it
			_store(key, on)
			if key == "perf":
				_build.call_deferred())  # (its Save log button)
		_row(grid, tr(t[0]), cb)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	if not debug.get_connections().is_empty():
		var d := Palette.button(tr("Debug tools"), "DebugTools")
		d.pressed.connect(func(): debug.emit())
		row.add_child(d)
	if (PerfLog.on or Settings.data.get("perf", false)) and PerfLog.instance:  # the log so far: a download, or where its file is
		var save := Palette.button(tr("Save log"), "SavePerfLog")
		save.pressed.connect(func(): save.text = PerfLog.instance.save().get_file())
		row.add_child(save)
	var b := Palette.button(tr("Back"), "Back")
	b.pressed.connect(func(): back.emit())
	row.add_child(b)


## The name of a pack's art, sound or music set in the interface language (an English name
## the pack does not translate goes through the game's own translations).
static func pack_set_name(pack: Pack, entry: Dictionary) -> String:
	var names = entry.get("name", {})
	var lang := TranslationServer.get_locale()
	if names is Dictionary and not names.has(lang) and names.has("en"):
		return TranslationServer.translate(names.en)
	var t := pack.text_of(names, lang)
	return t if t != "" else str(entry.get("id", "")).capitalize()


func _row(grid: GridContainer, text: String, control: Control) -> void:
	grid.add_child(Palette.label(text, 20))
	grid.add_child(control)


func _store(key: String, value: Variant) -> void:
	Settings.data[key] = value
	Settings.apply()
	Settings.save()


func set_language(code: String) -> void:
	_store("language", code)
	_build()
	language_changed.emit()
