class_name MainMenu
extends Control
## Main menu: Play (a submenu with online play, training and the tutorial),
## Collection, Debug Table, Settings, Exit.

signal training
signal collection
signal online
signal tutorial
signal debug_table
signal settings
signal quit

## Button labels (English keys); the translation tool reads this list.
const ITEMS := ["Play", "Online Game", "Training", "Tutorial", "Back", "Collection", "Debug Table", "Settings", "Exit"]

var _box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sound.music("menu")
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var pic := TextureRect.new()  # a quiet tavern behind the menu, slowly drifting closer
	pic.texture = load("res://ui/menu_bg.jpg")
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.modulate = Color(0.78, 0.74, 0.7)
	add_child(pic)
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.05, 0.03, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	add_child(_embers())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var title := TitleLogo.new()
	title.name = "Title"
	box.add_child(title)
	if not Anim.instant:
		pic.pivot_offset = Vector2(640, 360)
		var drift := pic.create_tween().set_loops()
		drift.tween_property(pic, "scale", Vector2(1.07, 1.07), 24.0).set_trans(Tween.TRANS_SINE)
		drift.tween_property(pic, "scale", Vector2.ONE, 24.0).set_trans(Tween.TRANS_SINE)
	_box = box
	show_main()
	var version := Button.new()
	version.name = "Version"
	version.text = "v" + str(ProjectSettings.get_setting("application/config/version"))
	version.flat = true
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.pressed.connect(func(): add_child(ChangelogView.new()))
	add_child(version)


## The first level: Play, Collection, Debug Table, Settings, Exit.
func show_main() -> void:
	var items := [["Play", show_play, true], ["Collection", collection, true], ["Debug Table", debug_table, true], ["Settings", settings, true]]
	if not OS.has_feature("web"):
		items.append(["Exit", quit, true])
	_fill(items)


## The Play submenu: online play, training, the tutorial, and Back.
func show_play() -> void:
	_fill([["Online Game", online, WebRtcTransport.available()], ["Training", training, true], ["Tutorial", tutorial, true], ["Back", show_main, true]])


func _fill(items: Array) -> void:
	for c in _box.get_children():
		if c.name != "Title":
			_box.remove_child(c)
			c.queue_free()
	for it in items:
		var b := Palette.button(tr(it[0]), it[0].replace(" ", ""))
		b.disabled = not it[2]
		if it[0] == "Online Game" and b.disabled:
			b.tooltip_text = tr("Online play works in the browser version of the game")
		if it[1] is Signal:
			var sig: Signal = it[1]
			b.pressed.connect(func(): sig.emit())
		else:
			b.pressed.connect(it[1])
		_box.add_child(b)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size = Vector2(300, 52)
		_animate_button(b, _box.get_child_count() - 2)


## Buttons come in one after another and grow a little under the mouse.
func _animate_button(b: Button, i: int) -> void:
	if Anim.instant:
		return
	b.pivot_offset = Vector2(150, 26)
	b.modulate.a = 0.0
	b.scale = Vector2(0.85, 0.85)
	var tw := b.create_tween().set_parallel()
	tw.tween_property(b, "modulate:a", 1.0, Anim.d(0.3)).set_delay(Anim.d(0.08 * i))
	tw.tween_property(b, "scale", Vector2.ONE, Anim.d(0.35)).set_delay(Anim.d(0.08 * i)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	b.mouse_entered.connect(func(): b.create_tween().tween_property(b, "scale", Vector2(1.06, 1.06), 0.12))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))


## Embers drifting up from the bottom of the screen.
func _embers() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = Vector2(640, 740)
	p.amount = 46
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(680, 10)
	p.direction = Vector2(0, -1)
	p.spread = 18.0
	p.gravity = Vector2(0, -6)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.7, 0.3, 0.9))
	ramp.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
	p.color_ramp = ramp
	p.emitting = not Anim.instant
	return p
