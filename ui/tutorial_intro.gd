class_name TutorialIntro
extends Control
## What a tutorial mission teaches, shown before it starts: a few panels of real
## cards with notes and arrows pointing at their parts. Next / Play, Skip, Back.

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
	var head := Palette.label("%d. %s" % [number, CardText.name(Missions.get_mission(number).boss)], 22, Palette.TEXT)
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
		elif it.has("mana"):
			var mb := ManaBar.new()
			mb.set_values(it.mana, it.mana, 0)
			mb.position = it.at
			mb.scale = Vector2(1.6, 1.6)
			_stage.add_child(mb)
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


static func _card(id: String, at: Vector2, k: float) -> Dictionary:
	return {"card": id, "at": at, "k": k}


## A note in box; with `to`, an arrow from the box's side to that point.
static func _note(text: String, box: Rect2, to: Variant = null) -> Dictionary:
	return {"note": text, "box": box, "to": to}


## A note pointing at part p of the card at `at` (scale k), the arrow stopping short of gems.
static func _note_at(text: String, box: Rect2, at: Vector2, k: float, p: String) -> Dictionary:
	var gem := p in ["cost", "attack", "health"]
	return _note(text, box, part(at, k, p, box.get_center(), 18.0 * k if gem else 0.0))


## The panels of this mission: {title, text, items}.
func panels() -> Array:
	var c := Vector2(520, 150)  # one big card in the middle (scale 2)
	match number:
		1:
			var yeti := Vector2(250, 160)
			var gnoll := Vector2(820, 160)
			return [
				{"title": tr("A minion card"), "text": tr("Every card costs Mana to play. Minions also have Attack and Health."),
					"items": [_card("VAN_CS2_172", c, 2.0),
						_note_at(tr("Mana cost: what it takes to play the card"), Rect2(130, 136, 320, 100), c, 2.0, "cost"),
						_note_at(tr("Attack: the damage it deals"), Rect2(130, 404, 320, 100), c, 2.0, "attack"),
						_note_at(tr("Health: at 0 the minion dies"), Rect2(830, 404, 320, 100), c, 2.0, "health")]},
				{"title": tr("Combat"), "text": tr("When minions fight, each deals its Attack as damage to the other. A minion with 0 Health dies."),
					"items": [_card("VAN_CS2_182", yeti, 1.8), _card("TU4a_002", gnoll, 1.8),
						{"attack": [yeti + Vector2(232, 150), gnoll + Vector2(-16, 150)]},
						{"big": "-2", "at": part(yeti, 1.8, "health") + Vector2(0, -70), "color": Color("ff6b6b")},
						{"big": "-4", "at": part(gnoll, 1.8, "health") + Vector2(0, -70), "color": Color("ff6b6b")},
						_note(tr("Survives with 3 Health"), Rect2(yeti.x - 20, 480, 256, 50)),
						_note(tr("Dies"), Rect2(gnoll.x - 20, 480, 256, 50))]},
				{"title": tr("Heroes"), "text": tr("Your hero has 30 Health. Attack the enemy hero with your minions: bring it to 0 Health to win!"),
					"items": [{"hero": Missions.JAINA, "at": Vector2(260, 300), "health": 30},
						{"hero": "TU4a_001", "at": Vector2(1020, 300), "health": 10},
						_card("VAN_CS2_168", Vector2(556, 200), 1.4),
						{"attack": [Vector2(740, 320), Vector2(912, 320)]},
						_note(tr("You"), Rect2(130, 430, 260, 50)),
						_note(tr("The enemy hero"), Rect2(890, 430, 260, 50))]},
			]
		2:
			var raider := Vector2(780, 190)
			var raptor := Vector2(980, 190)
			var items: Array = []
			for t in 4:
				items.append(_note(tr("Turn %d") % (t + 1), Rect2(60, 170 + t * 80, 150, 50)))
				items.append({"mana": t + 1, "at": Vector2(230, 160 + t * 80)})
			items.append_array([_card("VAN_CS2_168", raider, 1.3), _card("VAN_CS2_172", raptor, 1.3),
				_note(tr("Costs 1"), Rect2(raider.x - 20, 430, 200, 40)), _note(tr("Costs 2"), Rect2(raptor.x - 20, 430, 200, 40))])
			return [
				{"title": tr("Mana"), "text": tr("You get one more Mana Crystal every turn, up to 10. Playing a card spends its cost. Try to spend all your Mana every turn!"),
					"items": items},
				{"title": tr("Spells"), "text": tr("A spell does its effect once and is gone. Millhouse loves spells! A Frozen character misses its next attack."),
					"items": [_card("VAN_CS2_024", c, 2.0),
						_note_at(tr("Mana cost"), Rect2(130, 136, 320, 100), c, 2.0, "cost"),
						_note_at(tr("What the spell does"), Rect2(830, 356, 290, 100), c, 2.0, "text_r"),
						_note(tr("No Attack, no Health"), Rect2(500, 494, 280, 40))]},
			]
		3:
			var a := Vector2(360, 150)
			var b := Vector2(680, 150)
			return [
				{"title": tr("Battlecry"), "text": tr("A Battlecry happens once, when you play the card from your hand."),
					"items": [_card("VAN_CS2_189", a, 2.0), _card("VAN_EX1_011", b, 2.0),
						_note_at(tr("Battlecry: deals 1 damage when played"), Rect2(20, 346, 300, 120), a, 2.0, "text_l"),
						_note_at(tr("Battlecry: restores Health when played"), Rect2(960, 346, 300, 120), b, 2.0, "text_r")]},
				{"title": tr("Minions first"), "text": tr("While Cho has minions, he can't be attacked. Damage stays on a minion until it is healed, so finish them off!"),
					"items": [_card("TU4f_006", a, 2.0), _card("TU4f_003", b, 2.0),
						_note_at(tr("Cho hides behind his minions"), Rect2(20, 346, 300, 120), a, 2.0, "text_l"),
						_note(tr("Kill them first"), Rect2(960, 346, 300, 120), part(b, 2.0, "text_r"))]},
			]
		4:
			var monkey := Vector2(170, 130)
			var foot := Vector2(560, 260)
			var yeti := Vector2(360, 150)
			var boar := Vector2(680, 150)
			var barrel := Vector2(250, 150)
			var gnome := Vector2(790, 150)
			return [
				{"title": tr("Taunt"), "text": tr("Enemies must attack a minion with Taunt before anything else. Put one in front of your hero!"),
					"items": [_card("TU4f_007", monkey, 1.4), _card("VAN_CS1_042", foot, 1.4),
						{"hero": Missions.JAINA, "at": Vector2(1050, 280), "health": 30},
						{"attack": [monkey + Vector2(178, 170), foot + Vector2(-8, 80)]},
						{"attack": [monkey + Vector2(178, 70), Vector2(950, 230)], "blocked": true},
						_note_at(tr("Taunt: attack this one first"), Rect2(800, 420, 300, 70), foot, 1.4, "text_r")]},
				{"title": tr("Charge"), "text": tr("A minion can't attack on the turn it is played. Minions with Charge can attack right away."),
					"items": [_card("VAN_CS2_182", yeti, 2.0), _card("VAN_CS2_171", boar, 2.0),
						{"big": "Zzz", "at": part(yeti, 2.0, "top") + Vector2(80, -10), "color": Color("a5d8ff")},
						_note(tr("Played this turn: has to wait"), Rect2(20, 346, 300, 120), part(yeti, 2.0, "text_l")),
						_note_at(tr("Charge: attacks at once"), Rect2(960, 346, 300, 120), boar, 2.0, "text_r")]},
				{"title": tr("Deathrattle"), "text": tr("A Deathrattle happens when the minion dies. King Mukla's barrels hide surprises: break one to see what's inside!"),
					"items": [_card("TU4c_003", barrel, 2.0), _card("TU4c_005", gnome, 2.0),
						{"attack": [barrel + Vector2(256, 170), gnome + Vector2(-16, 170)]},
						_note(tr("When it dies..."), Rect2(barrel.x - 10, 494, 260, 40)),
						_note(tr("...out comes a gnome!"), Rect2(gnome.x - 10, 494, 260, 40))]},
			]
		5:
			var fire := Vector2(300, 150)
			var shot := Vector2(740, 150)
			return [
				{"title": tr("Hero Power"), "text": tr("Every hero has a Hero Power. It costs 2 Mana and can be used once each turn."),
					"items": [_card(Missions.FIREBLAST, fire, 2.0), _card("TU4d_003", shot, 2.0),
						_note(tr("Your Hero Power"), Rect2(fire.x - 10, 494, 260, 40)),
						_note(tr("Hemet's Hero Power"), Rect2(shot.x - 10, 494, 260, 40)),
						_note_at(tr("Mana cost"), Rect2(20, 120, 230, 80), fire, 2.0, "cost")]},
				{"title": tr("Freeze"), "text": tr("A Frozen character misses its next attack. Freeze Hemet's hunters and kill them before they swarm you!"),
					"items": [_card("VAN_CS2_033", c, 2.0),
						_note_at(tr("Freezes whatever it damages"), Rect2(830, 356, 290, 100), c, 2.0, "text_r")]},
			]
		_:
			var a := Vector2(170, 170)
			var b := Vector2(550, 170)
			var d := Vector2(930, 170)
			return [
				{"title": tr("Weapons"), "text": tr("A weapon lets a hero attack. Illidan wields warglaives! A hero who attacks a minion takes damage back."),
					"items": [_card("TU4e_004", c, 2.0),
						_note_at(tr("Attack: the damage the hero deals"), Rect2(130, 404, 320, 100), c, 2.0, "attack"),
						_note_at(tr("Durability: drops by 1 with each attack; at 0 the weapon breaks"), Rect2(820, 404, 340, 100), c, 2.0, "health")]},
				{"title": tr("Putting it all together"), "text": tr("Illidan is strong. Use everything you have learned: guard your hero with Taunt and clear his minions with spells."),
					"items": [_card("TU4e_002", a, 1.5), _card("VAN_CS2_027", b, 1.5), _card("VAN_CS2_032", d, 1.5),
						_note(tr("His Hero Power: two minions every turn"), Rect2(a.x - 40, 440, 260, 80)),
						_note(tr("Taunt guards your hero"), Rect2(b.x - 40, 440, 260, 80)),
						_note(tr("Hits all enemy minions"), Rect2(d.x - 40, 440, 260, 80))]},
			]
