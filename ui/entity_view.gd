class_name EntityView
extends Control
## Base of everything clickable on the table: knows its entity and draws a glow.

signal clicked(view: EntityView)
signal hovered(view: EntityView, on: bool)
signal right_clicked(view: EntityView)

var entity_id := -1
var glow := Color.TRANSPARENT
var _pops := {}  # a number that just changed ("atk", "hp", "armor", "cost") -> 1.0 down to 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): hovered.emit(self, true))
	mouse_exited.connect(func(): hovered.emit(self, false))


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		accept_event()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit(self)
		accept_event()


func set_glow(c: Color) -> void:
	glow = c
	queue_redraw()


func _draw_glow(rect: Rect2, radius: int) -> void:
	if glow.a > 0.0:
		soft_glow(self, func(g: float) -> PackedVector2Array: return PackedVector2Array(), glow, rect, radius)


## A soft light around a shape, not a line: layers of the shape grown wider and
## fainter, gently pulsing. shape(grow) gives the outline grown by grow pixels;
## with a rect, rounded rects are drawn instead.
static func soft_glow(ci: CanvasItem, shape: Callable, col: Color, rect := Rect2(), radius := 0) -> void:
	var pulse := 0.8 + 0.2 * sin(Time.get_ticks_msec() / 1000.0 * 3.0)
	for i in range(6, 0, -1):
		var gr := i * 3.0
		var c := Color(col, col.a * 0.17 * pulse)
		if rect.size != Vector2.ZERO:
			ci.draw_style_box(Palette.box(c, radius + int(gr)), rect.grow(gr))
		else:
			ci.draw_colored_polygon(shape.call(gr), c)


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


## A number that changed grows for a moment, with its gem, and settles back.
func pop(stat: String) -> void:
	if Anim.d(0.5) > 0.0:
		_pops[stat] = 1.0
		queue_redraw()


## How big a number draws now (1.0 when it is not popping).
func bump(stat: String) -> float:
	var p: float = _pops.get(stat, 0.0)
	return 1.0 + 0.55 * sin(PI * (1.0 - p)) if p > 0.0 else 1.0


func _process(delta: float) -> void:
	if glow.a > 0.0:
		queue_redraw()  # the glow pulses
	if _pops.is_empty():
		return
	for k in _pops.keys():
		_pops[k] -= delta / maxf(0.01, Anim.d(0.5))
		if _pops[k] <= 0.0:
			_pops.erase(k)
	queue_redraw()
