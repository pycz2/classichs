class_name CardView
extends EntityView
## A card face (or back). Stats can show current values from the game.

const SIZE := Vector2(120, 170)
## The tint of a set mark (Packs.set_mark) behind the card text.
const SET_MARK := Color(0.42, 0.29, 0.12, 0.2)

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
## The values of its text's "{0}", "{1}"… in a game (the engine's `text_args`: a Jade card's next Golem).
var text_args := []
## The card whose picture it shows ("" = its own: a Zombeast shows its first Beast's).
var art_id := ""
## A card in the hand with Echo (its keyword, or Glinda Crowskin's aura): a violet mark with rings in its top right corner.
var echo := false
## The Echo mark's colour.
const ECHO := Color("b48cff")
## A GHOSTLY copy (it goes away at the end of the turn): grey flames over the top of the card (ghost_flame.gdshader).
const GHOST_FLAME := preload("res://ui/ghost_flame.gdshader")
static var _ghost_mat: ShaderMaterial
var ghost: ColorRect
## The pack (a version of the active game) whose card it draws; null: the active pack's.
var pack: Pack


static func make(id: String, scale_factor := 1.0) -> CardView:
	var v := CardView.new()
	v.card_id = id
	v.custom_minimum_size = SIZE * scale_factor
	v.size = SIZE * scale_factor
	return v


## Current cost/attack/health from a hand card or a minion in play.
func show_entity(e: GameView.Ent, g: GameView) -> void:
	var was := cost if entity_id == e.id else -1
	entity_id = e.id
	card_id = e.card_id
	text_args = e.text_args
	art_id = e.art_id
	if e.choice >= 0 and str(e.card().get("text", {}).get("enUS", "")).contains("@"):  # (raw() gives one variant)
		text_args = ["@%d" % (e.choice + 1)]  # the text variant of its option (Fatespinner: only its player knows it)
	cost = g.cost(e) if e.zone == "HAND" else int(e.card().get("cost", 0))
	echo = e.zone == "HAND" and (e.has("ECHO") or KeywordTips.keywords_of(card_id).has("ECHO"))
	_set_ghost(e.has("GHOSTLY"))
	if was >= 0 and was != cost:
		pop("cost")
	var was_atk := attack if was >= 0 else -1
	var was_hp := health if was >= 0 else -1
	if e.is_minion():
		attack = e.atk()
		health = e.health()
	elif e.is_weapon():
		attack = e.atk()
		health = int(e.tags.get("DURABILITY", 0))
	if was_atk >= 0 and was_atk != attack:
		pop("atk")
	if was_hp >= 0 and was_hp != health:
		pop("hp")
	queue_redraw()


func _set_ghost(on: bool) -> void:
	if on == (ghost != null):
		return
	if not on:
		ghost.queue_free()
		ghost = null
		return
	if _ghost_mat == null:
		_ghost_mat = ShaderMaterial.new()
		_ghost_mat.shader = GHOST_FLAME
	ghost = ColorRect.new()
	ghost.name = "GhostFlame"
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.color = Color("c9ccd6")
	ghost.material = _ghost_mat
	ghost.position = Vector2(0, -0.14 * size.y)  # from a little above the card down to its name
	ghost.size = Vector2(size.x, 0.62 * size.y)
	add_child(ghost)


## The colours its numbers show against the card's own (green above, red below; the cost: green when cheaper).
func cost_color() -> Color:
	return Frames.cost_color(cost if cost >= 0 else int(CardDb.card(card_id).get("cost", 0)), int(CardDb.card(card_id).get("cost", 0)))


func attack_color() -> Color:
	return Frames.stat_color(attack, int(CardDb.card(card_id).get("attack", 0))) if attack >= 0 else Color.WHITE


func health_color() -> Color:
	var c := CardDb.card(card_id)
	return Frames.stat_color(health, int(c.get("health", c.get("durability", 0)))) if health >= 0 else Color.WHITE


