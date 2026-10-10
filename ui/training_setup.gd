class_name TrainingSetup
extends Control
## Pick your class and the bot's class.

signal start(my_class: String, bot_class: String)
signal back

const ORDER := ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"]

var my_class := "MAGE"
var bot_class := "WARRIOR"
var _groups := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := VBoxContainer.new()
	box.position = Vector2(140, 60)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	box.add_child(Palette.label(tr("Training"), 40, Palette.ATTACK))
	for side in ["you", "bot"]:
		box.add_child(Palette.label(tr("Your class") if side == "you" else tr("Opponent class"), 24))
		var grid := GridContainer.new()
		grid.columns = 5
		var group := ButtonGroup.new()
		_groups[side] = group
		for cls in ORDER:
			var b := Button.new()
			b.toggle_mode = true
			b.button_group = group
			b.name = side + "_" + cls
			b.text = CardText.name(Decks.hero(cls))
			b.custom_minimum_size = Vector2(190, 44)
			b.add_theme_stylebox_override("normal", Palette.box(Palette.of_class(cls).darkened(0.3)))
			b.add_theme_stylebox_override("pressed", Palette.box(Palette.of_class(cls), 8, Palette.SELECTED, 3))
			b.button_pressed = cls == (my_class if side == "you" else bot_class)
			b.toggled.connect(func(on):
				if on:
					if side == "you":
						my_class = cls
					else:
						bot_class = cls)
			grid.add_child(b)
		box.add_child(grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var go := Palette.button(tr("Play"), "Play")
	go.pressed.connect(func(): start.emit(my_class, bot_class))
	var bk := Palette.button(tr("Back"), "Back")
	bk.pressed.connect(func(): back.emit())
	row.add_child(go)
	row.add_child(bk)
	box.add_child(row)
