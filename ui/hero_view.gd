class_name HeroView
extends EntityView
## A hero portrait with health, armor and attack.

const SIZE := Vector2(130, 130)

var e: Entity  # the live entity
var g: GameState
## What the view shows: a copy taken by sync() (see MinionView.s).
var s: Entity
var _atk := 0


static func make(ent: Entity, game: GameState) -> HeroView:
	var v := HeroView.new()
	v.e = ent
	v.g = game
	v.entity_id = ent.id
	v.custom_minimum_size = SIZE
	v.size = SIZE
	v.sync()
	return v


func sync() -> void:
	var b := s
	var b_atk := _atk
	s = e.copy()
	_atk = g.hero_atk(e)
	if b:
		if b.health() != s.health():
			pop("hp")
		if int(b.tags.get("ARMOR", 0)) != int(s.tags.get("ARMOR", 0)):
			pop("armor")
		if b_atk != _atk:
			pop("atk")
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2(10, 6), SIZE - Vector2(20, 14))
	var cls: String = Decks.card_class(s.card_id) if Decks.HEROES.values().has(s.card_id) else s.card().get("cardClass", "NEUTRAL")
	var outline := Art.outline("arch", r)
	var gl := shown_glow()
	if gl.a > 0.0:  # drawn twice: a hero's light must stand out on the dark table
		for i in (2 if glow.a > 0.0 else 1):
			soft_glow(self, func(gr: float) -> PackedVector2Array: return Art.outline("arch", r.grow(1.0 + gr * 1.3)), gl)
	draw_colored_polygon(Art.outline("arch", r.grow(5)), Frames.GOLD.darkened(0.3))
	draw_colored_polygon(Art.outline("arch", r.grow(2)), Palette.of_class(cls).darkened(0.3))
	Art.paint_in(self, r, s.card_id, "arch")
	Frames.ring(self, outline, Frames.GOLD, 3)
	if s.has("FROZEN"):  # frost over the portrait and an icy rim
		var ice := Sprites.get_tex("ice")
		if ice:
			var uv := PackedVector2Array()
			for p in outline:
				uv.append((p - r.position) / r.size)
			draw_colored_polygon(outline, Color(0.85, 0.95, 1.0, 0.55), uv, ice)
		else:
			draw_colored_polygon(outline, Color(0.6, 0.85, 1.0, 0.45))
		Frames.ring(self, outline, Color(0.85, 0.96, 1.0, 0.95), 4)
	if s.has("IMMUNE"):
		Frames.ring(self, Art.outline("arch", r.grow(4)), Color(1, 0.9, 0.3), 3)
	Icons.paint(self, cls if Icons.CLASSES.has(cls) else "NEUTRAL", Rect2(Vector2(SIZE.x / 2 - 13, SIZE.y - 26), Vector2(26, 26)))
	Frames.health(self, Vector2(112, 108), s.health(), 18 * bump("hp"), Frames.DAMAGED if s.damage > 0 else Color.WHITE)
	if int(s.tags.get("ARMOR", 0)) > 0:
		Frames.shield(self, Vector2(112, 70), int(s.tags.ARMOR), 15 * bump("armor"))
	var atk := g.hero_atk(e)
	if atk > 0:
		Frames.attack(self, Vector2(18, 108), atk, 18 * bump("atk"))
