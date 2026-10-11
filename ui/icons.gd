class_name Icons
extends RefCounted
## Symbolic vector icons: a crest for every class and small interface icons.
## Shapes are plain data like Art's, in unit coordinates inside a square.

const CLASSES := ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR", "NEUTRAL"]
const GOLD := Color("f2c94c")
const DARK := Color("1b140f")


static func shapes(kind: String, rect: Rect2) -> Array:
	var side := minf(rect.size.x, rect.size.y)
	var sq := Rect2(rect.position + (rect.size - Vector2(side, side)) / 2.0, Vector2(side, side))
	var p := _Pen.new(sq)
	if kind in CLASSES:
		p.circle(0.5, 0.5, 0.48, GOLD.darkened(0.25))
		p.circle(0.5, 0.5, 0.43, Palette.of_class(kind).darkened(0.15))
	p.call("i_" + kind.to_lower())
	return p.out


static func paint(ci: CanvasItem, kind: String, rect: Rect2) -> void:
	for s in shapes(kind, rect):
		match s[0]:
			"circle":
				ci.draw_circle(s[1], s[2], s[3])
			"poly":
				ci.draw_colored_polygon(s[1], s[2])
			"line":
				ci.draw_line(s[1], s[2], s[3], s[4], true)


## Puts an icon on a button: alone (centred) or to the left of the text.
static func attach(b: Button, kind: String, side := 30.0) -> IconView:
	var v := IconView.new()
	v.kind = kind
	v.size = Vector2(side, side)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var place := func():
		v.position = Vector2(8, (b.size.y - side) / 2.0) if b.text != "" else (b.size - v.size) / 2.0
	b.resized.connect(place)
	place.call()
	return v


