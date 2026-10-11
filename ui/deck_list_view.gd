class_name DeckListView
extends Control
## "My decks": create, edit, copy, delete, import and export deck codes.
## Every change is saved to DeckStore at once.

signal back

## Button labels (English keys); the translation tool reads this list.
const BUTTONS := ["New Deck", "Edit", "Copy", "Delete", "Import Code", "Export Code", "Browse Cards", "Back"]

var decks: Array[Deck] = []
var list := VBoxContainer.new()
var _group := ButtonGroup.new()
var message: Label
var _overlay: Control
var _editor: CollectionView


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	decks = DeckStore.load_all()
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self)
	var title := Palette.label(tr("My Decks"), 34, Palette.ATTACK)
	title.position = Vector2(40, 20)
	add_child(title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 80)
	scroll.size = Vector2(620, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	list.name = "DeckList"
	list.custom_minimum_size.x = 604
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var col := VBoxContainer.new()
	col.position = Vector2(700, 80)
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	for spec in [["New Deck", _choose_hero], ["Edit", func(): edit_deck(_selected())],
			["Copy", func(): copy_deck(_selected())], ["Delete", func(): _confirm_delete(_selected())],
			["Import Code", _show_import], ["Export Code", func(): show_export(_selected())],
			["Browse Cards", browse], ["Back", func(): back.emit()]]:
		var b := Palette.button(tr(spec[0]), spec[0].replace(" ", ""))
		b.pressed.connect(spec[1])
		col.add_child(b)
	message = Palette.label("", 18, Palette.SELECTED)
	message.name = "Message"
	message.position = Vector2(40, 650)
	message.size = Vector2(1200, 50)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)
	refresh()
	if DeckStore.last_load_error != "":
		message.text = DeckStore.last_load_error


func refresh() -> void:
	var was := _selected()
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for i in decks.size():
		var row := DeckTiles.DeckRow.new(decks[i])
		row.name = "Deck%d" % i
		row.button_group = _group
		row.button_pressed = i == was
		var idx := i
		row.gui_input.connect(func(ev):  # a double click opens the deck
			if ev is InputEventMouseButton and ev.double_click:
				edit_deck(idx))
		list.add_child(row)


func _selected() -> int:
	for c in list.get_children():
		if c is Button and c.button_pressed and not c.is_queued_for_deletion():
			return c.get_index()
	return -1


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


func edit_deck(i: int) -> void:
	if i < 0 or i >= decks.size():
		message.text = tr("Select a deck first")
		return
	_editor = CollectionView.new()
	var deck := decks[i]
	_editor.deck = deck
	_editor.changed.connect(_save)
	_editor.done.connect(func(_d):
		if deck.name.strip_edges() == "":
			deck.name = tr("Custom %s") % CardText.name(deck.hero)
		_editor.queue_free()
		remove_child(_editor)
		_editor = null
		_save())
	add_child(_editor)


func browse() -> void:
	_editor = CollectionView.new()
	_editor.done.connect(func(_d):
		_editor.queue_free()
		remove_child(_editor)
		_editor = null)
	add_child(_editor)


func copy_deck(i: int) -> void:
	if i < 0:
		message.text = tr("Select a deck first")
		return
	var d := Deck.from_dict(decks[i].to_dict())
	d.name = tr("%s (copy)") % d.name
	decks.append(d)
	_save()


func delete_deck(i: int) -> void:
	if i >= 0 and i < decks.size():
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
	for cls in TrainingSetup.ORDER:
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
	if i < 0:
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
