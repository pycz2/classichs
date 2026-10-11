class_name CardView
extends EntityView
## A card face (or back). Stats can show current values from the game.

const SIZE := Vector2(120, 170)

var card_id := ""
var face_up := true
var cost := -1
var attack := -1
var health := -1
var marked := false  # mulligan: card will be replaced
## The language of the name and text ("" = the interface language); the card lab sets it.
var locale := ""
## Card lab: outline the name box, the text box, the lines and the gems.
var show_boxes := false
## A silenced minion's card (when hovered): a red cross over its text.
var silenced := false


static func make(id: String, scale_factor := 1.0) -> CardView:
	var v := CardView.new()
	v.card_id = id
	v.custom_minimum_size = SIZE * scale_factor
	v.size = SIZE * scale_factor
	return v


## Current cost/attack/health from a hand card or a minion in play.
func show_entity(e: Entity, g: GameState) -> void:
	var was := cost if entity_id == e.id else -1
	entity_id = e.id
	card_id = e.card_id
	cost = g.cost(e) if e.zone == "HAND" else int(e.card().get("cost", 0))
	if was >= 0 and was != cost:
		pop("cost")
	if e.is_minion():
		attack = e.atk()
		health = e.health()
	elif e.is_weapon():
		attack = e.atk()
		health = int(e.tags.get("DURABILITY", 0))
	queue_redraw()


func lang() -> String:
	var l := locale if locale != "" else TranslationServer.get_locale()
	return l if l in CardLayout.LANGS else "en"


## Name and text, laid out by CardLayout (the same measurement the checks use).
func _draw_words(k: float) -> void:
	var lg := lang()
	var sz := CardLayout.of(card_id, lg)
	var name := CardText.name(card_id, CardText.hs_locale(lg))
	var nf := CardLayout.name_font()
	var ns := int(sz.name * k)
	var nw := nf.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, ns).x
	var nb := Rect2(CardLayout.NAME_BOX.position * k, CardLayout.NAME_BOX.size * k)
	var at := Vector2(nb.get_center().x - nw / 2.0, nb.get_center().y + ns * 0.36)
	draw_string_outline(nf, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, maxi(2, int(3 * k)), Color.BLACK)
	draw_string(nf, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, Color("f4ead5"))
	var p := CardLayout.paragraph(card_id, lg, k)
	var rects := CardLayout.line_rects(card_id, lg, p, k)
	for i in rects.size():
		var r: Rect2 = rects[i]
		p.draw_line(get_canvas_item(), Vector2(r.position.x * k, r.position.y * k), i, Color("3b2a14"))
	if show_boxes:
		draw_rect(nb, Color(0.2, 0.6, 1, 0.8), false, 1)
		draw_rect(Rect2(CardLayout.TEXT_BOX.position * k, CardLayout.TEXT_BOX.size * k), Color(0.2, 0.6, 1, 0.8), false, 1)
		for r in CardLayout.ink_rects(card_id, lg, CardLayout.paragraph(card_id, lg), 1.0):
			draw_rect(Rect2(r.position * k, r.size * k), Color(0.2, 0.9, 0.3, 0.6), false, 1)
		if CardDb.card(card_id).get("type") in ["MINION", "WEAPON"]:
			for g in CardLayout.GEMS:
				draw_arc(g[0] * k, g[1] * k, 0, TAU, 32, Color(1, 0.3, 0.2, 0.8), 1)


