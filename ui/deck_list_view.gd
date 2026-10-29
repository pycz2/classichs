class_name DeckListView
extends Control
## The collection screen: all cards on the left (CollectionView), the player's
## decks on the right. A click on a deck opens it in the right panel: then a
## click on a card adds it and a click on a line removes one copy.
## Every change is saved to DeckStore at once.

signal back

## Button labels and tooltips (English keys); the translation tool reads this list.
const BUTTONS := ["New Deck", "Import Code", "Done", "Back", "Copy", "Export Code", "Delete"]
## The right panel (the deck list or the open deck).
const RIGHT := Rect2(916, 66, 348, 642)

var decks: Array[Deck] = []
## The deck being edited, null while the list of decks is shown.
var editing: Deck
var browser := CollectionView.new()
var list := VBoxContainer.new()
var message: Label
var _overlay: Control
var _list_box := Control.new()
var _edit_box := Control.new()
var _deck_list := VBoxContainer.new()
var _name_edit := LineEdit.new()
## How full the open deck is, behind the "n / 30" count.
var _bar := DeckTiles.Bar.new()
var _count: Label
## The deck's mana curve above its list (as in the Arena draft).
var _curve := ManaCurve.new()
var _panel := Panel.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	decks = DeckStore.load_all()
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self, "library_bg")
	browser.name = "Cards"
	browser.changed.connect(_on_deck_changed)
	add_child(browser)
	var title := Palette.label(tr("My Decks"), 30, Palette.ATTACK)
	title.position = Vector2(RIGHT.position.x + 4, 12)
	title.size = Vector2(RIGHT.size.x - 140, 50)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(title)
	var back_b := Palette.button(tr("Back"), "Back")
	back_b.custom_minimum_size = Vector2(130, 46)
	back_b.position = Vector2(RIGHT.end.x - 130, 12)
	back_b.pressed.connect(func():
		close_deck()
		back.emit())
	add_child(back_b)
	_panel.position = RIGHT.position
	_panel.size = RIGHT.size
	_panel.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL, 12, Color("6b5320"), 2))
	add_child(_panel)
	var inner := Rect2(RIGHT.position + Vector2(12, 12), RIGHT.size - Vector2(24, 24))
	# the list of decks
	_list_box.name = "DeckListBox"
	add_child(_list_box)
	var scroll := ScrollContainer.new()
	scroll.position = inner.position
	scroll.size = Vector2(inner.size.x, 512)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_box.add_child(scroll)
	list.name = "DeckList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var buttons := HBoxContainer.new()
	buttons.position = Vector2(inner.position.x, inner.end.y - 46)
	buttons.size = Vector2(inner.size.x, 46)
	buttons.add_theme_constant_override("separation", 8)
	_list_box.add_child(buttons)
	for spec in [["New Deck", _choose_hero], ["Import Code", _show_import]]:
		var b := Palette.button(tr(spec[0]), spec[0].replace(" ", ""))
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(spec[1])
		buttons.add_child(b)
	# the open deck
	_edit_box.name = "DeckEditor"
	add_child(_edit_box)
	_name_edit.name = "DeckName"
	_name_edit.max_length = Deck.NAME_MAX
	_name_edit.position = inner.position
	_name_edit.size = Vector2(inner.size.x, 40)
	_name_edit.text_changed.connect(func(t):
		if editing:
			editing.name = t
			_save())
	_edit_box.add_child(_name_edit)
	_bar.position = inner.position + Vector2(0, 48)
	_bar.size = Vector2(inner.size.x, 26)
	_edit_box.add_child(_bar)
	_count = Palette.label("", 17)
	_count.name = "Count"
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.position = _bar.position
	_count.size = _bar.size
	_edit_box.add_child(_count)
	_curve.name = "Curve"
	_curve.compact = true
	_curve.position = inner.position + Vector2(0, 80)
	_curve.size = Vector2(inner.size.x, 62)
	_edit_box.add_child(_curve)
	var tiles := ScrollContainer.new()
	tiles.position = inner.position + Vector2(0, 148)
	tiles.size = Vector2(inner.size.x, 364)
	tiles.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_edit_box.add_child(tiles)
	_deck_list.name = "Tiles"
	_deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_list.add_theme_constant_override("separation", 3)
	tiles.add_child(_deck_list)
	var done := Palette.button(tr("Done"), "Done")
	done.custom_minimum_size = Vector2(inner.size.x, 46)
	done.position = Vector2(inner.position.x, inner.end.y - 46)
	done.pressed.connect(close_deck)
	_edit_box.add_child(done)
	message = Palette.label("", 15, Palette.SELECTED)
	message.name = "Message"
	message.position = Vector2(inner.position.x, inner.position.y + 516)
	message.size = Vector2(inner.size.x, 58)
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)
	_show_mode()
	refresh()
	if DeckStore.last_load_error != "":
		message.text = DeckStore.last_load_error


