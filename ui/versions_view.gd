class_name VersionsView
extends Control
## The Versions of a game with versions (docs/packs/format.md §13), the screen entering it opens (from the games
## library or a server's games): the versions by era, each with its date and what changed; Play this version enters
## the one chosen (a game of its own: its menu, decks and look; leaving it comes back here). Compare versions: every
## card that differs between two versions, as in the first on the left and as in the second on the right, each drawn
## from its own version, the changed parts marked in red; then the cards added and removed. Its long list makes only
## the rows in view. Back leaves the comparison for the Versions, and the Versions for where the game was chosen.

## Back from the Versions.
signal back
## Play this version: the version's view (main enters it as a game).
signal play(version: Pack)

const LIST := Rect2(Vector2(36, 84), Vector2(1208, 548))
const PLAY_BAR_Y := 644.0  # the chosen version and Play this version, under the list
const DIFF := Rect2(Vector2(36, 196), Vector2(1208, 512))
const CARD := CardView.SIZE * 1.2
const HEAD_H := 46.0
const PAIR_H := 230.0  # two changed cards side by side in a row, each as in both versions
const CARDS_H := 222.0  # added or removed cards, PER_ROW in a row
const PER_ROW := 7
const PAIR_W := 596.0
const MARK := Color("ff3b30")

## The pack (the whole one, not a version of it).
var pack: Pack
## "choose" (the version to play), "from" or "to" (a side of the comparison), "compare".
var page := "choose"
## The version chosen to play (the last one played at first).
var chosen := ""
## The versions compared (version views): the first, the second.
var a: Pack
var b: Pack
var _views := {}  # version id -> its view (kept while the screen is open)
var _diff := {}  # Versions.diff(a, b)
var _shown := {}  # the part of it the filters let through
var _class := ""
var _field := ""  # "": every change; "added", "removed", or a field of Versions.FIELDS
var _query := ""
var _items: Array = []  # the list's rows: {kind: head | pairs | cards, y, h, …}
var _scroll: ScrollContainer
var _rows: Control
var _made := {}  # row index -> its node (only the rows in view)


func _ready() -> void:
	name = "Versions"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if chosen == "":
		chosen = Packs.version(pack)
	if page == "choose":
		show_list()


func _exit_tree() -> void:
	for v in _views.values():
		CardDb.forget(v)


## A version's view (the active game's own when it is the version played: its cards are loaded already).
func view(vid: String) -> Pack:
	if Packs.is_active(pack) and Packs.version(pack) == vid:
		return Packs.active()
	if not _views.has(vid):
		_views[vid] = pack.version_view(vid)
	return _views[vid]


func _clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_rows = null
	_made = {}


## The background, a title and Back.
func _base(title: String) -> void:
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self, "library")
	var t := Palette.label(title, 34, Palette.ATTACK)
	t.name = "Title"
	t.position = Vector2(LIST.position.x + 4, 18)
	t.size = Vector2(760, 48)
	t.clip_text = true
	add_child(t)
	var back := Palette.button(tr("Back"), "Back")
	back.custom_minimum_size = Vector2(150, 46)
	back.position = Vector2(LIST.end.x - 150, 20)
	back.pressed.connect(_back)
	add_child(back)


func _back() -> void:
	match page:
		"compare":
			show_list()
		"from", "to":
			compare(a, b)
		_:
			back.emit()


