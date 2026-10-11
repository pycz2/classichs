class_name HistoryStrip
extends Control
## The history bar on the left, like the original: a tile with the picture of
## every card played, attack or hero power, newest on top; blue edge for your
## moves, red for the opponent's. A gold "Turn N" line heads the moves of each
## turn. Hovering a tile shows the card and what the move did (whom it hit,
## healed, buffed, summoned…); a click opens the full text history.

signal open_history

const TILE := 46.0
const SEP := 18.0  # height of a turn line
const MAX := 11
const GOLD := Color("c9a74a")
const ROWS := 14  # effect rows shown in a pop-up

var _items: Array = []  # tiles [card_id, mine, history index]; turn lines [turn, mine]
var _hover := -1
var _g: GameState
var _viewer := -1
var popup: Control  # the hovered move: card, who, effects
var _tips: Control


func _ready() -> void:
	name = "HistoryStrip"
	position = Vector2(8, 60)
	size = Vector2(TILE + 8, (TILE + 6) * MAX)
	mouse_filter = Control.MOUSE_FILTER_STOP


static func _edge(mine: bool) -> Color:
	return Color("4dabf7") if mine else Color("ff6b6b")


static func _height(it: Array) -> float:
	return SEP if it[0] is int else TILE + 6


## Rebuilds the tiles from the game history, seen by viewer.
func update_from(g: GameState, viewer: int) -> void:
	_g = g
	_viewer = viewer
	var items := []
	var turn := -1
	var h := 0.0
	for i in range(g.history.size() - 1, -1, -1):
		var entry: Dictionary = g.history[i]
		var a: Dictionary = entry.action
		var e := g.ent(HistoryText.actor(entry, g))
		if e == null:
			continue
		var mine: bool = int(entry.player) == viewer
		var tile := []
		if entry.turn != turn:
			turn = entry.turn
			tile.append([turn, mine])
		var secret: bool = a.get("type") == "play" and e.card().get("mechanics", []).has("SECRET") and not mine and e.zone == "SECRET"
		tile.append(["" if secret else e.card_id, mine, i])
		for it in tile:
			h += _height(it)
		if h > (TILE + 6) * MAX:
			break
		items.append_array(tile)
	if items != _items:
		_items = items
		hover(-1)
		queue_redraw()


## Index in _items of the row at y, or -1.
func index_at(y: float) -> int:
	var top := 0.0
	for i in _items.size():
		var h := _height(_items[i])
		if y >= top and y < top + h:
			return i
		top += h
	return -1


func card_at(y: float) -> String:
	var i := index_at(y)
	return _items[i][0] if i >= 0 and _items[i][0] is String else ""


func _top_of(i: int) -> float:
	var top := 0.0
	for k in i:
		top += _height(_items[k])
	return top


## Shows the pop-up of row i (-1 or a turn line hides it).
func hover(i: int) -> void:
	if i >= 0 and _items[i][0] is int:
		i = -1
	if i == _hover:
		return
	_hover = i
	for c in [popup, _tips]:
		if c:
			c.queue_free()
	popup = null
	_tips = null
	if i >= 0 and _g and _items[i].size() > 2:
		_make_popup(_items[i], _top_of(i))


func _make_popup(it: Array, y: float) -> void:
	var entry: Dictionary = _g.history[it[2]]
	var card: String = it[0]
	popup = PanelContainer.new()
	popup.name = "HistoryPopup"
	var style := Palette.box(Palette.PANEL, 10, _edge(it[1]), 2)
	style.set_content_margin_all(10)
	popup.add_theme_stylebox_override("panel", style)
	popup.top_level = true
	popup.z_index = 95
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	popup.add_child(row)
	if card != "":
		var cv := CardView.make(card, 1.4)
		cv.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(cv)
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 300
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)
	var title := Palette.label(HistoryText.title(entry, _g, _viewer), 16, _edge(it[1]))
	title.name = "Title"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 300
	col.add_child(title)
	var from := ""
	var effects := HistoryText.effects(entry, _g, _viewer)
	for k in mini(effects.size(), ROWS):
		var ef: Dictionary = effects[k]
		if ef.from != from:
			from = ef.from
			if from != "":
				col.add_child(_line(from, 13, GOLD))
		var r := _effect_row(ef)
		r.name = "Effect%d" % k
		col.add_child(r)
	if effects.size() > ROWS:
		col.add_child(_line("…", 14, Palette.TEXT))
	add_child(popup)
	popup.reset_size()
	var h := popup.get_combined_minimum_size().y
	var bottom := get_viewport_rect().size.y - 8
	popup.global_position = Vector2(global_position.x + size.x + 6, clampf(global_position.y + y - 30, 8, bottom - h))
	if card != "":
		_tips = KeywordTips.make(card)
		if _tips.get_child_count() == 0:
			_tips.free()
			return
		_tips.top_level = true
		_tips.z_index = 95
		add_child(_tips)
		_tips.beside(Rect2(popup.global_position, popup.get_combined_minimum_size()))


static func _line(text: String, font: int, color: Color) -> Label:
	var l := Palette.label(text, font, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	return l


## One effect: the affected card's picture and name, and what happened to it.
static func _effect_row(ef: Dictionary) -> Control:
	var color: Color = {"good": Palette.BUFFED, "bad": Color("ff6b6b")}.get(ef.color, Palette.TEXT)
	if ef.name == "":
		return _line(ef.text, 14, color)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(26, 26)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if ef.card != "":
		pic.draw.connect(func(): Art.paint_in(pic, Rect2(Vector2.ZERO, pic.size), ef.card, "rect"))
	row.add_child(pic)
	var n := Palette.label(ef.name, 14)
	n.custom_minimum_size.x = 150
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.clip_text = true
	row.add_child(n)
	var what := Palette.label(ef.text, 14, color)  # long effects wrap rather than cut the name
	what.custom_minimum_size.x = 300 - 26 - 150 - 12  # a fixed width: a wrapping label has no height before it
	what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(what)
	return row


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		hover(index_at(ev.position.y))  # one pop-up per tile, not one per mouse move
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		open_history.emit()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover(-1)


func _draw() -> void:
	var font := get_theme_default_font()
	var top := 0.0
	for it in _items:
		if it[0] is int:  # turn line: gold rule, "Turn N" in the player's colour
			draw_line(Vector2(2, top + SEP / 2), Vector2(TILE + 6, top + SEP / 2), GOLD, 2)
			var text := tr("Turn %d") % it[0]
			var fs := 11
			while fs > 7 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > TILE + 2:
				fs -= 1
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var x := (TILE + 8 - w) / 2
			draw_rect(Rect2(x - 2, top + 3, w + 4, SEP - 6), Color("1b140f"))
			draw_string(font, Vector2(x, top + SEP / 2 + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _edge(it[1]))
		else:
			var r := Rect2(Vector2(4, top), Vector2(TILE, TILE))
			draw_style_box(Palette.box(Color("1b140f"), 8, _edge(it[1]), 3), r.grow(2))
			if it[0] == "":
				draw_style_box(Palette.box(Color("7048e8"), 6), r)
			else:
				Art.paint_in(self, r, it[0], "rect")
		top += _height(it)
