class_name MainMenu
extends Control
## Main menu. Online play, tutorial and collection come with later subprojects.

signal training
signal debug_table
signal quit


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	var title := Palette.label("Classic HS", 56, Palette.ATTACK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var items := [["Training", training, true], ["Online Game", null, false], ["Tutorial", null, false],
		["Collection", null, false], ["Debug Table", debug_table, true]]
	if not OS.has_feature("web"):
		items.append(["Exit", quit, true])
	for it in items:
		var b := Palette.button(tr(it[0]), it[0].replace(" ", ""))
		b.disabled = not it[2]
		if it[1] != null:
			var sig: Signal = it[1]
			b.pressed.connect(func(): sig.emit())
		box.add_child(b)
	box.position = -box.get_combined_minimum_size() / 2
