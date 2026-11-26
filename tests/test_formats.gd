extends TestCase
## Standard and Wild (rules.json `formats`, packs/eras): the client's card lists, Wild decks marked, the deck builder's
## format filter, and Training started in a format. A game with one format shows no switch and plays as before.

const STORE := "user://test_formats_decks.json"
## Naxxramas with two formats (made up for the test): Standard = the Basic and Classic cards without Fireball.
const FORMATS := {"standard": {"sets": ["VANILLA"], "exclude": ["VAN_CS2_029"]}, "wild": {"sets": ["VANILLA", "NAXX"]}}

var _pack: Pack


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## Installs and activates the test pack, with an empty deck store.
func _setup() -> void:
	var naxx: Pack = Packs.all().filter(func(p): return p.id() == "naxx-2014")[0]
	var at := "user://test_formats_src.cardpack"
	var f := FileAccess.open(at, FileAccess.WRITE)
	f.store_buffer(Packs.bytes_of(naxx))
	f.close()
	var p := Pack.open(at)
	var rules: Dictionary = p.rules().duplicate(true)
	var man: Dictionary = p.manifest.duplicate(true)
	p.close()
	rules.formats = FORMATS
	man.id = "test.formats"
	var bytes := _repacked(at, {"rules.json": Pack.canonical(rules).to_utf8_buffer()})
	f = FileAccess.open(at, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	p = Pack.open(at)
	man.rules_hash = p.computed_rules_hash()
	p.close()
	var r := Packs.install(_repacked(at, {"manifest.json": Pack.canonical(man).to_utf8_buffer()}), "imported")
	DirAccess.remove_absolute(at)
	_pack = r.get("pack")
	check(_pack != null, "installed: " + str(r))
	Packs.set_active(_pack)
	DeckStore.path = STORE
	DeckStore.save_all([])


func _teardown() -> void:
	Packs.set_active(Packs.all().filter(func(p): return p.id() == "classic-2014")[0])
	if _pack:
		Packs.remove(Packs.find(Packs.content_hash(_pack)))
	DirAccess.remove_absolute(STORE)
	DeckStore.path = DeckStore.DEFAULT_PATH


func _repacked(src: String, change: Dictionary) -> PackedByteArray:
	var out := "user://test_formats_out.zip"
	var r := ZIPReader.new()
	r.open(src)
	var w := ZIPPacker.new()
	w.open(out)
	for name in r.get_files():
		if not change.has(name):
			w.start_file(name)
			w.write_file(r.read_file(name))
			w.close_file()
	for name in change:
		w.start_file(name)
		w.write_file(change[name])
		w.close_file()
	w.close()
	r.close()
	var bytes := FileAccess.get_file_as_bytes(out)
	DirAccess.remove_absolute(out)
	return bytes


func _deck(name: String, cards: Array) -> Deck:
	var d := Deck.new()
	d.name = name
	d.hero = Decks.hero("MAGE")
	for c in cards:
		d.cards.append(c)
	return d


func test_the_cards_and_decks_of_each_format() -> void:
	_setup()
	eq(CardDb.formats(), ["standard", "wild"], "the game's formats")
	var std := CardDb.collectible("standard")
	check(not std.has("FP1_002") and not std.has("VAN_CS2_029") and std.has("VAN_EX1_277"), "Standard: no Naxxramas card, no Fireball")
	check(CardDb.collectible("wild").has("FP1_002") and CardDb.collectible().has("VAN_CS2_029"), "Wild and no format: every card")
	var basic := Decks.basic("MAGE", "standard")
	eq([basic.size(), basic.has("VAN_CS2_029")], [30, false], "the bot's Standard deck has no Wild card")
	check(Decks.basic("MAGE").has("VAN_CS2_029"), "its Wild deck has")
	var wild := _deck("Wild", basic.slice(0, 29) + ["FP1_002"])
	check(wild.wild_only() and not _deck("Std", basic).wild_only(), "a deck with a Naxxramas card is a Wild deck")
	wild.arena = true
	check(not wild.wild_only(), "an Arena deck is no Wild deck")
	wild.arena = false
	var d := {"hero": wild.hero, "cards": Array(wild.cards)}
	eq(Rules.deck_error(d, "standard"), "This deck has cards that are not in this format", "the engine refuses it in Standard")
	eq([Rules.deck_error(d, "wild"), Rules.deck_error(d)], ["", ""], "and takes it in Wild")
	eq(Rules.validate(d, "standard"), str(TranslationServer.translate("This deck has cards that are not in this format")), "translated")
	var row := DeckTiles.DeckRow.new(wild)
	check(row._tag().contains(tr("Wild")), "its tile says Wild")
	row.free()
	_teardown()


func test_training_in_standard_or_wild() -> void:
	_setup()
	var basic := Decks.basic("MAGE", "standard")
	DeckStore.save_all([_deck("Std", basic), _deck("Wild", basic.slice(0, 29) + ["FP1_002"])])
	var t := TrainingSetup.new()
	root().add_child(t)
	var started := []
	t.start.connect(func(deck, _bot): started.append([deck.name, t.format]))
	eq(t.format, "standard", "Standard first")
	var std_b := t.find_child("Format_standard", true, false) as Button
	var wild_b := t.find_child("Format_wild", true, false) as Button
	check(std_b != null and wild_b != null and std_b.button_pressed, "the Standard/Wild switch")
	var wild_row: DeckTiles.DeckRow = t.chooser.rows.filter(func(r): return r.deck.name == "Wild")[0]
	check(wild_row.disabled and wild_row.tooltip_text != "", "a Wild deck greyed out for Standard, with why")
	t.chooser.pick(wild_row.deck)
	eq(t.step, 1, "and refused")
	wild_b.button_pressed = true
	eq(t.format, "wild", "Wild chosen")
	check(not wild_row.disabled, "the Wild deck can be played in Wild")
	t.chooser.pick(wild_row.deck)
	t.play()
	eq(started, [["Wild", "wild"]], "started in Wild")
	t.free()
	# the menu's training starts the engine's game in the chosen format
	var m: Node = load("res://ui/main.tscn").instantiate()
	root().add_child(m)
	m.show_training_setup()
	var ts := m.screen as TrainingSetup
	var std_row: DeckTiles.DeckRow = ts.chooser.rows.filter(func(r): return r.deck.name == "Std")[0]
	ts.chooser.pick(std_row.deck)
	ts.play()
	var v := m.screen as MatchView
	check(v != null, "the game started")
	if v:
		var snap := Rules.request({"op": "snapshot", "game": v.controller.id})
		eq(snap.get("state", {}).get("format"), "standard", "a Standard game")
		eq(v.controller.setup_req.get("format"), "standard", "kept for its replay")
	m.free()
	_teardown()


func test_the_deck_builder_filters_by_format() -> void:
	_setup()
	var c := CollectionView.new()
	root().add_child(c)
	var fp := c.find_child("FormatFilter", true, false) as OptionButton
	check(fp != null, "a Standard/Wild filter")
	eq(c.format_filter, "wild", "browsing: every card")
	c.set_tab("NEUTRAL")
	check(c.filtered().has("FP1_002"), "Naxxramas cards in Wild")
	c.set_deck(_deck("Std", []))
	eq([c.format_filter, fp.selected], ["standard", 0], "a Standard deck: Standard cards")
	c.set_tab("NEUTRAL")
	check(not c.filtered().has("FP1_002") and c.filtered().has("VAN_CS2_189"), "no Naxxramas card")
	fp.item_selected.emit(1)
	check(c.filtered().has("FP1_002"), "Wild again")
	c.set_deck(_deck("Wild", ["FP1_002"]))
	eq(c.format_filter, "wild", "a Wild deck: every card")
	c.free()
	_teardown()


func test_a_game_with_one_format_has_no_switch() -> void:
	_setup()
	Packs.set_active(Packs.all().filter(func(p): return p.id() == "classic-2014")[0])
	eq(CardDb.formats(), [], "Classic: one format")
	var t := TrainingSetup.new()
	root().add_child(t)
	check(t.format == "" and t.find_child("Formats", true, false) == null, "no switch")
	t.free()
	var c := CollectionView.new()
	root().add_child(c)
	check(c.find_child("FormatFilter", true, false) == null, "no format filter")
	c.free()
	check(not _deck("x", ["FP1_002"]).wild_only(), "no Wild deck")
	_teardown()
