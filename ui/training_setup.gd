class_name TrainingSetup
extends Control
## Pick your deck (saved decks and the basic deck of each class) and the bot's class.

signal start(my_deck: Deck, bot_class: String)
signal back

const ORDER := ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"]

var bot_class := "WARRIOR"
var deck_picker := OptionButton.new()
var error: Label
var _decks: Array[Deck] = []


## Basic decks for all classes, then the player's saved decks.
static func available_decks() -> Array[Deck]:
	var out := DeckStore.load_all()
	var have := out.map(func(d: Deck): return [d.hero, d.sorted_counts()])
	for d in DeckStore.starter():
		if not have.has([d.hero, d.sorted_counts()]):
			out.append(d)
	return out


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self)
	var box := VBoxContainer.new()
	box.position = Vector2(140, 60)
	box.add_theme_constant_override("separation", 14)
	add_child(box)
	box.add_child(Palette.label(tr("Training"), 40, Palette.ATTACK))
	box.add_child(Palette.label(tr("Your deck"), 24))
	deck_picker.name = "DeckPicker"
	deck_picker.custom_minimum_size = Vector2(600, 40)
	_decks = available_decks()
	for d in _decks:
		var state := "" if d.validate() == "" else "  (%d/30)" % d.cards.size()
		deck_picker.add_item(d.name + state)
	deck_picker.selected = 2  # basic Mage deck
	box.add_child(deck_picker)
	box.add_child(Palette.label(tr("Opponent class"), 24))
	var grid := GridContainer.new()
	grid.columns = 5
	var group := ButtonGroup.new()
	for cls in ORDER:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.name = "bot_" + cls
		b.text = CardText.name(Decks.hero(cls))
		b.custom_minimum_size = Vector2(190, 44)
		for st in [["normal", Palette.box(Palette.of_class(cls).darkened(0.3))], ["pressed", Palette.box(Palette.of_class(cls), 8, Palette.SELECTED, 3)]]:
			st[1].content_margin_left = 44
			b.add_theme_stylebox_override(st[0], st[1])
		Icons.attach(b, cls, 32)
		b.button_pressed = cls == bot_class
		b.toggled.connect(func(on):
			if on:
				bot_class = cls)
		grid.add_child(b)
	box.add_child(grid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var go := Palette.button(tr("Play"), "Play")
	go.pressed.connect(play)
	var bk := Palette.button(tr("Back"), "Back")
	bk.pressed.connect(func(): back.emit())
	row.add_child(go)
	row.add_child(bk)
	box.add_child(row)
	error = Palette.label("", 18, Palette.TARGET)
	error.name = "Error"
	box.add_child(error)


func select_deck(i: int) -> void:
	deck_picker.selected = i


func play() -> void:
	var d: Deck = _decks[deck_picker.selected]
	var why := d.validate()
	if why != "":
		error.text = why
		return
	start.emit(d, bot_class)
