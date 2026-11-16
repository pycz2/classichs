class_name SpellOrb
extends Control
## A targeted spell while its player aims it: the card has turned into a swirl of its element's light
## (fire, frost, arcane…) where the arrow starts. Only that player sees it (the opponent sees the arrow).
## Drawn with circles and arcs only: nothing is made each frame.

var card_id := ""
var color := Color("ffd43b")
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 64  # under the arrow (65), over the hand


## Shows the orb of card at (its centre); a new card opens it again from a spark.
func show_at(card: String, at: Vector2) -> void:
	if card != card_id or not visible:
		card_id = card
		color = TableFx.element_color(card)
		_t = 0.0
	position = at
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var grow := minf(1.0, _t / maxf(0.01, Anim.d(0.18))) if not Anim.instant else 1.0
	var r := 34.0 * grow * (1.0 + 0.05 * sin(_t * 6.0))
	var light := color.lightened(0.45)
	draw_circle(Vector2.ZERO, r * 1.7, Color(color, 0.10))
	draw_circle(Vector2.ZERO, r * 1.25, Color(color, 0.22))
	draw_circle(Vector2.ZERO, r * 0.8, Color(color, 0.55))
	draw_circle(Vector2.ZERO, r * 0.5, Color(light, 0.9))
	draw_circle(Vector2.ZERO, r * 0.25, Color(1, 1, 1, 0.95))
	for i in 3:  # broken rings turning both ways: a sigil being drawn
		var a := _t * (2.2 + 0.8 * i) * (1.0 if i % 2 == 0 else -1.0) + i * 1.3
		draw_arc(Vector2.ZERO, r * (0.95 + 0.22 * i), a, a + 3.6, 28, Color(light, 0.85 - 0.22 * i), 3.0 - 0.6 * i, true)
		draw_arc(Vector2.ZERO, r * (0.95 + 0.22 * i), a + PI, a + PI + 1.4, 12, Color(light, 0.6 - 0.15 * i), 2.0, true)
	for i in 6:  # runes circling it
		var a := -_t * 1.4 + i * TAU / 6.0
		var p := Vector2(cos(a), sin(a)) * r * 1.45
		draw_circle(p, 3.2 * grow, Color(light, 0.9))
		draw_line(p - Vector2(0, 5) * grow, p + Vector2(0, 5) * grow, Color(color, 0.8), 1.5, true)
