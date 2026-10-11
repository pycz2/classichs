class_name EntityView
extends Control
## Base of everything clickable on the table: knows its entity and draws a glow.

signal clicked(view: EntityView)
signal hovered(view: EntityView, on: bool)

var entity_id := -1
var glow := Color.TRANSPARENT


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): hovered.emit(self, true))
	mouse_exited.connect(func(): hovered.emit(self, false))


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		accept_event()


func set_glow(c: Color) -> void:
	glow = c
	queue_redraw()


func _draw_glow(rect: Rect2, radius: int) -> void:
	if glow.a > 0.0:
		draw_style_box(Palette.box(Color.TRANSPARENT, radius, glow, 4), rect.grow(4))


## A number in a coloured circle (cost, attack, health).
func _draw_stat(center: Vector2, value: int, color: Color, text_color := Color.WHITE, r := 15.0) -> void:
	draw_circle(center, r + 2, Color.BLACK)
	draw_circle(center, r, color)
	var font := ThemeDB.fallback_font
	var size := int(r * 1.3)
	var s := str(value)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string_outline(font, center + Vector2(-w / 2, size * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color.BLACK)
	draw_string(font, center + Vector2(-w / 2, size * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, text_color)


## Card art (procedural, see Art).
func _draw_art(rect: Rect2, card_id: String) -> void:
	Art.paint(self, rect, card_id)
