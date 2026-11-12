class_name FpsCounter
extends CanvasLayer
## The frames per second in the top left corner over every screen, when the settings say so ("fps").
## main owns it, like the friends overlay. It follows the setting by itself, so a toggle shows at
## once; it never takes a click or a touch.

const EVERY := 0.5  # seconds between updates
## Game pixels (the screen is always 1280x720): the very corner; at a game table, under the
## opponent's name (12, 8) and over the history strip (8, 60), the only free place near a corner.
const CORNER := Vector2(3, -3)
const AT_TABLE := Vector2(12, 34)

var label := Label.new()
var _left := 0.0


func _ready() -> void:
	name = "FpsCounter"
	layer = 99  # over the friends and tournament overlays, under the long-press tip (100)
	label.name = "Fps"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	add_child(label)
	_follow()


func _process(delta: float) -> void:
	_left -= delta
	_follow()


func _follow() -> void:
	visible = bool(Settings.data.get("fps", false))
	if not visible or _left > 0.0:
		return
	_left = EVERY
	label.text = "%d FPS" % Engine.get_frames_per_second()
	var table := get_parent().get_children().any(func(c): return c is MatchView and c.visible)
	label.position = AT_TABLE if table else CORNER