## The versions by era; mode "choose" makes the one pressed the version to play (Play this version, or a double
## click, enters it), "from" and "to" put it into the comparison.
func show_list(mode := "choose") -> void:
	page = mode
	_clear()
	_base({"choose": tr("Versions"), "from": tr("Compare: the first version"), "to": tr("Compare: the second version")}[mode])
	var current := chosen if mode == "choose" else (a if mode == "from" else b).version_id
	if mode == "choose":
		var cmp := Palette.button(tr("Compare versions"), "Compare")
		cmp.position = Vector2(LIST.end.x - 150 - 16 - 260, 20)
		cmp.custom_minimum_size = Vector2(260, 46)
		cmp.pressed.connect(open_compare)
		add_child(cmp)
		var what := Palette.label(Versions.label(pack, chosen), 20, Palette.TEXT)
		what.name = "ChosenVersion"
		what.position = Vector2(160, PLAY_BAR_Y + 12)  # (right of the friends button in the corner)
		what.size = Vector2(LIST.end.x - 340 - 16 - 160, 32)
		what.clip_text = true
		add_child(what)
		var go := Palette.button(tr("Play this version"), "PlayVersion")
		go.position = Vector2(LIST.end.x - 340, PLAY_BAR_Y)
		go.custom_minimum_size = Vector2(340, 56)
		go.pressed.connect(func(): play.emit(pack.version_view(chosen)))
		add_child(go)
	var scroll := ScrollContainer.new()
	scroll.name = "VersionList"
	scroll.position = LIST.position
	scroll.size = LIST.size if mode == "choose" else Vector2(LIST.size.x, 720 - 16 - LIST.position.y)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var at: Control
	for era in Versions.eras(pack):
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 16)
		var name_l := Palette.label(era.name, 26, Palette.ATTACK)
		name_l.name = "Era_" + era.id
		head.add_child(name_l)
		var dates := Palette.label(era.from if era.from == era.to else "%s – %s" % [era.from, era.to], 16, Palette.MUTED)
		dates.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(dates)
		box.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 10)
		box.add_child(grid)
		for v in era.versions:
			var row := VersionRow.new(pack, v)
			row.chosen = row.id == current
			row.pressed.connect(_picked.bind(row.id))
			row.gui_input.connect(func(ev):  # a double click plays it
				if mode == "choose" and ev is InputEventMouseButton and ev.double_click:
					play.emit(pack.version_view(row.id)))
			grid.add_child(row)
			if row.chosen:
				at = row
	if at:  # the chosen one in view
		scroll.ensure_control_visible.call_deferred(at)


func _picked(vid: String) -> void:
	match page:
		"choose":
			chosen = vid
			for r in find_children("Version_*", "Button", true, false):
				r.chosen = r.id == vid
				r.queue_redraw()
			(find_child("ChosenVersion", false, false) as Label).text = Versions.label(pack, vid)
		"from":
			compare(view(vid), b)
		"to":
			compare(a, view(vid))


## Compare versions from the Versions: the version before the chosen one and the chosen one (the first version: it
## and the next).
func open_compare() -> void:
	var ids: Array = pack.versions().map(func(v): return str(v.get("id", "")))
	var i := maxi(0, ids.find(chosen))
	var j := i - 1 if i > 0 else mini(1, ids.size() - 1)
	compare(view(ids[mini(i, j)]), view(ids[maxi(i, j)]))


