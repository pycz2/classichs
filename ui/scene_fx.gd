class_name SceneFx
extends RefCounted
## Scene effects a pack names (docs/packs/format.md §12): particles over a whole 1280x720 screen.
## A spec is a name ("rain") or {"effect": name, "intensity": 0.1–3 (1), "colors": ["rrggbb", …]}.
## The menu (theme `menu.particles`), the tutorial's screens and its missions' tables play them.

const NAMES := ["embers", "rain", "snow"]


## The effect's node to add to a screen, or null for "none", nothing or an unknown name.
static func make(spec: Variant) -> CPUParticles2D:
	var d: Dictionary = spec if spec is Dictionary else {"effect": spec}
	var p: CPUParticles2D
	match str(d.get("effect", "")):
		"embers": p = _embers()
		"rain": p = _rain()
		"snow": p = _snow()
		_: return null
	p.name = "SceneFx"
	p.amount = maxi(1, int(p.amount * clampf(float(d.get("intensity", 1.0)), 0.1, 3.0)))
	var cols: Array = d.get("colors", []) if d.get("colors") is Array else []
	if not cols.is_empty():
		var ramp := Gradient.new()
		ramp.set_color(0, Color(Color.from_string(str(cols[0]), Color.WHITE), 0.0))
		for i in cols.size():
			ramp.add_point(0.15 + 0.7 * i / maxf(1.0, cols.size() - 1.0), Color(Color.from_string(str(cols[i]), Color.WHITE), 0.85))
		ramp.set_color(ramp.get_point_count() - 1, Color(Color.from_string(str(cols[-1]), Color.WHITE), 0.0))
		p.color_ramp = ramp
	p.emitting = not Anim.instant
	return p


static func _sheet(at: Vector2, amount: int, life: float, dir: Vector2, speed: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(760, 10)
	p.direction = dir
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	return p


## Embers drifting up from the bottom of the screen.
static func _embers() -> CPUParticles2D:
	var p := _sheet(Vector2(640, 740), 46, 9.0, Vector2(0, -1), Vector2(30, 70))
	p.emission_rect_extents = Vector2(680, 10)
	p.spread = 18.0
	p.gravity = Vector2(0, -6)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.7, 0.3, 0.9))
	ramp.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
	p.color_ramp = ramp
	return p


## Thin streaks of rain in the theme's accent colours, falling at a slant.
static func _rain() -> CPUParticles2D:
	var p := _sheet(Vector2(700, -40), 160, 1.6, Vector2(-0.18, 1), Vector2(520, 760))
	p.preprocess = 2.0
	p.spread = 2.0
	p.gravity = Vector2.ZERO
	p.particle_flag_align_y = true
	var img := Image.create(2, 40, false, Image.FORMAT_RGBA8)
	for y in 40:
		for x in 2:
			img.set_pixel(x, y, Color(1, 1, 1, float(y) / 39.0))
	p.texture = ImageTexture.create_from_image(img)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(Palette.ATTACK, 0.0))
	ramp.add_point(0.15, Color(Palette.ATTACK, 0.8))
	ramp.add_point(0.6, Color(Palette.tc("button_border", Palette.ATTACK), 0.7))
	ramp.set_color(ramp.get_point_count() - 1, Color(Palette.ATTACK, 0.0))
	p.color_ramp = ramp
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	return p


## Soft flakes drifting down and sideways.
static func _snow() -> CPUParticles2D:
	var p := _sheet(Vector2(640, -20), 90, 12.0, Vector2(0.1, 1), Vector2(30, 70))
	p.spread = 25.0
	p.gravity = Vector2(4, 6)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.1, Color(0.95, 0.97, 1.0, 0.85))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.9, 0.95, 1.0, 0.0))
	p.color_ramp = ramp
	return p
