class_name CardView
extends EntityView
## A card face (or back). Stats can show current values from the game.

const SIZE := Vector2(120, 170)

var card_id := ""
var face_up := true
var cost := -1
var attack := -1
var health := -1
var marked := false  # mulligan: card will be replaced
var _text: Label
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
	_text = Palette.label("", 10)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_constant_override("outline_size", 3)
	for l in [_name, _text]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	_refresh_labels()
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var k := size.x / SIZE.x
	_name.position = Vector2(8, 84) * k
	_name.size = Vector2(104, 18) * k
	var long_name := CardText.name(card_id).length() > 16 if card_id != "" else false
	_name.add_theme_font_size_override("font_size", int((9 if long_name else 11) * k))
	_text.position = Vector2(14, 107) * k
	_text.size = Vector2(92, 46) * k
	var n := CardText.text(card_id).length() if card_id != "" else 0
	_text.add_theme_font_size_override("font_size", int((10 if n <= 70 else 9 if n <= 90 else 8) * k))  # long texts fit the frame
	_text.add_theme_color_override("font_color", Color("3b2a14"))
	_text.add_theme_constant_override("outline_size", 0)


func _refresh_labels() -> void:
	if _name == null:
		return
	_name.visible = face_up
	_text.visible = face_up
	if face_up and card_id != "":
		_name.text = CardText.name(card_id)
		_text.text = CardText.text(card_id)
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
		Frames.crest(self, Vector2(60, 12) * k, 104 * k)
	# text box (parchment) and the name banner across it
	draw_style_box(Palette.box(Color("efe0bd"), int(6 * k), Color("8a6d3b"), int(2 * k)), Rect2(Vector2(12, 100) * k, Vector2(96, 56) * k))
	var bend := 4.0 * k if type == "MINION" else 0.0
	var banner := PackedVector2Array([Vector2(4, 86) * k, Vector2(60 * k, 86 * k - bend), Vector2(116, 86) * k, Vector2(116, 102) * k, Vector2(60 * k, 102 * k - bend), Vector2(4, 102) * k])
	draw_colored_polygon(banner, frame.darkened(0.15))
	Frames.ring(self, banner, Color("2a2118"), 1.5 * k)
	Frames.rarity(self, Vector2(60, 106) * k, c.get("rarity", ""), 5 * k)
	var base_cost := int(c.get("cost", 0))
	var shown_cost := cost if cost >= 0 else base_cost
	var cost_color := Color.WHITE if shown_cost == base_cost else (Color("8ce99a") if shown_cost < base_cost else Color("ff8787"))
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
