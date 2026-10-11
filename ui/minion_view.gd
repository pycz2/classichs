class_name MinionView
extends EntityView
## A minion on the board: an oval portrait with its attack gem and health drop,
## and animated marks for its effects (Taunt, Divine Shield, Windfury, Stealth,
## Frozen, sleep, triggers, Deathrattle, auras, Enrage, Spell Damage, Silence).

const SIZE := Vector2(96, 116)
const OVAL := Rect2(Vector2(12, 8), Vector2(72, 92))

var e: Entity  # the live entity
var g: GameState
## What the view shows: a copy taken by sync() (the table syncs its views when an
## animation reaches the moment of the change, e.g. the hit, not before).
var s: Entity
var _current := -1
var _t := 0.0


static func make(ent: Entity, game: GameState) -> MinionView:
	var v := MinionView.new()
	v.e = ent
	v.g = game
	v.entity_id = ent.id
	v.custom_minimum_size = SIZE
	v.size = SIZE
	v.sync()
	return v


func sync() -> void:
	var b := s
	s = e.copy()
	if b:
		if b.atk() != s.atk():
			pop("atk")
		if b.health() != s.health():
			pop("hp")
	_current = g.current
	queue_redraw()


func _animated() -> bool:
	var h := Cards.of(s.card_id)
	return glow.a > 0.0 or s.silenced or s.spellpower() > 0 or s.has("DIVINE_SHIELD") or s.has("WINDFURY") or s.has("IMMUNE") or s.has("STEALTH") or s.has("FROZEN") or _sleeping() \
		or (not s.silenced and (h.has("on") or h.has("aura")))


func _sleeping() -> bool:
	return s.has("EXHAUSTED") and not s.has("CHARGE") and s.controller == _current


