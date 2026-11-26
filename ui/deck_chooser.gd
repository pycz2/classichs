class_name DeckChooser
extends Control
## A scrollable list of the player's decks of the active game with their heroes' pictures:
## a click on a finished deck picks it at once; unfinished ones are greyed out, and so are Wild decks
## for a Standard game (set_format). With no deck yet it says so and offers to create one (edit_decks).

signal chosen(deck: Deck)
signal edit_decks
signal back

var decks: Array[Deck] = []
var rows: Array[DeckTiles.DeckRow] = []
## The format of the game the deck is for ("standard": no Wild deck; "": any).
var format := ""


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
	decks = DeckStore.load_all()
	if decks.is_empty():
		var none := Palette.label(tr("You have no deck for this game yet: create one first"), 24)
		none.name = "NoDecks"
		grid.add_child(none)
	for i in decks.size():
		var d := decks[i]
		var row := DeckTiles.DeckRow.new(d)
		row.name = "Deck%d" % i
		row.toggle_mode = false
		row.custom_minimum_size = Vector2(0, 64)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.pressed.connect(pick.bind(d))
		grid.add_child(row)
		rows.append(row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	var edit := Palette.button(tr("Create a deck") if decks.is_empty() else tr("Edit decks"), "EditDecks")
	edit.pressed.connect(func(): edit_decks.emit())
	buttons.add_child(edit)
	var bk := Palette.button(tr("Back"), "Back")
	bk.pressed.connect(func(): back.emit())
	buttons.add_child(bk)
	set_format(format)


## The format of the game: a deck that can't be played in it is shown greyed out, with why.
func set_format(f: String) -> void:
	format = f
	for row in rows:
		var why := _why(row.deck)
		row.disabled = why != ""  # shown, but it can't be played (yet)
		row.modulate = Color(0.55, 0.55, 0.55) if why != "" else Color.WHITE
		row.tooltip_text = why


func _why(d: Deck) -> String:
	var why := d.validate()
	if why == "" and format == "standard" and d.wild_only():
		return tr("A Wild deck: it has cards that are not in Standard")
	return why


## Picks a deck; an unfinished one, or a Wild one for a Standard game, is refused.
func pick(d: Deck) -> void:
	if _why(d) == "":
		chosen.emit(d)
