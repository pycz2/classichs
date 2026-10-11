class_name CollectionView
extends Control
## The left half of the collection screen: all collectible cards, 8 per page,
## under class tabs, with search, type, cost and rarity filters that combine.
## With a deck set it shows only the cards that deck can use, and a click on a
## card adds it (DeckListView keeps the deck list on the right).

## The deck changed (a card was added): the owner saves at once.
signal changed
## Browsing (no deck): a card was clicked.
signal picked(id: String)

const PER_PAGE := 8
const CLASSES := ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR", "NEUTRAL"]
const RARITIES := [["FREE", "Basic"], ["COMMON", "Common"], ["RARE", "Rare"], ["EPIC", "Epic"], ["LEGENDARY", "Legendary"]]
const TYPES := [["MINION", "Minions"], ["SPELL", "Spells"], ["WEAPON", "Weapons"]]
## The card area under the tabs (screen coordinates: this view sits at 0,0).
const AREA := Rect2(16, 66, 884, 642)
const CARD_SCALE := 1.32

var deck: Deck  # null = browse only
var page := 0
var tab := "DRUID"
var cost_filter := -1  # -1 = any, 7 = 7 or more
var query := ""
## "" = any rarity; else FREE (Basic), COMMON, RARE, EPIC or LEGENDARY.
var rarity_filter := ""
## "" = any type; else MINION, SPELL or WEAPON.
var type_filter := ""
## Only these cards (a Dictionary with the ids as keys); null = all.
var only: Variant = null
## Debug tools: tokens and other uncollectible cards are listed too (not heroes or hero powers).
var include_tokens := false
var _grid := GridContainer.new()
var _page_label: Label
var _prev: Button
var _next: Button
var _hint: Label
var _empty: Label
var _area := Panel.new()
var _tabs := HBoxContainer.new()
var _tips: KeywordTips
var _tooltip: CardView


func _ready() -> void:
	size = Vector2(AREA.end.x, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.name = "CardArea"
	_area.position = AREA.position
	_area.size = AREA.size
	add_child(_area)
	_tabs.name = "Tabs"
	_tabs.position = Vector2(AREA.position.x + 10, 10)
	_tabs.size = Vector2(AREA.size.x - 20, AREA.position.y - 10)
	_tabs.add_theme_constant_override("separation", 4)
	add_child(_tabs)
	for cls in CLASSES:
		var b := Button.new()
		b.name = "Tab" + cls
		b.tooltip_text = tr("Neutral") if cls == "NEUTRAL" else CardText.name(Decks.hero(cls))
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_vertical = Control.SIZE_SHRINK_END
		Icons.attach(b, cls, 34)
		var c: String = cls
		b.pressed.connect(func(): set_tab(c))
		_tabs.add_child(b)
	# row 1: search and card type; row 2: cost crystals and rarity gems
	var rows := VBoxContainer.new()
	rows.position = AREA.position + Vector2(14, 14)
	rows.size = Vector2(AREA.size.x - 28, 88)
	rows.add_theme_constant_override("separation", 8)
	add_child(rows)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	rows.add_child(row1)
	var search := LineEdit.new()
	search.name = "Search"
	search.placeholder_text = tr("Search")
	search.custom_minimum_size = Vector2(0, 40)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.clear_button_enabled = true
	search.text_changed.connect(func(t):
		query = t
		page = 0
		_fill())
	row1.add_child(search)
	for t in TYPES:  # a second click clears
		var b := chip("Type" + t[0], Vector2(120, 40))
		b.text = tr(t[1])
		var code: String = t[0]
		b.pressed.connect(func():
			type_filter = "" if type_filter == code else code
			page = 0
			_fill())
		row1.add_child(b)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	rows.add_child(row2)
	for c in range(-1, 8):
		var b := chip("Cost%d" % c, Vector2(56 if c < 0 else 44, 40))
		b.text = tr("All") if c < 0 else ""
		if c >= 0:  # a mana crystal with the cost
			var gem := _Crystal.new()
			gem.value = c
			gem.plus = c == 7
			gem.size = Vector2(44, 40)
			gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(gem)
		var v: int = c
		b.pressed.connect(func():
			cost_filter = v
			page = 0
			_fill())
		row2.add_child(b)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(gap)
	for r in RARITIES:  # a second click clears
		var b := chip("Rarity" + r[0], Vector2(44, 40))
		b.tooltip_text = tr(r[1])
		var gem := _Gem.new()
		gem.rarity = r[0]
		gem.size = Vector2(44, 40)
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(gem)
		var code: String = r[0]
		b.pressed.connect(func():
			rarity_filter = "" if rarity_filter == code else code
			page = 0
			_fill())
		row2.add_child(b)
	_grid.name = "Grid"
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 24)
	_grid.add_theme_constant_override("v_separation", 14)
	var card := CardView.SIZE * CARD_SCALE
	var grid_w := card.x * 4 + 24 * 3
	_grid.position = Vector2(AREA.position.x + (AREA.size.x - grid_w) / 2.0, AREA.position.y + 116)
	add_child(_grid)
	_empty = Palette.label(tr("No cards match the filters"), 20, Palette.ARMOR)
	_empty.name = "Empty"
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.position = Vector2(AREA.position.x, AREA.position.y + 300)
	_empty.size = Vector2(AREA.size.x, 30)
	add_child(_empty)
	# the pager, centred under the grid
	var pager := HBoxContainer.new()
	pager.name = "Pager"
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.position = Vector2(AREA.position.x, AREA.end.y - 52)
	pager.size = Vector2(AREA.size.x, 42)
	pager.add_theme_constant_override("separation", 10)
	add_child(pager)
	_prev = Palette.button("<", "Prev")
	_prev.custom_minimum_size = Vector2(56, 42)
	_prev.pressed.connect(func(): turn_page(-1))
	pager.add_child(_prev)
	_page_label = Palette.label("", 20)
	_page_label.name = "Page"
	_page_label.custom_minimum_size = Vector2(90, 42)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pager.add_child(_page_label)
	_next = Palette.button(">", "Next")
	_next.custom_minimum_size = Vector2(56, 42)
	_next.pressed.connect(func(): turn_page(1))
	pager.add_child(_next)
	_hint = Palette.label("", 15, Palette.SELECTED)
	_hint.name = "Hint"
	_hint.position = Vector2(AREA.position.x + 14, AREA.end.y - 56)
	_hint.size = Vector2(300, 50)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)
	set_deck(deck)


