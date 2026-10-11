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
## Stat numbers above or below the card's own value.
const BUFFED := Color("4dff5a")
const DAMAGED := Color("ff3b3b")


static func _number(ci: CanvasItem, c: Vector2, value: int, size: float, col := Color.WHITE) -> void:
	var font := ThemeDB.fallback_font
	var fs := int(size * 1.08)
	var s := str(value)
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := c + Vector2(-w / 2.0, fs * 0.36)
	var outline := maxi(4, int(fs * 0.34))  # a thick black edge keeps every colour readable on every gem
	ci.draw_string_outline(font, at + Vector2(0, 1.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0, 0, 0, 0.6))
	ci.draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color.BLACK)
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
	# a sword behind the gem: the blade sticks out to the top right, the hilt to the bottom left
	var d := Vector2(1, -1).normalized()
	var n := Vector2(-d.y, d.x)
	var dark := Color("3a2a05")
	var w := r * 0.32
	var tip := c + d * r * 1.75
	var base := c - d * r * 0.9
	var blade := PackedVector2Array([base + n * w, tip - d * w * 1.6 + n * w, tip, tip - d * w * 1.6 - n * w, base - n * w])
	_shape(ci, blade, ATTACK.lightened(0.15), dark, maxf(1.5, r * 0.12))
	ci.draw_line(base, tip - d * w * 1.8, Color(1, 1, 1, 0.45), maxf(1.0, r * 0.08), true)
	var guard := c - d * r * 1.0
	_shape(ci, PackedVector2Array([guard + n * r * 0.75 + d * w * 0.5, guard + n * r * 0.75 - d * w * 0.5, guard - n * r * 0.75 - d * w * 0.5, guard - n * r * 0.75 + d * w * 0.5]), ATTACK.darkened(0.15), dark, maxf(1.5, r * 0.12))
	var grip_end := c - d * r * 1.55
	ci.draw_line(guard, grip_end, dark, w * 1.5, true)
	ci.draw_line(guard, grip_end, Color("8a5a1a"), w * 0.9, true)
	ci.draw_circle(grip_end, w * 0.75, ATTACK.darkened(0.1))
	ci.draw_circle(c, r + maxf(1.5, r * 0.14), dark)
	ci.draw_circle(c, r, ATTACK)
	ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.45, Color(1, 1, 1, 0.18))
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
	_shape(ci, pts, HEALTH.darkened(0.5) if col == DAMAGED else HEALTH, Color("3d0508"), maxf(1.5, r * 0.14))  # a darker drop makes red damage numbers stand out
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


static var _dragon: Texture2D


## The gold dragon crest (generated with Codex, background cut out) sitting ON a
## line: base is the middle of its bottom edge, so it rises above a portrait or
## a card edge instead of covering it.
static func crest(ci: CanvasItem, base: Vector2, w: float) -> void:
	if _dragon == null:
		_dragon = load("res://ui/dragon_crest.png")
	var h := w * _dragon.get_height() / float(_dragon.get_width())
	ci.draw_texture_rect(_dragon, Rect2(base - Vector2(w / 2.0, h * 0.9), Vector2(w, h)), false, Color(1, 1, 1, 0.95))


static func ring(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, col, w, true)
