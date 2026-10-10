class_name HistoryPanel
extends Panel
## Scrollable list of every move since the start of the match (no length limit).

var _list := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _shown := 0
var _viewer := -1


func _ready() -> void:
	add_theme_stylebox_override("panel", Palette.box(Palette.PANEL, 10, Color("c9a74a"), 2))
	position = Vector2(150, 20)
	size = Vector2(520, 560)
	var title := Palette.label(tr("History"), 22, Palette.ATTACK)
	title.position = Vector2(14, 8)
	add_child(title)
	_scroll.position = Vector2(10, 44)
	_scroll.size = size - Vector2(20, 54)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list.custom_minimum_size.x = _scroll.size.x - 16
	_scroll.add_child(_list)


func line_count() -> int:
	return _list.get_child_count()


## Adds lines for history entries not shown yet; rebuilds when the viewer changes.
func update_from(g: GameState, viewer: int) -> void:
	if viewer != _viewer:
		for c in _list.get_children():
			_list.remove_child(c)
			c.queue_free()
		_shown = 0
		_viewer = viewer
	var added := false
	while _shown < g.history.size():
		for text in HistoryText.lines(g.history[_shown], g, viewer):
			var l := Palette.label(text, 14)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = _list.custom_minimum_size.x
			if text.begins_with(tr("Turn").left(4)):
				l.add_theme_color_override("font_color", Palette.ATTACK)
			_list.add_child(l)
			added = true
		_shown += 1
	if added and is_inside_tree():
		await get_tree().process_frame
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
