class_name KeywordTips
extends VBoxContainer
## Small parchment boxes beside a big card, one per keyword on it, explaining
## what the keyword does (data/keywords.json, in the interface language).

const WIDTH := 210.0

static var _data := {}


static func _keywords() -> Dictionary:
	if _data.is_empty():
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string("res://data/keywords.json")) == OK:
			_data = j.data
	return _data


static func make(card_id: String) -> KeywordTips:
	var tips := KeywordTips.new()
	tips.name = "KeywordTips"
	tips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tips.add_theme_constant_override("separation", 6)
	var lang := TranslationServer.get_locale()
	var kw := _keywords()
	for m in CardDb.card(card_id).get("mechanics", []):
		if not kw.has(m):
			continue
		var box := PanelContainer.new()
		var st := Palette.box(Color("efe0bd"), 10, Color("8a6d3b"), 2)
		st.set_content_margin_all(8)
		box.add_theme_stylebox_override("panel", st)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		box.add_child(col)
		var title := Label.new()
		title.name = "Title" + m
		title.text = kw[m].name.get(lang, kw[m].name.en)
		title.add_theme_font_size_override("font_size", 16)
		title.add_theme_color_override("font_color", Color("2a1a08"))
		col.add_child(title)
		var text := Label.new()
		text.text = kw[m].text.get(lang, kw[m].text.en)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = WIDTH - 16
		text.add_theme_font_size_override("font_size", 13)
		text.add_theme_color_override("font_color", Color("3b2a14"))
		col.add_child(text)
		tips.add_child(box)
	return tips


## Places the boxes beside rect (right of it, or left when there is no room).
func beside(rect: Rect2) -> void:
	var x := rect.end.x + 8 if rect.end.x + 8 + WIDTH < 1280 else rect.position.x - WIDTH - 8
	position = Vector2(x, rect.position.y + 6)