func refresh() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for i in decks.size():
		var row := DeckTiles.DeckRow.new(decks[i])
		row.name = "Deck%d" % i
		var idx := i
		row.pressed.connect(func(): edit_deck(idx))
		var acts := HBoxContainer.new()  # small buttons in the lower right corner
		acts.name = "Actions"
		acts.add_theme_constant_override("separation", 4)
		acts.alignment = BoxContainer.ALIGNMENT_END
		acts.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		acts.offset_left = -DeckTiles.DeckRow.ACTIONS_W - 10
		acts.offset_right = -10
		acts.offset_top = -34
		acts.offset_bottom = -8
		row.add_child(acts)
		for spec in [["copy", "Copy", copy_deck], ["export", "Export Code", show_export], ["delete", "Delete", _confirm_delete]]:
			var b := DeckTiles.Action.new(spec[0], tr(spec[1]))
			var act: Callable = spec[2]
			b.pressed.connect(func(): act.call(idx))
			acts.add_child(b)
		list.add_child(row)
	_refresh_deck()


func _show_mode() -> void:
	_list_box.visible = editing == null
	_edit_box.visible = editing != null
	var cls := editing.card_class() if editing else ""
	var edge := Palette.of_class(cls) if editing else Color("6b5320")
	_panel.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL, 12, edge, 3 if editing else 2))


func _save() -> void:
	if not DeckStore.save_all(decks):
		message.text = tr("Could not save the decks")
	refresh()


func new_deck(hero: String) -> Deck:
	var d := Deck.new()
	d.hero = hero
	d.name = tr("Custom %s") % CardText.name(hero)
	decks.append(d)
	_save()
	edit_deck(decks.size() - 1)
	return d


## Opens a deck in the right panel; the cards on the left become the ones it can use.
func edit_deck(i: int) -> void:
	if i < 0 or i >= decks.size():
		message.text = tr("Select a deck first")
		return
	editing = decks[i]
	_name_edit.text = editing.name
	message.text = ""
	browser.set_deck(editing)
	_show_mode()
	_refresh_deck()


## Back to the list of decks (an empty name gets the default one back).
func close_deck() -> void:
	if editing == null:
		return
	if editing.name.strip_edges() == "":
		editing.name = tr("Custom %s") % CardText.name(editing.hero)
	editing = null
	browser.set_deck(null)
	_show_mode()
	_save()


func _on_deck_changed() -> void:
	message.text = ""
	_save()


func remove_card(id: String) -> void:
	if editing and editing.remove(id):
		_save()
	browser.show_hint("")
	browser._fill()


func _refresh_deck() -> void:
	for c in _deck_list.get_children():
		_deck_list.remove_child(c)
		c.queue_free()
	if editing == null:
		return
	for pair in editing.sorted_counts():
		var id: String = pair[0]
		var b := DeckTiles.DeckTile.new(id, pair[1])
		b.pressed.connect(func(): remove_card(id))
		_deck_list.add_child(b)
	var n := editing.cards.size()
	_count.text = "%d / %d" % [n, Deck.SIZE]
	_curve.counts = ManaCurve.of(editing.cards)
	_bar.ratio = n / float(Deck.SIZE)
	_count.add_theme_color_override("font_color", Palette.BUFFED if n == Deck.SIZE else Palette.TEXT)


