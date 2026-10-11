class_name Frames
extends RefCounted
## Card-frame pieces in the style of the original: the mana crystal, the attack
## gem, the health drop, the armour and durability shield, the rarity gem, the
## legendary crest. All draw on any CanvasItem.

const MANA := Color("2f6fe0")
const ATTACK := Color("f2b705")
const HEALTH := Color("d6202a")
const ARMOR := Color("8d99a6")
const GOLD := Color("d9b44a")


static func _number(ci: CanvasItem, c: Vector2, value: int, size: float, col := Color.WHITE) -> void:
	var font := ThemeDB.fallback_font
	var fs := int(size)
	var s := str(value)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := c + Vector2(-w / 2.0, fs * 0.36)
	ci.draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, fs / 5), Color.BLACK)
	ci.draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func _shape(ci: CanvasItem, pts: PackedVector2Array, fill: Color, edge: Color, w: float) -> void:
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, edge, w, true)


static func mana(ci: CanvasItem, c: Vector2, value: int, r: float, col := Color.WHITE) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		var a := TAU * i / 6.0 + PI / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	_shape(ci, pts, MANA, Color("0b1d4a"), maxf(1.5, r * 0.14))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.85), c + Vector2(r * 0.6, -r * 0.35), c + Vector2(0, -r * 0.1), c + Vector2(-r * 0.6, -r * 0.35)]), Color(1, 1, 1, 0.25))
	_number(ci, c, value, r * 1.25, col)


static func attack(ci: CanvasItem, c: Vector2, value: int, r: float, col := Color.WHITE) -> void:
	ci.draw_circle(c, r + maxf(1.5, r * 0.14), Color("3a2a05"))
	ci.draw_circle(c, r, ATTACK)
	ci.draw_line(c + Vector2(-r * 0.55, r * 0.55), c + Vector2(r * 0.55, -r * 0.55), Color(1, 1, 1, 0.3), r * 0.25)
	_number(ci, c, value, r * 1.25, col)


static func health(ci: CanvasItem, c: Vector2, value: int, r: float, col := Color.WHITE) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		var p := Vector2(cos(a), sin(a)) * r
		if p.y < 0:  # the drop narrows to a point at the top
			p.x *= 1.0 + p.y / r * 0.45
			p.y *= 1.25
		pts.append(c + p + Vector2(0, r * 0.1))
	_shape(ci, pts, HEALTH, Color("3d0508"), maxf(1.5, r * 0.14))
	_number(ci, c + Vector2(0, r * 0.08), value, r * 1.25, col)


static func shield(ci: CanvasItem, c: Vector2, value: int, r: float, col := Color.WHITE) -> void:
	var pts := PackedVector2Array([c + Vector2(-r, -r * 0.9), c + Vector2(r, -r * 0.9), c + Vector2(r * 0.9, r * 0.2), c + Vector2(0, r * 1.05), c + Vector2(-r * 0.9, r * 0.2)])
	_shape(ci, pts, ARMOR, Color("2b3036"), maxf(1.5, r * 0.14))
	_number(ci, c, value, r * 1.15, col)


static func rarity(ci: CanvasItem, c: Vector2, rar: String, r: float) -> void:
	var col: Color = {"COMMON": Color("f8f9fa"), "RARE": Color("339af0"), "EPIC": Color("ae3ec9"), "LEGENDARY": Color("fd7e14")}.get(rar, Color.TRANSPARENT)
	if col.a == 0.0:
		return
	_shape(ci, PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)]), col, Color("2a2118"), maxf(1.0, r * 0.2))


## The gold dragon above a legendary portrait: a horned head in the middle and
## spread, scalloped wings along the top edge, like the original frame.
static func crest(ci: CanvasItem, top: Vector2, w: float) -> void:
	var dark := Color("3a2a08")
	var light := Color("f7dc7a")
	var line := maxf(1.0, w * 0.025)
	for sx in [-1.0, 1.0]:
		var p := func(x: float, y: float) -> Vector2: return top + Vector2(sx * x * w, y * w)
		var wing := PackedVector2Array([p.call(0.1, 0.12), p.call(0.28, -0.08), p.call(0.5, -0.07), p.call(0.64, 0.1),
			p.call(0.52, 0.08), p.call(0.5, 0.2), p.call(0.38, 0.14), p.call(0.32, 0.27), p.call(0.21, 0.18), p.call(0.12, 0.24)])
		ci.draw_colored_polygon(wing, GOLD)
		ring(ci, wing, dark, line)
		for tip in [[0.5, -0.07], [0.52, 0.08], [0.38, 0.14], [0.21, 0.18]]:
			ci.draw_line(p.call(0.12, 0.12), p.call(tip[0], tip[1]), Color(light, 0.8), line * 0.8, true)
		ci.draw_colored_polygon(PackedVector2Array([p.call(0.05, -0.08), p.call(0.15, -0.24), p.call(0.09, -0.05)]), light)
	var head := PackedVector2Array([top + Vector2(0, -0.17) * w, top + Vector2(0.08, -0.09) * w, top + Vector2(0.1, 0.05) * w,
		top + Vector2(0.04, 0.15) * w, top + Vector2(-0.04, 0.15) * w, top + Vector2(-0.1, 0.05) * w, top + Vector2(-0.08, -0.09) * w])
	ci.draw_colored_polygon(head, GOLD.lightened(0.1))
	ring(ci, head, dark, line)
	ci.draw_line(top + Vector2(0, -0.12) * w, top + Vector2(0, 0.1) * w, Color(light, 0.9), line, true)
	for sx in [-1.0, 1.0]:
		ci.draw_circle(top + Vector2(sx * 0.04, -0.02) * w, w * 0.022, Color("e03131"))
		ci.draw_circle(top + Vector2(sx * 0.025, 0.11) * w, w * 0.01, dark)


static func ring(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, col, w, true)