## Starts (a deck) or ends (null) building: only usable class tabs are shown.
func set_deck(d: Deck) -> void:
	deck = d
	if deck:
		tab = deck.card_class()
	elif not tab in CLASSES:
		tab = CLASSES[0]
	for b in _tabs.get_children():
		b.visible = (b.name as String).trim_prefix("Tab") in tabs()
	page = 0
	show_hint("")
	_fill()


func tabs() -> Array:
	return [deck.card_class(), "NEUTRAL"] if deck else CLASSES


func set_tab(cls: String) -> void:
	tab = cls
	page = 0
	_fill()


## Cards matching the tab and every filter, sorted by cost and name.
func filtered() -> Array:
	var out: Array = []
	var q := query.strip_edges().to_lower()
	for id in (CardDb.all_ids() if include_tokens else CardDb.collectible()):
		var c := CardDb.card(id)
		if include_tokens and c.get("type", "") in ["HERO", "HERO_POWER", "ENCHANTMENT"]:
			continue
		if c.cardClass != tab or (only != null and not only.has(id)):
			continue
		var cost := int(c.get("cost", 0))
		if cost_filter >= 0 and (cost != cost_filter if cost_filter < 7 else cost < 7):
			continue
		if rarity_filter != "" and c.get("rarity", "") != rarity_filter:
			continue
		if type_filter != "" and c.get("type", "") != type_filter:
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
	_on_hover(null, false)
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var ids := filtered()
	var pages := maxi(1, ceili(ids.size() / float(PER_PAGE)))
	page = clampi(page, 0, pages - 1)
	for id in ids.slice(page * PER_PAGE, (page + 1) * PER_PAGE):
		var cv := CardView.make(id, CARD_SCALE)
		cv.clicked.connect(func(v): click_card(v.card_id))
		cv.hovered.connect(_on_hover)
		if deck and deck.count(id) > 0:
			var badge := Palette.label("×%d" % deck.count(id), 22, Palette.ATTACK)
			badge.position = Vector2(cv.size.x - 34, -8)
			cv.add_child(badge)
		_grid.add_child(cv)
	_empty.visible = ids.is_empty()
	_page_label.text = "%d / %d" % [page + 1, pages]
	_prev.disabled = page == 0
	_next.disabled = page >= pages - 1
	var col := Palette.of_class(tab)
	_area.add_theme_stylebox_override("panel", Palette.box(col.darkened(0.78), 12, col.darkened(0.2), 2))
	for b: Button in _tabs.get_children():
		var cls := (b.name as String).trim_prefix("Tab")
		var on := cls == tab
		b.custom_minimum_size = Vector2(78, 56 if on else 46)
		var st: StyleBoxFlat
		if on:  # the open tab: lit, taller, and joined to the card area under it
			st = Palette.box(col.darkened(0.78), 12, col.darkened(0.2), 2)
			st.border_width_bottom = 0
			st.expand_margin_bottom = 2
		else:
			st = Palette.box(Palette.of_class(cls).darkened(0.55), 10, Color(0, 0, 0, 0.5), 1)
			st.border_width_bottom = 0
		st.corner_radius_bottom_left = 0
		st.corner_radius_bottom_right = 0
		for s in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(s, st)
		b.modulate = Color.WHITE if on else Color(0.75, 0.75, 0.75)
	for b in find_children("Cost*", "Button", true, false):
		b.set_pressed_no_signal(b.name == "Cost%d" % cost_filter)
	for b in find_children("Rarity*", "Button", true, false):
		b.set_pressed_no_signal(b.name == "Rarity" + rarity_filter)
	for b in find_children("Type*", "Button", true, false):
		b.set_pressed_no_signal(b.name == "Type" + type_filter)


