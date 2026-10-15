class_name TableFx
extends Control
## A short effect on the table where something happens to a minion or a hero:
## a burst for damage, sparkles for healing, rising arrows for a buff, ice for a
## freeze, a closing ring for Silence, smoke for a transform, a portal for a
## summon, a skull for a Deathrattle, a flare for a Battlecry and so on.

const LIFE := {"hurt": 0.55, "heal": 0.8, "buff": 0.8, "debuff": 0.7, "gain": 0.6, "freeze": 0.8,
	"silence": 0.7, "smoke": 0.8, "destroy": 0.7, "portal": 0.8, "skull": 1.1, "battlecry": 0.6,
	"whoosh": 0.6, "control": 0.8, "armor": 0.7}
## The colour of an effect when its card has no element of its own.
const COLORS := {"hurt": Color("ff7b2e"), "heal": Color("8ce99a"), "buff": Color("ffd43b"), "debuff": Color("b197fc"),
	"gain": Color("ffffff"), "freeze": Color("a5d8ff"), "silence": Color("b197fc"), "smoke": Color("f783ac"),
	"destroy": Color("343a40"), "portal": Color("ffd43b"), "skull": Color("f1f3f5"), "battlecry": Color("ffd43b"),
	"whoosh": Color("ffffff"), "control": Color("9775fa"), "armor": Color("ced4da")}

var kind := "hurt"
var color := Color.WHITE
var t := 0.0  # 0..1 over the effect's life
var _life := 0.6


## Starts an effect centred at at (the table's layer is the parent).
static func spawn(parent: Node, kind_name: String, at: Vector2, col := Color.TRANSPARENT) -> TableFx:
	var fx := TableFx.new()
	fx.kind = kind_name
	fx.color = col if col.a > 0.0 else COLORS.get(kind_name, Color.WHITE)
	fx.position = at
	fx._life = maxf(0.01, Anim.d(LIFE.get(kind_name, 0.6)))
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.z_index = 70
	parent.add_child(fx)
	return fx


