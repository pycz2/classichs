class_name ManaCurve
extends Control
## The mana curve: how many cards of each cost (0 … 6, 7+), as bars (the Arena draft, the deck
## editor). `compact`: no frame and title, small numbers (a strip above a deck list).

var counts: Array = [0, 0, 0, 0, 0, 0, 0, 0]:
	set(v):
		counts = v
		queue_redraw()
var compact := false


## The counts of a list of card ids.
static func of(cards: Array) -> Array:
	var out := [0, 0, 0, 0, 0, 0, 0, 0]
	for id in cards:
		out[mini(int(CardDb.card(id).get("cost", 0)), 7)] += 1
	return out


func _draw() -> void:
	var top := maxi(4, counts.max())
	var bw := size.x / 8.0
	var label_h := 16 if compact else 26
	var base := size.y - label_h
	var font := get_theme_default_font()
	if not compact:
		draw_style_box(Palette.box(Color(0.08, 0.06, 0.04, 0.7), 10, Color("6b5320"), 2), Rect2(Vector2(-12, -34), size + Vector2(24, 40)))
		draw_string(font, Vector2(0, -12), tr("Mana curve"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.ATTACK)
	var gap := 3.0 if compact else 6.0
	for i in 8:
		var h: float = (base - (14 if compact else 20)) * counts[i] / float(top)
		var r := Rect2(i * bw + gap, base - h, bw - 2 * gap, h)
		if counts[i] > 0:
			draw_rect(r, Color("3b82c4"))
			draw_rect(Rect2(r.position, Vector2(r.size.x, 2 if compact else 3)), Color("9fd0ff"))
			draw_string(font, Vector2(i * bw, r.position.y - 2), str(counts[i]), HORIZONTAL_ALIGNMENT_CENTER, bw, 12 if compact else 15, Palette.TEXT)
		draw_string(font, Vector2(i * bw, size.y - (2 if compact else 6)), "7+" if i == 7 else str(i), HORIZONTAL_ALIGNMENT_CENTER, bw, 12 if compact else 16, Color("9fd0ff"))