## Every card that differs between version views x and y.
func compare(x: Pack, y: Pack) -> void:
	a = x
	b = y
	page = "compare"
	_diff = Versions.diff(a, b)
	_clear()
	_base(tr("Compare versions"))
	var sides := HBoxContainer.new()
	sides.position = Vector2(DIFF.position.x, 76)
	sides.size = Vector2(DIFF.size.x, 54)
	sides.add_theme_constant_override("separation", 12)
	add_child(sides)
	for side in [["From", a], ["To", b]]:
		var pick := Palette.button(Versions.label(pack, side[1].version_id) if side[1].version_id != "" else side[1].title(), side[0])
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.custom_minimum_size = Vector2(0, 54)
		pick.add_theme_font_size_override("font_size", 17)
		pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		pick.tooltip_text = pick.text
		pick.pressed.connect(show_list.bind(side[0].to_lower()))
		sides.add_child(pick)
		if side[0] == "From":
			var arrow := Palette.label("»", 30, Palette.ATTACK)
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sides.add_child(arrow)
	var filters := HBoxContainer.new()
	filters.position = Vector2(DIFF.position.x, 140)
	filters.size = Vector2(DIFF.size.x, 44)
	filters.add_theme_constant_override("separation", 10)
	add_child(filters)
	var classes := {}
	for e in _diff.changed + _diff.added + _diff.removed:
		for s in ["a", "b"]:
			for c in _classes(e.get(s, {})):
				classes[c] = (b if s == "b" else a).text(["classes", c])
	var cls_ids := classes.keys()
	cls_ids.sort_custom(func(m, n): return str(classes[m]) < str(classes[n]))
	var cls := OptionButton.new()
	cls.name = "ClassFilter"
	cls.custom_minimum_size = Vector2(210, 44)
	cls.add_item(tr("All classes"))
	for c in cls_ids:
		cls.add_item(str(classes[c]) if str(classes[c]) != "" else str(c).capitalize())
	cls.item_selected.connect(func(i):
		_class = "" if i == 0 else str(cls_ids[i - 1])
		_refill())
	filters.add_child(cls)
	var fields: Array = ["", "added", "removed"] + Versions.FIELDS.map(func(f): return f[0])
	var field := OptionButton.new()
	field.name = "FieldFilter"
	field.custom_minimum_size = Vector2(230, 44)
	for f in fields:
		field.add_item({"": tr("All changes"), "added": tr("Added"), "removed": tr("Removed")}.get(f, tr(_field_name(f))))
	field.item_selected.connect(func(i):
		_field = fields[i]
		_refill())
	filters.add_child(field)
	var search := LineEdit.new()
	search.name = "Search"
	search.placeholder_text = tr("Search")
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.clear_button_enabled = true
	search.text_changed.connect(func(t):
		_query = t
		_refill())
	filters.add_child(search)
	var summary := Palette.label(tr("%d changed, %d added, %d removed") % [_diff.changed.size(), _diff.added.size(), _diff.removed.size()], 18)
	summary.name = "Summary"
	summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	filters.add_child(summary)
	_scroll = ScrollContainer.new()
	_scroll.name = "DiffList"
	_scroll.position = DIFF.position
	_scroll.size = DIFF.size
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_rows = Control.new()
	_rows.name = "Rows"
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_rows)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v): _fill_rows())
	_scroll.resized.connect(_fill_rows)
	_class = ""
	_field = ""
	_query = ""
	_refill()


## The diff as the filters show it: {changed, added, removed}.
func shown() -> Dictionary:
	return _shown


static func _classes(c: Dictionary) -> Array:
	if c.is_empty():
		return []
	return c.get("classes") if c.get("classes") is Array else [str(c.get("class", "NEUTRAL"))]


static func _field_name(f: String) -> String:
	for x in Versions.FIELDS:
		if x[0] == f:
			return x[1]
	return f


## Filters the diff and lays out its rows anew (from the top).
func _refill() -> void:
	var q := _query.strip_edges().to_lower()
	var ok := func(e: Dictionary) -> bool:
		for s in ["a", "b"]:
			var c: Dictionary = e.get(s, {})
			if not c.is_empty() and (_class == "" or _classes(c).has(_class)) and (q == "" or str(c.name).to_lower().contains(q)):
				return true
		return false
	_shown = {
		"changed": _diff.changed.filter(func(e): return _field not in ["added", "removed"] and (_field == "" or e.fields.has(_field)) and ok.call(e)),
		"added": _diff.added.filter(func(e): return _field in ["", "added"] and ok.call(e)),
		"removed": _diff.removed.filter(func(e): return _field in ["", "removed"] and ok.call(e))}
	_items = []
	if not _shown.changed.is_empty():
		_add({"kind": "head", "text": tr("Changed: %d") % _shown.changed.size()}, HEAD_H)
		for i in range(0, _shown.changed.size(), 2):
			_add({"kind": "pairs", "entries": _shown.changed.slice(i, i + 2)}, PAIR_H)
	for s in [["added", tr("Added: %d"), "b"], ["removed", tr("Removed: %d"), "a"]]:
		var list: Array = _shown[s[0]]
		if not list.is_empty():
			_add({"kind": "head", "text": s[1] % list.size()}, HEAD_H)
			for i in range(0, list.size(), PER_ROW):
				_add({"kind": "cards", "entries": list.slice(i, i + PER_ROW), "side": s[2], "what": s[0].capitalize()}, CARDS_H)
	if _items.is_empty():
		_add({"kind": "head", "text": tr("The cards of these versions are the same") if _field == "" and _class == "" and q == "" else tr("Nothing found")}, HEAD_H)
	for n in _made.values():
		_rows.remove_child(n)
		n.queue_free()
	_made = {}
	_rows.custom_minimum_size = Vector2(DIFF.size.x - 16, _items[-1].y + _items[-1].h)
	_scroll.scroll_vertical = 0
	_fill_rows()