func _process(delta: float) -> void:
	t += delta / _life
	if t >= 1.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var fade := 1.0 - t
	match kind:
		"hurt":  # a burst with sparks flying out
			draw_circle(Vector2.ZERO, 10 + 40 * t, Color(color, 0.35 * fade))
			for i in 10:
				var a := i * TAU / 10.0 + 0.3
				var d := Vector2(cos(a), sin(a))
				draw_line(d * (8 + 30 * t), d * (16 + 52 * t), Color(color.lightened(0.3), fade), 3, true)
		"heal", "buff":  # rising sparkles / arrows
			for i in 8:
				var x := (i - 3.5) * 10.0
				var y := 30 - 70 * fmod(t + i * 0.13, 1.0)
				if kind == "heal":
					_star(Vector2(x, y), 4 + 2 * (i % 2), Color(color, fade))
				else:
					draw_colored_polygon(PackedVector2Array([Vector2(x, y - 7), Vector2(x + 5, y), Vector2(x - 5, y)]), Color(color, fade))
			draw_circle(Vector2.ZERO, 46, Color(color, 0.18 * fade))
		"debuff":  # arrows sinking
			for i in 6:
				var x := (i - 2.5) * 12.0
				var y := -30 + 60 * fmod(t + i * 0.17, 1.0)
				draw_colored_polygon(PackedVector2Array([Vector2(x, y + 7), Vector2(x + 5, y), Vector2(x - 5, y)]), Color(color, fade))
		"gain", "battlecry":  # a bright ring opening out
			draw_arc(Vector2.ZERO, 20 + 40 * t, 0, TAU, 48, Color(color, fade), 5 * fade + 1, true)
			draw_circle(Vector2.ZERO, 30 * (1.0 - t), Color(color, 0.3 * fade))
		"freeze":  # ice shards
			for i in 8:
				var a := i * TAU / 8.0
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x)
				var r := 18 + 28 * t
				draw_colored_polygon(PackedVector2Array([d * r * 0.4 + n * 4, d * r, d * r * 0.4 - n * 4]), Color(color, fade))
			draw_circle(Vector2.ZERO, 40, Color(color, 0.25 * fade))
		"silence":  # a ring closing in
			draw_arc(Vector2.ZERO, 60 * (1.0 - t) + 6, 0, TAU, 48, Color(color, fade), 4, true)
			draw_arc(Vector2.ZERO, 40 * (1.0 - t) + 4, 0, TAU, 48, Color(color, 0.6 * fade), 2, true)
		"smoke", "destroy", "whoosh":  # puffs drifting apart (rising for whoosh)
			for i in 7:
				var a := i * TAU / 7.0
				var p := Vector2(cos(a), sin(a)) * 30 * t
				if kind == "whoosh":
					p.y -= 60 * t
				draw_circle(p, 16 + 10 * t, Color(color, 0.55 * fade))
		"portal":  # a golden ring with turning sparks
			draw_arc(Vector2.ZERO, 44, 0, TAU, 48, Color(color, fade), 4, true)
			for i in 6:
				var a := t * 6.0 + i * TAU / 6.0
				_star(Vector2(cos(a) * 44, sin(a) * 54), 4, Color(color.lightened(0.4), fade))
		"skull":  # a Deathrattle: the minion's skull mark grows and rises out of it, then fades
			var tex := Sprites.get_tex("deathrattle")
			if tex:
				var w := 16.0 + 70.0 * sin(t * PI / 2.0)
				var h := w * tex.get_height() / float(tex.get_width())
				var at := Vector2(0, 40 - 70 * t)
				draw_texture_rect(tex, Rect2(at - Vector2(w, h) / 2.0, Vector2(w, h)), false, Color(1, 1, 1, minf(1.0, fade * 1.6)))
				return
			var p := Vector2(0, -20 * t)
			draw_circle(p, 14, Color(0, 0, 0, fade))
			draw_circle(p, 12, Color(color, fade))
			draw_circle(p + Vector2(-4, -2), 3, Color(0, 0, 0, fade))
			draw_circle(p + Vector2(4, -2), 3, Color(0, 0, 0, fade))
			draw_rect(Rect2(p + Vector2(-5, 7), Vector2(10, 5)), Color(color, fade))
		"control":  # a swirl
			for i in 12:
				var a := t * 8.0 + i * 0.5
				draw_circle(Vector2(cos(a), sin(a)) * (10 + i * 3.5), 3, Color(color, fade))
		"armor":  # a grey shield popping up
			var s := 1.0 + 0.3 * sin(t * PI)
			var pts := PackedVector2Array([Vector2(-14, -16), Vector2(14, -16), Vector2(12, 4), Vector2(0, 18), Vector2(-12, 4)])
			for i in pts.size():
				pts[i] *= s
			draw_colored_polygon(pts, Color(color, fade))
			Frames.ring(self, pts, Color(0.2, 0.2, 0.2, fade), 2)


func _star(p: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.3, -r * 0.3), p + Vector2(r, 0), p + Vector2(r * 0.3, r * 0.3),
		p + Vector2(0, r), p + Vector2(-r * 0.3, r * 0.3), p + Vector2(-r, 0), p + Vector2(-r * 0.3, -r * 0.3)]), col)


## What happened to an entity between what its view shows (before) and now:
## the effect kinds to play on it.
static func kinds(before: GameView.Ent, now: GameView.Ent) -> Array:
	var out := []
	if before == null or now == null:
		return out
	if now.health() < before.health() and now.damage > before.damage:
		out.append("hurt")
	elif now.health() > before.health() and now.damage < before.damage:
		out.append("heal")
	var up := now.atk() > before.atk() or now.max_health() > before.max_health()
	var down := now.atk() < before.atk() or now.max_health() < before.max_health()
	if up and not down:
		out.append("buff")
	elif down and not up and not (now.silenced and not before.silenced):  # Silence takes buffs away
		out.append("debuff")
	for k in ["TAUNT", "DIVINE_SHIELD", "STEALTH", "WINDFURY", "CHARGE", "IMMUNE"]:
		if now.has(k) and not before.has(k):
			out.append("gain")
			break
	if now.has("FROZEN") and not before.has("FROZEN"):
		out.append("freeze")
	if now.silenced and not before.silenced:
		out.append("silence")
	if int(now.tags.get("ARMOR", 0)) > int(before.tags.get("ARMOR", 0)):
		out.append("armor")
	return out
