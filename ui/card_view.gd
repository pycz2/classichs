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
	_name.position = Vector2(6, 84) * k
	_name.size = Vector2(108, 20) * k
	var long_name := CardText.name(card_id).length() > 16 if card_id != "" else false
	_name.add_theme_font_size_override("font_size", int((9 if long_name else 11) * k))
	_text.position = Vector2(8, 106) * k
	_text.size = Vector2(104, 48) * k
	_text.add_theme_font_size_override("font_size", int(10 * k))


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
	_draw_glow(r, int(10 * k))
	if not face_up or card_id == "":
		draw_style_box(Palette.box(Palette.CARD_BACK, int(10 * k), Color("c9a74a"), int(3 * k)), r)
		draw_circle(size / 2, 24 * k, Color("c9a74a", 0.6))
		return
	var c := CardDb.card(card_id)
	var frame := Palette.of_class(c.get("cardClass", "NEUTRAL"))
	draw_style_box(Palette.box(Color("2a2118"), int(10 * k), frame, int(4 * k)), r)
	_draw_art(Rect2(Vector2(10, 12) * k, Vector2(100, 70) * k), card_id)
	draw_style_box(Palette.box(frame.darkened(0.4), int(4 * k)), Rect2(Vector2(4, 84) * k, Vector2(112, 20) * k))
	if Palette.RARITY.has(c.get("rarity", "")):
		draw_circle(Vector2(60, 82) * k, 5 * k, Palette.RARITY[c.rarity])
	var shown_cost := cost if cost >= 0 else int(c.get("cost", 0))
	var cost_color := Color.WHITE if shown_cost == int(c.get("cost", 0)) else (Palette.BUFFED if shown_cost < int(c.get("cost", 0)) else Palette.HEALTH)
	_draw_stat(Vector2(16, 16) * k, shown_cost, Palette.MANA, cost_color, 15 * k)
	if c.type == "MINION" or c.type == "WEAPON":
		var a := attack if attack >= 0 else int(c.get("attack", 0))
		var h := health if health >= 0 else int(c.get("health", c.get("durability", 0)))
		_draw_stat(Vector2(16, 154) * k, a, Palette.ATTACK, Color.BLACK, 15 * k)
		_draw_stat(Vector2(104, 154) * k, h, Palette.HEALTH if c.type == "MINION" else Palette.ARMOR, Color.WHITE, 15 * k)
	if marked:
		draw_line(Vector2(10, 10) * k, size - Vector2(10, 10) * k, Palette.TARGET, 6 * k)
		draw_line(Vector2(size.x - 10 * k, 10 * k), Vector2(10 * k, size.y - 10 * k), Palette.TARGET, 6 * k)
