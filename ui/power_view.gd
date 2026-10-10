class_name PowerView
extends EntityView
## Hero power button, weapon or secret icon next to a hero.

enum Kind { POWER, WEAPON, SECRET }

var e: Entity
var g: GameState
var kind := Kind.POWER
var face_down := false  # an enemy Secret: show "?" only


static func make(ent: Entity, game: GameState, k: Kind, hide := false) -> PowerView:
	var v := PowerView.new()
	v.e = ent
	v.g = game
	v.kind = k
	v.face_down = hide
	v.entity_id = ent.id
	var s := Vector2(36, 36) if k == Kind.SECRET else Vector2(76, 76)
	v.custom_minimum_size = s
	v.size = s
	return v


func _draw() -> void:
	var c := size / 2
	var r := size.x / 2 - 3
	if glow.a > 0:
		draw_circle(c, r + 5, glow)
	var cls: String = e.card().get("cardClass", "NEUTRAL")
	match kind:
		Kind.SECRET:
			draw_circle(c, r, Palette.of_class(cls) if not face_down else Color("7a5cc7"))
			var font := ThemeDB.fallback_font
			draw_string(font, Vector2(c.x - 6, c.y + 7), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		Kind.POWER:
			var used := e.has("USED")
			draw_circle(c, r, Color("444444") if used else Palette.of_class(cls))
			var inner := Rect2(c - Vector2(r, r) * 0.62, Vector2(r, r) * 1.24)
			_draw_art(inner, e.card_id)
			_draw_stat(Vector2(c.x, 10), g.cost(e), Palette.MANA, Color.WHITE, 11)
			if used:
				draw_circle(c, r, Color(0, 0, 0, 0.5))
		Kind.WEAPON:
			draw_circle(c, r, Color("5a4632"))
			_draw_art(Rect2(c - Vector2(r, r) * 0.62, Vector2(r, r) * 1.24), e.card_id)
			var active := e.controller == g.current
			_draw_stat(Vector2(12, size.y - 12), e.atk(), Palette.ATTACK if active else Color("776a2a"), Color.BLACK, 12)
			_draw_stat(Vector2(size.x - 12, size.y - 12), int(e.tags.get("DURABILITY", 0)), Palette.ARMOR, Color.WHITE, 12)
