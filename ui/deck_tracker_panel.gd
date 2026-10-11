class_name DeckTrackerPanel
extends Panel
## The deck tracker in a match, drawn like the deck builder's list: your deck
## (cards already drawn dimmed, the chance to draw each card next) and the cards
## the opponent played. Each section folds; the choice is saved in the settings.

## [node prefix, title (English key), settings key, share of the height]
const VIEWS := [["Deck", "Your deck", "tracker_deck", 3.0], ["Opponent", "Opponent played", "tracker_opp", 2.0]]
const SIZE := Vector2(330, 540)
## Where the open panel stands: left of End Turn, above the hand.
const SPOT := Vector2(794, 50)

var _lists := {}
var _headers := {}


func _ready() -> void:
	name = "DeckTracker"
	position = SPOT
	size = SIZE
	add_theme_stylebox_override("panel", Palette.box(Color(0.08, 0.06, 0.05, 0.94), 12, Color("6b5320"), 2))
	var box := VBoxContainer.new()
	box.position = Vector2(10, 8)
	box.size = size - Vector2(20, 16)
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	for v in VIEWS:
		var header := Button.new()
		header.name = v[0] + "Header"
		header.flat = true
		header.focus_mode = Control.FOCUS_NONE
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.add_theme_font_size_override("font_size", 18)
		header.add_theme_color_override("font_color", Palette.ATTACK)
		box.add_child(header)
		var scroll := ScrollContainer.new()
		scroll.name = v[0] + "Scroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_stretch_ratio = v[3]
		scroll.visible = Settings.data[v[2]]
		box.add_child(scroll)
		var list := VBoxContainer.new()
		list.name = v[0] + "List"
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 1)
		scroll.add_child(list)
		if v[0] == "Opponent":  # the list grows at the end: keep the newest card in sight
			var bar := scroll.get_v_scroll_bar()
			bar.changed.connect(func(): scroll.scroll_vertical = int(bar.max_value))
		_lists[v[0]] = list
		_headers[v[0]] = header
		var key: String = v[2]
		header.pressed.connect(func():
			scroll.visible = not scroll.visible
			Settings.data[key] = scroll.visible
			Settings.save()
			relabel())
	relabel()


func relabel() -> void:
	for v in VIEWS:
		_headers[v[0]].text = ("– " if _lists[v[0]].get_parent().visible else "+ ") + tr(v[1])


## Opens (slides in from the right edge) or closes the panel.
func slide(open: bool) -> void:
	if has_meta("tween"):
		(get_meta("tween") as Tween).kill()
	var to := SPOT.x if open else 1290.0
	if open and not visible:
		position.x = 1290.0
	visible = true
	if Anim.instant or not is_inside_tree():
		position.x = to
		visible = open
		return
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position:x", to, 0.25)
	if not open:
		tw.tween_callback(hide)
	set_meta("tween", tw)


func update_from(g: Game, me: int) -> void:
	_fill("Deck", DeckTracker.deck_view(g, me).map(func(r):
		return [r.card, r.left, r.left == 0, "%d%%" % roundi(r.chance * 100) if r.left > 0 else ""]))
	_fill("Opponent", DeckTracker.opponent_counts(g, me).map(func(r): return [r.card, r.count, false, ""]))


## Rows of [card id ("" = a hidden Secret), copies, dimmed, chance text].
func _fill(view: String, rows: Array) -> void:
	var list: VBoxContainer = _lists[view]
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for r in rows:
		var tile: Control = DeckTiles.DeckTile.new(r[0], r[1]) if r[0] != "" else _Hidden.new()
		tile.custom_minimum_size = Vector2(0, 32)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.mouse_filter = Control.MOUSE_FILTER_PASS  # the wheel still scrolls the list
		if r[2]:
			tile.modulate = Color(1, 1, 1, 0.35)
		if view != "Deck":
			list.add_child(tile)
			continue
		var row := HBoxContainer.new()
		row.name = "Row_" + r[0]
		row.add_theme_constant_override("separation", 4)
		row.add_child(tile)
		var chance := Palette.label(r[3], 15, Color("8fd3ff"))
		chance.name = "Chance"
		chance.custom_minimum_size = Vector2(44, 0)
		chance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		chance.tooltip_text = tr("Chance to draw it next")
		chance.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(chance)
		list.add_child(row)


## An opponent's Secret not revealed yet: a "?" instead of the card.
class _Hidden:
	extends Button

	func _init() -> void:
		name = "Entry_Secret"
		tooltip_text = tr("Secret")
		focus_mode = Control.FOCUS_NONE
		flat = true

	func _draw() -> void:
		draw_style_box(Palette.box(Color("1b140f"), 8, Color("6b5320"), 2), Rect2(Vector2(0, 1), size - Vector2(0, 2)))
		draw_rect(Rect2(Vector2(26, 2), size - Vector2(28, 4)), Color("3b2350"))
		DeckTiles.text(self, Vector2(11, size.y / 2.0 + 7), "?", 20, Frames.GOLD)
		DeckTiles.text(self, Vector2(36, size.y / 2.0 + 6), tr("Secret"), 16)
