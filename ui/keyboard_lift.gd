class_name KeyboardLift
extends Node
## Phones: the on-screen keyboard covers the lower half of the screen and Godot does not move the
## game, so a field low on the screen was typed into unseen. While a text field has the focus and
## the keyboard is up, this lifts the field's canvas layer (or the whole game) so the field stays
## just above the keyboard; it all goes back when the keyboard is gone. main adds it on phones.

const MARGIN := 12.0  # between the field and the keyboard, in game pixels

var _moved: Object  # the CanvasLayer or the Viewport lifted now


func _process(_d: float) -> void:
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
	var lift := field.end.y + MARGIN - kb_top
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
