class_name TouchInput
extends Node
## Touch screens, in every screen. A finger drag scrolls the list under it (a ScrollContainer, a
## RichTextLabel or an ItemList), also when it starts on a button or a row of the list: they stop
## the press, and Godot's own touch scroll only works where the list itself is pressed. A tap still
## presses; a drag lets go of the button it started on, and a quick one flings on. A long press
## shows the tooltip of what is held (a finger has no hover) and then presses nothing. Only touches
## (the mouse Godot makes of them): a real mouse keeps its wheel, bars and tooltips; scroll bars and
## sliders drag as they did. main adds it on every platform (no touch, nothing happens).

const SLOP := 12.0  # game pixels a tap may move
const HOLD := 0.5  # seconds: a long press
const FRICTION := 5.0  # a fling loses this share of its speed per second
const OFF := Vector2(-100000, -100000)  # a point off the screen: the control pressed lets go

var _from := Vector2.INF  # where the finger went down (INF: no touch, or one that does not scroll)
var _down_at := 0  # msec of the press
var _bar: ScrollBar  # the bar the finger drags (null until it moves past SLOP), then the one it flung
var _vertical := true
var _base := 0.0  # the bar's value when the drag took it
var _at := 0.0  # the finger's place along the bar then
var _speed := 0.0  # the bar's units per second: of the finger, then of the fling
var _moved_at := 0  # msec of the finger's last move: a finger held still and lifted does not fling
var _layer := CanvasLayer.new()  # the long press's tip, over everything
var _held := false  # a tip was shown: the release presses nothing


func _ready() -> void:
	_layer.layer = 100
	add_child(_layer)


func _input(event: InputEvent) -> void:
	if event.device != InputEvent.DEVICE_ID_EMULATION:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_from = mb.position
			_down_at = Time.get_ticks_msec()
			_bar = null
			_speed = 0.0  # a touch stops a fling
			_held = false
			for c in _layer.get_children():
				c.queue_free()
			return
		if _held or (_bar and _from != Vector2.INF):
			mb.canceled = true  # the button the drag (or the long press) started on is not pressed
			if Time.get_ticks_msec() - _moved_at > 100:
				_speed = 0.0
		_from = Vector2.INF
		return
	var mm := event as InputEventMouseMotion
	if not mm or _from == Vector2.INF:
		return
	if not _bar:
		var d := mm.position - _from
		if d.length() <= SLOP or _held:
			return
		_vertical = absf(d.y) >= absf(d.x)
		_bar = bar_under(get_viewport().gui_get_hovered_control(), _vertical)
		if not _bar:
			_from = Vector2.INF  # a slider, or a list that does not scroll this way: as it was
			return
		_base = _bar.value
		_at = _axis(mm.position)
		_moved_at = Time.get_ticks_msec()
		mm.position = OFF  # the control under the finger stops looking pressed
		return
	if not is_instance_valid(_bar):
		_from = Vector2.INF
		return
	_bar.value = _base + _at - _axis(mm.position)
	_speed = -_axis(mm.velocity)
	_moved_at = Time.get_ticks_msec()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _from != Vector2.INF and not _bar and not _held and Time.get_ticks_msec() - _down_at >= HOLD * 1000.0:
		var text := tooltip_at(get_viewport().gui_get_hovered_control(), _from)
		if text != "":
			_held = true
			show_tip(text, _from)
	if _from != Vector2.INF or not _bar or absf(_speed) < 30.0:
		return
	if not is_instance_valid(_bar):
		_bar = null
		return
	_bar.value += _speed * delta
	_speed *= maxf(0.0, 1.0 - FRICTION * delta)


func _axis(v: Vector2) -> float:
	return v.y if _vertical else v.x


## The scroll bar a drag along this axis moves: of the nearest list around c that can scroll that
## way, or null (c is a scroll bar or a slider itself, or nothing around it scrolls).
static func bar_under(c: Control, vertical: bool) -> ScrollBar:
	if c is Range:
		return null
	while c:
		var b: ScrollBar = null
		if c is ScrollContainer:
			var sc := c as ScrollContainer
			if (sc.vertical_scroll_mode if vertical else sc.horizontal_scroll_mode) != ScrollContainer.SCROLL_MODE_DISABLED:
				b = sc.get_v_scroll_bar() if vertical else sc.get_h_scroll_bar()
		elif vertical and (c is RichTextLabel or c is ItemList):
			b = c.get_v_scroll_bar()
			if not b.visible:
				b = null
		if b and b.max_value - b.page > 1.0:
			return b
		c = c.get_parent() as Control
	return null


## The tooltip of c at a point of the game, or of the first control around it that passes the
## press on; "" for none, and for a text field (its long press opens its menu: KeyboardLift).
static func tooltip_at(c: Control, at: Vector2) -> String:
	if c is LineEdit or c is TextEdit:
		return ""
	while c:
		var t := c.get_tooltip(c.get_global_transform_with_canvas().affine_inverse() * at)
		if t != "" or c.mouse_filter != Control.MOUSE_FILTER_PASS:
			return t
		c = c.get_parent() as Control
	return ""


## The tip above the finger, in the look of a tooltip; it goes at the next touch.
func show_tip(text: String, at: Vector2) -> Control:
	var p := PanelContainer.new()
	p.name = "TouchTip"
	p.theme = Fonts.theme()
	p.theme_type_variation = &"TooltipPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.theme_type_variation = &"TooltipLabel"
	l.text = text
	p.add_child(l)
	_layer.add_child(p)
	p.reset_size()
	var screen := get_viewport().get_visible_rect().size
	p.position = Vector2(clampf(at.x - p.size.x / 2.0, 8.0, screen.x - p.size.x - 8.0), maxf(at.y - p.size.y - 48.0, 8.0))
	return p


## A card that acts at once when pressed (EntityView.clicked) and shows itself big while hovered:
## a finger gets the act when it lifts from a tap, so a long press only shows the card. A mouse
## acts on the press as before.
static func act_on_tap(v: Control, act: Callable) -> void:
	var down := [0]
	v.gui_input.connect(func(ev: InputEvent):  # (the signal comes before the card's own _gui_input)
		var mb := ev as InputEventMouseButton
		if not mb or mb.device != InputEvent.DEVICE_ID_EMULATION or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		v.accept_event()
		if mb.pressed:
			down[0] = Time.get_ticks_msec()
		elif not mb.canceled and Time.get_ticks_msec() - down[0] < HOLD * 1000.0 and Rect2(Vector2.ZERO, v.size).has_point(mb.position):
			act.call())
