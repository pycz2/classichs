class_name Palette
extends RefCounted
## Colours of the interface, and of the classes and rarities (the active pack may give its own).
## The interface colours (TABLE, PANEL, TEXT, ATTACK, MUTED, DANGER, OK) and every panel, frame,
## button and heading follow the active pack's ui/theme.json (docs/packs/format.md, "UI theme");
## a pack without one looks like Classic. Fonts.theme() reloads them when the active pack changes.

const CLASS := {
	"WARRIOR": Color("8e1002"), "SHAMAN": Color("0070de"), "ROGUE": Color("4c4d48"),
	"PALADIN": Color("aa8f00"), "HUNTER": Color("016e01"), "DRUID": Color("703606"),
	"WARLOCK": Color("7624ad"), "MAGE": Color("0092ab"), "PRIEST": Color("b8b090"),
	"NEUTRAL": Color("6b6b6b"),
}
const RARITY := {"COMMON": Color("e8e8e8"), "RARE": Color("2f7cff"), "EPIC": Color("a335ee"),
	"LEGENDARY": Color("ff8000")}
const BOARD := Color("6b5a3e")
const MANA := Color("2e6be6")
const HEALTH := Color("d0302a")
const ARMOR := Color("9aa3ad")
const BUFFED := Color("3fd14b")
const PLAYABLE := Color("3fd14b")
const TARGET := Color("ff5a36")
const SELECTED := Color("ffe14a")
const COMBO := Color("ffc21a")  # a playable Combo card whose Combo is on
const OPPONENT := Color("ff3030")  # what the online opponent points at
const CARD_BACK := Color("27408b")

## Classic's look: every key ui/theme.json may set (format.md, "UI theme"). Colours are
## "rrggbb" or "rrggbbaa".
const CLASSIC_THEME := {
	"colors": {"text": "f4ead5", "muted": "c9b48a", "accent": "f2c200", "table": "3b2f22",
		"panel": "1c130bf5", "panel_border": "a8863a", "backdrop": "665c54",
		"button": "6b4428", "button_hover": "7a5030", "button_pressed": "4a2c18", "button_disabled": "3a2a1e",
		"button_border": "d9b44a", "button_text": "f4ead5", "button_text_hover": "fff3c4",
		"button_text_pressed": "e0c890", "button_text_disabled": "a89c88", "outline": "000000",
		"danger": "ff5a36", "ok": "3fd14b"},
	"outline_size": 4,
	"button": {"style": "wood", "radius": 11, "border": 2, "glow": "00000000", "glow_size": 0,
		"glow_hover": "00000000", "glow_hover_size": 0, "texture": "", "texture_margin": 13},
	"panel": {"radius": 14, "border": 3, "glow": "0000008c", "glow_size": 14, "texture": "", "texture_margin": 16},
	"fonts": {"title": "", "body": "", "title_size": 1.0},
	"end_turn": {"button": "", "border": "", "text": "", "ready": "", "ready_border": ""},
	"mana": "",
	"rarities": {},
	"menu": {"shade": "140d0859", "particles": "embers"},
}

static var TABLE := Color("3b2f22")
static var PANEL := Color(0.08, 0.07, 0.06, 0.92)
static var TEXT := Color("f4ead5")
## The interface's gold: headings, titles, highlights (the theme's accent).
static var ATTACK := Color("f2c200")
static var MUTED := Color("c9b48a")
static var DANGER := Color("ff5a36")
static var OK := Color("3fd14b")
## The active look: CLASSIC_THEME with the active pack's ui/theme.json over it.
static var UI: Dictionary = CLASSIC_THEME
## True while the active pack has no ui/theme.json: everything looks exactly as Classic always did.
static var CLASSIC := true
## Classic's own interface colours ("rrggbb") -> a role of the theme; empty for Classic,
## so a themed pack restyles the screens that pass Classic's colours (ui()).
static var _roles := {}
static var _for: Pack
static var _frames: Array = []  # [WeakRef StyleBoxFlat, fill, radius]: frames restyled in place


## The active pack's theme (loaded once per active pack).
static func load_theme() -> void:
	var p := Packs.active()
	if p == _for and p != null:
		return
	_for = p
	var own = p.json("ui/theme.json") if p and p.has("ui/theme.json") else null
	UI = _merge(CLASSIC_THEME, own) if own is Dictionary else CLASSIC_THEME
	CLASSIC = not own is Dictionary
	TABLE = tc("table")
	TEXT = tc("text")
	ATTACK = tc("accent")
	MUTED = tc("muted")
	DANGER = tc("danger")
	OK = tc("ok")
	PANEL = Color(0.08, 0.07, 0.06, 0.92) if CLASSIC else tc("panel")
	_roles = {}
	if not CLASSIC:
		var panel := tc("panel")
		var edge := tc("panel_border")
		var roles := {
			"panel": [Color(0.11, 0.075, 0.045), Color(0.1, 0.07, 0.05), Color(0.08, 0.05, 0.03), Color(0.08, 0.06, 0.04),
				Color(0.08, 0.06, 0.05), Color(0.07, 0.045, 0.025), Color(0.12, 0.09, 0.06), Color(0.12, 0.08, 0.05),
				Color(0.1, 0.067, 0.04), Color(0.1, 0.07, 0.04), Color(0.08, 0.07, 0.06), Color("3b2f22"), Color("1b140f"),
				Color("21150b"), Color("24170c"), Color("2c2119"), Color("2a1a08"), Color("1b0f06"), Color("2a2118")],
			"panel_hi": [Color(0.16, 0.11, 0.06), Color(0.18, 0.13, 0.08), Color(0.36, 0.26, 0.1), Color("5a3c12"), Color("6b3f12")],
			"edge": [Color("c9a74a"), Color("a8863a"), Color("a8873a"), Color("8a6d2a"), Color("e8cc78")],
			"edge_dim": [Color("6b5320"), Color("8a6d3b"), Color("5a4a36"), Color("7a5c1e")],
			"accent": [Color("d9b44a"), Color("f2c200"), Color("f2c94c")],
			"text": [Color("f4ead5"), Color("fff3c4"), Color("fff1c8")],
			"muted": [Color("c9b48a"), Color("d8c8a0"), Color("e0c890"), Color("a89c88")],
		}
		var to := {"panel": panel, "panel_hi": Color(panel.lerp(ATTACK, 0.22), panel.a), "edge": edge,
			"edge_dim": Color(edge, edge.a * 0.5), "accent": ATTACK, "text": TEXT, "muted": MUTED}
		for role in roles:
			for c: Color in roles[role]:
				_roles[c.to_html(false)] = to[role]
	_frames = _frames.filter(func(f): return f[0].get_ref() != null)
	for f in _frames:
		_restyle_frame(f[0].get_ref(), f[1], f[2])


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if base.get(k) is Dictionary and over[k] is Dictionary and k != "rarities":
			out[k] = _merge(base[k], over[k])
		elif base.has(k):
			out[k] = over[k]
	return out


