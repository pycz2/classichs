class_name ManaBar
extends Control
## Mana as crystals: full, spent, locked by Overload; the number beside them, all on a dark backing
## of its own (the own one stands in front of the hand: a card fanned over it never hides the number).

var mana := 0
var max_mana := 0
var locked := 0
## Overload owed: crystals locked next turn (shown as soon as the card is played).
var owed := 0
## Crystals the card under the mouse would spend: the top ones of the full crystals blink.
var preview := 0
var _t := 0.0
const LEFT := 64.0  # the first crystal's middle
const STEP := 18.0  # between the crystals


func _init() -> void:
	size = Vector2(LEFT + STEP * 9 + 14, 30)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(m: int, mx: int, lock: int, next_lock := 0) -> void:
	if [m, mx, lock, next_lock] != [mana, max_mana, locked, owed]:
		mana = m
		max_mana = mx
		locked = lock
		owed = next_lock
		queue_redraw()


func _process(delta: float) -> void:
	if preview > 0 or owed > 0:
		_t += delta
		queue_redraw()


func set_preview(n: int) -> void:
	if n != preview:
		preview = n
		_t = 0.0
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_style_box(Palette.box(Color(0.07, 0.05, 0.035, 0.88), 13, Color("a8863a"), 2), Rect2(-8, 2, size.x + 8, 26))
	var s := "%d/%d" % [mana, max_mana]
	draw_string_outline(font, Vector2(0, 22), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color.BLACK)
	draw_string(font, Vector2(0, 22), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("dbe4ff"))
	var col := crystal_colors()
	for i in 10:
		var c := Vector2(LEFT + i * STEP, 15)
		var pts := PackedVector2Array([c + Vector2(0, -8), c + Vector2(7, 0), c + Vector2(0, 8), c + Vector2(-7, 0)])
		if i >= max_mana:
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.15), 1.5)
			continue
		var full := i < mana
		if full and i >= mana - preview:  # would be spent: a bright crystal that pulses in size and glows
			var a := 0.5 + 0.5 * sin(_t * 8.0)
			var k := 1.15 + 0.25 * a
			var big := PackedVector2Array([c + Vector2(0, -8) * k, c + Vector2(7, 0) * k, c + Vector2(0, 8) * k, c + Vector2(-7, 0) * k])
			for gi in range(4, 0, -1):
				var gk := k + gi * 0.18
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8) * gk, c + Vector2(7, 0) * gk, c + Vector2(0, 8) * gk, c + Vector2(-7, 0) * gk]), Color(1, 0.85, 0.3, 0.12 + 0.1 * a))
			draw_colored_polygon(big, Color("ffd43b").lerp(Color.WHITE, 0.4 * a))
			draw_polyline(big + PackedVector2Array([big[0]]), Color("fff3bf"), 2.0)
			continue
		draw_colored_polygon(pts, col[0] if full else col[2])
		draw_polyline(pts + PackedVector2Array([pts[0]]), col[1] if full else col[3], 1.5)
		if full:
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6), c + Vector2(3, -1), c + Vector2(0, 1), c + Vector2(-3, -1)]), col[4])
		if i >= max_mana - locked:  # locked by Overload this turn: a padlock on the crystal
			draw_colored_polygon(pts, Color(0.05, 0.05, 0.08, 0.55))
			_lock(c + Vector2(0, 1), 1.0, Color("ced4da"))
	var next_max := mini(10, max_mana + 1)
	for i in range(maxi(0, next_max - owed), next_max):  # locked next turn: small orange padlocks above
		_lock(Vector2(LEFT + i * STEP, 15) + Vector2(0, -15 + 1.5 * sin(_t * 4.0 + i)), 0.8, Color("ff922b"))


## A crystal's colours: full, its edge, empty, its edge, the shine (the theme's "mana" colour, or Classic's blue).
static func crystal_colors() -> Array:
	var m := Palette.tc("mana")
	if m.a == 0.0:
		return [Color("1c7ed6"), Color("a5d8ff"), Color("1b2a44"), Color("364fc7"), Color("e7f5ff")]
	return [m, m.lerp(Color.WHITE, 0.6), m.darkened(0.75), m.darkened(0.25), m.lerp(Color.WHITE, 0.85)]


## A small padlock: a shackle and a body with a keyhole.
func _lock(c: Vector2, k: float, col: Color) -> void:
	draw_arc(c + Vector2(0, -2.5) * k, 3.2 * k, PI, TAU, 12, Color(0, 0, 0, 0.8), 3.2 * k, true)
	draw_arc(c + Vector2(0, -2.5) * k, 3.2 * k, PI, TAU, 12, col, 1.8 * k, true)
	var body := Rect2(c + Vector2(-5, -2.5) * k, Vector2(10, 8) * k)
	draw_rect(body.grow(1.2 * k), Color(0, 0, 0, 0.8))
	draw_rect(body, col)
	draw_circle(c + Vector2(0, 1) * k, 1.3 * k, Color(0, 0, 0, 0.8))
