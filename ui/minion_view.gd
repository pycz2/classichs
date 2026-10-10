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
	var font := ThemeDB.fallback_font
	var icons := ""
	var h := Cards.of(e.card_id)
	if not e.silenced and h.has("deathrattle"):
		icons += "☠"
	if not e.silenced and (h.has("on") or h.has("aura")):
		icons += "⚡"
	if e.silenced:
		icons += "∅"
	if e.has("EXHAUSTED") and not e.has("CHARGE"):
		icons += "z"
	if icons != "":
		draw_string_outline(font, Vector2(30, 98), icons, HORIZONTAL_ALIGNMENT_CENTER, 36, 16, 3, Color.BLACK)
		draw_string(font, Vector2(30, 98), icons, HORIZONTAL_ALIGNMENT_CENTER, 36, 16, Palette.TEXT)
	var base_atk := int(c.get("attack", 0))
	var base_hp := int(c.get("health", 0))
	_draw_stat(Vector2(16, 100), e.atk(), Palette.ATTACK, Palette.BUFFED if e.atk() > base_atk else Color.BLACK)
	var hp_color := Color.WHITE
	if e.damage > 0:
		hp_color = Color("ff9a9a")
	elif e.max_health() > base_hp:
		hp_color = Palette.BUFFED
	_draw_stat(Vector2(80, 100), e.health(), Palette.HEALTH, hp_color)