func _draw() -> void:
	var k := size.x / SIZE.x
	var r := Rect2(Vector2.ZERO, size)
	_draw_glow(r, int(12 * k))
	if not face_up or card_id == "":
		DeckPile.draw_back(self, r)
		return
	var c := CardDb.card(card_id)
	var type: String = c.get("type", "MINION")
	var frame := Palette.of_class(c.get("cardClass", "NEUTRAL"))
	draw_style_box(Palette.box(frame.darkened(0.25), int(12 * k), Frames.GOLD.darkened(0.2), int(3 * k)), r)
	draw_style_box(Palette.box(frame.darkened(0.55), int(8 * k)), r.grow(-6 * k))
	var shape: String = {"MINION": "oval", "WEAPON": "circle", "SPELL": "arch", "HERO_POWER": "circle", "HERO": "arch"}.get(type, "arch")
	var art := {"oval": Rect2(Vector2(22, 8), Vector2(76, 84)), "circle": Rect2(Vector2(25, 10), Vector2(70, 70)),
		"arch": Rect2(Vector2(14, 10), Vector2(92, 76))}[shape] as Rect2
	art = Rect2(art.position * k, art.size * k)
	var outline := Art.outline(shape, art)
	draw_colored_polygon(Art.outline(shape, art.grow(3 * k)), Frames.GOLD.darkened(0.35))
	Art.paint_in(self, art, card_id, shape)
	Frames.ring(self, outline, Frames.GOLD.darkened(0.1), 2 * k)
	if c.get("rarity", "") == "LEGENDARY":
		Frames.crest(self, Vector2(60, 5) * k, 104 * k)  # along the card's top edge
	# text box (parchment) and the name banner across it
	draw_style_box(Palette.box(Color("efe0bd"), int(6 * k), Color("8a6d3b"), int(2 * k)), Rect2(Vector2(11, 100) * k, Vector2(98, 56) * k))
	var bend := 4.0 * k if type == "MINION" else 0.0
	var banner := PackedVector2Array([Vector2(4, 86) * k, Vector2(60 * k, 86 * k - bend), Vector2(116, 86) * k, Vector2(116, 102) * k, Vector2(60 * k, 102 * k - bend), Vector2(4, 102) * k])
	draw_colored_polygon(banner, frame.darkened(0.15))
	Frames.ring(self, banner, Color("2a2118"), 1.5 * k)
	Frames.rarity(self, Vector2(60, 101) * k, c.get("rarity", ""), 5 * k)
	_draw_words(k)
	if silenced:  # a red cross over the text box, drawn like two brush strokes with a dark edge
		var tb := Rect2(Vector2(14, 104) * k, Vector2(92, 50) * k)
		for line in [[tb.position, tb.end], [Vector2(tb.end.x, tb.position.y), Vector2(tb.position.x, tb.end.y)]]:
			draw_line(line[0], line[1], Color("3d0508", 0.9), 9 * k, true)
			draw_line(line[0], line[1], Color("e03131"), 5.5 * k, true)
			draw_line(line[0] + Vector2(0, -1.2 * k), line[1] + Vector2(0, -1.2 * k), Color("ff8787", 0.7), 1.5 * k, true)
	var race := CardText.race(card_id, CardText.hs_locale(lang()))
	if race != "":  # the race on a plate across the bottom edge, between the gems
		var rf := CardLayout.name_font()
		var rs := int(8 * k)
		var rw := rf.get_string_size(race, HORIZONTAL_ALIGNMENT_LEFT, -1, rs).x
		var plate := Rect2(Vector2(60 * k - rw / 2.0 - 5 * k, 158 * k), Vector2(rw + 10 * k, 11 * k))
		draw_style_box(Palette.box(Color("2a2118"), int(4 * k), Frames.GOLD.darkened(0.25), maxi(1, int(1.5 * k))), plate)
		draw_string(rf, Vector2(plate.position.x + 5 * k, plate.position.y + 8.6 * k), race, HORIZONTAL_ALIGNMENT_LEFT, -1, rs, Color("f4ead5"))
	var base_cost := int(c.get("cost", 0))
	var shown_cost := cost if cost >= 0 else base_cost
	var cost_color := Color.WHITE if shown_cost == base_cost else (Frames.BUFFED if shown_cost < base_cost else Frames.DAMAGED)
	Frames.mana(self, Vector2(17, 17) * k, shown_cost, 15 * k * bump("cost"), cost_color)
	if type == "MINION" or type == "WEAPON":
		var a := attack if attack >= 0 else int(c.get("attack", 0))
		var h := health if health >= 0 else int(c.get("health", c.get("durability", 0)))
		Frames.attack(self, Vector2(17, 154) * k, a, 15 * k)
		if type == "MINION":
			Frames.health(self, Vector2(103, 154) * k, h, 15 * k)
		else:
			Frames.shield(self, Vector2(103, 154) * k, h, 14 * k, Color.WHITE, "durability")
	if marked:  # to be replaced: the card darkens and a red seal with a white cross sits on it
		draw_style_box(Palette.box(Color(0, 0, 0, 0.45), int(12 * k)), r)
		var mc := Vector2(60, 70) * k
		var rr := 26 * k
		draw_circle(mc + Vector2(0, 3 * k), rr + 3 * k, Color(0, 0, 0, 0.5))
		draw_circle(mc, rr + 3 * k, Color("2a0b0b"))
		draw_circle(mc, rr, Color("c92a2a"))
		draw_circle(mc + Vector2(-rr * 0.25, -rr * 0.3), rr * 0.55, Color(1, 1, 1, 0.12))
		draw_arc(mc, rr - 3 * k, 0, TAU, 40, Color("ffa8a8", 0.6), 1.5 * k, true)
		var d := rr * 0.48
		for line in [[mc + Vector2(-d, -d), mc + Vector2(d, d)], [mc + Vector2(d, -d), mc + Vector2(-d, d)]]:
			draw_line(line[0], line[1], Color("2a0b0b"), 9 * k, true)
			draw_line(line[0], line[1], Color.WHITE, 5.5 * k, true)
