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
	if kind in CLASSES and Sprites.draw(ci, "class_" + kind, rect.get_center(), minf(rect.size.x, rect.size.y)):
		return  # the generated emblem
	if not kind in CLASSES and Decks.hero(kind) != "":  # a pack's own class: its champion in a gold ring
		var side := minf(rect.size.x, rect.size.y)
		var c := rect.get_center()
		ci.draw_circle(c, side * 0.48, GOLD.darkened(0.25))
		ci.draw_circle(c, side * 0.44, Palette.of_class(kind).darkened(0.15))
		Art.paint_in(ci, Rect2(c - Vector2(side, side) * 0.41, Vector2(side, side) * 0.82), Decks.hero(kind), "circle")
		return
	for s in shapes(kind, rect):  # the gold and dark of interface icons follow the pack's theme
		match s[0]:
			"circle":
				ci.draw_circle(s[1], s[2], Palette.ui(s[3]))
			"poly":
				ci.draw_colored_polygon(s[1], Palette.ui(s[2]))
			"line":
				ci.draw_line(s[1], s[2], Palette.ui(s[3]), s[4], true)


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

	# --- interface icons ------------------------------------------------------------

	func i_gear() -> void:
		for i in 8:
			var a := TAU * i / 8.0
			var d := Vector2(cos(a), sin(a))
			var n := Vector2(-d.y, d.x) * 0.08
			var p0 := Vector2(0.5, 0.5) + d * 0.28
			var p1 := Vector2(0.5, 0.5) + d * 0.44
			poly([p0.x - n.x, p0.y - n.y, p1.x - n.x, p1.y - n.y, p1.x + n.x, p1.y + n.y, p0.x + n.x, p0.y + n.y], Icons.GOLD)
		circle(0.5, 0.5, 0.3, Icons.GOLD)
		circle(0.5, 0.5, 0.13, Icons.DARK)

	func i_cards() -> void:  # three fanned cards (the deck tracker)
		for a in [-0.42, 0.0, 0.42]:
			var pts := []
			for c in [[-0.17, -0.5], [0.17, -0.5], [0.17, 0.0], [-0.17, 0.0]]:  # around the bottom middle
				var v := Vector2(c[0], c[1]).rotated(a) * 1.25
				pts.append_array([0.5 + v.x, 0.86 + v.y])
			poly(pts, Icons.GOLD)
			var inner := []
			for c in [[-0.12, -0.45], [0.12, -0.45], [0.12, -0.05], [-0.12, -0.05]]:
				var v := Vector2(c[0], c[1]).rotated(a) * 1.25
				inner.append_array([0.5 + v.x, 0.86 + v.y])
			poly(inner, Color("6b3a1a"))

	## Half an ellipse (the shoulders of a bust) as polygon points.
	func _shoulders(cx: float, top: float, rx: float, ry: float) -> Array:
		var pts := []
		for i in 13:
			var a := PI + PI * i / 12.0
			pts.append_array([cx + cos(a) * rx, top + ry + sin(a) * ry])
		return pts

	func i_friends() -> void:  # two busts, one behind the other
		poly(_shoulders(0.66, 0.5, 0.22, 0.3), Icons.GOLD.darkened(0.35))
		circle(0.66, 0.36, 0.13, Icons.GOLD.darkened(0.35))
		poly(_shoulders(0.4, 0.56, 0.26, 0.34), Icons.GOLD)
		circle(0.4, 0.4, 0.15, Icons.GOLD)

	func i_chat() -> void:  # a speech bubble with three dots
		var pts := []
		for i in 24:
			var a := TAU * i / 24.0
			pts.append_array([0.5 + cos(a) * 0.42, 0.44 + sin(a) * 0.3])
		poly(pts, Icons.GOLD)
		poly([0.24, 0.62, 0.4, 0.7, 0.16, 0.88], Icons.GOLD)
		for x in [0.33, 0.5, 0.67]:
			circle(x, 0.44, 0.06, Icons.DARK)

	func i_swords() -> void:  # crossed swords (a friendly duel)
		for s in [1.0, -1.0]:
			var a := Vector2(0.5 - 0.34 * s, 0.16)
			var b := Vector2(0.5 + 0.3 * s, 0.8)
			line(a.x, a.y, b.x, b.y, Icons.GOLD, 0.09)
			var g := a.lerp(b, 0.78)
			var n := Vector2(b.y - a.y, -(b.x - a.x)).normalized() * 0.13
			line(g.x - n.x, g.y - n.y, g.x + n.x, g.y + n.y, Icons.GOLD, 0.08)

	func i_more() -> void:  # three dots
		for x in [0.22, 0.5, 0.78]:
			circle(x, 0.5, 0.09, Icons.GOLD)

	func i_check() -> void:  # a tick (accept)
		line(0.2, 0.52, 0.42, 0.74, Color("7be36f"), 0.13)
		line(0.42, 0.74, 0.8, 0.26, Color("7be36f"), 0.13)

	func i_cross() -> void:  # a cross (decline, unblock)
		line(0.25, 0.25, 0.75, 0.75, Color("ff7a5c"), 0.12)
		line(0.75, 0.25, 0.25, 0.75, Color("ff7a5c"), 0.12)
