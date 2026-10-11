extends TestCase

const TEST_STORE := "user://test_ui_decks.json"


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _store_reset() -> void:
	DeckStore.path = TEST_STORE
	if FileAccess.file_exists(TEST_STORE):
		DirAccess.remove_absolute(TEST_STORE)
	DeckStore.save_all([])  # an empty list (a missing file means the first run with starter decks)


func _store_restore() -> void:
	if FileAccess.file_exists(TEST_STORE):
		DirAccess.remove_absolute(TEST_STORE)
	DeckStore.path = DeckStore.DEFAULT_PATH


func test_browse_pages_tabs_cost_and_search() -> void:
	var c := CollectionView.new()
	root().add_child(c)
	eq(c.shown_cards().size(), 8, "8 per page")
	var first := c.shown_cards()
	c.turn_page(1)
	check(c.shown_cards() != first, "next page")
	c.set_tab("MAGE")
	check(c.shown_cards().all(func(id): return CardDb.card(id).cardClass == "MAGE"), "mage tab")
	c.cost_filter = 7
	c.turn_page(0)
	check(c.shown_cards().all(func(id): return CardDb.card(id).cost >= 7), "7+ filter")
	c.cost_filter = -1
	c.set_tab("NEUTRAL")
	c.query = "yeti"
	c.turn_page(0)
	eq(c.shown_cards(), ["VAN_CS2_182"], "search")
	c.free()


func test_builder_add_limits_and_remove() -> void:
	_store_reset()
	var v := DeckListView.new()
	root().add_child(v)
	var d := v.new_deck("HERO_08")
	var c := v.browser
	eq(c.tabs(), ["MAGE", "NEUTRAL"], "only the deck class and neutral")
	check(not (c.find_child("TabDRUID", true, false) as Button).visible, "other class tabs hidden")
	c.click_card("VAN_CS2_029")
	c.click_card("VAN_CS2_029")
	c.click_card("VAN_CS2_029")
	eq(d.count("VAN_CS2_029"), 2, "two copies")
	check(c._hint.text != "", "hint for the third copy")
	v.remove_card("VAN_CS2_029")
	eq(d.count("VAN_CS2_029"), 1, "removed one")
	v.close_deck()
	eq(c.tabs().size(), 10, "every class tab again when browsing")
	check((c.find_child("TabDRUID", true, false) as Button).visible, "class tabs back")
	v.free()
	_store_restore()


func test_deck_list_new_import_export_delete_persist() -> void:
	_store_reset()
	var v := DeckListView.new()
	root().add_child(v)
	var d := v.new_deck("HERO_08")
	eq(v.decks.size(), 1, "new deck")
	eq(v.editing, d, "editor opened")
	for id in Decks.basic("MAGE"):
		d.add(id)
	v.close_deck()
	var code := v.export_code(0)
	eq(code, DeckCode.encode(d), "export")
	eq(v.import_code(code), "", "import ok")
	eq(v.decks.size(), 2, "imported")
	check(v.import_code("garbage") != "", "bad code rejected")
	eq(v.decks.size(), 2, "nothing added for garbage")
	v.delete_deck(0)
	eq(v.decks.size(), 1, "deleted")
	v.free()
	eq(DeckStore.load_all().size(), 1, "saved to the store")
	_store_restore()


func test_export_incomplete_deck_refused() -> void:
	_store_reset()
	var v := DeckListView.new()
	root().add_child(v)
	v.new_deck("HERO_01")
	v.close_deck()
	eq(v.export_code(0), "", "no code for 0/30")
	check(v.message.text != "", "reason shown")
	v.free()
	_store_restore()


func test_training_with_saved_deck_and_incomplete_deck() -> void:
	_store_reset()
	var full := Deck.new()
	full.hero = "HERO_09"
	full.name = "Priest"
	for id in Decks.basic("PRIEST"):
		full.add(id)
	var half := Deck.new()
	half.hero = "HERO_01"
	half.name = "Half"
	half.add("VAN_CS2_108")
	DeckStore.save_all([full, half])
	var t := TrainingSetup.new()
	root().add_child(t)
	var started := []
	t.start.connect(func(deck, bot): started.append(deck))
	var half_row: DeckTiles.DeckRow = t.chooser.rows[1]  # the incomplete one (saved decks come first)
	check(half_row.disabled, "incomplete deck greyed out")
	check(half_row.tooltip_text != "", "reason shown")
	t.chooser.pick(half_row.deck)
	t.play()
	eq(t.step, 1, "incomplete deck refused")
	eq(started.size(), 0, "nothing started")
	t.chooser.rows[0].pressed.emit()
	t.play()
	eq(started.size(), 1, "saved deck starts")
	eq(started[0].name, "Priest", "the saved deck")
	t.free()
	_store_restore()



func test_import_error_visible_in_popup() -> void:
	_store_reset()
	var v := DeckListView.new()
	root().add_child(v)
	v._show_import()
	(v.find_child("CodeInput", true, false) as TextEdit).text = "garbage"
	(v.find_child("DoImport", true, false) as Button).pressed.emit()
	var err := v.find_child("PopupError", true, false) as Label
	check(err != null and err.text != "", "error shown inside the popup")
	v.free()
	_store_restore()


