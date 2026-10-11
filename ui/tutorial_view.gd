class_name TutorialView
extends Control
## Tutorial missions: each opens after the previous one is won; won missions can be replayed.

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
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var title := Palette.label(tr("Tutorial"), 44, Palette.ATTACK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var done := Progress.completed()
	for n in range(1, Missions.count() + 1):
		var m := Missions.get_mission(n)
		var b := Palette.button("%d. %s%s" % [n, CardText.name(m.boss), "  — " + tr("done") if done.has(n) else ""], "Mission%d" % n)
		b.custom_minimum_size = Vector2(420, 50)
		b.disabled = not Progress.unlocked(n)
		var num: int = n
		b.pressed.connect(func(): start.emit(num))
		box.add_child(b)
	var bk := Palette.button(tr("Back"), "Back")
	bk.custom_minimum_size = Vector2(420, 50)
	bk.pressed.connect(func(): back.emit())
	box.add_child(bk)
