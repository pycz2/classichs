class_name ManaBar
extends Control
## Mana as crystals: full, spent, locked by Overload; the number beside them.

var mana := 0
var max_mana := 0
var locked := 0
## Crystals the card under the mouse would spend: the top ones of the full crystals blink.
var preview := 0
var _t := 0.0


func _init() -> void:
	size = Vector2(270, 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(m: int, mx: int, lock: int) -> void:
	if [m, mx, lock] != [mana, max_mana, locked]:
		mana = m
		max_mana = mx
		locked = lock
		queue_redraw()


func _process(delta: float) -> void:
	if preview > 0:
		_t += delta
		queue_redraw()


func set_preview(n: int) -> void:
	if n != preview:
		preview = n
		_t = 0.0
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var s := "%d/%d" % [mana, max_mana]
	draw_string_outline(font, Vector2(0, 22), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color.BLACK)
	draw_string(font, Vector2(0, 22), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("dbe4ff"))
	for i in 10:
		var c := Vector2(66 + i * 20, 15)
		var pts := PackedVector2Array([c + Vector2(0, -10), c + Vector2(8, 0), c + Vector2(0, 10), c + Vector2(-8, 0)])
		if i >= max_mana:
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.15), 1.5)
			continue
		var full := i < mana
		draw_colored_polygon(pts, Color("1c7ed6") if full else Color("1b2a44"))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color("a5d8ff") if full else Color("364fc7"), 1.5)
		if full:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(3, -1), c + Vector2(0, 1), c + Vector2(-3, -1)]), Color("e7f5ff"))
			if i >= mana - preview:  # would be spent: blinks
				var a := 0.5 + 0.5 * sin(_t * 9.0)
				draw_colored_polygon(pts, Color(1, 1, 1, 0.65 * a))
				draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 0.95, 0.6, a), 2.5)
		if i >= max_mana - locked:
			draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), Color("ff6b6b"), 2)
			draw_line(c + Vector2(5, -5), c + Vector2(-5, 5), Color("ff6b6b"), 2)
