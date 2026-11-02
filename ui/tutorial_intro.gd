class_name TutorialIntro
extends Control
## What a tutorial mission teaches, shown before it starts: the pages of the active pack's tutorial
## (cards, champions, mana, pictures, notes with arrows pointing at a card's parts, attack arrows,
## big numbers, a scene effect). Next / Play, Skip, Back.

signal done
signal back

## Points on a card (in CardView.SIZE units): the gems, the name banner, the text box edges.
const PARTS := {"cost": Vector2(17, 17), "attack": Vector2(17, 154), "health": Vector2(103, 154),
	"text": Vector2(60, 128), "text_l": Vector2(12, 128), "text_r": Vector2(108, 128), "top": Vector2(60, 0)}
const NOTE_COLOR := Color("ffe9a8")

var number := 1
var page := 0
var _panels: Array = []
var _stage: Control
var _marks: Control
var _title: Label
var _text: Label
var _count: Label
var _next: Button


static func make(n: int) -> TutorialIntro:
	var t := TutorialIntro.new()
	t.number = n
	return t


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self)
	var head := Palette.label("%d. %s" % [Missions.ids().find(number) + 1, CardText.name(Missions.get_mission(number).boss)], 22, Palette.TEXT)
	head.position = Vector2(40, 22)
	add_child(head)
	_title = Palette.label("", 38, Palette.ATTACK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.position = Vector2(0, 40)
	_title.size = Vector2(1280, 50)
	add_child(_title)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_text = Palette.label("", 22)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.position = Vector2(110, 540)
	_text.size = Vector2(1060, 96)
	add_child(_text)
	var bk := Palette.button(tr("Back"), "Back")
	bk.custom_minimum_size = Vector2(200, 48)
	bk.position = Vector2(40, 652)
	bk.pressed.connect(func(): back.emit())
	add_child(bk)
	var skip := Palette.button(tr("Skip"), "Skip")
	skip.custom_minimum_size = Vector2(200, 48)
	skip.position = Vector2(820, 652)
	skip.pressed.connect(func(): done.emit())
	add_child(skip)
	_next = Palette.button(tr("Next"), "Next")
	_next.custom_minimum_size = Vector2(200, 48)
	_next.position = Vector2(1040, 652)
	_next.pressed.connect(next_page)
	add_child(_next)
	_count = Palette.label("", 20)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.position = Vector2(540, 662)
	_count.size = Vector2(200, 30)
	add_child(_count)
	_panels = panels()
	if _panels.is_empty():
		done.emit.call_deferred()  # a mission without intro pages starts at once
	else:
		_show(0)


## The next panel, or done after the last one.
func next_page() -> void:
	if page + 1 >= _panels.size():
		done.emit()
	else:
		_show(page + 1)


func _show(i: int) -> void:
	page = i
	var p: Dictionary = _panels[i]
	_title.text = p.title
	_text.text = p.text
	_count.text = "%d / %d" % [i + 1, _panels.size()]
	_count.visible = _panels.size() > 1
	_next.text = tr("Play") if i == _panels.size() - 1 else tr("Next")
	for c in _stage.get_children():
		c.free()
	for it in p.items:
		if it.has("card"):
			var cv := CardView.make(it.card, it.k)
			cv.position = it.at
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_stage.add_child(cv)
		elif it.has("picture"):
			var pic := TextureRect.new()
			pic.texture = Packs.active().texture(it.picture)
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.position = it.at
			pic.size = it.size
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_stage.add_child(pic)
		elif it.has("mana"):
			var mb := ManaBar.new()
			mb.set_values(it.mana, it.mana, 0)
			mb.position = it.at
			mb.scale = Vector2(1.6, 1.6)
			_stage.add_child(mb)
	var fx := SceneFx.make(p.get("effect"))
	if fx:
		_stage.add_child(fx)
	_marks = Control.new()
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.size = Vector2(1280, 720)
	_marks.draw.connect(_draw_marks.bind(p.items))
	_stage.add_child(_marks)
	for it in p.items:
		if it.has("note"):
			var l := Palette.label(it.note, 20, NOTE_COLOR)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.vertical_alignment = VERTICAL_ALIGNMENT_TOP if it.to == null else VERTICAL_ALIGNMENT_CENTER
			l.horizontal_alignment = _align(it)
			l.position = it.box.position
			l.size = it.box.size
			_stage.add_child(l)


func _align(it: Dictionary) -> HorizontalAlignment:
	if it.to == null:
		return HORIZONTAL_ALIGNMENT_CENTER
	if it.to.x > it.box.end.x:
		return HORIZONTAL_ALIGNMENT_RIGHT
	if it.to.x < it.box.position.x:
		return HORIZONTAL_ALIGNMENT_LEFT
	return HORIZONTAL_ALIGNMENT_CENTER


## Heroes, arrows from notes, attack arrows and floating numbers, over the cards.
func _draw_marks(items: Array) -> void:
	var font := Fonts.ui(800)
	for it in items:
		if it.has("hero"):
			var r := Rect2(it.at - Vector2(90, 110), Vector2(180, 220))
			var oval := Art.outline("oval", r)
			_marks.draw_colored_polygon(Art.outline("oval", r.grow(6)), Frames.GOLD.darkened(0.35))
			Art.paint_in(_marks, r, it.hero, "oval")
			Frames.ring(_marks, oval, Frames.GOLD, 4)
			Frames.health(_marks, r.end - Vector2(18, 26), it.health, 26)
		elif it.has("note") and it.to != null:
			var b: Rect2 = it.box
			var from := Vector2(b.end.x + 10, b.get_center().y)
			if it.to.x < b.position.x:
				from = Vector2(b.position.x - 10, b.get_center().y)
			elif it.to.x <= b.end.x:
				from = Vector2(b.get_center().x, b.end.y + 6 if it.to.y > b.end.y else b.position.y - 6)
			_arrow(from, it.to, Color("ffd43b"), 5.0, 18.0)
		elif it.has("attack"):
			_arrow(it.attack[0], it.attack[1], Palette.TARGET, 9.0, 30.0)
			if it.get("blocked", false):
				var m: Vector2 = (it.attack[0] + it.attack[1]) / 2.0
				for d in [Vector2(1, 1), Vector2(1, -1)]:
					_marks.draw_line(m - d * 24, m + d * 24, Color.BLACK, 16, true)
					_marks.draw_line(m - d * 22, m + d * 22, Color("ff2b2b"), 9, true)
		elif it.has("big"):
			var s: String = it.big
			var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 52).x
			var at: Vector2 = it.at - Vector2(w / 2.0, -18)
			_marks.draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, 10, Color.BLACK)
			_marks.draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 52, it.color)


