extends TestCase
## The 0.40 migration (game/migration.gd) over a user folder as a 0.32 client left it: settings,
## profile, saved server sessions and decks move to their new places, once; nothing the player
## made is lost.

const A := "wss://play.example:7377"


static func _write(path: String, value: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(value))
	f.close()


static func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null


func _template(key: String) -> Dictionary:
	for t in Decks.templates():
		if t.key == key:
			return t
	return {}


## The files of a 0.32 player: Classic's sets in the old settings, a game's back, a server with a
## saved login, a name, decks with an unchanged ready deck, a renamed one, the player's own, and a
## Neonfall deck in Classic's file.
func _old_folder() -> Dictionary:
	var freeze: Deck = _template("08_freeze_mage").deck
	var mine := Deck.new()
	mine.name = "My Mage"
	mine.hero = "HERO_08"
	mine.cards.assign(Decks.basic("MAGE"))
	var neon: Pack = Packs.all().filter(func(p: Pack): return p.id() == "neon")[0]
	var neon_deck: Dictionary = neon.json("decks/zero_trace.json")
	_write(Settings.path, {"language": "de", "music": 0.3, "art": "cartoon", "music_set": "open", "card_back": "horde",
		"servers": [{"url": A, "name": "Play"}], "pack_sets": {"neon": {"back": "pack", "art": "simple"}}})
	_write(Profile.path, {"name": "Jaina"})
	_write(ServerLink.session_path, {"servers": {A: {"token": "tok", "deck": {"name": "My Mage", "hero": "HERO_08"}}}, "last": A})
	var decks := [
		{"name": "Freeze Mage", "hero": "HERO_08", "cards": Array(freeze.cards)},  # put there by 0.32, never changed
		{"name": "Freeze Mage (mine)", "hero": "HERO_08", "cards": Array(freeze.cards)},  # renamed: the player's
		mine.to_dict(),
		{"name": "Neon in the wrong file", "hero": neon_deck.champion, "cards": neon_deck.cards},
	]
	_write(DeckStore.file(Packs.CLASSIC), {"version": 1, "classic": 1, "basic": 1, "decks": decks})
	DirAccess.remove_absolute(DeckStore.file("neon"))
	return {"mine": mine, "neon": neon_deck}


func test_the_old_folder_moves_to_the_new_layout() -> void:
	var old := _old_folder()
	Settings.load_settings()
	eq(Settings.data.layout, 0, "an old folder")
	check(Migration.run(), "the migration runs")
	eq(Settings.data.pack_sets[Packs.CLASSIC], {"art": "cartoon", "music": "open"}, "Classic's sets: its choices per game")
	eq(Settings.data.pack_sets.neon, {"art": "simple"}, "a game's chosen back goes, its art stays")
	eq(Settings.data.card_back, CardBacks.DEFAULT, "a game's back (Horde) becomes the neutral default")
	eq([Settings.data.language, Settings.data.music], ["de", 0.3], "the rest stays")
	eq(Settings.data.servers, [{"id": A, "url": A, "name": "Play"}], "the server: a connection, by its address")
	eq(ServerLink.saved_for(Settings.data.servers[0].id).get("token"), "tok", "its saved login stays")
	eq(Profile.load_name(), "Jaina", "the name stays: the code play name")
	var classic: Array = _read(DeckStore.file(Packs.CLASSIC)).decks
	eq(classic.map(func(d): return d.name), ["Freeze Mage (mine)", "My Mage"], "the unchanged ready deck goes; the player's stay")
	eq(classic[1].cards, Array(old.mine.cards), "as they were")
	var neon: Array = _read(DeckStore.file("neon")).decks
	eq(neon.map(func(d): return [d.name, d.hero]), [["Neon in the wrong file", old.neon.champion]], "a Neonfall deck moves to Neonfall")
	Settings.load_settings()
	eq(Settings.data.layout, Migration.LAYOUT, "saved: the new layout")
	check(not Migration.run(), "once only")
	eq(DeckStore.load_all().map(func(d): return d.name), ["Freeze Mage (mine)", "My Mage"], "Classic's list reads them")


## main runs it at start-up, before anything else.
func test_main_migrates_at_start_up() -> void:
	_old_folder()
	var m: Node = load("res://ui/main.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(m)
	eq(Settings.data.layout, Migration.LAYOUT, "migrated")
	check(m.screen is MainMenu, "then the menu (not a first run: the language was set)")
	eq(DeckStore.count_local("neon"), 1, "the decks in their games")
	m.free()
	Locale.set_language("en")


## A first run: nothing to move, the layout is new.
func test_a_new_folder_has_nothing_to_move() -> void:
	DirAccess.remove_absolute(Settings.path)
	DirAccess.remove_absolute(DeckStore.file(Packs.CLASSIC))
	Settings.load_settings()
	check(Migration.run(), "it runs once")
	eq(Settings.data.layout, Migration.LAYOUT, "the new layout")
	check(not FileAccess.file_exists(DeckStore.file(Packs.CLASSIC)), "no decks made up")