class _Pen:
	var sq: Rect2
	var out := []

	func _init(p_sq: Rect2) -> void:
		sq = p_sq

	func at(x: float, y: float) -> Vector2:
		return sq.position + Vector2(x, y) * sq.size.x

	func poly(pts: Array, col: Color) -> void:
		var a := PackedVector2Array()
		for i in range(0, pts.size(), 2):
			a.append(at(pts[i], pts[i + 1]))
		out.append(["poly", a, col])

	func circle(x: float, y: float, r: float, col: Color) -> void:
		out.append(["circle", at(x, y), r * sq.size.x, col])

	func line(x0: float, y0: float, x1: float, y1: float, col: Color, w := 0.06) -> void:
		out.append(["line", at(x0, y0), at(x1, y1), col, maxf(1.0, w * sq.size.x)])

	# --- class crests (gold symbols) ---------------------------------------------

	func i_druid() -> void:  # a paw with a leaf
		circle(0.5, 0.6, 0.13, Icons.GOLD)
		for p in [[0.3, 0.42], [0.42, 0.32], [0.58, 0.32], [0.7, 0.42]]:
			circle(p[0], p[1], 0.06, Icons.GOLD)
		poly([0.5, 0.86, 0.6, 0.76, 0.5, 0.72, 0.4, 0.76], Color("8ce99a"))

	func i_hunter() -> void:  # a bow and an arrow
		for i in 8:
			var a0 := lerpf(-1.2, 1.2, i / 8.0)
			var a1 := lerpf(-1.2, 1.2, (i + 1) / 8.0)
			line(0.36 + cos(a0) * 0.3, 0.5 + sin(a0) * 0.3, 0.36 + cos(a1) * 0.3, 0.5 + sin(a1) * 0.3, Icons.GOLD, 0.07)
		line(0.36 + cos(-1.2) * 0.3, 0.5 + sin(-1.2) * 0.3, 0.36 + cos(1.2) * 0.3, 0.5 + sin(1.2) * 0.3, Color("f8f9fa"), 0.025)
		line(0.22, 0.5, 0.8, 0.5, Icons.GOLD, 0.045)
		poly([0.86, 0.5, 0.76, 0.43, 0.76, 0.57], Icons.GOLD)

	func i_mage() -> void:  # an arcane eye
		poly([0.14, 0.5, 0.32, 0.34, 0.5, 0.28, 0.68, 0.34, 0.86, 0.5, 0.68, 0.66, 0.5, 0.72, 0.32, 0.66], Icons.GOLD)
		circle(0.5, 0.5, 0.15, Color("e5dbff"))
		circle(0.5, 0.5, 0.08, Icons.DARK)
		poly([0.5, 0.12, 0.54, 0.24, 0.46, 0.24], Icons.GOLD)
		poly([0.5, 0.88, 0.54, 0.76, 0.46, 0.76], Icons.GOLD)

	func i_paladin() -> void:  # a hammer over the sun
		for i in 8:
			var a := TAU * i / 8.0
			line(0.5 + cos(a) * 0.2, 0.5 + sin(a) * 0.2, 0.5 + cos(a) * 0.36, 0.5 + sin(a) * 0.36, Color("fff3bf"), 0.04)
		line(0.5, 0.36, 0.5, 0.84, Icons.GOLD, 0.08)
		poly([0.3, 0.2, 0.7, 0.2, 0.7, 0.4, 0.3, 0.4], Icons.GOLD)

	func i_priest() -> void:  # a winged halo
		for sx in [-1, 1]:
			poly([0.5 + sx * 0.08, 0.5, 0.5 + sx * 0.4, 0.3, 0.5 + sx * 0.36, 0.46, 0.5 + sx * 0.42, 0.52, 0.5 + sx * 0.3, 0.6, 0.5 + sx * 0.32, 0.68, 0.5 + sx * 0.1, 0.62], Icons.GOLD)
		for i in 16:
			var a0 := TAU * i / 16.0
			var a1 := TAU * (i + 1) / 16.0
			line(0.5 + cos(a0) * 0.12, 0.42 + sin(a0) * 0.12, 0.5 + cos(a1) * 0.12, 0.42 + sin(a1) * 0.12, Color("fff3bf"), 0.05)

	func i_rogue() -> void:  # crossed daggers
		for sx in [-1, 1]:
			line(0.5 - sx * 0.24, 0.78, 0.5 + sx * 0.22, 0.22, Icons.GOLD, 0.08)
			line(0.5 - sx * 0.3, 0.66, 0.5 - sx * 0.12, 0.74, Icons.GOLD, 0.06)
		circle(0.5, 0.5, 0.06, Icons.DARK)

	func i_shaman() -> void:  # a lightning bolt in a ring of elements
		for i in 4:
			var a := TAU * i / 4.0 + PI / 4
			circle(0.5 + cos(a) * 0.3, 0.5 + sin(a) * 0.3, 0.06, [Color("ff6b6b"), Color("74c0fc"), Color("8ce99a"), Color("f8f9fa")][i])
		poly([0.56, 0.16, 0.34, 0.54, 0.48, 0.54, 0.42, 0.84, 0.66, 0.44, 0.52, 0.44], Icons.GOLD)

	func i_warlock() -> void:  # a horned skull
		for sx in [-1, 1]:
			poly([0.5 + sx * 0.14, 0.34, 0.5 + sx * 0.34, 0.16, 0.5 + sx * 0.26, 0.4], Icons.GOLD)
		circle(0.5, 0.48, 0.2, Icons.GOLD)
		poly([0.38, 0.6, 0.62, 0.6, 0.58, 0.76, 0.42, 0.76], Icons.GOLD)
		circle(0.43, 0.48, 0.05, Color("82c91e"))
		circle(0.57, 0.48, 0.05, Color("82c91e"))

	func i_warrior() -> void:  # crossed axes over a shield
		poly([0.32, 0.3, 0.68, 0.3, 0.66, 0.58, 0.5, 0.78, 0.34, 0.58], Icons.DARK)
		for sx in [-1, 1]:
			line(0.5 - sx * 0.26, 0.8, 0.5 + sx * 0.2, 0.2, Icons.GOLD, 0.06)
			poly([0.5 + sx * 0.2, 0.2, 0.5 + sx * 0.36, 0.14, 0.5 + sx * 0.32, 0.36, 0.5 + sx * 0.14, 0.3], Icons.GOLD)

	func i_neutral() -> void:  # a gem
		poly([0.5, 0.2, 0.74, 0.42, 0.5, 0.8, 0.26, 0.42], Icons.GOLD)
		poly([0.5, 0.28, 0.64, 0.42, 0.5, 0.68, 0.36, 0.42], Color("fff3bf"))
