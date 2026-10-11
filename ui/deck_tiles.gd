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


static func text(ci: Control, at: Vector2, s: String, size: int, col := Color("f4ead5"), width := -1.0) -> void:
	var f := ci.get_theme_font("font", "Label")
	if width > 0 and f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		while s.length() > 1 and f.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			s = s.left(-1)
		s = s.strip_edges() + "…"
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
		var legendary: bool = CardDb.card(card_id).get("rarity", "") == "LEGENDARY"
		var marked := copies > 1 or legendary
		DeckTiles.text(self, Vector2(36, size.y / 2.0 + 6), CardText.name(card_id), 16, Color("f4ead5"), size.x - (78 if marked else 42))
		if marked:
			var box := Rect2(Vector2(size.x - 36, 5), Vector2(32, size.y - 10))
			draw_style_box(Palette.box(Color("2a1a08"), 6, Frames.GOLD, 2), box)
			if legendary:
				var c := box.get_center()
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(2.5, -2.5), c + Vector2(8, 0), c + Vector2(2.5, 2.5), c + Vector2(0, 8), c + Vector2(-2.5, 2.5), c + Vector2(-8, 0), c + Vector2(-2.5, -2.5)]), Color("fd7e14"))
			else:
				DeckTiles.text(self, box.position + Vector2(5, 18), "×%d" % copies, 16, Frames.GOLD)


## A deck in the list of decks: the hero's portrait behind the deck's name;
## an unfinished deck shows how full it is. The owner may put small buttons
## in the lower right corner (ACTIONS_W wide).
class DeckRow:
	extends Button
	const ACTIONS_W := 100.0
	var deck: Deck

	func _init(d: Deck) -> void:
		deck = d
		custom_minimum_size = Vector2(300, 68)
		focus_mode = Control.FOCUS_NONE
		flat = true

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		var cls := deck.card_class()
		draw_style_box(Palette.box(Palette.of_class(cls).darkened(0.5), 12), r)
		DeckTiles.strip(self, r.grow(-3), deck.hero, 0.3)
		Icons.paint(self, cls, Rect2(Vector2(10, 14), Vector2(40, 40)))
		DeckTiles.text(self, Vector2(60, 29), deck.name, 19, Color("f4ead5"), size.x - 70)
		var n := deck.cards.size()
		var f := get_theme_font("font", "Label")
		var tag := "  %d/%d" % [n, Deck.SIZE] if n < Deck.SIZE else ""  # an unfinished deck: how full it is
		var room := size.x - 60 - ACTIONS_W - 14 - f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var sub := CardText.name(deck.hero)
		DeckTiles.text(self, Vector2(60, 52), sub, 14, Palette.of_class(cls).lightened(0.5), room)
		if tag != "":
			var x := 60.0 + minf(f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, room)
			DeckTiles.text(self, Vector2(x, 52), tag, 13, Frames.GOLD)
			var bar := Rect2(Vector2(14, size.y - 8), Vector2(size.x - 28, 3))
			draw_rect(bar, Color(0, 0, 0, 0.6))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * n / Deck.SIZE, bar.size.y)), Frames.GOLD)
		var edge := Color("c9a74a", 0.7) if is_hovered() else Color(0, 0, 0, 0)
		draw_style_box(Palette.box(Color(0, 0, 0, 0), 12, edge, 3), r)


## How full a deck is, behind its "n / 30" count.
class Bar:
	extends Control
	var ratio := 0.0:
		set(v):
			ratio = clampf(v, 0.0, 1.0)
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(Palette.box(Color(0, 0, 0, 0.55), 13, Color("6b5320"), 2), r)
		if ratio > 0.0:
			var fill := Color("f2c94c") if ratio >= 1.0 else Color("b8862b")
			draw_style_box(Palette.box(fill, 13), Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * ratio, r.size.y - 4)))


## A small square button with a drawn sign: "copy", "export" or "delete".
class Action:
	extends Button
	var kind := ""

	func _init(k: String, tip: String) -> void:
		kind = k
		name = k.capitalize()
		tooltip_text = tip
		custom_minimum_size = Vector2(28, 26)
		size = custom_minimum_size
		focus_mode = Control.FOCUS_NONE
		flat = true
		pressed.connect(Sound.play.bind("click"))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var red := kind == "delete"
		var edge := (Color("ff7a5c") if red else Frames.GOLD) if is_hovered() else Color("6b5320")
		draw_style_box(Palette.box(Color(0.08, 0.05, 0.03, 0.85), 6, edge, 1), r)
		var c := r.get_center()
		var ink := Color("ffb4a2") if red and is_hovered() else Color("f4ead5")
		match kind:
			"delete":  # a cross
				draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), ink, 2.0, true)
				draw_line(c + Vector2(5, -5), c + Vector2(-5, 5), ink, 2.0, true)
			"copy":  # two sheets
				draw_rect(Rect2(c + Vector2(-6, -7), Vector2(9, 10)), ink, false, 1.5)
				draw_rect(Rect2(c + Vector2(-2, -3), Vector2(9, 10)), Color(0.08, 0.05, 0.03), true)
				draw_rect(Rect2(c + Vector2(-2, -3), Vector2(9, 10)), ink, false, 1.5)
			"export":  # an arrow out of a tray
				draw_polyline(PackedVector2Array([c + Vector2(-6, 0), c + Vector2(-6, 6), c + Vector2(6, 6), c + Vector2(6, 0)]), ink, 1.5, true)
				draw_line(c + Vector2(0, 3), c + Vector2(0, -7), ink, 1.5, true)
				draw_polyline(PackedVector2Array([c + Vector2(-3.5, -4), c + Vector2(0, -7.5), c + Vector2(3.5, -4)]), ink, 1.5, true)
