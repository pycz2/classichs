extends TestCase

const HEARTHSIM := "AAECAR8GxwPJBLsFmQfZB/gIDI0B2AGoArUDhwSSBe0G6wfbCe0JgQr+DAA="


func _mage_deck() -> Deck:
	var d := Deck.new()
	d.name = "Test"
	d.hero = "HERO_08"
	for id in Decks.basic("MAGE"):
		d.cards.append(id)
	return d


func test_limits() -> void:
	var d := Deck.new()
	d.hero = "HERO_08"
	eq(d.add("VAN_CS2_029"), "", "fireball 1")
	eq(d.add("VAN_CS2_029"), "", "fireball 2")
	check(d.add("VAN_CS2_029") != "", "no third copy")
	eq(d.add("VAN_EX1_559"), "", "Antonidas")
	check(d.add("VAN_EX1_559") != "", "one legendary copy")
	check(d.add("VAN_CS2_108") != "", "no warrior cards in a mage deck")
	check(d.add("VAN_CS2_101t") != "", "no tokens")
	check(d.add("NOPE") != "", "unknown card")


func test_thirty_cards() -> void:
	var d := _mage_deck()
	eq(d.validate(), "", "basic deck is valid")
	check(d.add("VAN_CS2_231") != "", "no 31st card")
	d.cards.pop_back()
	check(d.validate() != "", "29 cards is not complete")


func test_dict_roundtrip_with_odd_name() -> void:
	var d := _mage_deck()
	d.name = "Огонь \"и\" лёд ✨ \\ \n" + "x".repeat(30)
	var d2 := Deck.from_dict(d.to_dict())
	eq([d2.name, d2.hero, d2.cards], [d.name, d.hero, d.cards], "same deck")
	d.name = "y".repeat(200)
	eq(Deck.from_dict(d.to_dict()).name.length(), Deck.NAME_MAX, "long name cut to the limit")


func test_code_roundtrip() -> void:
	var d := _mage_deck()
	var code := DeckCode.encode(d)
	var r := DeckCode.decode(code)
	eq(r.error, "", "decoded")
	var a: Array = r.deck.cards.duplicate()
	var b: Array = d.cards.duplicate()
	a.sort()
	b.sort()
	eq([r.deck.hero, a], [d.hero, b], "same cards and hero")


func test_code_header_is_classic_format() -> void:
	var raw := Marshalls.base64_to_raw(DeckCode.encode(_mage_deck()))
	eq([raw[0], raw[1], raw[2], raw[3]], [0, 1, 3, 1], "reserved, version, format Classic, one hero")


func test_decode_reference_structure() -> void:
	var p := DeckCode.parse(HEARTHSIM)
	eq(p.error, "", "parsed")
	eq([p.format, p.heroes, p.singles.size(), p.doubles.size()], [2, [31], 6, 12], "HearthSim example")


func test_decode_reference_deck_imports() -> void:
	var r := DeckCode.decode(HEARTHSIM)  # a real 2016 Hunter deck of Basic/Classic cards
	eq(r.error, "", "imported")
	eq([r.deck.hero, r.deck.cards.size()], ["HERO_05", 30], "Rexxar, 30 cards")


func test_decode_rejects_non_classic_cards() -> void:
	var d := DeckCode.pack(2, [31], [99999], [])
	var r := DeckCode.decode(d)
	eq(r.deck, null, "no deck")
	check(r.error.contains("Classic"), r.error)


func test_decode_legacy_dbf_ids() -> void:
	var d := _mage_deck()
	var singles := []
	var doubles := []
	var counts := {}
	for id in d.cards:
		counts[id] = counts.get(id, 0) + 1
	for id in counts:
		(doubles if counts[id] == 2 else singles).append(CardDb.card(id).legacyDbfId)
	var code := DeckCode.pack(1, [637], singles, doubles)  # Wild format, original ids
	var r := DeckCode.decode(code)
	eq(r.error, "", "legacy code imported")
	eq(r.deck.cards.size(), 30, "30 cards")


func test_decode_client_text() -> void:
	var text := "### My Mage\n# Class: Mage\n# Format: Classic\n#\n# 2x (4) Fireball\n#\n%s\n#\n# To use this deck, copy it to your clipboard.\n" % DeckCode.encode(_mage_deck())
	var r := DeckCode.decode(text)
	eq(r.error, "", "client text")
	eq(r.deck.name, "My Mage", "name from ###")


func test_decode_garbage() -> void:
	for bad in ["", "   ", "hello world!", "AAAA", "AAECAQcAAAA=", "%%%%"]:
		var r := DeckCode.decode(bad)
		check(r.deck == null and r.error != "", "rejected: '%s'" % bad)


