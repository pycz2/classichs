class_name Fuse
extends Control
## The burning rope of the turn timer: a twisted cord across the table that burns
## down from the right, a glowing ember at its end throwing sparks and smoke, ash
## behind it. left: 1.0 = whole, 0.0 = burnt out.

const FROM := Vector2(170, 322)
const LENGTH := 940.0

var left := 1.0:
	set(v):
		left = clampf(v, 0.0, 1.0)
		var tip := _tip()
		_sparks.position = tip
		_smoke.position = tip
		queue_redraw()
var _sparks := CPUParticles2D.new()
var _smoke := CPUParticles2D.new()
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sparks.amount = 28
	_sparks.lifetime = 0.55
	_sparks.direction = Vector2(0.3, -1)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 40.0
	_sparks.initial_velocity_max = 110.0
	_sparks.gravity = Vector2(0, 260)
	_sparks.scale_amount_min = 1.2
	_sparks.scale_amount_max = 2.6
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 0.95, 0.6))
	fade.set_color(1, Color(1, 0.35, 0.05, 0.0))
	_sparks.color_ramp = fade
	add_child(_sparks)
	_smoke.amount = 14
	_smoke.lifetime = 1.4
	_smoke.direction = Vector2(-0.2, -1)
	_smoke.spread = 20.0
	_smoke.initial_velocity_min = 12.0
	_smoke.initial_velocity_max = 24.0
	_smoke.gravity = Vector2.ZERO
	_smoke.scale_amount_min = 3.0
	_smoke.scale_amount_max = 6.0
	var grey := Gradient.new()
	grey.set_color(0, Color(0.35, 0.32, 0.3, 0.35))
	grey.set_color(1, Color(0.35, 0.32, 0.3, 0.0))
	_smoke.color_ramp = grey
	add_child(_smoke)


func _tip() -> Vector2:
	return FROM + Vector2(LENGTH * left, 0)


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()
	_sparks.emitting = visible and left > 0.0
	_smoke.emitting = visible and left > 0.0


func _draw() -> void:
	var tip := _tip()
	# ash: a thin broken grey line where the cord has burnt
	var x := tip.x + 6.0
	while x < FROM.x + LENGTH:
		draw_line(Vector2(x, FROM.y + 1), Vector2(minf(x + 5.0, FROM.x + LENGTH), FROM.y + 1), Color(0.35, 0.33, 0.3, 0.55), 2.0)
		x += 9.0
	if left <= 0.0:
		return
	# the cord: dark edge, hemp colour, and diagonal twists along it
	draw_line(FROM, tip, Color("2a1d10"), 13.0)
	draw_line(FROM, tip, Color("b08850"), 9.0)
	x = FROM.x
	while x < tip.x - 3.0:
		draw_line(Vector2(x, FROM.y + 4), Vector2(x + 6.0, FROM.y - 4), Color("7a5a30"), 2.5, true)
		draw_line(Vector2(x + 1.5, FROM.y + 3), Vector2(x + 4.5, FROM.y - 2), Color("e2c08a", 0.7), 1.2, true)
		x += 9.0
	# charred end and the ember
	draw_line(tip - Vector2(18, 0), tip, Color("1a1208"), 10.0)
	draw_line(tip - Vector2(8, 0), tip, Color(0.9, 0.3, 0.05, 0.8), 5.0)
	var flick := 0.75 + 0.25 * sin(_t * 23.0) * sin(_t * 7.0)
	draw_circle(tip, 22.0 * flick, Color(1.0, 0.45, 0.05, 0.16))
	draw_circle(tip, 12.0 * flick, Color(1.0, 0.55, 0.1, 0.45))
	draw_circle(tip, 6.5, Color(1.0, 0.8, 0.3))
	draw_circle(tip, 3.2, Color(1.0, 1.0, 0.85))