## A passive Hero Power cannot be used: it has no cost.
func shows_cost() -> bool:
	return not CardDb.passive_power(card_id)


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
	var bend := 2.0 if CardDb.card(card_id).get("type") == "MINION" else 0.0  # (a minion's banner bends up in the middle)
	var at := Vector2(nb.get_center().x - nw / 2.0, nb.get_center().y + ns * 0.36 - (1.0 + bend) * k)
	draw_string_outline(nf, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, maxi(2, int(3 * k)), Color.BLACK)
	draw_string(nf, at, name, HORIZONTAL_ALIGNMENT_LEFT, -1, ns, Color("f4ead5"))
	var p := CardLayout.paragraph(card_id, lg, k, text_args)
	var rects := CardLayout.line_rects(card_id, lg, p, k, text_args)
	for i in rects.size():
		var r: Rect2 = rects[i]
		p.draw_line(get_canvas_item(), Vector2(r.position.x * k, r.position.y * k), i, Color("3b2a14"))
	if show_boxes:
		draw_rect(nb, Color(0.2, 0.6, 1, 0.8), false, 1)
		draw_rect(Rect2(CardLayout.TEXT_BOX.position * k, CardLayout.TEXT_BOX.size * k), Color(0.2, 0.6, 1, 0.8), false, 1)
		for r in CardLayout.ink_rects(card_id, lg, CardLayout.paragraph(card_id, lg, 1.0, text_args), 1.0, text_args):
			draw_rect(Rect2(r.position * k, r.size * k), Color(0.2, 0.9, 0.3, 0.6), false, 1)
		if CardDb.card(card_id).get("type") in CardLayout.GEM_TYPES:
			for g in CardLayout.GEMS:
				draw_arc(g[0] * k, g[1] * k, 0, TAU, 32, Color(1, 0.3, 0.2, 0.8), 1)


func _draw() -> void:
	var other := pack != null and pack != Packs.active()
	if other:
		CardDb.begin(pack)
	_draw_card()
	if other:
		CardDb.end()


func _draw_card() -> void:
	var k := size.x / SIZE.x
	var r := Rect2(Vector2.ZERO, size)
	_draw_glow(r, int(12 * k))
	if not face_up or card_id == "":
		DeckPile.draw_back(self, r)
		return
	var c := CardDb.card(card_id)
	var type: String = c.get("type", "MINION")
	var frame := Palette.of_class(c.get("cardClass", "NEUTRAL"))
	draw_style_box(Palette.raw_box(frame.darkened(0.25), int(12 * k), Frames.GOLD.darkened(0.2), int(3 * k)), r)
	var classes: Array = c.get("classes", [])
	if classes.size() > 1:  # a multi-class card: its frame in the colours of its classes, side by side
		var band := r.grow(-3 * k)
		var w := band.size.x / classes.size()
		for i in classes.size():
			var part := Rect2(band.position + Vector2(w * i, 0), Vector2(w, band.size.y))
			var sb := StyleBoxFlat.new()
			sb.bg_color = Palette.of_class(classes[i]).darkened(0.2)
			var rad := int(10 * k)
			sb.corner_radius_top_left = rad if i == 0 else 0
			sb.corner_radius_bottom_left = rad if i == 0 else 0
			sb.corner_radius_top_right = rad if i == classes.size() - 1 else 0
			sb.corner_radius_bottom_right = rad if i == classes.size() - 1 else 0
			draw_style_box(sb, part)
	draw_style_box(Palette.raw_box(frame.darkened(0.55), int(8 * k)), r.grow(-6 * k))
	var shape: String = {"MINION": "oval", "WEAPON": "circle", "SPELL": "arch", "HERO_POWER": "circle", "HERO": "arch"}.get(type, "arch")
	var art := {"oval": Rect2(Vector2(22, 8), Vector2(76, 84)), "circle": Rect2(Vector2(25, 10), Vector2(70, 70)),
		"arch": Rect2(Vector2(14, 10), Vector2(92, 76))}[shape] as Rect2
	art = Rect2(art.position * k, art.size * k)
	var outline := Art.outline(shape, art)
	draw_colored_polygon(Art.outline(shape, art.grow(3 * k)), Frames.GOLD.darkened(0.35))
	Art.paint_in(self, art, art_id if art_id != "" else card_id, shape)
	Frames.ring(self, outline, Frames.GOLD.darkened(0.1), 2 * k)
	if type == "HERO":  # a hero card (Knights of the Frozen Throne): a portrait in a double steel-and-gold rim
		Frames.ring(self, Art.outline(shape, art.grow(3 * k)), Color("aeb8c2"), 2.5 * k)
		Frames.ring(self, Art.outline(shape, art.grow(5 * k)), Frames.GOLD, 1.5 * k)
	if c.get("rarity", "") == "LEGENDARY":
		Frames.crest(self, Vector2(60, 5) * k, 104 * k)  # along the card's top edge
	# text box (parchment) and the name banner across it
	draw_style_box(Palette.raw_box(Color("efe0bd"), int(6 * k), Color("8a6d3b"), int(2 * k)), Rect2(Vector2(9, 100) * k, Vector2(102, 60) * k))
	var mark := Packs.set_mark(CardText.set_key(card_id))
	if mark:  # the card's set, faint behind its text (the packs after Classic)
		draw_texture_rect(mark, Rect2(Vector2(42, 114) * k, Vector2(36, 36) * k), false, SET_MARK)
	var bend := 4.0 * k if type == "MINION" else 0.0
	var banner := PackedVector2Array([Vector2(4, 86) * k, Vector2(60 * k, 86 * k - bend), Vector2(116, 86) * k, Vector2(116, 102) * k, Vector2(60 * k, 102 * k - bend), Vector2(4, 102) * k])
	draw_colored_polygon(banner, frame.darkened(0.15))
	if classes.size() > 1:  # the name banner in the classes' colours too
		var w := 112.0 * k / classes.size()
		for i in classes.size():
			var x0 := 4 * k + w * i
			var slab := PackedVector2Array([Vector2(x0, 0), Vector2(x0 + w, 0), Vector2(x0 + w, size.y), Vector2(x0, size.y)])
			for part in Geometry2D.intersect_polygons(banner, slab):
				draw_colored_polygon(part, Palette.of_class(classes[i]).darkened(0.3))
	Frames.ring(self, banner, Color("2a2118"), 1.5 * k)
	Frames.rarity(self, Vector2(60, 104.5) * k - Vector2(0, bend), c.get("rarity", ""), 4.5 * k)  # under the name, at the banner's edge
	_draw_words(k)
	if silenced:  # a red cross over the text box, drawn like two brush strokes with a dark edge
		var tb := Rect2(CardLayout.TEXT_BOX.position * k, CardLayout.TEXT_BOX.size * k)
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
		draw_style_box(Palette.raw_box(Color("2a2118"), int(4 * k), Frames.GOLD.darkened(0.25), maxi(1, int(1.5 * k))), plate)
		draw_string(rf, Vector2(plate.position.x + 5 * k, plate.position.y + 8.6 * k), race, HORIZONTAL_ALIGNMENT_LEFT, -1, rs, Color("f4ead5"))
	if shows_cost():
		Frames.mana(self, Vector2(17, 17) * k, cost if cost >= 0 else int(c.get("cost", 0)), 15 * k * bump("cost"), cost_color())
	if type == "HERO" and int(c.get("armor", 0)) > 0:  # the Armor it gives, on the shield where a minion's Health goes
		Frames.shield(self, CardLayout.HEALTH_AT * k, int(c.armor), 14 * k)
	if type == "MINION" or type == "WEAPON":
		var a := attack if attack >= 0 else int(c.get("attack", 0))
		var h := health if health >= 0 else int(c.get("health", c.get("durability", 0)))
		Frames.attack(self, CardLayout.ATTACK_AT * k, a, 15 * k * bump("atk"), attack_color(), -PI / 4.0)
		if type == "MINION":
			Frames.health(self, CardLayout.HEALTH_AT * k, h, 15 * k * bump("hp"), health_color())
		else:
			Frames.shield(self, CardLayout.HEALTH_AT * k, h, 14 * k * bump("hp"), health_color(), "durability")
	if classes.size() > 1:  # a multi-class card: its classes' emblems on one round mark in its top right corner
		_draw_classes(Vector2(102, 18) * k, 13 * k, classes)
	if echo:
		var at := Vector2(103, 17) * k
		draw_circle(at, 10 * k, Color("2b1846"))
		draw_arc(at, 10 * k, 0, TAU, 28, Frames.GOLD.darkened(0.2), 1.5 * k, true)
		draw_circle(at, 3 * k, ECHO)
		for i in 2:
			draw_arc(at, (5.5 + 2.5 * i) * k, 0, TAU, 24, Color(ECHO, 0.9 - 0.35 * i), 1.3 * k, true)
	if marked:  # to be replaced: the card darkens and a red seal with a white cross sits on it
		draw_style_box(Palette.raw_box(Color(0, 0, 0, 0.45), int(12 * k)), r)
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


