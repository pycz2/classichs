class_name LanguagePicker
extends Control
## The first run: the player picks the game's language from big buttons, each in
## its own language; the one matching the system is lit.

signal chosen(code: String)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	var title := Palette.label("Language · Язык · Sprache · Langue · Idioma · Lingua · Język", 30, Palette.ATTACK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(grid)
	var guess := Locale.pick(OS.get_locale())
	for code in Locale.LANGS:
		var b := Palette.button(Locale.LANGS[code], "Lang_" + code)
		b.custom_minimum_size = Vector2(320, 58)
		b.add_theme_font_size_override("font_size", 24)
		if code == guess:
			b.modulate = Color(1.25, 1.2, 0.9)  # the system's language
		var c: String = code
		b.pressed.connect(func(): chosen.emit(c))
		grid.add_child(b)