## A colour of the theme's "colors" (or "<section>.<key>"); fallback when it is empty.
static func tc(key: String, fallback := Color.TRANSPARENT) -> Color:
	var v = UI.colors.get(key) if not "." in key else UI.get(key.get_slice(".", 0), {}).get(key.get_slice(".", 1))
	return Color(v) if v is String and v != "" and Color.html_is_valid(v) else fallback


## A Classic interface colour in the active theme (the same colour for Classic). The alpha is kept.
static func ui(c: Color) -> Color:
	if _roles.is_empty():
		return c
	var to = _roles.get(c.to_html(false))
	return Color(to, to.a * c.a) if to is Color else c


## A class's colour: the active pack's (manifest `colors.classes`), else the built-in one.
static func of_class(card_class: String) -> Color:
	var p := Packs.active()
	var c = p.manifest.get("colors", {}).get("classes", {}).get(card_class) if p else null
	if c is String:
		return Color(c)
	return CLASS.get(card_class, CLASS.NEUTRAL)


## A rarity's colour: the theme's, the active pack's (manifest `colors.rarities`), else the built-in one.
static func of_rarity(rarity: String, fallback := TEXT) -> Color:
	var t = UI.rarities.get(rarity)
	if t is String:
		return Color(t)
	var p := Packs.active()
	var c = p.manifest.get("colors", {}).get("rarities", {}).get(rarity) if p else null
	return Color(c) if c is String else RARITY.get(rarity, fallback)


## A filled rounded box style for panels (Classic's colours follow the theme, ui()).
static func box(color: Color, radius := 12, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	return raw_box(ui(color), radius, ui(border), border_width)


## A box in exactly these colours (card faces and backs, which keep their own look).
static func raw_box(color: Color, radius := 12, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_width)
	return s


## A label; the interface's text and gold follow the theme even after it changes.
static func label(text: String, size := 16, color := TEXT) -> Label:
	Fonts.theme()  # the label kinds below are defined there
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if color == TEXT:
		l.theme_type_variation = &"TextLabel"
	elif color == ATTACK:
		l.theme_type_variation = &"HeadingLabel" if size >= 22 else &"AccentLabel"
	else:
		l.add_theme_color_override("font_color", ui(color))
		l.add_theme_color_override("font_outline_color", tc("outline"))
		l.add_theme_constant_override("outline_size", UI.outline_size)
	return l


static func button(text: String, name := "") -> Button:
	var b := Button.new()
	b.text = text
	b.name = name if name != "" else text.replace(" ", "")
	b.custom_minimum_size = Vector2(260, 48)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(Sound.play.bind("click"))
	return b


## A generated picture (the tavern by default), darkened, behind a screen. A pack with
## its own pictures (ui/menu, ui/library) shows them instead.
static func backdrop(parent: Control, picture := "menu_bg") -> void:
	var pic := TextureRect.new()
	var own := Packs.picture(picture.trim_suffix("_bg"))
	pic.texture = own if own else (Packs.picture("menu") if Packs.picture("menu") else load("res://ui/%s.jpg" % picture))
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.modulate = Color(0.4, 0.36, 0.33) if CLASSIC else tc("backdrop")
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pic)


## A panel of the game: dark wood inside a gold rim, with a soft shadow (the theme's panel
## for a themed pack; it changes with the theme).
static func frame(fill := Color(0.11, 0.075, 0.045, 0.96), radius := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_content_margin_all(14)
	_restyle_frame(s, fill, radius, true)
	_frames.append([weakref(s), fill, radius])
	if _frames.size() > 512:
		_frames = _frames.filter(func(f): return f[0].get_ref() != null)
	return s


## Colours, rim and glow of a frame from the theme; a side a caller took the border off stays off.
static func _restyle_frame(s: StyleBoxFlat, fill: Color, radius: int, fresh := false) -> void:
	var panel: Dictionary = UI.panel
	s.bg_color = fill if CLASSIC else ui(fill)
	s.border_color = Color("a8863a") if CLASSIC else tc("panel_border")
	s.set_corner_radius_all(radius if CLASSIC else mini(radius, int(panel.radius)))
	var w := 3 if CLASSIC else int(panel.border)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		if fresh or s.get_border_width(side) > 0:
			s.set_border_width(side, w)
	s.shadow_color = Color(0, 0, 0, 0.55) if CLASSIC else tc("panel.glow")
	s.shadow_size = 14 if CLASSIC else int(panel.glow_size)
