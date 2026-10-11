extends TestCase

const TEST_STORE := "user://test_ui_decks.json"


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _store_reset() -> void:
	DeckStore.path = TEST_STORE
	if FileAccess.file_exists(TEST_STORE):
		DirAccess.remove_absolute(TEST_STORE)


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
	var d := Deck.new()
	d.hero = "HERO_08"
	var c := CollectionView.new()
	c.deck = d
	root().add_child(c)
	eq(c.tabs(), ["MAGE", "NEUTRAL"], "only the deck class and neutral")
	c.click_card("VAN_CS2_029")
	c.click_card("VAN_CS2_029")
	c.click_card("VAN_CS2_029")
	eq(d.count("VAN_CS2_029"), 2, "two copies")
	check(c._hint.text != "", "hint for the third copy")
	c.remove_card("VAN_CS2_029")
	eq(d.count("VAN_CS2_029"), 1, "removed one")
	c.free()


func test_deck_list_new_import_export_delete_persist() -> void:
	_store_reset()
	var v := DeckListView.new()
	root().add_child(v)
	var d := v.new_deck("HERO_08")
	eq(v.decks.size(), 1, "new deck")
	check(v._editor != null, "editor opened")
	for id in Decks.basic("MAGE"):
		d.add(id)
	v._editor.done.emit(d)
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
	v._editor.done.emit(v.decks[0])
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
	t.select_deck(10)  # the incomplete one (after 9 basic decks and "Priest")
	t.play()
	eq(started.size(), 0, "incomplete deck refused")
	check(t.error.text != "", "reason shown")
	t.select_deck(9)
	t.play()
	eq(started.size(), 1, "saved deck starts")
	eq(started[0].name, "Priest", "the saved deck")
	t.free()
	_store_restore()
