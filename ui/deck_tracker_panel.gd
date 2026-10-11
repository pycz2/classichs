class_name DeckTrackerPanel
extends Panel
## The deck tracker in a match: own starting deck, cards left with the chance to
## draw each next, cards the opponent played. Each view can be hidden; the choice
## is saved in the settings.

## [node prefix, title (English key), settings key]
const VIEWS := [["Deck", "Your deck", "tracker_deck"], ["Left", "Cards left in deck", "tracker_left"],
	["Opponent", "Opponent played", "tracker_opp"]]

var _lists := {}
var _headers := {}


func _ready() -> void:
	name = "DeckTracker"
	position = Vector2(760, 20)
	size = Vector2(360, 560)
	add_theme_stylebox_override("panel", Palette.box(Color(0.08, 0.06, 0.05, 0.92), 12))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(10, 10)
	scroll.size = size - Vector2(20, 20)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = scroll.size.x - 16
	scroll.add_child(box)
	for v in VIEWS:
		var header := Button.new()
		header.name = v[0] + "Header"
		header.flat = true
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.add_theme_font_size_override("font_size", 18)
		header.add_theme_color_override("font_color", Palette.ATTACK)
		box.add_child(header)
		var list := VBoxContainer.new()
		list.name = v[0] + "List"
		list.visible = Settings.data[v[2]]
		box.add_child(list)
		_lists[v[0]] = list
		_headers[v[0]] = header
		var key: String = v[2]
		header.pressed.connect(func():
			list.visible = not list.visible
			Settings.data[key] = list.visible
			Settings.save()
			relabel())
	relabel()


func relabel() -> void:
	for v in VIEWS:
		_headers[v[0]].text = ("– " if _lists[v[0]].visible else "+ ") + tr(v[1])


func update_from(g: Game, me: int) -> void:
	_fill("Deck", DeckTracker.deck_view(g, me).map(func(r):
		return [_cost(r.card), "%s  %d/%d" % [CardText.name(r.card), r.left, r.total], r.left > 0]))
	_fill("Left", DeckTracker.remaining(g, me).map(func(r):
		return [_cost(r.card), "%s ×%d  %d%%" % [CardText.name(r.card), r.count, roundi(r.chance * 100)], true]))
	_fill("Opponent", DeckTracker.opponent_played(g, me).map(func(c):
		return ["?" if c == "" else _cost(c), tr("Secret") if c == "" else CardText.name(c), true]))


func _cost(card: String) -> String:
	return str(CardDb.card(card).get("cost", 0))


func _fill(view: String, rows: Array) -> void:
	var list: VBoxContainer = _lists[view]
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for r in rows:
		var l := Palette.label("%s  %s" % [r[0], r[1]], 15)
		if not r[2]:
			l.modulate = Color(1, 1, 1, 0.35)
		list.add_child(l)
