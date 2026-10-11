class_name CollectionView
extends Control
## All collectible cards, 8 per page, with class tabs, cost filter and search.
## With a deck it becomes the deck builder: click a card to add it, click a
## line in the deck list to remove one copy.

signal done(deck: Deck)
## The deck changed (card added or removed, name edited): the owner saves at once.
signal changed

const PER_PAGE := 8
const CLASSES := ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR", "NEUTRAL"]

var deck: Deck  # null = browse only
var page := 0
var tab := "DRUID"
var cost_filter := -1  # -1 = any, 7 = 7 or more
var query := ""
var _grid := GridContainer.new()
var _page_label: Label
var _hint: Label
var _deck_list := VBoxContainer.new()
var _count: Label
var _name_edit := LineEdit.new()
var _tabs := HBoxContainer.new()
var _tooltip: CardView


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if deck:
		tab = deck.card_class()
	_tabs.position = Vector2(16, 10)
	_tabs.add_theme_constant_override("separation", 4)
	add_child(_tabs)
	for cls in tabs():
		var b := Button.new()
		b.name = "Tab" + cls
		b.tooltip_text = tr("Neutral") if cls == "NEUTRAL" else CardText.name(Decks.hero(cls))
		b.custom_minimum_size = Vector2(52, 40)
		b.add_theme_stylebox_override("normal", Palette.box(Palette.of_class(cls).darkened(0.35), 8))
		Icons.attach(b, cls, 34)
		var c: String = cls
		b.pressed.connect(func(): set_tab(c))
		_tabs.add_child(b)
	var search := LineEdit.new()
	search.name = "Search"
	search.placeholder_text = tr("Search")
	search.position = Vector2(16, 52)
	search.size = Vector2(260, 34)
	search.text_changed.connect(func(t):
		query = t
		page = 0
		_fill())
	add_child(search)
	var costs := HBoxContainer.new()
	costs.position = Vector2(290, 52)
	add_child(costs)
	for c in range(-1, 8):
		var b := Button.new()
		b.name = "Cost%d" % c
		b.text = tr("All") if c < 0 else ("7+" if c == 7 else str(c))
		b.custom_minimum_size = Vector2(44, 34)
		var v: int = c
		b.pressed.connect(func():
			cost_filter = v
			page = 0
			_fill())
		costs.add_child(b)
	_grid.columns = 4
	_grid.position = Vector2(24, 96)
	_grid.add_theme_constant_override("h_separation", 22)
	_grid.add_theme_constant_override("v_separation", 14)
	add_child(_grid)
	var prev := Palette.button("<", "Prev")
	prev.custom_minimum_size = Vector2(60, 44)
	prev.position = Vector2(30, 660)
	prev.pressed.connect(func(): turn_page(-1))
	add_child(prev)
	var next := Palette.button(">", "Next")
	next.custom_minimum_size = Vector2(60, 44)
	next.position = Vector2(560, 660)
	next.pressed.connect(func(): turn_page(1))
	add_child(next)
	_page_label = Palette.label("", 18)
	_page_label.position = Vector2(110, 670)
	add_child(_page_label)
	_hint = Palette.label("", 18, Palette.SELECTED)
	_hint.position = Vector2(200, 670)
	_hint.name = "Hint"
	add_child(_hint)
	if deck:
		_build_sidebar()
	else:
		var back := Palette.button(tr("Back"), "Back")
		back.custom_minimum_size = Vector2(160, 44)
		back.position = Vector2(1100, 660)
		back.pressed.connect(func(): done.emit(null))
		add_child(back)
	_fill()


func tabs() -> Array:
	return [deck.card_class(), "NEUTRAL"] if deck else CLASSES


func set_tab(cls: String) -> void:
	tab = cls
	page = 0
	_fill()


## Cards matching the current tab, cost filter and search, sorted by cost and name.
func filtered() -> Array:
	var out: Array = []
	var q := query.strip_edges().to_lower()
	for id in CardDb.collectible():
		var c := CardDb.card(id)
		if c.cardClass != tab:
			continue
		var cost := int(c.get("cost", 0))
		if cost_filter >= 0 and (cost != cost_filter if cost_filter < 7 else cost < 7):
			continue
		if q != "" and not CardText.name(id).to_lower().contains(q) and not CardText.text(id).to_lower().contains(q):
			continue
		out.append(id)
	out.sort_custom(func(a, b):
		var ca := int(CardDb.card(a).get("cost", 0))
		var cb := int(CardDb.card(b).get("cost", 0))
		return ca < cb or (ca == cb and CardText.name(a) < CardText.name(b)))
	return out


