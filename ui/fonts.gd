class_name Fonts
extends RefCounted
## The game's look: Alegreya (OFL; Latin, Cyrillic, Greek) for the interface with
## lining figures, Cinzel Decorative (OFL) for the title, and tavern-style wooden
## buttons with a gold frame. main.gd puts theme() on the root window. A pack's
## ui/theme.json (Palette.UI) may bring its own fonts (ui/fonts/) and buttons; the
## theme is rebuilt in place when the active pack changes.

static var _title: Font
static var _theme: Theme
static var _pack_fonts := {}  # "<pack path>|<file>" -> FontFile (or null)


static func _tag(t: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(t)


## A font file of a pack's theme ("body" or "title"; the active pack by default), or null.
static func _pack_font(kind: String, p: Pack = null) -> Font:
	if p == null:
		p = Packs.active()
	var file = Palette.UI.fonts.get(kind, "")
	if p != Packs.active():
		var t = p.json("ui/theme.json") if p.has("ui/theme.json") else null
		file = t.get("fonts", {}).get(kind, "") if t is Dictionary and t.get("fonts") is Dictionary else ""
	if not file is String or file == "" or p == null:
		return null
	var key: String = p.path + "|" + file
	if not _pack_fonts.has(key):
		var bytes := p.read(file)
		var f: FontFile = null
		if not bytes.is_empty():
			f = FontFile.new()
			f.data = bytes
		_pack_fonts[key] = f
	return _pack_fonts[key]


## The interface font (a weight for buttons, lining figures): the theme's body font or Alegreya.
static func ui(weight := 600) -> Font:
	var own := _pack_font("body")
	return own_weight(own, weight) if own else card(weight)


## The font of card texts: always Alegreya (the card layout is measured with it).
static func card(weight := 600) -> Font:
	var f := FontVariation.new()
	f.base_font = load("res://fonts/Alegreya.ttf")
	f.variation_opentype = {_tag("wght"): weight}
	f.opentype_features = {_tag("lnum"): 1}
	return f


static func own_weight(base: Font, weight: int) -> Font:
	var f := FontVariation.new()
	f.base_font = base
	f.variation_opentype = {_tag("wght"): weight}
	f.opentype_features = {_tag("lnum"): 1}
	return f


## The title font: the theme's (bold) or Cinzel Decorative; of the active pack, or of p.
static func title(p: Pack = null) -> Font:
	var own := _pack_font("title", p)
	if own:
		return own_weight(own, 800)
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


## The look of every control below the root (main.gd) and the social overlay; one Theme,
## refilled in place when the active pack changes, so open screens restyle at once.
static func theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		Packs.on_change(restyle)
		Palette.load_theme()
		_fill(_theme)
	return _theme


static func restyle() -> void:
	Palette.load_theme()
	if _theme:
		_theme.clear()
		_fill(_theme)


static func _fill(t: Theme) -> void:
	t.default_font = ui()
	t.set_font("font", "Button", ui(700))
	t.set_font("normal_font", "RichTextLabel", ui(500))
	t.set_font("bold_font", "RichTextLabel", ui(800))
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "Button", button_box(st))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var radius := 10 if Palette.CLASSIC else mini(10, int(Palette.UI.button.radius))
	if Palette.CLASSIC:
		t.set_color("font_color", "Button", Color("f4ead5"))
		t.set_color("font_hover_color", "Button", Color("fff3c4"))
		t.set_color("font_pressed_color", "Button", Color("e0c890"))
		t.set_color("font_outline_color", "Button", Color("1b0f06"))
		t.set_constant("outline_size", "Button", 4)
	else:
		t.set_color("font_color", "Button", Palette.tc("button_text"))
		t.set_color("font_hover_color", "Button", Palette.tc("button_text_hover"))
		t.set_color("font_hover_pressed_color", "Button", Palette.tc("button_text_hover"))
		t.set_color("font_pressed_color", "Button", Palette.tc("button_text_pressed"))
		t.set_color("font_focus_color", "Button", Palette.tc("button_text"))
		t.set_color("font_disabled_color", "Button", Palette.tc("button_text_disabled"))
		t.set_color("font_outline_color", "Button", Palette.tc("outline"))
		t.set_constant("outline_size", "Button", int(Palette.UI.outline_size))
	_labels(t)
	_labels(ThemeDB.get_default_theme())  # also for labels on layers outside the root's theme
	var field := Palette.box(Color(0.1, 0.07, 0.05, 0.9), radius, Color("8a6d3b"), 1)
	field.set_content_margin_all(8)
	var focus := Palette.box(Color(0.12, 0.09, 0.06, 0.95), radius, Color("d9b44a"), 2)
	focus.set_content_margin_all(8)
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("read_only", type, field)
	var popup := Palette.box(Color(0.12, 0.08, 0.05, 0.98), radius, Color("c9a74a"), 2)
	popup.set_content_margin_all(6)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("panel", "ItemList", field)
	t.set_stylebox("panel", "TooltipPanel", popup)
	if not Palette.CLASSIC:  # a light row under the mouse in lists and menus, readable text in fields
		var hover := Palette.raw_box(Color(Palette.ATTACK, 0.22), 4)
		t.set_stylebox("hover", "PopupMenu", hover)
		t.set_color("font_hover_color", "PopupMenu", Palette.TEXT)
		t.set_color("font_color", "PopupMenu", Palette.TEXT)
		for type in ["LineEdit", "TextEdit"]:
			t.set_color("font_color", type, Palette.TEXT)
			t.set_color("font_placeholder_color", type, Color(Palette.MUTED, 0.7))
			t.set_color("caret_color", type, Palette.ATTACK)
			t.set_color("selection_color", type, Color(Palette.ATTACK, 0.35))
		t.set_color("font_color", "TooltipLabel", Palette.TEXT)
	var pic := _picture(Palette.UI.panel.texture)
	if pic:  # the theme's panel picture: popups, tooltips and plain panels (frames the screens draw stay flat)
		var sb := StyleBoxTexture.new()
		sb.texture = pic
		sb.set_texture_margin_all(int(Palette.UI.panel.texture_margin))
		sb.set_content_margin_all(12)
		for type in ["PopupMenu", "TooltipPanel", "PanelContainer", "PopupPanel"]:
			t.set_stylebox("panel", type, sb)
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
	t.emit_changed()


