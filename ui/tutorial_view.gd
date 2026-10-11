class_name TutorialView
extends Control
## Tutorial missions as tiles with the boss's portrait: each opens after the previous
## one is won; won missions can be replayed. A mission's intro comes before it starts.

signal start(n: int)
signal back


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
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Palette.label(tr("Tutorial"), 44, Palette.ATTACK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 18)
	box.add_child(grid)
	var done := Progress.completed()
	var next := -1  # the first open mission not won yet
	for n in range(1, Missions.count() + 1):
		if next < 0 and Progress.unlocked(n) and not done.has(n):
			next = n
	for n in range(1, Missions.count() + 1):
		grid.add_child(_tile(n, done.has(n), n == next))
	var bk := Palette.button(tr("Back"), "Back")
	bk.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bk.pressed.connect(func(): back.emit())
	box.add_child(bk)


## Mission n's tile: portrait, number and name, and done / up next / locked.
func _tile(n: int, won: bool, is_next: bool) -> Button:
	var boss: String = Missions.get_mission(n).boss
	var b := Palette.button("", "Mission%d" % n)
	b.custom_minimum_size = Vector2(340, 248)
	var edge := Palette.ATTACK if is_next else Frames.GOLD.darkened(0.4)
	var normal := Palette.box(Palette.PANEL, 14, edge, 4 if is_next else 2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("disabled", normal)
	b.add_theme_stylebox_override("hover", Palette.box(Palette.PANEL.lightened(0.12), 14, Palette.ATTACK, 4))
	b.add_theme_stylebox_override("pressed", Palette.box(Palette.PANEL.lightened(0.2), 14, Palette.ATTACK, 4))
	b.disabled = not Progress.unlocked(n)
	if b.disabled:
		b.modulate = Color(0.5, 0.5, 0.5)
	b.pressed.connect(func():
		if Progress.unlocked(n):
			show_intro(n))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var pic := Control.new()
	pic.name = "Picture"
	pic.custom_minimum_size = Vector2(140, 150)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.draw.connect(func():
		var r := Rect2(Vector2.ZERO, pic.size)
		pic.draw_colored_polygon(Art.outline("arch", r.grow(4)), Frames.GOLD.darkened(0.35))
		Art.paint_in(pic, r, boss, "arch")
		Frames.ring(pic, Art.outline("arch", r), Frames.GOLD, 3))
	col.add_child(pic)
	var name_l := Palette.label("%d. %s" % [n, CardText.name(boss)], 22)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)
	var status := ""
	var status_col := Palette.TEXT
	if won:
		status = tr("done")
		status_col = Palette.BUFFED
	elif is_next:
		status = tr("Up next")
		status_col = Palette.ATTACK
	elif b.disabled:
		status = tr("Locked")
	var s := Palette.label(status, 18, status_col)
	s.name = "Status"
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(s)
	return b


## The intro of mission n over the list; when it is done the mission starts.
func show_intro(n: int) -> TutorialIntro:
	var intro := TutorialIntro.make(n)
	intro.name = "Intro"
	intro.done.connect(func(): start.emit(n))
	intro.back.connect(intro.queue_free)
	add_child(intro)
	return intro
