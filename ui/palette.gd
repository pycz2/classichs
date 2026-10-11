class_name Palette
extends RefCounted
## Colours of the interface and of the nine classes.

const CLASS := {
	"WARRIOR": Color("8e1002"), "SHAMAN": Color("0070de"), "ROGUE": Color("4c4d48"),
	"PALADIN": Color("aa8f00"), "HUNTER": Color("016e01"), "DRUID": Color("703606"),
	"WARLOCK": Color("7624ad"), "MAGE": Color("0092ab"), "PRIEST": Color("b8b090"),
	"NEUTRAL": Color("6b6b6b"),
}
const RARITY := {"COMMON": Color("e8e8e8"), "RARE": Color("2f7cff"), "EPIC": Color("a335ee"),
	"LEGENDARY": Color("ff8000")}
const TABLE := Color("3b2f22")
const BOARD := Color("6b5a3e")
const PANEL := Color(0.08, 0.07, 0.06, 0.92)
const TEXT := Color("f4ead5")
const MANA := Color("2e6be6")
const ATTACK := Color("f2c200")
const HEALTH := Color("d0302a")
const ARMOR := Color("9aa3ad")
const BUFFED := Color("3fd14b")
const PLAYABLE := Color("3fd14b")
const TARGET := Color("ff5a36")
const SELECTED := Color("ffe14a")
const CARD_BACK := Color("27408b")


static func of_class(card_class: String) -> Color:
	return CLASS.get(card_class, CLASS.NEUTRAL)


## A filled rounded box style for panels and card parts.
static func box(color: Color, radius := 12, border := Color.TRANSPARENT, border_width := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_width)
	return s


static func label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l


static func button(text: String, name := "") -> Button:
	var b := Button.new()
	b.text = text
	b.name = name if name != "" else text.replace(" ", "")
	b.custom_minimum_size = Vector2(260, 48)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(Sound.play.bind("click"))
	return b


## The tavern picture, darkened, behind a screen (menus, collection, settings).
static func backdrop(parent: Control) -> void:
	var pic := TextureRect.new()
	pic.texture = load("res://ui/menu_bg.jpg")
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.modulate = Color(0.4, 0.36, 0.33)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pic)
