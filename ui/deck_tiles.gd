class_name DeckTiles
extends RefCounted
## Deck rows in the style of the original: a strip of the picture behind the
## text — the card's art in a deck list, the hero's portrait in the list of decks.


## Draws a horizontal strip of a card's picture across rect, darker on the left
## so white text there stays readable.
static func strip(ci: CanvasItem, rect: Rect2, card_id: String, focus := 0.45) -> void:
	var tex := Art.texture(card_id)
	if tex:
		var tw := float(tex.get_width())
		var band_h := tw * rect.size.y / rect.size.x
		var y := clampf(tex.get_height() * focus - band_h / 2.0, 0.0, tex.get_height() - band_h)
		ci.draw_texture_rect_region(tex, rect, Rect2(0, y, tw, band_h))
	else:
		Art.paint(ci, rect, card_id)
	var dark := Color(0.06, 0.04, 0.02, 0.92)
	var clear := Color(0.06, 0.04, 0.02, 0.15)
	ci.draw_polygon(PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]),
		PackedColorArray([dark, clear, clear, dark]))


static func text(ci: Control, at: Vector2, s: String, size: int, col := Color("f4ead5")) -> void:
	var f := ci.get_theme_font("font", "Label")
	ci.draw_string_outline(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color.BLACK)
	ci.draw_string(f, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## A card in a deck list: cost crystal, name over a strip of the card's art, copies.
class DeckTile:
	extends Button
	var card_id := ""
	var copies := 1

	func _init(id: String, n: int) -> void:
		card_id = id
		copies = n
		name = "Entry_" + id
		custom_minimum_size = Vector2(272, 34)
		tooltip_text = CardText.name(id)
		focus_mode = Control.FOCUS_NONE
		flat = true

	func _draw() -> void:
		var r := Rect2(Vector2(26, 2), size - Vector2(28, 4))
		draw_style_box(Palette.box(Color("1b140f"), 8, Color("6b5320"), 2), Rect2(Vector2(0, 1), size - Vector2(0, 2)))
		DeckTiles.strip(self, r, card_id)
		if is_hovered():
			draw_rect(r, Color(1, 0.9, 0.6, 0.12))
		Frames.mana(self, Vector2(17, size.y / 2.0), int(CardDb.card(card_id).get("cost", 0)), 13)
		DeckTiles.text(self, Vector2(36, size.y / 2.0 + 6), CardText.name(card_id), 16)
		var legendary: bool = CardDb.card(card_id).get("rarity", "") == "LEGENDARY"
		if copies > 1 or legendary:
			var box := Rect2(Vector2(size.x - 30, 5), Vector2(26, size.y - 10))
			draw_style_box(Palette.box(Color("2a1a08"), 6, Frames.GOLD, 2), box)
			if legendary:
				var c := box.get_center()
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(2.5, -2.5), c + Vector2(8, 0), c + Vector2(2.5, 2.5), c + Vector2(0, 8), c + Vector2(-2.5, 2.5), c + Vector2(-8, 0), c + Vector2(-2.5, -2.5)]), Color("fd7e14"))
			else:
				DeckTiles.text(self, box.position + Vector2(6, 18), "2", 16, Frames.GOLD)


## A deck in the list of decks: the hero's portrait behind the deck's name.
class DeckRow:
	extends Button
	var deck: Deck

	func _init(d: Deck) -> void:
		deck = d
		custom_minimum_size = Vector2(600, 64)
		toggle_mode = true
		focus_mode = Control.FOCUS_NONE
		flat = true

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		var cls := deck.card_class()
		draw_style_box(Palette.box(Palette.of_class(cls).darkened(0.5), 12), r)
		DeckTiles.strip(self, r.grow(-3), deck.hero, 0.3)
		Icons.paint(self, cls, Rect2(Vector2(12, 12), Vector2(40, 40)))
		DeckTiles.text(self, Vector2(64, 30), deck.name, 20)
		DeckTiles.text(self, Vector2(64, 52), CardText.name(deck.hero), 14, Palette.of_class(cls).lightened(0.5))
		var n := deck.cards.size()
		if n < Deck.SIZE:  # an unfinished deck: how full it is
			var bar := Rect2(Vector2(size.x - 150, size.y - 22), Vector2(130, 10))
			draw_style_box(Palette.box(Color(0, 0, 0, 0.6), 5), bar)
			draw_style_box(Palette.box(Frames.GOLD, 5), Rect2(bar.position, Vector2(bar.size.x * n / Deck.SIZE, bar.size.y)))
			DeckTiles.text(self, Vector2(size.x - 150, size.y - 28), "%d / %d" % [n, Deck.SIZE], 13)
		var edge := Frames.GOLD if button_pressed else (Color("c9a74a", 0.5) if is_hovered() else Color(0, 0, 0, 0))
		draw_style_box(Palette.box(Color(0, 0, 0, 0), 12, edge, 3), r)