## A round mark split into one slice per class, each in its class's colour with its emblem.
func _draw_classes(at: Vector2, r: float, classes: Array) -> void:
	draw_circle(at + Vector2(0, r * 0.12), r + 2.5, Color(0, 0, 0, 0.45))
	draw_circle(at, r + 1.5, Frames.GOLD.darkened(0.2))
	var n := classes.size()
	for i in n:
		var a0 := -PI / 2.0 + TAU * i / n
		var pts := PackedVector2Array([at])
		for j in 13:
			pts.append(at + Vector2.from_angle(a0 + TAU / n * j / 12.0) * r)
		draw_colored_polygon(pts, Palette.of_class(classes[i]).darkened(0.15))
	for i in n:
		draw_line(at, at + Vector2.from_angle(-PI / 2.0 + TAU * i / n) * r, Color("2a2118"), maxf(1.0, r * 0.08), true)
	for i in n:
		var mid := at + Vector2.from_angle(-PI / 2.0 + TAU * (i + 0.5) / n) * r * 0.5
		Icons.paint(self, str(classes[i]), Rect2(mid - Vector2.ONE * r * 0.36, Vector2.ONE * r * 0.72))
	draw_arc(at, r, 0, TAU, 32, Frames.GOLD, maxf(1.0, r * 0.1), true)
