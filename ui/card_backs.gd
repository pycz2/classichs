class_name CardBacks
extends RefCounted
## Card backs, drawn in code so they scale to any card size (deck piles, the
## opponent's hand, cards turning over). The player picks one in the settings.

const NAMES := ["classic", "horde", "druid", "arcane", "gold", "night"]
const LABELS := {"classic": "Classic", "horde": "Horde", "druid": "Druid", "arcane": "Arcane", "gold": "Gold", "night": "Night"}


## Draws the back named in the settings (or the given one) into r.
static func draw(ci: CanvasItem, r: Rect2, back := "") -> void:
	if back == "":
		back = Settings.data.get("card_back", "classic")
	var k := r.size.x / 72.0  # the designs are made for a 72 px wide card
	var c := r.get_center()
	match back:
		"horde":
			_frame(ci, r, k, Color("7a1410"), Color("4a0a08"), Color("3a3a3a"), Color("9a9a9a"))
			for i in 8:  # an iron sun with spikes
				var a := i * TAU / 8.0
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x)
				ci.draw_colored_polygon(PackedVector2Array([c + d * 9 * k + n * 4 * k, c + d * 22 * k, c + d * 9 * k - n * 4 * k]), Color("5c5c5c"))
			ci.draw_circle(c, 11 * k, Color("2a2a2a"))
			ci.draw_circle(c, 8 * k, Color("b3261e"))
			_lines(ci, [c + Vector2(-4, -4) * k, c + Vector2(4, 4) * k], Color("2a2a2a"), 2 * k)
			_lines(ci, [c + Vector2(4, -4) * k, c + Vector2(-4, 4) * k], Color("2a2a2a"), 2 * k)
		"druid":
			_frame(ci, r, k, Color("2f5d2a"), Color("1d3d1a"), Color("8a6a3a"), Color("c9a74a"))
			for i in 6:  # leaves around a ring of bark
				var a := i * TAU / 6.0 + 0.3
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x)
				var p := c + d * 16 * k
				ci.draw_colored_polygon(PackedVector2Array([p - d * 7 * k, p + n * 4 * k, p + d * 7 * k, p - n * 4 * k]), Color("7fc15a"))
				_lines(ci, [p - d * 6 * k, p + d * 6 * k], Color("3d6b2a"), 1 * k)
			ci.draw_arc(c, 10 * k, 0, TAU, 32, Color("8a6a3a"), 3 * k, true)
			ci.draw_circle(c, 4 * k, Color("f2e394"))
		"arcane":
			_frame(ci, r, k, Color("3b2470"), Color("23154a"), Color("9b7be0"), Color("d8c8ff"))
			var star := PackedVector2Array()
			for i in 10:  # a star in a runed circle
				var a := -PI / 2.0 + i * TAU / 10.0
				star.append(c + Vector2(cos(a), sin(a)) * (16.0 if i % 2 == 0 else 7.0) * k)
			ci.draw_arc(c, 20 * k, 0, TAU, 40, Color("9b7be0"), 1.5 * k, true)
			ci.draw_arc(c, 23 * k, 0, TAU, 40, Color("9b7be0", 0.5), 1 * k, true)
			for i in 12:
				var a := i * TAU / 12.0
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * 21.5 * k, 1.2 * k, Color("e5dbff"))
			ci.draw_colored_polygon(star, Color("d8c8ff"))
			ci.draw_circle(c, 3 * k, Color("ffffff"))
		"gold":
			_frame(ci, r, k, Color("c9a74a"), Color("8a6d2a"), Color("5a4210"), Color("fff1b8"))
			for i in 16:  # a sunburst
				var a := i * TAU / 16.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * 10 * k, c + d * (20.0 if i % 2 == 0 else 15.0) * k, Color("fff1b8"), 2 * k, true)
			ci.draw_circle(c, 10 * k, Color("5a4210"))
			ci.draw_circle(c, 8 * k, Color("e8b830"))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -6) * k, c + Vector2(4, 0) * k, c + Vector2(0, 6) * k, c + Vector2(-4, 0) * k]), Color("fff1b8"))
		"night":
			_frame(ci, r, k, Color("15192e"), Color("0b0e1c"), Color("4a5578"), Color("aab4d6"))
			for i in range(1, 31):  # stars spread evenly (an R2 sequence), always in the same places
				var p := Vector2(fmod(i * 0.7548777, 1.0) - 0.5, fmod(i * 0.5698403, 1.0) - 0.5) * Vector2(46, 78)
				if p.length() > 17:  # not on the moon
					ci.draw_circle(c + p * k, (0.8 + (i % 3) * 0.4) * k, Color("dfe6ff", 0.8))
			ci.draw_circle(c, 13 * k, Color("f2eccf"))  # a crescent moon
			ci.draw_circle(c + Vector2(5, -3) * k, 11 * k, Color("0b0e1c"))
		_:  # classic
			_frame(ci, r, k, Color("2b4a8b"), Color("1f3a68"), Color("7a5c1e"), Color("c9a74a"))
			ci.draw_circle(c, r.size.x * 0.2, Color("c9a74a"))
			ci.draw_circle(c, r.size.x * 0.14, Color("1f3a68"))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9) * k, c + Vector2(7, 0) * k, c + Vector2(0, 9) * k, c + Vector2(-7, 0) * k]), Color("f2c94c"))


## The card's body, an inner panel and their two borders.
static func _frame(ci: CanvasItem, r: Rect2, k: float, body: Color, inner: Color, inner_edge: Color, edge: Color) -> void:
	ci.draw_style_box(Palette.box(body, int(8 * k), edge, maxi(2, int(3 * k))), r)
	ci.draw_style_box(Palette.box(inner, int(6 * k), inner_edge, maxi(1, int(2 * k))), r.grow(-8 * k))


static func _lines(ci: CanvasItem, pts: Array, col: Color, w: float) -> void:
	ci.draw_line(pts[0], pts[1], col, w, true)


## A small picture of a back, for the settings.
class Preview:
	extends Control
	var back := "classic"

	func _init() -> void:
		custom_minimum_size = Vector2(26, 36)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		CardBacks.draw(self, Rect2(Vector2.ZERO, size), back)