## A line with a dark edge and a triangle head at `to`.
func _arrow(from: Vector2, to: Vector2, col: Color, w: float, head: float) -> void:
	var d := (to - from).normalized()
	var n := Vector2(-d.y, d.x)
	var base := to - d * head
	var tri := PackedVector2Array([to, base + n * head * 0.6, base - n * head * 0.6])
	var edge := PackedVector2Array([to + d * 3, base + n * (head * 0.6 + 3) - d * 2, base - n * (head * 0.6 + 3) - d * 2])
	_marks.draw_line(from, base, Color.BLACK, w + 4, true)
	_marks.draw_colored_polygon(edge, Color.BLACK)
	_marks.draw_line(from, base + d * 2, col, w, true)
	_marks.draw_colored_polygon(tri, col)


## A point on a card drawn at `at` with scale k; `back` pulls it toward `from` (to stop an arrow at a gem's edge).
static func part(at: Vector2, k: float, p: String, from := Vector2.ZERO, back := 0.0) -> Vector2:
	var pt: Vector2 = at + PARTS[p] * k
	return pt + (from - pt).normalized() * back if back > 0.0 else pt


## The panels of this mission from the active pack's tutorial.json (docs/packs/format.md §12), in the
## form the screen draws: {title, text, effect, items} with points, boxes and colours as Godot values.
func panels() -> Array:
	var p := Packs.active()
	var say := func(key: Variant) -> String: return p.text(["tutorial", str(key)]) if p else ""
	var out := []
	for page in Missions.get_mission(number).pages:
		if not page is Dictionary:
			continue
		var cards := []  # [at, scale] of the page's cards, in order (a note points at one by its index)
		var items := []
		for it in page.get("items", []):
			if not it is Dictionary:
				continue
			var at := _vec(it.get("at"))
			if it.has("card"):
				var k := float(it.get("scale", 1.0))
				cards.append([at, k])
				items.append({"card": str(it.card), "at": at, "k": k})
			elif it.has("note"):
				var b: Array = it.box if it.get("box") is Array and it.box.size() == 4 else [0, 0, 0, 0]
				var box := Rect2(b[0], b[1], b[2], b[3])
				var to: Variant = null
				var t = it.get("to")
				if t is Array:
					to = _vec(t)
				elif t is Dictionary and int(t.get("card", -1)) in range(cards.size()) and PARTS.has(t.get("part")):
					var c: Array = cards[int(t.card)]
					var gem: bool = t.part in ["cost", "attack", "health"]  # the arrow stops at a gem's edge
					to = part(c[0], c[1], t.part, box.get_center(), 18.0 * c[1] if gem else 0.0)
				items.append({"note": say.call(it.note), "box": box, "to": to})
			elif it.has("hero"):
				items.append({"hero": str(it.hero), "at": at, "health": int(it.get("health", 30))})
			elif it.has("mana"):
				items.append({"mana": int(it.mana), "at": at})
			elif it.has("attack") and it.attack is Array and it.attack.size() == 2:
				items.append({"attack": [_vec(it.attack[0]), _vec(it.attack[1])], "blocked": it.get("blocked", false) == true})
			elif it.has("big"):
				items.append({"big": str(it.big), "at": at, "color": Color.from_string(str(it.get("color", "ffffff")), Color.WHITE)})
			elif it.has("picture"):
				items.append({"picture": str(it.picture), "at": at, "size": _vec(it.get("size", [256, 256]))})
		out.append({"title": say.call(page.get("title", "")), "text": say.call(page.get("text", "")),
			"effect": page.get("effect"), "items": items})
	return out


static func _vec(v: Variant) -> Vector2:
	return Vector2(float(v[0]), float(v[1])) if v is Array and v.size() == 2 else Vector2.ZERO


