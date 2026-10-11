class_name TitleLogo
extends Control
## The game title drawn as a vector logo: a gold dragon crest, "Classic HS" in
## Cinzel Decorative with shadow and two outlines, and a shine that sweeps
## across the letters (clipped to them).

const TEXT := "Classic HS"
const FONT_SIZE := 86

var _shine: Control


func _ready() -> void:
	custom_minimum_size = Vector2(640, 190)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mask := _Letters.new()  # the gold letters; the shine is drawn only inside them
	mask.size = size
	mask.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	add_child(mask)
	_shine = _Shine.new()
	_shine.size = Vector2(90, size.y)
	_shine.position = Vector2(-200, 0)
	mask.add_child(_shine)
	if not Anim.instant:
		var tw := create_tween().set_loops()
		tw.tween_property(_shine, "position:x", size.x + 100, 1.4).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(2.6)
		tw.tween_callback(func(): _shine.position.x = -200)


static func baseline(s: Vector2) -> Vector2:
	var w := Fonts.title().get_string_size(TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	return Vector2((s.x - w) / 2.0, s.y - 46)


func _draw() -> void:
	var f := Fonts.title()
	var at := baseline(size)
	Frames.crest(self, Vector2(size.x / 2.0, 30), 300)
	draw_string(f, at + Vector2(5, 7), TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0, 0, 0, 0.55))
	draw_string_outline(f, at, TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 20, Color("1b0f06"))
	draw_string_outline(f, at, TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 10, Color("8a6d2a"))
	draw_string_outline(f, at, TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, Color("f7dc7a"))


class _Letters:
	extends Control

	func _draw() -> void:
		var f := Fonts.title()
		var at := TitleLogo.baseline(size)
		draw_string(f, at, TitleLogo.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, TitleLogo.FONT_SIZE, Color("e8b830"))
		# a lighter top half of the letters, like polished gold
		draw_string(f, at + Vector2(0, -2), TitleLogo.TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, TitleLogo.FONT_SIZE, Color(1, 0.93, 0.6, 0.35))


class _Shine:
	extends Control

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(30, 0), Vector2(70, 0), Vector2(40, size.y), Vector2(0, size.y)]), Color(1, 1, 0.9, 0.55))