func test_damaged_store_message_shown() -> void:
	_store_reset()
	var f := FileAccess.open(TEST_STORE, FileAccess.WRITE)
	f.store_string("{ broken")
	f.close()
	var v := DeckListView.new()
	root().add_child(v)
	check(v.message.text != "", "player is told about the damaged file")
	v.free()
	DirAccess.remove_absolute("user://test_ui_decks.bad.json")
	DeckStore.last_load_error = ""
	_store_restore()


func test_builder_saves_every_change() -> void:
	_store_reset()
	var v := DeckListView.new()
	root().add_child(v)
	v.new_deck("HERO_08")
	v.browser.click_card("VAN_CS2_029")
	eq(DeckStore.load_all()[0].cards, ["VAN_CS2_029"] as Array[String], "saved without pressing Done")
	v.free()
	_store_restore()


func test_empty_name_falls_back_on_done() -> void:
	_store_reset()
	var v := DeckListView.new()
	root().add_child(v)
	var d := v.new_deck("HERO_08")
	d.name = "   "
	v.close_deck()
	check(d.name.strip_edges() != "", "default name restored")
	v.free()
	_store_restore()


func test_rarity_filter() -> void:
	var c := CollectionView.new()
	root().add_child(c)
	c.tab = "NEUTRAL"
	c.rarity_filter = "LEGENDARY"
	var cards := c.filtered()
	check(not cards.is_empty(), "some neutral legendaries")
	check(cards.all(func(id): return CardDb.card(id).get("rarity") == "LEGENDARY"), "only legendaries")
	(c.find_child("RarityEPIC", true, false) as Button).pressed.emit()
	check(c.filtered().all(func(id): return CardDb.card(id).get("rarity") == "EPIC"), "epic button")
	(c.find_child("RarityEPIC", true, false) as Button).pressed.emit()
	eq(c.rarity_filter, "", "a second click clears it")
	c.free()


func test_deck_rows_tiles_and_fill_bar() -> void:
	_store_reset()
	var v := DeckListView.new()
	root().add_child(v)
	v.new_deck("HERO_08")
	var c := v.browser
	c.click_card("VAN_CS2_029")
	c.click_card("VAN_CS2_029")
	var tile := v.find_child("Entry_VAN_CS2_029", true, false)
	check(tile is DeckTiles.DeckTile and tile.copies == 2, "a tile with two copies")
	eq(v._bar.ratio, 2.0 / 30.0, "the bar shows 2 of 30")
	eq(v._count.text, "2 / 30", "the count")
	(v.find_child("Done", true, false) as Button).pressed.emit()
	eq(v.editing, null, "Done goes back to the list")
	var row := v.find_child("Deck0", true, false)
	check(row is DeckTiles.DeckRow, "the deck shows as a row with its hero")
	(row as Button).pressed.emit()
	eq(v.editing, v.decks[0], "a click on a row opens the deck")
	v.free()
	_store_restore()


func _two_decks() -> DeckListView:
	_store_reset()
	var full := Deck.new()
	full.hero = "HERO_08"
	full.name = "Mage"
	for id in Decks.basic("MAGE"):
		full.add(id)
	var half := Deck.new()
	half.hero = "HERO_01"
	half.name = "Half"
	half.add("VAN_CS2_108")
	DeckStore.save_all([full, half])
	var v := DeckListView.new()
	root().add_child(v)
	return v


func test_one_screen_shows_cards_and_decks() -> void:
	var v := _two_decks()
	eq(v.browser.shown_cards().size(), 8, "the cards on the left")
	eq(v.list.get_child_count(), 2, "the decks on the right")
	check(v._list_box.visible and not v._edit_box.visible, "the list, not an open deck")
	check(v.find_child("NewDeck", true, false) != null and v.find_child("ImportCode", true, false) != null, "new and import buttons")
	var backs := []
	v.back.connect(func(): backs.append(1))
	(v.find_child("Back", true, false) as Button).pressed.emit()
	eq(backs.size(), 1, "one Back to the menu")
	v.browser.click_card("VAN_CS2_029")
	eq(v.decks[0].cards.size(), 30, "browsing adds nothing")
	v.free()
	_store_restore()


