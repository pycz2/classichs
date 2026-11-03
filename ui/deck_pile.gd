class_name DeckPile
extends Control
## A player's deck beside the hero: the pile is thicker with more cards; the
## exact number, and the cards in that player's hand, show on hover (on touch: a finger held on
## it, TouchInput).

const SIZE := Vector2(84, 120)
const STEP := Vector2(-0.9, -1.2)  # one layer of the pile (2 cards): a full deck stands 18 px high

var count := -1:
	set(v):
		if v == count:
			return
		count = v
		_tip()
		queue_redraw()
## Cards in the same player's hand (shown on hover too; -1 = not shown).
var hand := -1:
	set(v):
		if v != hand:
			hand = v
			_tip()


func _tip() -> void:
	tooltip_text = TranslationServer.translate("Cards in deck: %d") % count
	if hand >= 0:
		tooltip_text += "\n" + TranslationServer.translate("Cards in hand: %d") % hand


func _init() -> void:
	size = SIZE
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


## Where the top card is (cards are drawn from here).
func top() -> Vector2:
	return position + Vector2(6, 8) + STEP * ceili(maxi(count, 0) / 2.0)


static func draw_back(ci: CanvasItem, r: Rect2) -> void:
	CardBacks.draw(ci, r)


func _draw() -> void:
	var card := Rect2(Vector2(6, 8), Vector2(72, 104))
	if count <= 0:
		draw_style_box(Palette.box(Color(0, 0, 0, 0.3), 8, Color(1, 1, 1, 0.2), 2), card)
		return
	var layers := ceili(count / 2.0)
	for i in layers:  # card edges, light and dark by turns, so the height shows
		var edge := Color("8a6d2c") if i % 2 == 0 else Color("4a3815")
		draw_style_box(Palette.box(Color("18233a"), 8, edge, 1), Rect2(card.position + STEP * i + Vector2(1, 1), card.size))
	draw_back(self, Rect2(card.position + STEP * layers, card.size))