func _add(item: Dictionary, h: float) -> void:
	item.y = _items[-1].y + _items[-1].h if not _items.is_empty() else 0.0
	item.h = h
	_items.append(item)


## Makes the rows in view (and a little around them), frees the others.
func _fill_rows() -> void:
	if _rows == null:
		return
	var top := float(_scroll.scroll_vertical) - 250.0
	var bottom := float(_scroll.scroll_vertical) + _scroll.size.y + 250.0
	for i in _made.keys():
		if _items[i].y + _items[i].h < top or _items[i].y > bottom:
			_rows.remove_child(_made[i])
			_made[i].queue_free()
			_made.erase(i)
	for i in _items.size():  # ponytail: a scan of every row on each scroll; a binary search if lists grow to thousands
		var it: Dictionary = _items[i]
		if it.y + it.h >= top and it.y <= bottom and not _made.has(i):
			_made[i] = _make_row(i)


func _make_row(i: int) -> Control:
	var it: Dictionary = _items[i]
	var row := Control.new()
	row.name = "Row_%d" % i
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(0, it.y)
	row.size = Vector2(DIFF.size.x - 16, it.h)
	match it.kind:
		"head":
			var l := Palette.label(it.text, 24, Palette.ATTACK)
			l.position = Vector2(4, 8)
			row.add_child(l)
		"pairs":
			for k in it.entries.size():
				row.add_child(_pair(it.entries[k], Vector2(k * (PAIR_W + 12), 0)))
		"cards":
			for k in it.entries.size():
				var e: Dictionary = it.entries[k]
				var c := _card(e[it.side], a if it.side == "a" else b, [])
				c.name = "%s_%s" % [it.what, e.id]
				c.position = Vector2(k * (CARD.x + 26) + 6, 6)
				row.add_child(c)
	_rows.add_child(row)
	return row


## A changed card: as in the first version, an arrow, as in the second, and what changed.
func _pair(e: Dictionary, at: Vector2) -> Control:
	var p := Panel.new()
	p.name = "Change_" + e.id
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = at
	p.size = Vector2(PAIR_W, PAIR_H - 12)
	p.add_theme_stylebox_override("panel", Palette.box(Color(0.1, 0.07, 0.05, 0.85), 10, Color("6b5320"), 1))
	var old := _card(e.a, a, e.fields)
	old.name = "Old"
	old.position = Vector2(8, 7)
	p.add_child(old)
	var arrow := Palette.label("»", 30, Palette.ATTACK)
	arrow.position = Vector2(CARD.x + 12, CARD.y / 2.0 - 22)
	p.add_child(arrow)
	var new := _card(e.b, b, e.fields)
	new.name = "New"
	new.position = Vector2(CARD.x + 44, 7)
	p.add_child(new)
	var text := VBoxContainer.new()
	text.position = Vector2(CARD.x * 2 + 58, 10)
	text.size = Vector2(PAIR_W - CARD.x * 2 - 68, PAIR_H - 32)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(text)
	var name_l := Palette.label(str(e.b.name), 19, Palette.ATTACK)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(name_l)
	for f in e.fields:
		var line := Palette.label(_change(f, e.a, e.b), 17, Color("ff8a80"))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(line)
	return p


## "Cost: 4 » 5"; a change of words or looks: its name.
func _change(f: String, x: Dictionary, y: Dictionary) -> String:
	var what := tr(_field_name(f))
	if f in ["cost", "attack", "health", "durability"]:
		var n := func(v): return "—" if v == null else str(int(v))
		return "%s: %s » %s" % [what, n.call(x.get(f)), n.call(y.get(f))]
	return what


