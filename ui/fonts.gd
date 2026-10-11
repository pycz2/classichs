class_name Fonts
extends RefCounted
## The game's look: Alegreya (OFL; Latin, Cyrillic, Greek) for the interface with
## lining figures, Cinzel Decorative (OFL) for the title, and tavern-style wooden
## buttons with a gold frame. main.gd puts theme() on the root window.

static var _ui: Font
static var _title: Font
static var _theme: Theme


static func _tag(t: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(t)


## The interface font (a weight for buttons, lining figures).
static func ui(weight := 600) -> Font:
	var f := FontVariation.new()
	f.base_font = load("res://fonts/Alegreya.ttf")
	f.variation_opentype = {_tag("wght"): weight}
	f.opentype_features = {_tag("lnum"): 1}
	return f


static func title() -> Font:
	if _title == null:
		_title = load("res://fonts/CinzelDecorative-Black.ttf")
	return _title


## A wooden plank with grain, a dark seam and a gold frame (tint: hover/pressed).
static func plank(tint := Color.WHITE) -> StyleBoxTexture:
	var w := 96
	var h := 40
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2014
	var phase := []
	for i in 6:
		phase.append(rng.randf() * TAU)
	var r := 11.0  # rounded corners; the frame follows them
	var half := Vector2(w, h) / 2.0
	for y in h:
		for x in w:
			var q := (Vector2(x + 0.5, y + 0.5) - half).abs() - (half - Vector2(r, r))
			var dist := Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0.0) - r
			var edge := -dist
			if edge < -0.5:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var grain := sin(x * 0.11 + sin(y * 0.6 + phase[y % 6]) * 2.2) * 0.5 + 0.5
			var c := Color("6b4428").lerp(Color("4a2c18"), grain * 0.55 + (0.12 if y % 9 == 0 else 0.0))
			if edge < 2.2:
				c = Color("d9b44a").lerp(Color("8a6d2a"), float(y) / h)
			elif edge < 3.4:
				c = Color("2a170b")
			elif edge < 5.5:
				c = c.lightened(0.12) if y < h / 2 else c.darkened(0.15)
			c = c * tint
			c.a = clampf(edge + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, c)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.set_texture_margin_all(13)
	sb.set_content_margin_all(10)
	return sb


static func theme() -> Theme:
	if _theme == null:
		var t := Theme.new()
		t.default_font = ui()
		t.set_font("font", "Button", ui(700))
		t.set_font("normal_font", "RichTextLabel", ui(500))
		t.set_font("bold_font", "RichTextLabel", ui(800))
		t.set_stylebox("normal", "Button", plank())
		t.set_stylebox("hover", "Button", plank(Color(1.18, 1.12, 1.05)))
		t.set_stylebox("pressed", "Button", plank(Color(0.8, 0.78, 0.75)))
		t.set_stylebox("hover_pressed", "Button", plank(Color(0.92, 0.88, 0.82)))  # a ticked box or a lit toggle under the mouse
		t.set_stylebox("disabled", "Button", plank(Color(0.55, 0.55, 0.55)))
		t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
		t.set_color("font_color", "Button", Color("f4ead5"))
		t.set_color("font_hover_color", "Button", Color("fff3c4"))
		t.set_color("font_pressed_color", "Button", Color("e0c890"))
		t.set_color("font_outline_color", "Button", Color("1b0f06"))
		t.set_constant("outline_size", "Button", 4)
		var field := Palette.box(Color(0.1, 0.07, 0.05, 0.9), 10, Color("8a6d3b"), 1)
		field.set_content_margin_all(8)
		var focus := Palette.box(Color(0.12, 0.09, 0.06, 0.95), 10, Color("d9b44a"), 2)
		focus.set_content_margin_all(8)
		for type in ["LineEdit", "TextEdit"]:
			t.set_stylebox("normal", type, field)
			t.set_stylebox("focus", type, focus)
			t.set_stylebox("read_only", type, field)
		var popup := Palette.box(Color(0.12, 0.08, 0.05, 0.98), 10, Color("c9a74a"), 2)
		popup.set_content_margin_all(6)
		t.set_stylebox("panel", "PopupMenu", popup)
		t.set_stylebox("panel", "ItemList", field)
		t.set_stylebox("panel", "TooltipPanel", popup)
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			t.set_stylebox(st, "CheckButton", StyleBoxEmpty.new())  # a switch, not a plank
		var track := Palette.box(Color(0.08, 0.05, 0.03, 0.9), 6, Color("6b5320"), 1)
		track.content_margin_top = 4
		track.content_margin_bottom = 4
		var filled := Palette.box(Color("c9a74a"), 6)
		filled.content_margin_top = 4
		filled.content_margin_bottom = 4
		t.set_stylebox("slider", "HSlider", track)
		t.set_stylebox("grabber_area", "HSlider", filled)
		t.set_stylebox("grabber_area_highlight", "HSlider", filled)
		_theme = t
	return _theme
