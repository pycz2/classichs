class_name PowerView
extends EntityView
## Hero power button, weapon or secret icon next to a hero.

enum Kind { POWER, WEAPON, SECRET }

const SECRET_COLORS := {"MAGE": Color("9b4dff"), "HUNTER": Color("2fb344"), "PALADIN": Color("f2c230")}

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
		soft_glow(self, func(gr: float) -> PackedVector2Array: return Art.outline("circle", Rect2(c - Vector2(r, r) - Vector2(gr, gr), Vector2(r, r) * 2 + Vector2(gr, gr) * 2)), glow)
	var cls: String = s.card().get("cardClass", "NEUTRAL")
	var art := Rect2(c - Vector2(r, r) * 0.86, Vector2(r, r) * 1.72)
	match kind:
		Kind.SECRET:  # a round gem in the class's colour (the opponent sees it too, with a "?")
			var col: Color = SECRET_COLORS.get(cls, Color("7048e8"))
			draw_circle(c + Vector2(0, 2), r + 2, Color(0, 0, 0, 0.45))
			draw_circle(c, r + 1.5, Frames.GOLD.darkened(0.2))
			draw_circle(c, r - 0.5, col.darkened(0.4))
			draw_circle(c + Vector2(0, -r * 0.1), r * 0.8, col)
			draw_circle(c + Vector2(-r * 0.3, -r * 0.35), r * 0.28, Color(1, 1, 1, 0.55))
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
			Frames.attack(self, Vector2(12, size.y - 12), s.atk(), 12 * bump("atk"))
			Frames.shield(self, Vector2(size.x - 12, size.y - 12), int(s.tags.get("DURABILITY", 0)), 11 * bump("hp"), Color.WHITE, "durability")


## Turns the hero power over when it becomes used or ready again (a flip animation).
func sync() -> void:
	var b := s
	s = e.copy()
	if b and kind == Kind.WEAPON:
		if b.atk() != s.atk():
			pop("atk")
		if int(b.tags.get("DURABILITY", 0)) != int(s.tags.get("DURABILITY", 0)):
			pop("hp")
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