## Palette.label's kinds: the interface's text, its gold, and headings (the theme's title font).
static func _labels(t: Theme) -> void:
	for v in [["TextLabel", Palette.TEXT], ["AccentLabel", Palette.ATTACK], ["HeadingLabel", Palette.ATTACK]]:
		t.set_type_variation(v[0], "Label")
		t.set_color("font_color", v[0], v[1])
		t.set_color("font_outline_color", v[0], Palette.tc("outline"))
		t.set_constant("outline_size", v[0], int(Palette.UI.outline_size))
	if _pack_font("title"):
		t.set_font("font", "HeadingLabel", title())
	elif t.get_font_list("HeadingLabel").has("font"):
		t.clear_font("font", "HeadingLabel")


const _TINT := {"normal": Color.WHITE, "hover": Color(1.18, 1.12, 1.05), "pressed": Color(0.8, 0.78, 0.75),
	"hover_pressed": Color(0.92, 0.88, 0.82), "disabled": Color(0.55, 0.55, 0.55)}


## A button's box in a state (normal, hover, pressed, hover_pressed — a ticked box or a lit
## toggle under the mouse —, disabled): Classic's plank, the theme's picture, or a flat
## (and for "neon" glowing) box in the theme's colours.
static func button_box(state: String) -> StyleBox:
	var b: Dictionary = Palette.UI.button
	var pic := _picture(b.texture)
	if pic:
		var sb := StyleBoxTexture.new()
		sb.texture = pic
		sb.set_texture_margin_all(int(b.texture_margin))
		sb.set_content_margin_all(10)
		sb.modulate_color = _TINT[state]
		return sb
	if b.style == "wood":
		return plank(_TINT[state])
	var key: String = {"normal": "button", "hover": "button_hover", "pressed": "button_pressed",
		"hover_pressed": "button_pressed", "disabled": "button_disabled"}[state]
	var lit := state in ["hover", "hover_pressed"]
	var edge := Palette.tc("button_border")
	if lit:
		edge = edge.lerp(Color.WHITE, 0.35)
	elif state == "disabled":
		edge = Color(edge, edge.a * 0.35)
	return flat_box(Palette.tc(key), edge, b.style == "neon" and state != "disabled",
		Palette.tc("button.glow_hover" if lit else "button.glow"), int(b.glow_hover_size if lit else b.glow_size))


## A picture of the active pack (a theme's button or panel texture), or null.
static func _picture(file: Variant) -> Texture2D:
	var p := Packs.active()
	return p.texture(file) if file is String and file != "" and p and p.has(file) else null


## A flat themed box: the button radius and border, a glow around it ("neon").
static func flat_box(fill: Color, edge: Color, glow: bool, glow_color := Color.TRANSPARENT, glow_size := 0) -> StyleBoxFlat:
	var b: Dictionary = Palette.UI.button
	var sb := Palette.raw_box(fill, int(b.radius), edge, int(b.border))
	sb.set_content_margin_all(10)
	sb.anti_aliasing = true
	if glow:
		sb.shadow_color = glow_color
		sb.shadow_size = glow_size
	return sb


## End Turn: Classic's plank (green while nothing is left to do), or the theme's end_turn
## colours; k brightens (hover) or darkens (pressed).
static func end_turn(ready: bool, k := 1.0) -> StyleBox:
	if Palette.UI.button.style == "wood" and Palette.tc("end_turn.button").a == 0.0:
		return plank((Color(0.75, 1.35, 0.7) if ready else Color.WHITE) * k)
	var fill := Palette.tc("end_turn.ready", Palette.OK.darkened(0.55)) if ready else Palette.tc("end_turn.button", Palette.tc("button"))
	var edge := Palette.tc("end_turn.ready_border", Palette.OK) if ready else Palette.tc("end_turn.border", Palette.tc("button_border"))
	fill = fill.lightened(k - 1.0) if k > 1.0 else fill.darkened(1.0 - k)
	var b: Dictionary = Palette.UI.button
	var sb := flat_box(fill, edge, b.style == "neon", Color(edge, 0.55 if ready else 0.35), int(b.glow_hover_size if ready else b.glow_size))
	sb.set_border_width_all(maxi(2, int(b.border)))
	return sb