func copy_deck(i: int) -> void:
	if i < 0 or i >= decks.size():
		message.text = tr("Select a deck first")
		return
	var d := Deck.from_dict(decks[i].to_dict())
	d.name = tr("%s (copy)") % d.name
	decks.append(d)
	_save()


func delete_deck(i: int) -> void:
	if i >= 0 and i < decks.size():
		if decks[i] == editing:
			close_deck()
		decks.remove_at(i)
		_save()


## Imports a code (or client text); returns the error, "" on success.
func import_code(text: String) -> String:
	var r := DeckCode.decode(text)
	if r.error != "":
		message.text = r.error
		return r.error
	decks.append(r.deck)
	_save()
	message.text = tr("Deck imported: %s") % r.deck.name
	return ""


func export_code(i: int) -> String:
	if i < 0 or i >= decks.size():
		return ""
	var why := decks[i].validate()
	if why != "":
		message.text = why
		return ""
	return DeckCode.encode(decks[i])


# --- popups ---------------------------------------------------------------------

func _close() -> void:
	if _overlay:
		remove_child(_overlay)
		_overlay.queue_free()
		_overlay = null


func _popup(title: String) -> VBoxContainer:
	_close()
	_overlay = Control.new()
	_overlay.name = "Popup"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	box.add_child(Palette.label(title, 26, Palette.ATTACK))
	add_child(_overlay)
	return box


func _choose_hero() -> void:
	var box := _popup(tr("Choose a hero"))
	var grid := GridContainer.new()
	grid.columns = 3
	for cls in Decks.classes():
		var b := Button.new()
		b.name = "Hero" + cls
		b.text = CardText.name(Decks.hero(cls))
		b.custom_minimum_size = Vector2(220, 48)
		var st := Palette.box(Palette.of_class(cls), 8)
		st.content_margin_left = 46
		b.add_theme_stylebox_override("normal", st)
		Icons.attach(b, cls, 34)
		var hero := Decks.hero(cls)
		b.pressed.connect(func():
			_close()
			new_deck(hero))
		grid.add_child(b)
	box.add_child(grid)
	var cancel := Palette.button(tr("Cancel"), "Cancel")
	cancel.pressed.connect(_close)
	box.add_child(cancel)


func _confirm_delete(i: int) -> void:
	if i < 0 or i >= decks.size():
		message.text = tr("Select a deck first")
		return
	var box := _popup(tr("Delete \"%s\"?") % decks[i].name)
	var yes := Palette.button(tr("Delete"), "ConfirmDelete")
	yes.pressed.connect(func():
		_close()
		delete_deck(i))
	box.add_child(yes)
	var no := Palette.button(tr("Cancel"), "Cancel")
	no.pressed.connect(_close)
	box.add_child(no)


func _show_import() -> void:
	var box := _popup(tr("Paste a deck code"))
	var ed := TextEdit.new()
	ed.name = "CodeInput"
	ed.custom_minimum_size = Vector2(700, 200)
	box.add_child(ed)
	var err := Palette.label("", 18, Palette.TARGET)
	err.name = "PopupError"
	err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	err.custom_minimum_size.x = 700
	box.add_child(err)
	var ok := Palette.button(tr("Import"), "DoImport")
	ok.pressed.connect(func():
		err.text = import_code(ed.text)
		if err.text == "":
			_close())
	box.add_child(ok)
	var no := Palette.button(tr("Cancel"), "Cancel")
	no.pressed.connect(_close)
	box.add_child(no)


func show_export(i: int) -> void:
	if i < 0:
		message.text = tr("Select a deck first")
		return
	var code := export_code(i)
	if code == "":
		return
	DisplayServer.clipboard_set(code)
	var box := _popup(tr("Deck code (copied to clipboard)"))
	var ed := LineEdit.new()
	ed.name = "CodeOutput"
	ed.text = code
	ed.editable = false
	ed.custom_minimum_size = Vector2(700, 40)
	box.add_child(ed)
	var close := Palette.button(tr("Close"), "Close")
	close.pressed.connect(_close)
	box.add_child(close)