func show_hint(text: String) -> void:
	_hint.text = text


func click_card(id: String) -> void:
	if deck == null:
		picked.emit(id)
		return
	var why := deck.add(id)
	show_hint(why)
	_fill()
	if why == "":
		changed.emit()


## The big card beside the hovered one, with its keyword tips.
func _on_hover(v: EntityView, on: bool) -> void:
	if _tooltip:
		_tooltip.queue_free()
		_tooltip = null
	if _tips:
		_tips.queue_free()
		_tips = null
	if on:
		_tooltip = CardView.make((v as CardView).card_id, 1.9)
		_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tooltip.z_index = 50
		_tooltip.top_level = true  # screen coordinates, at full size even in a scaled-down view
		var r := v.get_global_rect()
		var x := r.end.x + 10 if r.end.x + 10 + _tooltip.size.x < 1270 else r.position.x - _tooltip.size.x - 10
		_tooltip.position = Vector2(x, clampf(r.position.y - 40, 8, 712 - _tooltip.size.y))
		add_child(_tooltip)
		_tips = KeywordTips.make(_tooltip.card_id)
		_tips.z_index = 50
		_tips.top_level = true
		if _tips.get_child_count() > 0:
			add_child(_tips)
			_tips.beside(Rect2(_tooltip.position, _tooltip.size))


## A filter button: dark when off, lit with a gold edge when on.
static func chip(id: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.name = id
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 17)
	var off := Palette.box(Color(0.1, 0.07, 0.05, 0.85), 8, Color("6b5320"), 1)
	var hover := Palette.box(Color(0.18, 0.13, 0.08, 0.9), 8, Color("a8873a"), 1)
	var on := Palette.box(Color(0.36, 0.26, 0.1, 0.95), 8, Frames.GOLD, 2)
	for st: StyleBoxFlat in [off, hover, on]:
		st.content_margin_left = 8
		st.content_margin_right = 8
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", Color("fff3c4"))
	b.add_theme_color_override("font_hover_pressed_color", Color("fff3c4"))
	b.pressed.connect(Sound.play.bind("click"))
	return b


class _Crystal:
	extends Control
	var value := 0
	var plus := false

	func _draw() -> void:
		Frames.mana(self, size / 2.0, value, 15)
		if plus:
			var font := ThemeDB.fallback_font
			draw_string_outline(font, size / 2.0 + Vector2(9, -6), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 3, Color.BLACK)
			draw_string(font, size / 2.0 + Vector2(9, -6), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


class _Gem:
	extends Control
	var rarity := ""

	func _draw() -> void:
		if rarity == "FREE":  # Basic cards have no gem: a plain grey one stands for them
			draw_colored_polygon(PackedVector2Array([size / 2 + Vector2(0, -9), size / 2 + Vector2(7, 0), size / 2 + Vector2(0, 9), size / 2 + Vector2(-7, 0)]), Color("868e96"))
		else:
			Frames.rarity(self, size / 2.0, rarity, 9)

