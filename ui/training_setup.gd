class_name TrainingSetup
extends Control
## Training in three steps: pick your deck (of the active game; none yet: create one first; a game with
## Standard and Wild: in which of them), then the bot's hero, then how well it plays (Settings bot_level): a list
## from easy to hard, each level with a picture of its strength. Back and Next go between the steps.

signal start(my_deck: Deck, bot_class: String)
signal back
signal edit_decks

var deck: Deck
var bot_class := "WARRIOR"
## The game's format ("standard", "wild"; "" for a game with one format: CardDb.formats()); the last one chosen
## (Settings training_format) when the game has it.
var format := ""
var step := 1
var chooser := DeckChooser.new()
var tiles: Array[HeroTile] = []
var _step1 := Control.new()
var _step2 := Control.new()
var _step3 := Control.new()
var _deck_line: Label
var _opponent_line: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self, "library")
	for s in [_step1, _step2, _step3]:
		s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(s)
	_step1.name = "Step1"
	_step2.name = "Step2"
	_step3.name = "Step3"
	# step 1: the deck
	_title(_step1, tr("Training"), tr("Choose your deck"))
	chooser.name = "DeckChooser"
	chooser.position = Vector2(140, 130)
	chooser.size = Vector2(1000, 560)
	chooser.chosen.connect(choose_deck)
	chooser.edit_decks.connect(func(): edit_decks.emit())
	chooser.back.connect(func(): back.emit())
	_step1.add_child(chooser)
	var formats := CardDb.formats()
	var last := str(Settings.data.get("training_format", ""))
	format = last if formats.has(last) else (formats[0] if formats else "")
	chooser.set_format(format)
	if formats.size() > 1:  # Standard or Wild
		var row := HBoxContainer.new()
		row.name = "Formats"
		row.position = Vector2(860, 70)
		row.add_theme_constant_override("separation", 10)
		_step1.add_child(row)
		var fg := ButtonGroup.new()
		for f in formats:
			var b := Palette.button({"standard": tr("Standard"), "wild": tr("Wild")}[f], "Format_" + f)
			b.toggle_mode = true
			b.button_group = fg
			b.button_pressed = f == format
			b.toggled.connect(func(on):
				if on:
					format = f
					chooser.set_format(f)
					Settings.data.training_format = f
					Settings.save())
			row.add_child(b)
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
	if not Decks.classes().has(bot_class):
		bot_class = Decks.classes()[-1]
	for cls in Decks.classes():
		var t := HeroTile.new(cls)
		t.button_group = group
		t.button_pressed = cls == bot_class
		t.toggled.connect(func(on):
			if on:
				bot_class = cls)
		t.gui_input.connect(func(ev):  # a double click goes on
			if ev is InputEventMouseButton and ev.double_click:
				bot_class = cls
				show_step(3))
		grid.add_child(t)
		tiles.append(t)
	_nav(_step2, ["Next", tr("Next"), show_step.bind(3)], show_step.bind(1))
	# step 3: how well the bot plays (BotBrain; it sees only its own cards), from easy to hard
	_opponent_line = _title(_step3, tr("Bot difficulty"), "")
	var levels := VBoxContainer.new()
	levels.name = "Levels"
	levels.position = Vector2(140, 130)
	levels.add_theme_constant_override("separation", 12)
	_step3.add_child(levels)
	var lg := ButtonGroup.new()
	var room := ImageTexture.create_from_image(Image.create(LevelPicture.SIZE.x, LevelPicture.SIZE.y, false, Image.FORMAT_RGBA8))
	for i in BotBrain.LEVELS.size():
		var lvl: String = BotBrain.LEVELS[i]
		var b := Palette.button({"easy": tr("Easy"), "medium": tr("Medium"), "hard": tr("Hard"), "superhard": tr("Super hard")}[lvl], "Level_" + lvl)
		b.custom_minimum_size = Vector2(620, 108)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 30)
		b.icon = room  # (an empty icon: the picture is drawn over it)
		b.add_theme_constant_override("h_separation", 22)
		b.toggle_mode = true
		b.button_group = lg
		b.button_pressed = Settings.data.get("bot_level", "medium") == lvl
		b.toggled.connect(func(on):
			if on:
				Settings.data.bot_level = lvl
				Settings.save()
			_mark_levels(levels))
		b.gui_input.connect(func(ev):  # a double click starts the game
			if ev is InputEventMouseButton and ev.double_click:
				play())
		var pic := LevelPicture.new()
		pic.name = "Picture"
		pic.level = i
		pic.position = Vector2(14, (108 - LevelPicture.SIZE.y) / 2.0)
		b.add_child(pic)
		levels.add_child(b)
	_mark_levels(levels)
	_nav(_step3, ["Play", tr("Play"), play], show_step.bind(2))
	show_step(1)


