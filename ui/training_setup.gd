class_name TrainingSetup
extends Control
## Training in two steps: pick your deck, then the bot's hero.

signal start(my_deck: Deck, bot_class: String)
signal back
signal edit_decks

const ORDER := ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"]

var deck: Deck
var bot_class := "WARRIOR"
var step := 1
var chooser := DeckChooser.new()
var tiles: Array[HeroTile] = []
var _step1 := Control.new()
var _step2 := Control.new()
var _deck_line: Label


## The player's saved decks, then the ready decks (DeckStore.starter) not among them.
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
	Palette.backdrop(self, "library_bg")
	for s in [_step1, _step2]:
		s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(s)
	_step1.name = "Step1"
	_step2.name = "Step2"
	# step 1: the deck
	_title(_step1, tr("Training"), tr("Choose your deck"))
	chooser.name = "DeckChooser"
	chooser.position = Vector2(140, 130)
	chooser.size = Vector2(1000, 560)
	chooser.chosen.connect(choose_deck)
	chooser.edit_decks.connect(func(): edit_decks.emit())
	chooser.back.connect(func(): back.emit())
	_step1.add_child(chooser)
	# step 2: the opponent
	_deck_line = _title(_step2, tr("Choose your opponent"), "")
	var grid := GridContainer.new()
	grid.name = "Opponents"
	grid.columns = 3
	grid.position = Vector2(140, 130)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 14)
	_step2.add_child(grid)
	var group := ButtonGroup.new()
	for cls in ORDER:
		var t := HeroTile.new(cls)
		t.button_group = group
		t.button_pressed = cls == bot_class
		t.toggled.connect(func(on):
			if on:
				bot_class = cls)
		t.gui_input.connect(func(ev):  # a double click starts the game
			if ev is InputEventMouseButton and ev.double_click:
				bot_class = cls
				play())
		grid.add_child(t)
		tiles.append(t)
	var row := HBoxContainer.new()
	row.position = Vector2(140, 642)
	row.add_theme_constant_override("separation", 16)
	_step2.add_child(row)
	var go := Palette.button(tr("Play"), "Play")
	go.pressed.connect(play)
	row.add_child(go)
	var bk := Palette.button(tr("Back"), "Back")
	bk.pressed.connect(show_step.bind(1))
	row.add_child(bk)
	show_step(1)


## A big title and a smaller line under it; returns the smaller line.
func _title(parent: Control, text: String, sub: String) -> Label:
	var t := Palette.label(text, 40, Palette.ATTACK)
	t.position = Vector2(140, 24)
	parent.add_child(t)
	var s := Palette.label(sub, 22)
	s.position = Vector2(142, 80)
	parent.add_child(s)
	return s


func show_step(n: int) -> void:
	step = n
	_step1.visible = n == 1
	_step2.visible = n == 2


func choose_deck(d: Deck) -> void:
	deck = d
	_deck_line.text = tr("Your deck: %s") % d.name
	show_step(2)


func play() -> void:
	if deck:
		start.emit(deck, bot_class)


## One of the nine opponents: the hero's portrait, name and class emblem.
class HeroTile:
	extends Button
	var cls := ""

	func _init(p_cls: String) -> void:
		cls = p_cls
		name = "bot_" + cls
		toggle_mode = true
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(322, 150)
		tooltip_text = CardText.name(Decks.hero(cls))
		var icon := IconView.new()
		icon.kind = cls
		icon.size = Vector2(48, 48)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
		resized.connect(func(): icon.position = Vector2(size.x - 60, 12))

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		draw_style_box(Palette.box(Palette.of_class(cls).darkened(0.5), 12), r)
		DeckTiles.strip(self, r.grow(-4), Decks.hero(cls), 0.35)
		DeckTiles.text(self, Vector2(16, size.y - 18), CardText.name(Decks.hero(cls)), 24)
		var edge := Palette.SELECTED if button_pressed else (Color("c9a74a", 0.6) if is_hovered() else Palette.of_class(cls).darkened(0.2))
		draw_style_box(Palette.box(Color(0, 0, 0, 0), 12, edge, 5 if button_pressed else 3), r)
