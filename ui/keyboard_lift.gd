class_name KeyboardLift
extends Node
## Phones: the on-screen keyboard covers the lower half of the screen and Godot does not move the
## game, so a field low on the screen was typed into unseen. While a text field has the focus and
## the keyboard is up, this lifts the field's canvas layer (or the whole game) so the field stays
## above the keyboard; it all goes back when the keyboard is gone. A long press on a text field opens
## its menu (Paste, Copy, Cut, Select all): a phone has no right click. main adds it on phones.

const MARGIN := 12.0  # between the field and the keyboard, in game pixels
## A lifted field goes up to this far from the top of the screen: the height Android reports leaves
## out the keyboard's tool strip and a password keyboard's number row (a OnePlus Open, Gboard).
const TOP := 120.0
const HOLD := 0.5  # seconds: a long press
const STILL := 14.0  # game pixels a long press may move

var _press := {}  # a touch held: {at (the lift taken out), screen (as it came), since}

var _moved: Object  # the CanvasLayer or the Viewport lifted now


func _process(_d: float) -> void:
	if not _press.is_empty() and Time.get_ticks_msec() - int(_press.since) >= HOLD * 1000.0:
		# the press gave the field the focus (a touch has no hover): the field held is the focused one
		var c := get_viewport().gui_get_focus_owner()
		var at: Vector2 = _press.at
		var screen: Vector2 = _press.screen
		_press = {}
		var raw := screen
		if (c is LineEdit or c is TextEdit) and c.editable and _held_on(c, [at, raw]):
			show_menu(c, raw)
	var vp := get_viewport()
	var f := vp.gui_get_focus_owner()
	var kb := float(DisplayServer.virtual_keyboard_get_height())
	if not (f is LineEdit or f is TextEdit) or kb <= 0.0:
		apply(null, 0.0)
		return
	# (the global rect leaves out the lift itself: no feedback between frames)
	apply(f, lift_for(f.get_global_rect(), kb, DisplayServer.window_get_size().y, vp.get_final_transform()))


## How far to lift a field (its rect in game coordinates) above a keyboard kb_px high (screen
## pixels) in a window win_h high; xf maps the game to the window (the stretch and its bars).
static func lift_for(field: Rect2, kb_px: float, win_h: float, xf: Transform2D) -> float:
	if kb_px <= 0.0:
		return 0.0
	var kb_top := (win_h - kb_px - xf.origin.y) / xf.get_scale().y
	var lift := maxf(field.end.y + MARGIN - kb_top, field.position.y - TOP)
	return clampf(lift, 0.0, field.position.y)  # never past the top of the screen


## Lifts the layer that draws the field by `by` (0 or no field: nothing is lifted).
func apply(field: Control, by: float) -> void:
	var target: Object = null
	if field and by > 0.0:
		var layer := field.get_canvas_layer_node()
		target = layer if layer else field.get_viewport()
	if _moved and _moved != target:
		_shift(_moved, 0.0)
	_moved = target
	if target:
		_shift(target, by)


static func _shift(o: Object, by: float) -> void:
	if o is CanvasLayer:
		(o as CanvasLayer).offset = Vector2(0, -by)
	elif o is Viewport:
		(o as Viewport).canvas_transform = Transform2D(0.0, Vector2(0, -by))


func _input(event: InputEvent) -> void:
	var t := event as InputEventScreenTouch
	if t and t.index == 0:
		if t.pressed:
			# (touches come in game coordinates) the point under the finger, the lift taken out
			var at := get_viewport().canvas_transform.affine_inverse() * t.position
			_press = {"at": at, "screen": t.position, "since": Time.get_ticks_msec()}
		else:
			_press = {}
	var d := event as InputEventScreenDrag
	if d and not _press.is_empty() and d.position.distance_to(_press.at) > STILL:
		_press = {}


## Whether one of the points (game coordinates; the field may be lifted or not yet) is on the field.
static func _held_on(c: Control, points: Array) -> bool:
	var layer := c.get_canvas_layer_node()
	var shift := layer.offset if layer else c.get_viewport().canvas_transform.origin
	var r := c.get_global_rect().grow(8)
	for p in points:
		if r.has_point(p) or r.has_point(p - shift):
			return true
	return false


## The field's menu at a point: Paste, and Copy, Cut, Select all when it has text (a secret field
## gives nothing to copy). The items run the field's own actions.
static func show_menu(c: Control, at: Vector2) -> PopupMenu:
	c.grab_focus()
	var m := PopupMenu.new()
	m.name = "TextMenu"
	var secret := c is LineEdit and (c as LineEdit).secret
	var has_text: bool = str(c.get("text")) != ""
	m.add_item(TranslationServer.translate("Paste"), 0)
	if has_text:
		m.add_item(TranslationServer.translate("Select all"), 1)
		if not secret:
			m.add_item(TranslationServer.translate("Copy"), 2)
			m.add_item(TranslationServer.translate("Cut"), 3)
	m.add_theme_font_size_override("font_size", 30)
	m.id_pressed.connect(func(id: int):
		if c is LineEdit:
			(c as LineEdit).menu_option([LineEdit.MENU_PASTE, LineEdit.MENU_SELECT_ALL, LineEdit.MENU_COPY, LineEdit.MENU_CUT][id])
		elif c is TextEdit:
			(c as TextEdit).menu_option([TextEdit.MENU_PASTE, TextEdit.MENU_SELECT_ALL, TextEdit.MENU_COPY, TextEdit.MENU_CUT][id])
		m.queue_free())
	m.popup_hide.connect(func(): m.queue_free.call_deferred())
	c.add_child(m)
	# above the field where it is drawn now (lifted over the keyboard: the menu is not)
	var layer := c.get_canvas_layer_node()
	var shown := (layer.transform if layer else c.get_viewport().canvas_transform) * c.get_global_rect().position
	m.reset_size()
	var top := maxf(shown.y - m.size.y - 6, 0.0)
	m.popup(Rect2i(Vector2i(int(clampf(at.x - m.size.x / 2.0, 0, 1280 - m.size.x)), int(top)), Vector2i.ZERO))
	return m