## A step's buttons at the bottom: forward ([its id, text, action]), then Back.
func _nav(parent: Control, forward: Array, back_fn: Callable) -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(140, 642)
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var go := Palette.button(forward[1], forward[0])
	go.pressed.connect(forward[2])
	row.add_child(go)
	var bk := Palette.button(tr("Back"), "Back")
	bk.pressed.connect(back_fn)
	row.add_child(bk)


## A big title and a smaller line under it; returns the smaller line.
func _title(parent: Control, text: String, sub: String) -> Label:
	var t := Palette.label(text, 40, Palette.ATTACK)
	t.position = Vector2(140, 24)
	parent.add_child(t)
	var s := Palette.label(sub, 22)
	s.position = Vector2(142, 80)
	parent.add_child(s)
	return s


## The chosen level stands out: bright with gold letters; the others dimmed.
static func _mark_levels(row: Control) -> void:
	for b in row.get_children():
		if b is Button:
			b.modulate = Color.WHITE if b.button_pressed else Color(0.62, 0.62, 0.62)
			if b.button_pressed:
				b.add_theme_color_override("font_color", Palette.ATTACK)
			else:
				b.remove_theme_color_override("font_color")


func show_step(n: int) -> void:
	step = n
	_step1.visible = n == 1
	_step2.visible = n == 2
	_step3.visible = n == 3
	_opponent_line.text = tr("Opponent: %s") % CardText.name(Decks.hero(bot_class))


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


## A level's strength, drawn: a medallion in the level's colour (green to red) with one to four
## swords fanned out in it, and four marks under it, as many lit as the level is strong.
class LevelPicture:
	extends Control
	const SIZE := Vector2i(96, 94)
	const COLORS := [Color("4caf50"), Color("e0b020"), Color("e8701c"), Color("d22a2a")]
	var level := 0  # 0 easy … 3 super hard

	func _ready() -> void:
		size = SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(SIZE.x / 2.0, 38)
		var col: Color = COLORS[level]
		draw_circle(c, 38, Color(0, 0, 0, 0.55), true, -1.0, true)
		draw_circle(c, 35, col.darkened(0.5), true, -1.0, true)
		draw_circle(c, 29, col.darkened(0.2), false, 2.0, true)
		draw_circle(c, 35, Color("e8cc78"), false, 3.0, true)
		var n := level + 1
		for k in n:
			_sword(c + Vector2(0, 20), 0.0 if n == 1 else lerpf(-0.75, 0.75, k / float(n - 1)))
		for k in 4:  # the strength meter
			var r := Rect2(Vector2(SIZE.x / 2.0 - 35 + k * 18, 84), Vector2(16, 9))
			draw_rect(r, col if k <= level else Color(0, 0, 0, 0.55))
			draw_rect(r, Color(0, 0, 0, 0.85), false, 1.0)

	## A sword standing on its grip at `at`, leaning by angle a.
	func _sword(at: Vector2, a: float) -> void:
		draw_set_transform(at, a)
		var blade := PackedVector2Array([Vector2(-3.5, -7), Vector2(-3.5, -40), Vector2(0, -47), Vector2(3.5, -40), Vector2(3.5, -7)])
		draw_colored_polygon(blade, Color("e6edf3"))
		blade.append(blade[0])
		draw_polyline(blade, Color(0.1, 0.1, 0.12), 1.2, true)
		draw_line(Vector2(0, -9), Vector2(0, -38), Color("9aa6b2"), 1.0, true)
		draw_rect(Rect2(Vector2(-10, -8), Vector2(20, 4)), Color("d9b44a"))
		draw_rect(Rect2(Vector2(-10, -8), Vector2(20, 4)), Color(0.1, 0.06, 0.02), false, 1.0)
		draw_rect(Rect2(Vector2(-2, -4), Vector2(4, 9)), Color("6b3f12"))
		draw_circle(Vector2(0, 6.5), 3.0, Color("d9b44a"), true, -1.0, true)
		draw_set_transform(Vector2.ZERO, 0.0)
