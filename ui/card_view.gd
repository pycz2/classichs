class_name CardView
extends EntityView
## A card face (or back). Stats can show current values from the game.

const SIZE := Vector2(120, 170)
## Where the name and the text go at scale 1, and their largest font sizes.
const NAME_BOX := Rect2(Vector2(10, 86), Vector2(100, 16))
const TEXT_BOX := Rect2(Vector2(15, 107), Vector2(90, 46))
const NAME_MAX := 12
const TEXT_MAX := 11

var card_id := ""
var face_up := true
var cost := -1
var attack := -1
var health := -1
var marked := false  # mulligan: card will be replaced
var _text: RichTextLabel
var _name: Label


static func make(id: String, scale_factor := 1.0) -> CardView:
	var v := CardView.new()
	v.card_id = id
	v.custom_minimum_size = SIZE * scale_factor
	v.size = SIZE * scale_factor
	return v


## Current cost/attack/health from a hand card or a minion in play.
func show_entity(e: Entity, g: GameState) -> void:
	entity_id = e.id
	card_id = e.card_id
	cost = g.cost(e) if e.zone == "HAND" else int(e.card().get("cost", 0))
	if e.is_minion():
		attack = e.atk()
		health = e.health()
	elif e.is_weapon():
		attack = e.atk()
		health = int(e.tags.get("DURABILITY", 0))
	_refresh_labels()


func _ready() -> void:
	_name = Palette.label("", 11)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_color_override("default_color", Color("3b2a14"))
	for l in [_name, _text]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	_refresh_labels()
	resized.connect(_layout)
	_layout()


## The largest font size (hi down to lo) at which text fits box; -1 if none does.
static func fit_text(font: Font, text: String, box: Vector2, hi: int, lo := 5) -> int:
	for fs in range(hi, lo - 1, -1):
		var sz := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, box.x, fs)
		if sz.y <= box.y * 0.92 and sz.x <= box.x:
			return fs
	return -1


## The largest font size at which a name fits on one line of width w; -1 if none does.
static func fit_name(font: Font, name: String, w: float, hi: int, lo := 6) -> int:
	for fs in range(hi, lo - 1, -1):
		if font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= w:
			return fs
	return -1


func _layout() -> void:
	var k := size.x / SIZE.x
	_name.position = NAME_BOX.position * k
	_name.size = NAME_BOX.size * k
	_text.position = TEXT_BOX.position * k
	_text.size = TEXT_BOX.size * k
	if card_id == "":
		return
	var name_font := _name.get_theme_font("font")
	_name.add_theme_font_size_override("font_size", maxi(1, fit_name(name_font, CardText.name(card_id), NAME_BOX.size.x * k, int(NAME_MAX * k), maxi(1, int(5 * k)))))
	var bold := _text.get_theme_font("bold_font")
	var fs := fit_text(bold, CardText.plain_rich(CardText.rich(card_id)), TEXT_BOX.size * k, int(TEXT_MAX * k), maxi(1, int(4 * k)))
	for key in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		_text.add_theme_font_size_override(key, maxi(1, fs))


func _refresh_labels() -> void:
	if _name == null:
		return
	_name.visible = face_up
	_text.visible = face_up
	if face_up and card_id != "":
		_name.text = CardText.name(card_id)
		_text.text = "[center]%s[/center]" % CardText.rich(card_id)
		_layout()
	queue_redraw()


func _draw() -> void:
	var k := size.x / SIZE.x
	var r := Rect2(Vector2.ZERO, size)
	_draw_glow(r, int(12 * k))
	if not face_up or card_id == "":
		DeckPile.draw_back(self, r)
		return
	var c := CardDb.card(card_id)
	var type: String = c.get("type", "MINION")
	var frame := Palette.of_class(c.get("cardClass", "NEUTRAL"))
	draw_style_box(Palette.box(frame.darkened(0.25), int(12 * k), Frames.GOLD.darkened(0.2), int(3 * k)), r)
	draw_style_box(Palette.box(frame.darkened(0.55), int(8 * k)), r.grow(-6 * k))
	var shape: String = {"MINION": "oval", "WEAPON": "circle", "SPELL": "arch", "HERO_POWER": "circle", "HERO": "arch"}.get(type, "arch")
	var art := {"oval": Rect2(Vector2(22, 8), Vector2(76, 84)), "circle": Rect2(Vector2(25, 10), Vector2(70, 70)),
		"arch": Rect2(Vector2(14, 10), Vector2(92, 76))}[shape] as Rect2
	art = Rect2(art.position * k, art.size * k)
	var outline := Art.outline(shape, art)
	draw_colored_polygon(Art.outline(shape, art.grow(3 * k)), Frames.GOLD.darkened(0.35))
	Art.paint_in(self, art, card_id, shape)
	Frames.ring(self, outline, Frames.GOLD.darkened(0.1), 2 * k)
	if c.get("rarity", "") == "LEGENDARY":
		Frames.crest(self, Vector2(60, 5) * k, 104 * k)  # along the card's top edge
	# text box (parchment) and the name banner across it
	draw_style_box(Palette.box(Color("efe0bd"), int(6 * k), Color("8a6d3b"), int(2 * k)), Rect2(Vector2(12, 100) * k, Vector2(96, 56) * k))
	var bend := 4.0 * k if type == "MINION" else 0.0
	var banner := PackedVector2Array([Vector2(4, 86) * k, Vector2(60 * k, 86 * k - bend), Vector2(116, 86) * k, Vector2(116, 102) * k, Vector2(60 * k, 102 * k - bend), Vector2(4, 102) * k])
	draw_colored_polygon(banner, frame.darkened(0.15))
	Frames.ring(self, banner, Color("2a2118"), 1.5 * k)
	Frames.rarity(self, Vector2(60, 106) * k, c.get("rarity", ""), 5 * k)
	var base_cost := int(c.get("cost", 0))
	var shown_cost := cost if cost >= 0 else base_cost
	var cost_color := Color.WHITE if shown_cost == base_cost else (Frames.BUFFED if shown_cost < base_cost else Frames.DAMAGED)
	Frames.mana(self, Vector2(17, 17) * k, shown_cost, 15 * k, cost_color)
	if type == "MINION" or type == "WEAPON":
		var a := attack if attack >= 0 else int(c.get("attack", 0))
		var h := health if health >= 0 else int(c.get("health", c.get("durability", 0)))
		Frames.attack(self, Vector2(17, 154) * k, a, 15 * k)
		if type == "MINION":
			Frames.health(self, Vector2(103, 154) * k, h, 15 * k)
		else:
			Frames.shield(self, Vector2(103, 154) * k, h, 14 * k)
	if marked:
		draw_line(Vector2(10, 10) * k, size - Vector2(10, 10) * k, Palette.TARGET, 6 * k)
		draw_line(Vector2(size.x - 10 * k, 10 * k), Vector2(10 * k, size.y - 10 * k), Palette.TARGET, 6 * k)