func _process(delta: float) -> void:
	super(delta)
	if s and _animated():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var c := s.card()
	var h := Cards.of(s.card_id)
	var oval := Art.outline("oval", OVAL)
	var center := OVAL.get_center()
	var gl := shown_glow()
	if gl.a > 0.0:  # always outside everything else on it
		var taunt := s.has("TAUNT")
		var reach := _reach()
		soft_glow(self, func(gr: float) -> PackedVector2Array:
			return _scaled(taunt_shield(), center, 1.0 + gr / 44.0) if taunt else Art.outline("oval", OVAL.grow(reach + gr)), gl)
	if s.has("WINDFURY"):
		_wind(false)  # the half of the swirl behind the card
	if s.has("TAUNT"):  # a stone and iron shield behind the portrait
		if not Sprites.draw(self, "taunt_shield", TAUNT_RECT.get_center(), TAUNT_RECT.size.x):
			var shield := taunt_shield()
			draw_colored_polygon(shield, Color("7d7f7d"))
			Frames.ring(self, shield, Color("3b3d3b"), 3)
	draw_colored_polygon(Art.outline("oval", OVAL.grow(3)), Color("2a2118"))
	Art.paint_in(self, OVAL, s.card_id, "oval")
	if s.silenced:
		draw_colored_polygon(oval, Color(0.45, 0.35, 0.5, 0.18))
	if s.has("STEALTH"):  # drifting smoke: two layers of noise moving apart; the portrait shows faintly
		var uv := _oval_uv(oval)
		draw_colored_polygon(oval, Color(0.1, 0.09, 0.16, 0.3))
		draw_colored_polygon(oval, Color(0.62, 0.58, 0.75, 0.5), _shift(uv, Vector2(_t * 0.05, _t * 0.02)), _smoke())
		draw_colored_polygon(oval, Color(0.4, 0.38, 0.52, 0.4), _shift(uv, Vector2(-_t * 0.03, 0.4 + _t * 0.04)), _smoke())
	if s.has("FROZEN"):  # a sheet of frost over the portrait, an icy rim, a cold shimmer
		var ice := Sprites.get_tex("ice")
		if ice:
			draw_colored_polygon(oval, Color(0.85, 0.95, 1.0, 0.55), _oval_uv(oval), ice)
		else:
			draw_colored_polygon(oval, Color(0.6, 0.85, 1.0, 0.45))
		draw_colored_polygon(oval, Color(0.55, 0.8, 1.0, 0.15 + 0.08 * sin(_t * 2.0)))
		Frames.ring(self, Art.outline("oval", OVAL.grow(1)), Color(0.85, 0.96, 1.0, 0.95), 4)
	var edge := Frames.GOLD if c.get("rarity", "") == "LEGENDARY" else Color("8a7a5c")
	Frames.ring(self, oval, edge, 3)
	if s.silenced:
		_silence_ribbons()
	if c.get("rarity", "") == "LEGENDARY":
		Frames.crest_around(self, OVAL.grow(2), 15, PI + PI / 6.0, TAU - PI / 6.0)  # around the top quarter of the oval
	if s.has("IMMUNE"):  # a white light around it with sparks turning (not the golden bubble)
		var halo := Art.outline("oval", OVAL.grow(9))
		draw_colored_polygon(halo, Color(1, 1, 1, 0.16 + 0.08 * sin(_t * 5)))
		Frames.ring(self, halo, Color(1, 1, 1, 0.85), 2.5)
		for i in 4:
			var a := -_t * 2.0 + i * TAU / 4.0
			var p := center + Vector2(cos(a) * 44, sin(a) * 54)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(1.5, -1.5), p + Vector2(6, 0), p + Vector2(1.5, 1.5), p + Vector2(0, 6), p + Vector2(-1.5, 1.5), p + Vector2(-6, 0), p + Vector2(-1.5, -1.5)]), Color(1, 1, 0.92))
	if s.has("DIVINE_SHIELD"):  # a shimmering golden bubble
		draw_colored_polygon(Art.outline("oval", OVAL.grow(5)), Color(1, 0.86, 0.3, 0.18))
		Frames.ring(self, Art.outline("oval", OVAL.grow(5)), Color(1, 0.9, 0.4, 0.75 + 0.25 * sin(_t * 4)), 3)
		var a := _t * 1.5
		draw_circle(center + Vector2(cos(a) * 34, sin(a) * 44), 4, Color(1, 1, 0.8, 0.9))
	if s.has("WINDFURY"):
		_wind(true)  # the half of the swirl in front of the card
	if not s.silenced and h.has("aura"):
		Frames.ring(self, Art.outline("oval", OVAL.grow(8 + 2 * sin(_t * 2))), Color(0.5, 0.9, 1.0, 0.45), 2)
	if not s.silenced and KeywordTips.keywords_of(s.card_id).has("ENRAGED") and s.damage > 0:
		Frames.ring(self, Art.outline("oval", OVAL.grow(4)), Color("ff4d4d"), 3)
	if s.spellpower() > 0 and not s.silenced:
		for i in 3:
			var p := center + Vector2(-20 + i * 20, -40 + 4 * sin(_t * 3 + i))
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(1.5, -1.5), p + Vector2(5, 0), p + Vector2(1.5, 1.5), p + Vector2(0, 5), p + Vector2(-1.5, 1.5), p + Vector2(-5, 0), p + Vector2(-1.5, -1.5)]), Color("e5dbff"))
	var marks := []
	if not s.silenced and h.has("deathrattle"):
		marks.append("deathrattle")
	if not s.silenced and KeywordTips.keywords_of(s.card_id).has("POISONOUS"):
		marks.append("poison")
	elif not s.silenced and h.has("on"):
		marks.append("trigger")
	if s.silenced:
		marks.append("silenced")
	for i in marks.size():
		_draw_icon(marks[i], Vector2(48 + (i - (marks.size() - 1) / 2.0) * 18, 98))
	if _sleeping():
		var font := ThemeDB.fallback_font
		for i in 3:
			var ph := fmod(_t * 0.6 + i / 3.0, 1.0)
			var p := Vector2(60 + ph * 16, 50 - ph * 40)
			var fs := 12 + i * 3
			draw_string_outline(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 1.0 - ph))
			draw_string(font, p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 1.0 - ph))
	var base_atk := int(c.get("attack", 0))
	var base_hp := int(c.get("health", 0))
	Frames.attack(self, Vector2(16, 98), s.atk(), 15 * bump("atk"), Frames.BUFFED if s.atk() > base_atk else Color.WHITE)
	var hp_color := Color.WHITE
	if s.damage > 0:
		hp_color = Frames.DAMAGED
	elif s.max_health() > base_hp:
		hp_color = Frames.BUFFED
	Frames.health(self, Vector2(80, 98), s.health(), 15 * bump("hp"), hp_color)


## Where the Taunt shield picture goes (behind the oval, a little wider and longer).
const TAUNT_RECT := Rect2(Vector2(2, 1), Vector2(92, 114))


## The Taunt shield's outline (for the glow and when there is no picture): a flat
## top, straight sides, then curving in to a point under the portrait.
static func taunt_shield() -> PackedVector2Array:
	var r := TAUNT_RECT
	var out := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y)])
	var side := r.position.y + r.size.y * 0.42
	for i in 13:  # the right side down to the point, then the left side up
		var t := i / 12.0
		out.append(Vector2(lerpf(r.end.x, r.get_center().x, t * t), lerpf(side, r.end.y, sin(t * PI / 2.0))))
	for i in range(11, -1, -1):
		var t := i / 12.0
		out.append(Vector2(lerpf(r.position.x, r.get_center().x, t * t), lerpf(side, r.end.y, sin(t * PI / 2.0))))
	return out


static func _scaled(pts: PackedVector2Array, c: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c) * k)
	return out


## How far out of the oval the effects on it reach (the glow starts there).
func _reach() -> float:
	if s.has("IMMUNE"):
		return 9.0
	if Cards.of(s.card_id).has("aura") and not s.silenced:
		return 9.0
	if s.has("DIVINE_SHIELD"):
		return 6.0
	return 3.0


