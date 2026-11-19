class_name Marquee
extends Control
## One line of text in a box: a line too long for the box slides slowly to its end and back,
## with a pause at each end, so all of it can be read; a line that fits stands still.

const SPEED := 30.0  # pixels a second
const PAUSE := 1.5  # seconds at each end

var label: Label
var _t := 0.0


## A marquee with a Palette label (outline: the label kinds' own, or outline px of black).
static func make(text: String, font_size: int, color := Palette.TEXT, outline := 0) -> Marquee:
	var m := Marquee.new()
	m.clip_contents = true
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.label = Palette.label(text, font_size, color)
	m.label.name = "Text"
	m.label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	m.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if outline > 0:
		m.label.add_theme_color_override("font_outline_color", Color.BLACK)
		m.label.add_theme_constant_override("outline_size", outline)
	m.add_child(m.label)
	return m


## How much wider the text is than the box (0 when it fits).
func overflow() -> float:
	return maxf(0.0, label.get_minimum_size().x - size.x)


func _process(delta: float) -> void:
	var room := overflow()
	label.size = Vector2(maxf(label.get_minimum_size().x, size.x), size.y)
	if room <= 0.0:
		label.position = Vector2.ZERO
		_t = 0.0
		return
	_t += delta
	var run := room / SPEED
	var k := fmod(_t, 2.0 * (run + PAUSE))  # a pause, to the end, a pause, back
	var x := 0.0
	if k < PAUSE:
		x = 0.0
	elif k < PAUSE + run:
		x = (k - PAUSE) * SPEED
	elif k < 2.0 * PAUSE + run:
		x = room
	else:
		x = room - (k - 2.0 * PAUSE - run) * SPEED
	label.position = Vector2(-x, 0)
