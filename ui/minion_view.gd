class_name MinionView
extends EntityView
## A minion on the board with its keywords and current stats.

const SIZE := Vector2(96, 116)

var e: Entity
var g: GameState


static func make(ent: Entity, game: GameState) -> MinionView:
	var v := MinionView.new()
	v.e = ent
	v.g = game
	v.entity_id = ent.id
	v.custom_minimum_size = SIZE
	v.size = SIZE
	return v


func _draw() -> void:
	var r := Rect2(Vector2(6, 4), SIZE - Vector2(12, 8))
	_draw_glow(r, 40)
	if e.has("TAUNT"):
		draw_style_box(Palette.box(Color("8a8a8a"), 14, Color("3a3a3a"), 3), r.grow(5))
	var c := e.card()
	var frame := Palette.of_class(c.get("cardClass", "NEUTRAL"))
	draw_style_box(Palette.box(Color("2a2118"), 40), r)
	_draw_art(Rect2(r.position + Vector2(10, 12), r.size - Vector2(20, 24)), e.card_id)
	draw_style_box(Palette.box(Color.TRANSPARENT, 40, frame, 5), r)
	if e.has("DIVINE_SHIELD"):
		draw_style_box(Palette.box(Color(1, 0.85, 0.2, 0.25), 44, Color(1, 0.9, 0.3, 0.9), 3), r.grow(3))
	if e.has("FROZEN"):
		draw_style_box(Palette.box(Color(0.6, 0.85, 1.0, 0.45), 40), r)
	if e.has("STEALTH"):
		draw_style_box(Palette.box(Color(0, 0, 0, 0.45), 40), r)
	var icons := []
	var h := Cards.of(e.card_id)
	if not e.silenced and h.has("deathrattle"):
		icons.append("deathrattle")
	if not e.silenced and (h.has("on") or h.has("aura")):
		icons.append("trigger")
	if e.silenced:
		icons.append("silenced")
	if e.has("EXHAUSTED") and not e.has("CHARGE"):
		icons.append("sleep")
	for i in icons.size():
		_draw_icon(icons[i], Vector2(48 + (i - (icons.size() - 1) / 2.0) * 14, 92))
	var base_atk := int(c.get("attack", 0))
	var base_hp := int(c.get("health", 0))
	_draw_stat(Vector2(16, 100), e.atk(), Palette.ATTACK, Palette.BUFFED if e.atk() > base_atk else Color.BLACK)
	var hp_color := Color.WHITE
	if e.damage > 0:
		hp_color = Color("ff9a9a")
	elif e.max_health() > base_hp:
		hp_color = Palette.BUFFED
	_draw_stat(Vector2(80, 100), e.health(), Palette.HEALTH, hp_color)


## Small status marks under the art (vector: the font has no symbol glyphs).
func _draw_icon(kind: String, c: Vector2) -> void:
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
		"sleep":
			var font := ThemeDB.fallback_font
			draw_string_outline(font, c + Vector2(-4, 5), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color.BLACK)
			draw_string(font, c + Vector2(-4, 5), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.TEXT)