func test_open_deck_in_right_panel_add_remove_saves() -> void:
	var v := _two_decks()
	(v.find_child("Deck1", true, false) as Button).pressed.emit()
	var d := v.decks[1]
	eq(v.editing, d, "the deck is open")
	check(v._edit_box.visible and not v._list_box.visible, "the right panel shows the deck")
	eq((v.find_child("DeckName", true, false) as LineEdit).text, "Half", "its name")
	eq(v.browser.tab, "WARRIOR", "the cards of its class")
	check(v.browser.shown_cards().all(func(id): return CardDb.card(id).cardClass == "WARRIOR"), "only its class")
	var id: String = v.browser.shown_cards()[0]
	(v.browser._grid.get_child(0) as CardView).clicked.emit(v.browser._grid.get_child(0))
	eq(d.count(id), 1 + int(id == "VAN_CS2_108"), "a click on a card adds it")
	eq(v._count.text, "%d / 30" % d.cards.size(), "the count follows")
	eq(DeckStore.load_all()[1].cards.size(), d.cards.size(), "saved at once")
	(v.find_child("Entry_VAN_CS2_108", true, false) as Button).pressed.emit()
	eq(d.count("VAN_CS2_108"), int(id == "VAN_CS2_108"), "a click on a line removes one copy")
	eq(DeckStore.load_all()[1].cards.size(), d.cards.size(), "the removal is saved")
	var name_edit := v.find_child("DeckName", true, false) as LineEdit
	name_edit.text = "Renamed"
	name_edit.text_changed.emit("Renamed")
	eq(DeckStore.load_all()[1].name, "Renamed", "the new name is saved")
	v.free()
	_store_restore()


func test_inline_delete_copy_export() -> void:
	var v := _two_decks()
	(v.find_child("Deck0", true, false).find_child("Copy", true, false) as Button).pressed.emit()
	eq(v.decks.size(), 3, "duplicated")
	eq(v.decks[2].cards, v.decks[0].cards, "the same cards")
	eq(DeckStore.load_all().size(), 3, "the copy is saved")
	(v.find_child("Deck0", true, false).find_child("Export", true, false) as Button).pressed.emit()
	var out := v.find_child("CodeOutput", true, false) as LineEdit
	check(out != null and out.text == DeckCode.encode(v.decks[0]), "the code in a popup")
	v._close()
	(v.find_child("Deck1", true, false).find_child("Export", true, false) as Button).pressed.emit()
	check(v.find_child("CodeOutput", true, false) == null, "no code for an unfinished deck")
	check(v.message.text != "", "the reason is shown")
	(v.find_child("Deck1", true, false).find_child("Delete", true, false) as Button).pressed.emit()
	eq(v.decks.size(), 3, "asks first")
	(v.find_child("ConfirmDelete", true, false) as Button).pressed.emit()
	eq(v.decks.size(), 2, "deleted after the confirm")
	eq(v.decks[1].name, "Mage (copy)", "the right one")
	eq(DeckStore.load_all().size(), 2, "the deletion is saved")
	v.free()
	_store_restore()


func test_filters_combine() -> void:
	var c := CollectionView.new()
	root().add_child(c)
	(c.find_child("TabNEUTRAL", true, false) as Button).pressed.emit()
	(c.find_child("Cost4", true, false) as Button).pressed.emit()
	(c.find_child("RarityRARE", true, false) as Button).pressed.emit()
	(c.find_child("TypeMINION", true, false) as Button).pressed.emit()
	var cards := c.filtered()
	check(not cards.is_empty(), "some neutral rare 4-cost minions")
	for id in cards:
		var card := CardDb.card(id)
		check(card.cardClass == "NEUTRAL" and card.cost == 4 and card.rarity == "RARE" and card.type == "MINION", id)
	eq(c.shown_cards(), cards.slice(0, 8), "the grid shows them")
	var search := c.find_child("Search", true, false) as LineEdit
	var first := CardText.name(cards[0])
	search.text_changed.emit(first)
	check(c.filtered().has(cards[0]) and c.filtered().size() <= cards.size(), "search narrows the rest")
	search.text_changed.emit("zzzz")
	eq(c.shown_cards(), [], "nothing matches")
	check(c._empty.visible, "and it says so")
	search.text_changed.emit("")
	(c.find_child("TypeMINION", true, false) as Button).pressed.emit()
	eq(c.type_filter, "", "a second click clears the type")
	(c.find_child("TypeWEAPON", true, false) as Button).pressed.emit()
	(c.find_child("Cost-1", true, false) as Button).pressed.emit()
	(c.find_child("RarityRARE", true, false) as Button).pressed.emit()
	check(c.filtered().all(func(id): return CardDb.card(id).type == "WEAPON"), "weapons only")
	check((c.find_child("TypeWEAPON", true, false) as Button).button_pressed, "the active filter is lit")
	check(not (c.find_child("TypeMINION", true, false) as Button).button_pressed, "the others are not")
	c.free()


func test_pager_moves_pages() -> void:
	var c := CollectionView.new()
	root().add_child(c)
	c.set_tab("NEUTRAL")
	var n := c.page_count()
	check(n > 2, "several pages")
	var prev := c.find_child("Prev", true, false) as Button
	var next := c.find_child("Next", true, false) as Button
	check(prev.disabled and not next.disabled, "at the first page")
	var first := c.shown_cards()
	next.pressed.emit()
	eq(c.page, 1, "next page")
	check(c.shown_cards() != first, "other cards")
	eq((c.find_child("Page", true, false) as Label).text, "2 / %d" % n, "the page indicator")
	prev.pressed.emit()
	eq(c.shown_cards(), first, "back")
	c.turn_page(99)
	eq(c.page, n - 1, "stops at the last page")
	check(next.disabled, "next is off at the end")
	(c.find_child("Cost7", true, false) as Button).pressed.emit()
	eq(c.page, 0, "a filter goes back to the first page")
	c.free()
