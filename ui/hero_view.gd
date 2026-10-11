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
	var r := Rect2(Vector2(8, 8), SIZE - Vector2(16, 16))
	_draw_glow(r, 20)
	var cls: String = Decks.card_class(e.card_id) if Decks.HEROES.values().has(e.card_id) else e.card().get("cardClass", "NEUTRAL")
	draw_style_box(Palette.box(Palette.of_class(cls), 20, Color("c9a74a"), 4), r)
	_draw_art(r.grow(-10), e.card_id)
	if e.has("FROZEN"):
		draw_style_box(Palette.box(Color(0.6, 0.85, 1.0, 0.45), 20), r)
	if e.has("IMMUNE"):
		draw_style_box(Palette.box(Color(1, 1, 1, 0.0), 22, Color(1, 0.9, 0.3), 3), r.grow(3))
	_draw_stat(Vector2(112, 112), e.health(), Palette.HEALTH, Color("ff9a9a") if e.damage > 0 else Color.WHITE, 18)
	if int(e.tags.get("ARMOR", 0)) > 0:
		_draw_stat(Vector2(112, 72), int(e.tags.ARMOR), Palette.ARMOR, Color.WHITE, 15)
	var atk := g.hero_atk(e)
	if atk > 0:
		_draw_stat(Vector2(18, 112), atk, Palette.ATTACK, Color.BLACK, 18)
