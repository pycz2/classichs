class_name DeckListView
extends Control
## The collection screen: all cards on the left (CollectionView), the player's
## decks on the right. A click on a deck opens it in the right panel: then a
## click on a card adds it and a click on a line removes one copy.
## Every change is saved to DeckStore at once. Logged in on a server, a tick on each deck
## keeps it there too (deck_save on every change, deck_delete when unticked); the server's
## decks from another device join the list (server/README.md, "Decks").

signal back

## Button labels and tooltips (English keys); the translation tool reads this list.
const BUTTONS := ["New Deck", "Import Code", "Done", "Back", "Copy", "Export Code", "Delete"]
## The server's answers about decks the player is told (English keys, translated).
const SERVER_TEXTS := ["You have 100 decks on this server: delete one first", "A deck name is at most 60 characters",
	"This deck has cards this game does not have", "Arena decks are not kept"]
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
## The server the decks can be kept on (the lobby's chosen one; main sets it; null = none).
var link: ServerLink
## The server answered `decks`: it keeps decks (an older one does not, and shows no ticks).
var _server_ok := false
## Decks whose first deck_save is on the way, by the ref it carries.
var _pending := {}
var _refs := 0


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
			_save(editing))
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
	if link:
		link.message.connect(_on_server)
		link.closed.connect(refresh.unbind(1))
		link.packs_changed.connect(refresh)
		if link.logged_in():
			link.send({"t": "decks"})


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
		if server_on():
			var tick := DeckTiles.Action.new("server", tr("Keep on the server"))
			tick.toggle_mode = true
			tick.button_pressed = on_server(decks[i])
			tick.toggled.connect(func(on): set_on_server(idx, on))
			acts.add_child(tick)
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


## Saves the decks; changed: the deck that changed, sent to the server too when kept there.
func _save(changed: Deck = null) -> void:
	if not DeckStore.save_all(decks):
		message.text = tr("Could not save the decks")
	if changed and server_on() and on_server(changed):
		_push(changed)
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
	var d := editing
	if d.name.strip_edges() == "":
		d.name = tr("Custom %s") % CardText.name(d.hero)
	editing = null
	browser.set_deck(null)
	_show_mode()
	_save(d)


func _on_deck_changed() -> void:
	message.text = ""
	_save(editing)


func remove_card(id: String) -> void:
	if editing and editing.remove(id):
		_save(editing)
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
	d.servers = {}  # a new deck: kept here only until ticked
	decks.append(d)
	_save()


func delete_deck(i: int) -> void:
	if i >= 0 and i < decks.size():
		if decks[i] == editing:
			close_deck()
		if server_on() and server_id(decks[i]) > 0:
			link.send({"t": "deck_delete", "id": server_id(decks[i])})
		# ponytail: a deck kept on a server and deleted while not logged in there comes back
		# from it at the next login; keep the deleted ids if that ever bothers anyone.
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


# --- decks kept on the server (server/README.md, "Decks") ----------------------------------------

## Whether decks can be kept on the server now (else the ticks are hidden): logged in on one
## that keeps decks and has this game (its packs known).
func server_on() -> bool:
	return link != null and _server_ok and link.logged_in() and link.has_packs and link.has_game(Packs.active(), true)


## The deck's id on the server (0 = not kept there).
func server_id(d: Deck) -> int:
	return int(d.servers.get(link.url, {}).get("id", 0)) if link else 0


## Ticked: kept on the server, or its first save is on the way.
func on_server(d: Deck) -> bool:
	return server_id(d) > 0 or _pending.values().has(d)


## The tick: on saves the deck to the server, off deletes it there (it stays here).
func set_on_server(i: int, on: bool) -> void:
	if i < 0 or i >= decks.size() or not server_on() or on == on_server(decks[i]):
		return
	var d := decks[i]
	if on:
		_push(d)
	else:
		if server_id(d) > 0:
			link.send({"t": "deck_delete", "id": server_id(d)})
		d.servers.erase(link.url)
		for r in _pending.keys().filter(func(k): return _pending[k] == d):
			_pending.erase(r)  # its id, when it comes, is deleted there (_on_server)
	_save()


## Sends the deck to the server (an update by its id, or a new one with a ref).
func _push(d: Deck) -> void:
	var msg := {"t": "deck_save", "deck": {"name": d.name, "hero": d.hero, "cards": Array(d.cards)}}
	if server_id(d) > 0:
		msg["id"] = server_id(d)
	elif _pending.values().has(d):
		return  # its first save is on the way: the answer brings the id, then the changes follow
	else:
		_refs += 1
		msg["ref"] = str(_refs)
		_pending[msg.ref] = d
	msg["pack"] = Packs.active().rules_hash()  # (a server that keeps decks knows packs)
	link.send(msg)


static func _same(d: Deck, sd: Dictionary) -> bool:
	return JSON.stringify([d.name, d.hero, d.cards]) == JSON.stringify([sd.get("name"), sd.get("hero"), sd.get("cards")])


func _on_server(msg: Dictionary) -> void:
	match msg.get("t"):
		"auth":
			if msg.get("ok", false):
				link.send({"t": "decks"})
		"logged_out":
			refresh()
		"decks":
			_server_ok = true
			merge(msg.get("list") if msg.get("list") is Array else [])
		"deck_saved":
			var sd: Dictionary = msg.get("deck") if msg.get("deck") is Dictionary else {}
			var id := int(sd.get("id", 0))
			var r = msg.get("ref")
			var d: Deck = _pending.get(r) if r is String else null
			if r is String:
				_pending.erase(r)
				if d == null or not decks.has(d):  # unticked or deleted meanwhile
					link.send({"t": "deck_delete", "id": id})
					return
			for x in decks:
				if d == null and server_id(x) == id:
					d = x
			if d == null:
				return
			d.servers[link.url] = {"id": id, "at": int(sd.get("updated", 0))}
			DeckStore.save_all(decks)
			if not _same(d, sd):  # changed while its first save was on the way
				_push(d)
			refresh()
		"error":
			if msg.get("code") in ["deck", "bad_name", "decks_full", "pack"]:
				if not _pending.is_empty():  # (answers come in order: the oldest new deck)
					_pending.erase(_pending.keys()[0])
				message.text = Rules.tr_error(str(msg.get("text", "")))
				refresh()


## The server's decks after login: the active game's ones from another device join the list;
## one changed there since this copy matched it replaces it; one changed only here is sent;
## one gone from there (deleted or unticked elsewhere) stays here only.
func merge(list: Array) -> void:
	var there := {}  # server id -> the server's deck
	for sd in list:
		if sd is Dictionary and str(sd.get("pack", "")) == Packs.active().id():
			there[int(sd.get("id", 0))] = sd
	var changed := false
	for d in decks:
		var id := server_id(d)
		if id <= 0:
			continue
		var sd = there.get(id)
		there.erase(id)
		if sd == null:
			d.servers.erase(link.url)
			changed = true
		elif int(sd.get("updated", 0)) > int(d.servers[link.url].at):
			# ponytail: changed on both sides: the server's copy wins
			var nd := Deck.from_dict(sd)
			if nd:
				d.name = nd.name
				d.hero = nd.hero
				d.cards = nd.cards
				d.servers[link.url].at = int(sd.updated)
				changed = true
		elif not _same(d, sd):
			_push(d)
	for id in there:
		var nd := Deck.from_dict(there[id])
		if nd:
			nd.servers[link.url] = {"id": id, "at": int(there[id].get("updated", 0))}
			decks.append(nd)
			changed = true
	if changed:
		_save()
	else:
		refresh()


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