## A card as its version has it, with the fields that changed marked.
func _card(c: Dictionary, version: Pack, fields: Array) -> CardView:
	var v := CardView.make(str(c.id), CARD.x / CardView.SIZE.x)
	v.pack = version
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if c.get("art") is String:
		v.art_id = c.art
	var m := Marks.new()
	m.fields = fields
	m.size = v.size
	v.add_child(m)
	return v


## Red rings over the parts of a card that changed (on the card's own 120x170 drawing, scaled).
class Marks:
	extends Control
	var fields: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var k := size.x / CardView.SIZE.x
		var w := 2.5 * k
		var fill := Color(VersionsView.MARK, 0.16)
		for f in fields:
			match f:
				"cost":
					_ring(Vector2(17, 17) * k, 17 * k, w, fill)
				"attack":
					_ring(CardLayout.ATTACK_AT * k, 17 * k, w, fill)
				"health", "durability":
					_ring(CardLayout.HEALTH_AT * k, 17 * k, w, fill)
				"rarity":
					_ring(Vector2(60, 104.5) * k, 7 * k, w, fill)
				"name":
					_box(Rect2(CardLayout.NAME_BOX.position * k, CardLayout.NAME_BOX.size * k).grow(1.5 * k), w, fill)
				"text", "keywords":
					_box(Rect2(CardLayout.TEXT_BOX.position * k, CardLayout.TEXT_BOX.size * k).grow(2 * k), w, fill)
				"race":
					_box(Rect2(Vector2(28, 156) * k, Vector2(64, 14) * k), w, fill)
				"art":
					_box(Rect2(Vector2(16, 6) * k, Vector2(88, 86) * k), w, fill)
				"class":
					_box(Rect2(Vector2.ZERO, size).grow(-1.5 * k), w, Color.TRANSPARENT)

	func _ring(at: Vector2, r: float, w: float, fill: Color) -> void:
		draw_circle(at, r, fill)
		draw_arc(at, r, 0, TAU, 32, VersionsView.MARK, w, true)

	func _box(r: Rect2, w: float, fill: Color) -> void:
		var s := Palette.raw_box(fill, int(6 * size.x / CardView.SIZE.x), VersionsView.MARK, int(ceil(w)))
		draw_style_box(s, r)


## A version in the list: what changed, its date and patch; the chosen one marked.
class VersionRow:
	extends Button
	var id := ""
	var chosen := false
	var _name := ""
	var _when := ""

	func _init(p: Pack, v: Dictionary) -> void:
		id = str(v.get("id", ""))
		name = "Version_" + id
		_name = p.text_of(v.get("name", id))
		_when = "  ·  ".join([str(v.get("date", "")), str(v.get("patch", ""))].filter(func(s): return s != ""))
		tooltip_text = _name
		custom_minimum_size = Vector2(590, 70)
		focus_mode = Control.FOCUS_NONE
		flat = true
		pressed.connect(Sound.play.bind("click"))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var edge := (Palette.SELECTED if Palette.CLASSIC else Palette.ATTACK) if chosen else (Color("c9a74a") if is_hovered() else Color("6b5320"))
		draw_style_box(Palette.box(Color(0.1, 0.07, 0.05, 0.88) if not chosen else Color(0.2, 0.15, 0.06, 0.95), 10, edge, 3 if chosen else 2), r)
		var font := get_theme_font("font", "Label")
		var mark := TranslationServer.translate("Chosen")
		var mark_w := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 20 if chosen else 0.0
		var width := size.x - 32 - mark_w
		var fs := 20
		while fs > 15 and font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
			fs -= 1
		DeckTiles.text(self, Vector2(16, 30), _name, fs, Color("f4ead5"), width)
		DeckTiles.text(self, Vector2(16, 56), _when, 15, Color("d8c8a0"), width)
		if chosen:  # a green pill at the right, as the library's Active mark
			var box := Rect2(Vector2(size.x - 14 - mark_w, 12), Vector2(mark_w, 23))
			var ribbon := Palette.box(Color("2f6b2a"), 8, Color("c9e88a"), 2) if Palette.CLASSIC else Palette.box(Palette.OK.darkened(0.7), 4, Palette.OK, 1)
			draw_style_box(ribbon, box)
			draw_string(font, box.position + Vector2(10, 17), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f4ffe0"))
