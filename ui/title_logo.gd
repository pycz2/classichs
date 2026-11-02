class_name TitleLogo
extends Control
## The title of a menu: the client's name (App.NAME) in the client's menu, a game's name in its
## menu. The styling pack's logo picture (manifest `logo`) when it has one; with a crest (theme
## `menu.crest`, Classic's gold dragon) the crest above the name in embossed gold letters with a
## shine that sweeps across them (clipped to them); else the name, plain, in the theme's title font.

const FONT_SIZE := 86

## The title (a game's name in its menu).
var text := App.NAME

var _shine: Control
var _crest: Texture2D


func _ready() -> void:
	custom_minimum_size = Vector2(640, 190)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Packs.picture("logo"):  # the pack's own logo, light on black: added to what is behind it
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
		return
	# a title font without some of the name's letters (Cinzel Decorative has no Cyrillic) shows them
	# in the client's font: capitals then, as the title font's own letters look
	if not Fonts.title_covers(text):
		text = text.to_upper()
	var crest = Palette.UI.menu.get("crest", "")
	_crest = Packs.look().texture(crest) if crest is String and crest != "" and Packs.look() and Packs.look().has(crest) else null
	if _crest == null:
		return
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


## The font size that fits the text in the logo's width.
func font_size() -> int:
	var fs := FONT_SIZE if _crest else 72
	while fs > 40 and Fonts.title().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 40:
		fs -= 4
	return fs


func baseline() -> Vector2:
	var w := Fonts.title().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size()).x
	return Vector2((size.x - w) / 2.0, size.y - 46)


func _draw() -> void:
	var logo := Packs.picture("logo")
	if logo:  # its middle band, where a wide logo's letters are, fills the title's place
		var h := logo.get_width() * size.y / size.x
		draw_texture_rect_region(logo, Rect2(Vector2.ZERO, size), Rect2(0, (logo.get_height() - h) / 2.0, logo.get_width(), h))
		return
	var f := Fonts.title()
	var at := baseline()
	var fs := font_size()
	if _crest == null:  # plain: the name in the accent colour on a soft shadow
		draw_string(f, at + Vector2(0, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.45))
		draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Palette.tc("outline"))
		draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.ATTACK)
		return
	var dw := 250.0
	var dh := dw * _crest.get_height() / _crest.get_width()
	draw_texture_rect(_crest, Rect2(Vector2((size.x - dw) / 2.0, 34 - dh * 0.35), Vector2(dw, dh)), false)
	draw_string(f, at + Vector2(5, 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.55))
	draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 20, Color("1b0f06"))
	draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color("8a6d2a"))
	draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color("f7dc7a"))


class _Letters:
	extends Control

	func _draw() -> void:
		var logo: TitleLogo = get_parent()
		var f := Fonts.title()
		var at := logo.baseline()
		draw_string(f, at, logo.text, HORIZONTAL_ALIGNMENT_LEFT, -1, logo.font_size(), Color("e8b830"))
		# a lighter top half of the letters, like polished gold
		draw_string(f, at + Vector2(0, -2), logo.text, HORIZONTAL_ALIGNMENT_LEFT, -1, logo.font_size(), Color(1, 0.93, 0.6, 0.35))


class _Shine:
	extends Control

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(30, 0), Vector2(70, 0), Vector2(40, size.y), Vector2(0, size.y)]), Color(1, 1, 0.9, 0.55))
