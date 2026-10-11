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
	var r := size.x / 2 - 4
	if glow.a > 0:
		draw_circle(c, r + 6, glow)
	var cls: String = e.card().get("cardClass", "NEUTRAL")
	var art := Rect2(c - Vector2(r, r) * 0.86, Vector2(r, r) * 1.72)
	match kind:
		Kind.SECRET:
			var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.85, 0), c + Vector2(0, r), c + Vector2(-r * 0.85, 0)])
			draw_colored_polygon(pts, Color("7048e8") if face_down else Palette.of_class(cls))
			Frames.ring(self, pts, Frames.GOLD, 2)
			var font := ThemeDB.fallback_font
			draw_string_outline(font, Vector2(c.x - 5, c.y + 7), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 3, Color.BLACK)
			draw_string(font, Vector2(c.x - 5, c.y + 7), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		Kind.POWER:
			var used := e.has("USED")
			draw_circle(c, r + 3, Frames.GOLD.darkened(0.3))
			Art.paint_in(self, art, e.card_id, "circle")
			Frames.ring(self, Art.outline("circle", art), Frames.GOLD, 3)
			if used:
				draw_circle(c, r, Color(0.1, 0.1, 0.1, 0.65))
			else:
				Frames.mana(self, Vector2(c.x, 9), g.cost(e), 11)
		Kind.WEAPON:
			draw_circle(c, r + 3, Color("3b2f22"))
			Art.paint_in(self, art, e.card_id, "circle")
			Frames.ring(self, Art.outline("circle", art), Color("8a7a5c"), 3)
			var active := e.controller == g.current
			if not active:
				draw_circle(c, r, Color(0, 0, 0, 0.35))
			Frames.attack(self, Vector2(12, size.y - 12), e.atk(), 12)
			Frames.shield(self, Vector2(size.x - 12, size.y - 12), int(e.tags.get("DURABILITY", 0)), 11)
