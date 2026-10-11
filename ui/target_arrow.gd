class_name TargetArrow
extends Control
## The targeting arrow: a curved, segmented arrow from a source to the mouse,
## like the original. Gold while aiming, red-hot over a valid target.

var from := Vector2.ZERO
var to := Vector2.ZERO
var hot := false
## The opponent's arrow is red.
var tint := Color.TRANSPARENT
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func aim(a: Vector2, b: Vector2, over_target: bool) -> void:
	from = a
	to = b
	hot = over_target
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func point(t: float) -> Vector2:
	var mid := (from + to) / 2.0 + Vector2(0, -minf(160.0, from.distance_to(to) * 0.35))
	return from.lerp(mid, t).lerp(mid.lerp(to, t), t)


func _draw() -> void:
	var col := tint if tint.a > 0.0 else (Color("ff6b3d") if hot else Color("f2c94c"))
	var n := maxi(6, int(from.distance_to(to) / 26.0))
	for i in n:
		var t0 := (i + fmod(_t * 2.0, 1.0)) / (n + 1.0)
		var t1 := t0 + 0.55 / (n + 1.0)
		var a := point(t0)
		var b := point(minf(t1, 0.93))
		draw_line(a, b, Color.BLACK, 14, true)
		draw_line(a, b, col, 9, true)
	var tip := to
	var dir := (to - point(0.9)).normalized()
	var side := Vector2(-dir.y, dir.x)
	var head := PackedVector2Array([tip + dir * 6, tip - dir * 26 + side * 18, tip - dir * 26 - side * 18])
	draw_colored_polygon(head, Color.BLACK)
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 22 + side * 13, tip - dir * 22 - side * 13]), col)
	draw_circle(from, 10, Color(col, 0.6))