func test_store_roundtrip_and_broken_file() -> void:
	var path := "user://test_decks.json"
	DeckStore.path = path
	var d := _mage_deck()
	DeckStore.save_all([d])
	var back := DeckStore.load_all()
	eq(back.size(), 1, "one deck")
	eq(back[0].cards, d.cards, "same cards")
	DirAccess.remove_absolute("user://test_decks.bad.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	eq(DeckStore.load_all().size(), 0, "broken file gives no decks")
	check(FileAccess.file_exists("user://test_decks.bad.json"), "broken file kept aside")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://test_decks.bad.json")
	DeckStore.path = DeckStore.DEFAULT_PATH



func _tmp_store(text: String) -> void:
	DeckStore.path = "user://test_store2.json"
	for p in ["user://test_store2.json", "user://test_store2.bad.json", "user://test_store2.bad1.json"]:
		DirAccess.remove_absolute(p)
	var f := FileAccess.open(DeckStore.path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _tmp_clean() -> void:
	for p in ["user://test_store2.json", "user://test_store2.bad.json", "user://test_store2.bad1.json"]:
		DirAccess.remove_absolute(p)
	DeckStore.path = DeckStore.DEFAULT_PATH
	DeckStore.last_load_error = ""


func test_store_drops_unknown_cards_and_rejects_unknown_hero() -> void:
	_tmp_store('{"version": 1, "decks": [{"name": "A", "hero": "HERO_08", "cards": ["VAN_CS2_029", "VAN_GONE"]}, {"name": "B", "hero": "HERO_99", "cards": []}]}')
	var decks := DeckStore.load_all()
	eq(decks.size(), 1, "deck with unknown hero kept aside")
	eq(decks[0].cards, ["VAN_CS2_029"] as Array[String], "unknown card dropped")
	check(DeckStore.last_load_error != "", "player is told")
	check(FileAccess.file_exists("user://test_store2.bad.json"), "copy kept")
	_tmp_clean()


func test_store_backup_not_overwritten() -> void:
	_tmp_store("{ broken")
	DeckStore.load_all()
	var f := FileAccess.open(DeckStore.path, FileAccess.WRITE)
	f.store_string("{ broken again")
	f.close()
	DeckStore.load_all()
	check(FileAccess.file_exists("user://test_store2.bad1.json"), "second backup gets a new name")
	eq(FileAccess.get_file_as_string("user://test_store2.bad.json"), "{ broken", "first backup kept")
	_tmp_clean()


func test_decode_hero_skin_uses_card_class() -> void:
	var d := _mage_deck()
	var singles := []
	var doubles := []
	for pair in d.sorted_counts():
		(doubles if pair[1] == 2 else singles).append(CardDb.card(pair[0]).dbfId)
	var r := DeckCode.decode(DeckCode.pack(3, [2828], singles, doubles))  # an unknown hero (skin)
	eq(r.error, "", "imported")
	eq(r.deck.hero, "HERO_08", "class from the cards")


func test_decode_truncated_code_message() -> void:
	var code := DeckCode.encode(_mage_deck())
	var raw := Marshalls.base64_to_raw(code)
	var cut := Marshalls.raw_to_base64(raw.slice(0, raw.size() - 3))
	var r := DeckCode.decode(cut)
	eq(r.error, str(TranslationServer.translate("This is not a deck code")), "truncated is not a deck code")


func test_decode_code_on_a_later_line() -> void:
	var r := DeckCode.decode("My great deck\n" + DeckCode.encode(_mage_deck()))
	eq(r.error, "", "code found on line 2")


func test_imported_name_limited() -> void:
	var r := DeckCode.decode("### " + "N".repeat(100) + "\n" + DeckCode.encode(_mage_deck()))
	eq(r.deck.name.length(), Deck.NAME_MAX, "name cut to the limit")


func test_starter_decks_for_every_hero_when_no_decks() -> void:
	DeckStore.path = "user://test_starter_decks.json"
	DirAccess.remove_absolute(DeckStore.path)
	var decks := DeckStore.load_all()
	eq(decks.size(), 19, "one Basic deck per hero and the 10 classic decks")
	var classes := {}
	for d in decks:
		eq(d.validate(), "", d.name)
		classes[d.card_class()] = true
	eq(classes.size(), 9, "every class")
	eq(TrainingSetup.available_decks().size(), 19, "the pickers show each starter deck once")
	DeckStore.save_all(decks.slice(0, 2))
	eq(DeckStore.load_all().size(), 2, "saved decks are kept as they are")
	DeckStore.save_all([])
	eq(DeckStore.load_all().size(), 0, "deleting every deck leaves the list empty")
	DeckStore.save_all(decks.slice(0, 2))
	eq(TrainingSetup.available_decks().size(), 19, "plus the starter decks the player deleted")
	DirAccess.remove_absolute(DeckStore.path)


func test_classic_decks_come_ready_and_valid() -> void:
	eq(DeckStore.CLASSIC.size(), 10, "ten classic decks")
	for spec in DeckStore.CLASSIC:
		var r := DeckCode.decode(spec[1])
		check(r.deck != null, "%s: %s" % [spec[0], r.error])
	var first := DeckStore.starter()
	eq(first.size(), 19, "9 Basic decks and the 10 classic ones on a first run")
	eq(first[9].name, "Control Warrior", "named")


func test_classic_decks_are_added_once_to_saved_decks() -> void:
	_tmp_store('{"version": 1, "decks": [{"name": "Mine", "hero": "HERO_08", "cards": ["VAN_CS2_029"]}]}')
	var decks := DeckStore.load_all()
	eq(decks.size(), 11, "my deck and the classic decks")
	eq(decks[0].name, "Mine", "mine first")
	decks.remove_at(1)  # the player deletes one and the list is saved
	DeckStore.save_all(decks)
	eq(DeckStore.load_all().size(), 10, "a deleted classic deck does not come back")
	_tmp_clean()
