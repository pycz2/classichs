class_name CardLab
extends Control
## A tool to check and set how a card's name and text sit on the card: the card
## in all 8 languages at once, with its boxes and gems outlined and its layout
## problems listed; sizes, alignment and the text's lines can be changed per
## language and saved to data/card_layout/<lang>.json.
## (A developer tool: its labels are not translated.)

signal back

var ids: Array = []
var index := 0
var _search := LineEdit.new()
var _title := Label.new()
var _grid := GridContainer.new()
var _boxes := CheckButton.new()
var _message := Label.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	ids = CardDb.all_ids()
	ids.sort()
	var bar := HBoxContainer.new()
	bar.position = Vector2(10, 6)
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	_search.name = "Search"
	_search.placeholder_text = "card id or name"
	_search.custom_minimum_size = Vector2(200, 34)
	_search.text_submitted.connect(find)
	bar.add_child(_search)
	for spec in [["<", func(): show_card(index - 1)], [">", func(): show_card(index + 1)],
			["Next problem", next_problem], ["Save", save], ["Back", func(): back.emit()]]:
		var b := Button.new()
		b.text = spec[0]
		b.name = String(spec[0]).replace(" ", "")
		b.custom_minimum_size = Vector2(0, 34)
		b.pressed.connect(spec[1])
		bar.add_child(b)
	_boxes.text = "Boxes"
	_boxes.button_pressed = true
	_boxes.toggled.connect(func(_on): show_card(index))
	bar.add_child(_boxes)
	_title.position = Vector2(12, 44)
	add_child(_title)
	_message.position = Vector2(700, 44)
	_message.add_theme_color_override("font_color", Palette.SELECTED)
	add_child(_message)
	_grid.columns = 4
	_grid.position = Vector2(8, 70)
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 2)
	add_child(_grid)
	show_card(0)


func find(q: String) -> void:
	q = q.strip_edges().to_lower()
	for i in ids.size():
		if ids[i].to_lower() == q or CardText.name(ids[i], "enUS").to_lower().contains(q) or CardText.name(ids[i]).to_lower().contains(q):
			show_card(i)
			return
	_message.text = "not found: " + q


func show_card(i: int) -> void:
	index = posmod(i, ids.size())
	var id: String = ids[index]
	_title.text = "%s  —  %s  (%d / %d)" % [id, CardText.name(id, "enUS"), index + 1, ids.size()]
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for lang in CardLayout.LANGS:
		_grid.add_child(_panel(id, lang))


func _panel(id: String, lang: String) -> Control:
	var col := VBoxContainer.new()
	col.name = "Lang_" + lang
	col.add_theme_constant_override("separation", 1)
	col.custom_minimum_size = Vector2(310, 0)
	var e := CardLayout.of(id, lang)
	var top := HBoxContainer.new()
	col.add_child(top)
	var cv := CardView.make(id, 1.5)
	cv.locale = lang
	cv.show_boxes = _boxes.button_pressed
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(cv)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 1)
	top.add_child(side)
	var pr := CardLayout.problems(id, lang)
	var status := Label.new()
	status.name = "Status"
	status.text = "%s  %s" % [lang, "OK" if pr.is_empty() else ", ".join(pr)]
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 124
	status.add_theme_color_override("font_color", Color("69db7c") if pr.is_empty() else Color("ff6b6b"))
	side.add_child(status)
	var info := Label.new()
	info.text = "text %d  name %d\n%s  dy %d" % [e.text, e.name, e.get("valign", "center"), e.get("dy", 0)]
	info.add_theme_font_size_override("font_size", 12)
	side.add_child(info)
	for row in [[["text -", "text", -1], ["text +", "text", 1]], [["name -", "name", -1], ["name +", "name", 1]],
			[["up", "dy", -1], ["down", "dy", 1]], [["top/mid", "valign", 0], ["edit lines", "edit", 0]]]:
		var h := HBoxContainer.new()
		for b_spec in row:
			var b := Button.new()
			b.text = b_spec[0]
			b.custom_minimum_size = Vector2(60, 24)
			b.add_theme_font_size_override("font_size", 11)
			var what: String = b_spec[1]
			var step: int = b_spec[2]
			b.pressed.connect(func(): change(id, lang, what, step))
			h.add_child(b)
		side.add_child(h)
	return col


## Changes one setting of a card face and shows the card again.
func change(id: String, lang: String, what: String, step: int) -> void:
	var e := CardLayout.of(id, lang).duplicate(true)
	match what:
		"text":
			e.text = clampi(int(e.text) + step, 4, 14)
		"name":
			e.name = clampi(int(e.name) + step, 4, 14)
		"dy":
			e.dy = int(e.get("dy", 0)) + step
			if e.dy == 0:
				e.erase("dy")
		"valign":
			if e.get("valign", "") == "top":
				e.erase("valign")
			else:
				e.valign = "top"
		"edit":
			_edit_lines(id, lang)
			return
	CardLayout.store(id, lang, e)
	show_card(index)


## The text's lines as typed: one line per line, [b]bold[/b].
func set_lines(id: String, lang: String, text: String) -> void:
	var e := CardLayout.of(id, lang).duplicate(true)
	e.lines = Array(text.strip_edges().split("\n")).map(func(l): return l.strip_edges())
	CardLayout.store(id, lang, e)
	show_card(index)


func _edit_lines(id: String, lang: String) -> void:
	var pop := AcceptDialog.new()
	pop.title = "%s (%s): one line per line, [b]bold[/b]" % [id, lang]
	var ed := TextEdit.new()
	ed.custom_minimum_size = Vector2(620, 160)
	ed.text = "\n".join(CardLayout.of(id, lang).get("lines", []))
	pop.add_child(ed)
	pop.confirmed.connect(func():
		set_lines(id, lang, ed.text)
		pop.queue_free())
	add_child(pop)
	pop.popup_centered()


## The next card (after the current one) with a problem in any language.
func next_problem() -> void:
	for step in range(1, ids.size() + 1):
		var i := (index + step) % ids.size()
		for lang in CardLayout.LANGS:
			if not CardLayout.problems(ids[i], lang).is_empty():
				show_card(i)
				return
	_message.text = "no problems left"


func save() -> void:
	var ok := true
	for lang in CardLayout.LANGS:
		ok = CardLayout.save(lang) and ok
	_message.text = "saved to " + CardLayout.DIR if ok else "cannot save here (run the game from its source folder)"
