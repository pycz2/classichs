class_name PowerView
extends EntityView
## Hero power button, weapon or secret icon next to a hero.

enum Kind { POWER, WEAPON, SECRET }

var e: Entity  # the live entity
var g: GameState
## What the view shows: a copy taken by sync() (see MinionView.s).
var s: Entity
var _cost := 0
var _active := false
var kind := Kind.POWER
var face_down := false  # an enemy Secret: show "?" only
## A used hero power lies face down (it turns over when used and again when ready).
var face_down_used := false


static func make(ent: Entity, game: GameState, k: Kind, hide := false) -> PowerView:
	var v := PowerView.new()
	v.e = ent
	v.g = game
	v.kind = k
	v.face_down = hide
	v.entity_id = ent.id
	var sz := Vector2(36, 36) if k == Kind.SECRET else Vector2(76, 76)
	v.custom_minimum_size = sz
	v.size = sz
	v.s = ent.copy()
	v._cost = game.cost(ent)
	v._active = ent.controller == game.current
	return v


func _draw() -> void:
	var c := size / 2
	var r := size.x / 2 - 4
	if glow.a > 0:
		draw_circle(c, r + 6, glow)
	var cls: String = s.card().get("cardClass", "NEUTRAL")
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
			draw_circle(c, r + 3, Frames.GOLD.darkened(0.3))
			if face_down_used:  # the back: dark stone with the class crest
				draw_circle(c, r, Color("2a2118"))
				var cls_icon: String = cls if Icons.CLASSES.has(cls) else "NEUTRAL"
				Icons.paint(self, cls_icon, Rect2(c - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2))
				draw_circle(c, r, Color(0, 0, 0, 0.35))
				Frames.ring(self, Art.outline("circle", art), Frames.GOLD.darkened(0.4), 3)
			else:
				Art.paint_in(self, art, s.card_id, "circle")
				Frames.ring(self, Art.outline("circle", art), Frames.GOLD, 3)
				Frames.mana(self, Vector2(c.x, 9), _cost, 11)
		Kind.WEAPON:
			draw_circle(c, r + 3, Color("3b2f22"))
			Art.paint_in(self, art, s.card_id, "circle")
			Frames.ring(self, Art.outline("circle", art), Color("8a7a5c"), 3)
			var active := _active
			if not active:
				draw_circle(c, r, Color(0, 0, 0, 0.35))
			Frames.attack(self, Vector2(12, size.y - 12), s.atk(), 12)
			Frames.shield(self, Vector2(size.x - 12, size.y - 12), int(s.tags.get("DURABILITY", 0)), 11)


## Turns the hero power over when it becomes used or ready again (a flip animation).
func sync() -> void:
	s = e.copy()
	_cost = g.cost(e)
	_active = e.controller == g.current
	queue_redraw()
	if kind != Kind.POWER:
		return
	var used := e.has("USED")
	if used == face_down_used:
		return
	if Anim.instant or not is_inside_tree():
		face_down_used = used
		queue_redraw()
		return
	pivot_offset = size / 2.0
	var tw := create_tween()
	tw.tween_property(self, "scale:x", 0.0, Anim.d(0.14))
	tw.tween_callback(func():
		face_down_used = used
		queue_redraw())
	tw.tween_property(self, "scale:x", 1.0, Anim.d(0.14))
