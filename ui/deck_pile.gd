class_name DeckPile
extends Control
## A player's deck beside the hero: the pile is thicker with more cards; the
## exact number shows on hover.

const SIZE := Vector2(84, 120)

var count := -1:
	set(v):
		if v == count:
			return
		count = v
		tooltip_text = TranslationServer.translate("Cards in deck: %d") % v
		queue_redraw()


func _init() -> void:
	size = SIZE
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


## Where the top card is (cards are drawn from here).
func top() -> Vector2:
	var layers := ceili(maxi(count, 0) / 3.0)
	return position + Vector2(6 - layers * 0.7, 8 - layers * 0.9)


static func draw_back(ci: CanvasItem, r: Rect2) -> void:
	CardBacks.draw(ci, r)


func _draw() -> void:
	var card := Rect2(Vector2(6, 8), Vector2(72, 104))
	if count <= 0:
		draw_style_box(Palette.box(Color(0, 0, 0, 0.3), 8, Color(1, 1, 1, 0.2), 2), card)
		return
	var layers := ceili(count / 3.0)
	for i in layers:
		var off := Vector2(-i * 0.7, -i * 0.9)
		draw_style_box(Palette.box(Color("18233a"), 8, Color("6b5320"), 1), Rect2(card.position + off + Vector2(1, 1), card.size))
	draw_back(self, Rect2(card.position + Vector2(-layers * 0.7, -layers * 0.9), card.size))
