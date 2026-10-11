class_name MinionView
extends EntityView
## A minion on the board: an oval portrait with its attack gem and health drop,
## and animated marks for its effects (Taunt, Divine Shield, Windfury, Stealth,
## Frozen, sleep, triggers, Deathrattle, auras, Enrage, Spell Damage, Silence).

const SIZE := Vector2(96, 116)
const OVAL := Rect2(Vector2(12, 8), Vector2(72, 92))

var e: Entity
var g: GameState
var _t := 0.0


static func make(ent: Entity, game: GameState) -> MinionView:
	var v := MinionView.new()
	v.e = ent
	v.g = game
	v.entity_id = ent.id
	v.custom_minimum_size = SIZE
	v.size = SIZE
	return v


func _animated() -> bool:
	var h := Cards.of(e.card_id)
	return e.has("DIVINE_SHIELD") or e.has("WINDFURY") or e.has("STEALTH") or e.has("FROZEN") or _sleeping() \
		or (not e.silenced and (h.has("on") or h.has("aura")))


func _sleeping() -> bool:
	return e.has("EXHAUSTED") and not e.has("CHARGE") and e.controller == g.current


func _process(delta: float) -> void:
	if e and _animated():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var c := e.card()
	var h := Cards.of(e.card_id)
	var oval := Art.outline("oval", OVAL)
	var center := OVAL.get_center()
	if glow.a > 0.0:
		draw_colored_polygon(Art.outline("oval", OVAL.grow(6)), Color(glow, 0.9))
	if e.has("TAUNT"):  # a stone shield behind the portrait
		var s := PackedVector2Array([Vector2(6, 10), Vector2(90, 10), Vector2(88, 64), Vector2(48, 112), Vector2(8, 64)])
		draw_colored_polygon(s, Color("7d7f7d"))
		Frames.ring(self, s, Color("3b3d3b"), 3)
	draw_colored_polygon(Art.outline("oval", OVAL.grow(3)), Color("2a2118"))
	Art.paint_in(self, OVAL, e.card_id, "oval")
	if e.silenced:
		draw_colored_polygon(oval, Color(0.5, 0.5, 0.55, 0.45))
	if e.has("STEALTH"):
		draw_colored_polygon(oval, Color(0.05, 0.05, 0.12, 0.45))
		for i in 6:
			var a := _t * 0.8 + i * 1.1
			draw_circle(center + Vector2(cos(a) * 26, sin(a * 1.3) * 34), 7, Color(0.6, 0.6, 0.8, 0.18))
	if e.has("FROZEN"):
		draw_colored_polygon(oval, Color(0.6, 0.85, 1.0, 0.4))
		for i in 5:
			var p := center + Vector2(cos(i * 1.3) * 30, sin(i * 1.3) * 40)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -9), p + Vector2(4, 0), p + Vector2(0, 9), p + Vector2(-4, 0)]), Color(0.9, 0.97, 1.0, 0.8 + 0.2 * sin(_t * 3 + i)))
	var edge := Frames.GOLD if c.get("rarity", "") == "LEGENDARY" else Color("8a7a5c")
	Frames.ring(self, oval, edge, 3)
	if c.get("rarity", "") == "LEGENDARY":
		Frames.crest(self, Vector2(48, 10), 96)
	if e.has("DIVINE_SHIELD"):  # a shimmering golden bubble
		draw_colored_polygon(Art.outline("oval", OVAL.grow(5)), Color(1, 0.86, 0.3, 0.18))
		Frames.ring(self, Art.outline("oval", OVAL.grow(5)), Color(1, 0.9, 0.4, 0.75 + 0.25 * sin(_t * 4)), 3)
		var a := _t * 1.5
		draw_circle(center + Vector2(cos(a) * 34, sin(a) * 44), 4, Color(1, 1, 0.8, 0.9))
	if e.has("WINDFURY"):  # two swirls circling the portrait
		for k in 2:
			for i in 5:
				var a0 := _t * 3.0 + k * PI + i * 0.25
				var a1 := a0 + 0.22
				draw_line(center + Vector2(cos(a0) * 42, sin(a0) * 52), center + Vector2(cos(a1) * 42, sin(a1) * 52), Color(0.85, 0.95, 1.0, 0.25 + i * 0.15), 3, true)
	if not e.silenced and h.has("aura"):
		Frames.ring(self, Art.outline("oval", OVAL.grow(8 + 2 * sin(_t * 2))), Color(0.5, 0.9, 1.0, 0.45), 2)
	if not e.silenced and c.get("mechanics", []).has("ENRAGED") and e.damage > 0:
		Frames.ring(self, Art.outline("oval", OVAL.grow(4)), Color("ff4d4d"), 3)
	if e.spellpower() > 0 and not e.silenced:
		for i in 3:
			var p := center + Vector2(-20 + i * 20, -40 + 4 * sin(_t * 3 + i))
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(1.5, -1.5), p + Vector2(5, 0), p + Vector2(1.5, 1.5), p + Vector2(0, 5), p + Vector2(-1.5, 1.5), p + Vector2(-5, 0), p + Vector2(-1.5, -1.5)]), Color("e5dbff"))
	var marks := []
	if not e.silenced and h.has("deathrattle"):
		marks.append("deathrattle")
	if not e.silenced and h.has("on"):
		marks.append("trigger")
	if e.silenced:
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
	Frames.attack(self, Vector2(16, 98), e.atk(), 15, Color("8ce99a") if e.atk() > base_atk else Color.WHITE)
	var hp_color := Color.WHITE
	if e.damage > 0:
		hp_color = Color("ff9a9a")
	elif e.max_health() > base_hp:
		hp_color = Color("8ce99a")
	Frames.health(self, Vector2(80, 98), e.health(), 15, hp_color)


## Small status marks under the portrait (vector: the font has no symbol glyphs).
func _draw_icon(kind: String, at: Vector2) -> void:
	var pulse := 1.0 + 0.12 * sin(_t * 4.0)
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