func page_count() -> int:
	return maxi(1, ceili(filtered().size() / float(PER_PAGE)))


func turn_page(delta: int) -> void:
	page = clampi(page + delta, 0, page_count() - 1)
	_fill()


func shown_cards() -> Array:
	return _grid.get_children().map(func(c): return c.card_id)


func _fill() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var ids := filtered()
	for id in ids.slice(page * PER_PAGE, (page + 1) * PER_PAGE):
		var cv := CardView.make(id, 1.5 if deck == null else 1.36)
		cv.clicked.connect(func(v): click_card(v.card_id))
		cv.hovered.connect(_on_hover)
		if deck and deck.count(id) > 0:
			var badge := Palette.label("×%d" % deck.count(id), 22, Palette.ATTACK)
			badge.position = Vector2(cv.size.x - 34, -8)
			cv.add_child(badge)
		_grid.add_child(cv)
	_page_label.text = "%d / %d" % [page + 1, page_count()]
	for b in _tabs.get_children():
		b.modulate = Color.WHITE if b.name == "Tab" + tab else Color(1, 1, 1, 0.6)


func show_hint(text: String) -> void:
	_hint.text = text


func click_card(id: String) -> void:
	if deck == null:
		return
	var why := deck.add(id)
	show_hint(why)
	_fill()
	_refresh_deck()
	if why == "":
		changed.emit()


func _on_hover(v: EntityView, on: bool) -> void:
	if _tooltip:
		_tooltip.queue_free()
		_tooltip = null
	if on:
		_tooltip = CardView.make((v as CardView).card_id, 1.9)
		_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tooltip.position = Vector2(650, 120) if deck == null else Vector2(640, 110)
		add_child(_tooltip)


# --- deck sidebar ---------------------------------------------------------------

func _build_sidebar() -> void:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL, 10, Palette.of_class(deck.card_class()), 3))
	panel.position = Vector2(960, 52)
	panel.size = Vector2(304, 600)
	add_child(panel)
	_name_edit.name = "DeckName"
	_name_edit.text = deck.name
	_name_edit.max_length = Deck.NAME_MAX
	_name_edit.position = Vector2(10, 10)
	_name_edit.size = Vector2(284, 36)
	_name_edit.text_changed.connect(func(t):
		deck.name = t
		changed.emit())
	panel.add_child(_name_edit)
	_count = Palette.label("", 18)
	_count.position = Vector2(12, 52)
	panel.add_child(_count)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 84)
	scroll.size = Vector2(288, 506)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_deck_list.custom_minimum_size.x = 272
	scroll.add_child(_deck_list)
	var save := Palette.button(tr("Done"), "Done")
	save.custom_minimum_size = Vector2(160, 44)
	save.position = Vector2(1100, 660)
	save.pressed.connect(func(): done.emit(deck))
	add_child(save)
	_refresh_deck()


func _refresh_deck() -> void:
	if deck == null:
		return
	for c in _deck_list.get_children():
		_deck_list.remove_child(c)
		c.queue_free()
	for pair in deck.sorted_counts():
		var b := Button.new()
		var id: String = pair[0]
		b.name = "Entry_" + id
		b.text = "(%d) %s%s" % [CardDb.card(id).get("cost", 0), CardText.name(id), "  ×2" if pair[1] == 2 else ""]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(272, 30)
		b.pressed.connect(func(): remove_card(id))
		_deck_list.add_child(b)
	_count.text = "%d / %d" % [deck.cards.size(), Deck.SIZE]
	_count.add_theme_color_override("font_color", Palette.BUFFED if deck.cards.size() == Deck.SIZE else Palette.TEXT)


func remove_card(id: String) -> void:
	if deck.remove(id):
		changed.emit()
	show_hint("")
	_fill()
	_refresh_deck()
