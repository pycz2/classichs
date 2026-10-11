class_name DeckChooser
extends Control
## A scrollable list of the player's decks with their heroes' pictures:
## a click on a finished deck picks it at once; unfinished ones are greyed out.

signal chosen(deck: Deck)
signal edit_decks
signal back

var decks: Array[Deck] = []
var rows: Array[DeckTiles.DeckRow] = []


func _ready() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 16)
	add_child(box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Decks"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	decks = TrainingSetup.available_decks()
	for i in decks.size():
		var d := decks[i]
		var row := DeckTiles.DeckRow.new(d)
		row.name = "Deck%d" % i
		row.toggle_mode = false
		row.custom_minimum_size = Vector2(0, 64)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var why := d.validate()
		if why != "":  # shown, but it can't be played yet
			row.disabled = true
			row.modulate = Color(0.55, 0.55, 0.55)
			row.tooltip_text = why
		row.pressed.connect(pick.bind(d))
		grid.add_child(row)
		rows.append(row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	var edit := Palette.button(tr("Edit decks"), "EditDecks")
	edit.pressed.connect(func(): edit_decks.emit())
	buttons.add_child(edit)
	var bk := Palette.button(tr("Back"), "Back")
	bk.pressed.connect(func(): back.emit())
	buttons.add_child(bk)


## Picks a deck; an unfinished one is refused.
func pick(d: Deck) -> void:
	if d.validate() == "":
		chosen.emit(d)
