extends TestCase
## Touch screens: a finger drag scrolls a list also when it starts on one of its buttons, and that
## button is not pressed; a tap still presses it; a real mouse drags as it did.

var _root: Window
var _scroll: ScrollContainer
var _ts: TouchInput
var _pressed := 0


## A list of 20 buttons 60 high in a 300x300 scroll, at (10, 10) of the game, with the touch scroll.
func _list() -> Button:
	_root = (Engine.get_main_loop() as SceneTree).root
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(10, 10)
	_scroll.size = Vector2(300, 300)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	_scroll.add_child(box)
	for i in 20:
		var b := Button.new()
		b.custom_minimum_size = Vector2(280, 60)
		b.pressed.connect(func(): _pressed += 1)
		box.add_child(b)
	_root.add_child(_scroll)
	_ts = TouchInput.new()
	_root.add_child(_ts)
	box.notification(Container.NOTIFICATION_SORT_CHILDREN)  # (the layout, now: tests do not wait a frame)
	_scroll.notification(Container.NOTIFICATION_SORT_CHILDREN)
	return box.get_child(3)  # y 202..262 in the game


func _done() -> void:
	_scroll.free()
	_ts.free()


## A finger goes down at `from`, moves to `to` in steps, and lifts; device 0 is a real mouse.
func _drag(from: Vector2, to: Vector2, steps := 10, device := InputEvent.DEVICE_ID_EMULATION) -> void:
	var b := InputEventMouseButton.new()
	b.device = device
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = true
	b.button_mask = MOUSE_BUTTON_MASK_LEFT
	b.position = from
	_root.push_input(b, true)
	for i in steps:
		var m := InputEventMouseMotion.new()
		m.device = device
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.position = from.lerp(to, (i + 1.0) / steps)
		m.relative = (to - from) / steps
		m.velocity = (to - from) * 6.0
		_root.push_input(m, true)
	var up := b.duplicate() as InputEventMouseButton
	up.pressed = false
	up.button_mask = 0
	up.position = to
	_root.push_input(up, true)


func test_a_drag_over_a_button_scrolls_and_does_not_press_it() -> void:
	var b := _list()
	check(_scroll.get_v_scroll_bar().max_value > 1000, "the list is longer than its box")
	_drag(Vector2(100, 230), Vector2(100, 30))
	check(_scroll.scroll_vertical >= 150, "scrolled by the finger: %d" % _scroll.scroll_vertical)
	eq(_pressed, 0, "the button the drag started on is not pressed")
	var at := _scroll.scroll_vertical
	_ts._process(0.1)
	check(_scroll.scroll_vertical > at, "a quick drag flings on")
	_done()


func test_a_tap_presses() -> void:
	_list()
	_drag(Vector2(100, 230), Vector2(104, 236), 2)
	eq([_pressed, _scroll.scroll_vertical], [1, 0], "a tap that moved a little presses, no scroll")
	_done()


func test_a_sideways_drag_and_a_real_mouse_do_not_scroll() -> void:
	_list()
	_drag(Vector2(100, 230), Vector2(250, 236))
	eq(_scroll.scroll_vertical, 0, "sideways: the list does not scroll that way")
	_drag(Vector2(100, 230), Vector2(100, 30), 10, 0)
	eq(_scroll.scroll_vertical, 0, "a real mouse keeps its wheel and bars")
	_done()


func test_scroll_bars_and_text_scroll_by_finger() -> void:
	_list()
	eq(TouchInput.bar_under(_scroll.get_v_scroll_bar(), true), null, "the bar itself drags as it did")
	var text := RichTextLabel.new()
	text.size = Vector2(200, 100)
	text.text = "line\n".repeat(80)
	_root.add_child(text)
	text.get_v_scroll_bar().max_value = 2000  # (its layout is threaded: the bar as it will be)
	text.get_v_scroll_bar().page = 100
	text.get_v_scroll_bar().show()
	eq(TouchInput.bar_under(text, true), text.get_v_scroll_bar(), "the changelog's text")
	text.free()
	_done()


## A finger has no hover: a long press shows the tooltip (why a deck cannot be played, what an icon
## does), and the release then presses nothing.
func test_a_long_press_shows_the_tooltip_and_presses_nothing() -> void:
	var b := _list()
	b.tooltip_text = "Copy"
	var down := InputEventMouseButton.new()
	down.device = InputEvent.DEVICE_ID_EMULATION
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(100, 230)
	_root.push_input(down, true)
	_ts._process(0.0)
	eq(_ts._layer.get_child_count(), 0, "a short press: no tip yet")
	_ts._down_at -= 1000  # (held for a second)
	_ts._process(0.0)
	var tips := _ts._layer.get_children()
	eq(tips.map(func(t): return (t.get_child(0) as Label).text), ["Copy"], "the tip")
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	_root.push_input(up, true)
	eq(_pressed, 0, "the long press presses nothing")
	_done()


## Collection cards act at once on a press and show themselves big on hover: a finger adds the card
## when it lifts from a tap (a long press only looks); a mouse click acts on the press as before.
func test_a_card_acts_on_a_tap_when_it_lifts() -> void:
	_root = (Engine.get_main_loop() as SceneTree).root
	var cv := CardView.make("VAN_CS2_029")
	cv.position = Vector2(400, 100)
	var acts := [0, 0]
	cv.clicked.connect(func(_v): acts[0] += 1)
	TouchInput.act_on_tap(cv, func(): acts[1] += 1)
	_root.add_child(cv)
	var down := InputEventMouseButton.new()
	down.device = InputEvent.DEVICE_ID_EMULATION
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(450, 180)
	_root.push_input(down, true)
	eq(acts, [0, 0], "nothing on the finger's press")
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	_root.push_input(up, true)
	eq(acts, [0, 1], "the tap acts when it lifts")
	var click := down.duplicate() as InputEventMouseButton
	click.device = 0
	_root.push_input(click, true)
	eq(acts, [1, 1], "a mouse acts on the press")
	click.pressed = false
	_root.push_input(click, true)
	cv.free()
