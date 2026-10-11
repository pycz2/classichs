class_name HeroView
extends EntityView
## A hero portrait with health, armor and attack.

const SIZE := Vector2(130, 130)

var e: Entity
var g: GameState


static func make(ent: Entity, game: GameState) -> HeroView:
	var v := HeroView.new()
	v.e = ent
	v.g = game
	v.entity_id = ent.id
	v.custom_minimum_size = SIZE
	v.size = SIZE
	return v


func _draw() -> void:
	var r := Rect2(Vector2(10, 6), SIZE - Vector2(20, 14))
	var cls: String = Decks.card_class(e.card_id) if Decks.HEROES.values().has(e.card_id) else e.card().get("cardClass", "NEUTRAL")
	var outline := Art.outline("arch", r)
	if glow.a > 0.0:
		draw_colored_polygon(Art.outline("arch", r.grow(6)), Color(glow, 0.9))
	draw_colored_polygon(Art.outline("arch", r.grow(5)), Frames.GOLD.darkened(0.3))
	draw_colored_polygon(Art.outline("arch", r.grow(2)), Palette.of_class(cls).darkened(0.3))
	Art.paint_in(self, r, e.card_id, "arch")
	Frames.ring(self, outline, Frames.GOLD, 3)
	if e.has("FROZEN"):
		draw_colored_polygon(outline, Color(0.6, 0.85, 1.0, 0.45))
	if e.has("IMMUNE"):
		Frames.ring(self, Art.outline("arch", r.grow(4)), Color(1, 0.9, 0.3), 3)
	Icons.paint(self, cls if Icons.CLASSES.has(cls) else "NEUTRAL", Rect2(Vector2(SIZE.x / 2 - 13, SIZE.y - 26), Vector2(26, 26)))
	Frames.health(self, Vector2(112, 108), e.health(), 18, Frames.DAMAGED if e.damage > 0 else Color.WHITE)
	if int(e.tags.get("ARMOR", 0)) > 0:
		Frames.shield(self, Vector2(112, 70), int(e.tags.ARMOR), 15)
	var atk := g.hero_atk(e)
	if atk > 0:
		Frames.attack(self, Vector2(18, 108), atk, 18)
