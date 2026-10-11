class_name SettingsView
extends Control
## Settings: language, volumes, speech, screen shake, fullscreen, player name.
## Every change is applied and saved at once. Works as a screen and as an overlay.

signal back
## The language changed; the owner relabels its own texts.
signal language_changed
## The picture set changed; the owner redraws its cards.
signal art_changed

## Row labels (English keys); the translation tool reads these lists.
const SLIDERS := [["Music", "music"], ["Sounds", "sfx"], ["Voice", "voice"]]
const TOGGLES := [["Speech", "Tts", "tts"], ["Screen shake", "Shake", "shake"], ["Fullscreen", "Fullscreen", "fullscreen"]]


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

	var art := OptionButton.new()
	art.name = "ArtSet"
	var sets := Art.sets()
	for name in sets:
		art.add_item({"generated": tr("Generated"), "original": tr("Original")}.get(name, name.capitalize()))
	art.select(maxi(0, sets.find(Settings.data.art)))
	art.item_selected.connect(func(i):
		_store("art", sets[i])
		Art.reset()
		art_changed.emit())
	_row(grid, tr("Card art"), art)

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
			_store(key, on))
		_row(grid, tr(t[0]), cb)

	var ed := LineEdit.new()
	ed.name = "Name"
	ed.text = Profile.load_name()
	ed.max_length = Profile.NAME_MAX
	ed.custom_minimum_size = Vector2(300, 36)
	ed.text_changed.connect(Profile.save_name)
	_row(grid, tr("Your name"), ed)

	var b := Palette.button(tr("Back"), "Back")
	b.pressed.connect(func(): back.emit())
	box.add_child(b)


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