## Silence: glowing magenta ribbons wound around the portrait, slowly turning.
func _silence_ribbons() -> void:
	var c := OVAL.get_center()
	for k in 3:  # three soft wisps sweeping across the portrait at different slants
		var tilt := Transform2D(-0.6 + k * 0.55 + 0.12 * sin(_t * 0.8 + k * 2.0), Vector2.ZERO)
		var rx := 46.0 - k * 4.0
		var ry := 20.0 + k * 6.0
		var start := _t * (0.7 + 0.15 * k) + k * 2.1
		var pts := PackedVector2Array()
		var n := 22
		for i in n:  # about half an ellipse, wavering a little
			var a := start + i * 0.15
			var wob := 1.0 + 0.06 * sin(a * 3.0 + _t * 2.0)
			pts.append(c + tilt * Vector2(cos(a) * rx * wob, sin(a) * ry * wob))
		for i in n - 1:  # thin at both ends, widest in the middle
			var f := sin(PI * i / float(n - 1))
			draw_line(pts[i], pts[i + 1], Color(1.0, 0.2, 0.7, 0.25 * f), 10.0 * f + 1.0, true)
			draw_line(pts[i], pts[i + 1], Color(1.0, 0.45, 0.85, 0.65 * f), 4.0 * f + 0.5, true)
			draw_line(pts[i], pts[i + 1], Color(1.0, 0.9, 0.98, 0.95 * f), 1.5 * f + 0.3, true)


## Windfury: two gusts on a tilted orbit (like a planet's, at 45 degrees), passing
## behind the card and in front of it.
func _wind(front: bool) -> void:
	var c := OVAL.get_center()
	var tilt := Transform2D(-PI / 4.0, Vector2.ZERO)
	for k in 2:
		for i in 9:
			var a0 := _t * 2.5 + k * PI + i * 0.12
			var a1 := a0 + 0.13
			if (sin(a0) > 0.0) != front:  # the lower half of the orbit is nearer the viewer
				continue
			var p0 := c + tilt * Vector2(cos(a0) * 54, sin(a0) * 18)
			var p1 := c + tilt * Vector2(cos(a1) * 54, sin(a1) * 18)
			var depth := 0.6 + 0.4 * sin(a0)
			draw_line(p0, p1, Color(0.88, 0.96, 1.0, (0.15 + i * 0.09) * depth), 2.0 + 2.5 * depth, true)


## Texture coordinates for a shape: its bounding box mapped to 0..1.
static func _oval_uv(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append((p - OVAL.position) / OVAL.size)
	return out


static func _shift(uv: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in uv:
		out.append(p + by)
	return out


static var _smoke_tex: NoiseTexture2D


## A soft seamless noise for the Stealth smoke (made once).
static func _smoke() -> Texture2D:
	if _smoke_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_PERLIN
		n.frequency = 0.012
		n.fractal_octaves = 4
		_smoke_tex = NoiseTexture2D.new()
		_smoke_tex.width = 128
		_smoke_tex.height = 128
		_smoke_tex.seamless = true
		_smoke_tex.noise = n
	return _smoke_tex


## Small status marks under the portrait (vector: the font has no symbol glyphs).
func _draw_icon(kind: String, at: Vector2) -> void:
	var w: float = {"trigger": 9.0, "poison": 12.0}.get(kind, 16.0)
	var bob := bump("mark") if kind in ["trigger", "poison"] else 1.0 + 0.08 * sin(_t * 4.0)  # still; they pop when they go off
	var tint := Color(0.5, 1.0, 0.35) if kind == "poison" else Color.WHITE  # (green can't survive the green-screen cut)
	if Sprites.draw(self, kind, at + Vector2(0, -1), w * bob, 0.0, tint):
		return
	var pulse := bump("mark") if kind in ["trigger", "poison"] else 1.0 + 0.12 * sin(_t * 4.0)
	draw_set_transform(at, 0.0, Vector2(1.4, 1.4) * pulse)
	var c := Vector2.ZERO
	match kind:
		"deathrattle":
			draw_circle(c, 6, Color.BLACK)
			draw_circle(c, 5, Color("f1f3f5"))
			draw_circle(c + Vector2(-2, -1), 1.4, Color.BLACK)
			draw_circle(c + Vector2(2, -1), 1.4, Color.BLACK)
		"trigger":
			var bolt := PackedVector2Array([c + Vector2(1, -7), c + Vector2(-4, 1), c + Vector2(0, 1), c + Vector2(-1, 7), c + Vector2(4, -1), c + Vector2(0, -1)])
			draw_colored_polygon(bolt, Color("ffd43b"))
			draw_polyline(bolt + PackedVector2Array([bolt[0]]), Color.BLACK, 1.0)
		"silenced":
			draw_arc(c, 5, 0, TAU, 16, Color("ff6b6b"), 2.0)
			draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), Color("ff6b6b"), 2.0)
	draw_set_transform(Vector2.ZERO)
