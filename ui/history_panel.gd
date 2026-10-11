class_name HistoryPanel
extends Panel
## Scrollable list of every move since the start of the match (no length limit).

var _list := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _shown := 0
var _viewer := -1
var _title: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", Palette.box(Palette.PANEL, 10, Color("c9a74a"), 2))
	position = Vector2(150, 20)
	size = Vector2(520, 560)
	_title = Palette.label(tr("History"), 22, Palette.ATTACK)
	_title.name = "HistoryTitle"
	_title.position = Vector2(14, 8)
	add_child(_title)
	_scroll.position = Vector2(10, 44)
	_scroll.size = size - Vector2(20, 54)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_list.custom_minimum_size.x = _scroll.size.x - 16
	_scroll.add_child(_list)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_scroll_to_end())


func relabel() -> void:
	_title.text = tr("History")


## True when new lines should scroll into view: the panel is closed, or the
## reader is already at the bottom (an open panel never yanks a reader away).
func following() -> bool:
	var bar := _scroll.get_v_scroll_bar()
	return not is_visible_in_tree() or _scroll.scroll_vertical >= int(bar.max_value - bar.page) - 8


func _scroll_to_end() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame  # the scroll range updates after layout
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


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
	var follow := following()
	while _shown < g.history.size():
		for r in HistoryText.rows(g.history[_shown], g, viewer):
			var l := Palette.label(r.text, 14)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = _list.custom_minimum_size.x
			var style := StyleBoxFlat.new()  # a turn opens with a gold rule; its moves are indented under it
			style.bg_color = Color.TRANSPARENT
			if r.turn:
				l.add_theme_color_override("font_color", Palette.ATTACK)
				style.border_color = Color("c9a74a")
				style.border_width_top = 2
				style.content_margin_top = 4
			else:
				style.content_margin_left = 14
			l.add_theme_stylebox_override("normal", style)
			_list.add_child(l)
			added = true
		_shown += 1
	if added and follow and is_visible_in_tree():
		_scroll_to_end()
