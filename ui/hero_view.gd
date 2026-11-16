class_name HeroView
extends EntityView
## A hero portrait with health, armor and attack.

const SIZE := Vector2(130, 130)

var e: GameView.Ent  # the live entity
var g: GameView
## What the view shows: a copy taken by sync() (see MinionView.s).
var s: GameView.Ent
var _atk := 0


static func make(ent: GameView.Ent, game: GameView) -> HeroView:
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


const PORTRAIT := Rect2(Vector2(10, 6), SIZE - Vector2(20, 14))
const FROST_AREA := Rect2(Vector2(8, 4), SIZE - Vector2(16, 10))
static var _frost_mat: ShaderMaterial
## The ice over a Frozen hero (frost.gdshader, MinionView.set_frost), null when it is not frozen.
var frost: ColorRect


static func _frost_material() -> ShaderMaterial:
	if _frost_mat == null:
		var o := FROST_AREA.position
		_frost_mat = ShaderMaterial.new()
		_frost_mat.shader = MinionView.FROST_SHADER
		_frost_mat.set_shader_parameter("size", FROST_AREA.size)
		_frost_mat.set_shader_parameter("arch", 1.0)
		_frost_mat.set_shader_parameter("center", PORTRAIT.get_center() - o)
		_frost_mat.set_shader_parameter("radii", Vector2(PORTRAIT.size.x / 2.0, PORTRAIT.size.x * 0.3))  # (Art.outline's arch)
		_frost_mat.set_shader_parameter("box", Vector4(PORTRAIT.position.x - o.x, PORTRAIT.position.y - o.y, PORTRAIT.end.x - o.x, PORTRAIT.end.y - o.y))
		_frost_mat.set_shader_parameter("hole_a", Vector3(112 - o.x, 108 - o.y, 19))  # the gems stay clear
		_frost_mat.set_shader_parameter("hole_b", Vector3(18 - o.x, 108 - o.y, 19))
		_frost_mat.set_shader_parameter("cell", 15.0)
	return _frost_mat


func _process(delta: float) -> void:
	super(delta)
	frost = MinionView.set_frost(self, frost, s != null and s.has("FROZEN"), _frost_material(), FROST_AREA)


func _draw() -> void:
	var r := PORTRAIT
	var cls: String = Decks.card_class(s.card_id) if Decks.heroes().values().has(s.card_id) else s.card().get("cardClass", "NEUTRAL")
	var outline := Art.outline("arch", r)
	var gl := shown_glow()
	if outer_mark().a > 0.0:  # under the own glow: the glows are filled shapes
		soft_glow(self, func(gr: float) -> PackedVector2Array: return Art.outline("arch", r.grow(MARK_OUT + gr * 1.3)), outer_mark())
	if gl.a > 0.0:  # drawn twice: a hero's light must stand out on the dark table
		for i in (2 if glow.a > 0.0 else 1):
			soft_glow(self, func(gr: float) -> PackedVector2Array: return Art.outline("arch", r.grow(1.0 + gr * 1.3)), gl)
	draw_colored_polygon(Art.outline("arch", r.grow(5)), Frames.GOLD.darkened(0.3))
	draw_colored_polygon(Art.outline("arch", r.grow(2)), Palette.of_class(cls).darkened(0.3))
	Art.paint_in(self, r, s.card_id, "arch")
	Frames.ring(self, outline, Frames.GOLD, 3)
	if s.has("IMMUNE"):
		Frames.ring(self, Art.outline("arch", r.grow(4)), Color(1, 0.9, 0.3), 3)
	if s.has("ELUSIVE"):  # spells and hero powers can't pick it (Kobold Monk): a golden haze, as on an Elusive minion
		draw_colored_polygon(outline, Color(1.0, 0.85, 0.3, 0.22))
		Frames.ring(self, Art.outline("arch", r.grow(1)), Color(1.0, 0.85, 0.35, 0.8), 2.5)
	Icons.paint(self, cls if Icons.CLASSES.has(cls) else "NEUTRAL", Rect2(Vector2(SIZE.x / 2 - 13, SIZE.y - 26), Vector2(26, 26)))
	Frames.health(self, Vector2(112, 108), s.health(), 18 * bump("hp"), Frames.DAMAGED if s.damage > 0 else Color.WHITE)
	if int(s.tags.get("ARMOR", 0)) > 0:
		Frames.shield(self, Vector2(112, 70), int(s.tags.ARMOR), 15 * bump("armor"))
	var atk := g.hero_atk(e)
	if atk > 0:
		Frames.attack(self, Vector2(18, 108), atk, 18 * bump("atk"))
