extends TestCase
## ClassicHS Studio's project (studio/studio_project.gd): a new game with a class and five cards is built into a
## .cardpack that the pack checks (the game's and tools/pack.py's) and the rules engine accept and bots play;
## an installed pack opened as a copy; a card renamed everywhere.

const ROOT := "user://test_studio_project"


func _fresh() -> void:
	StudioProject.root = ROOT
	_wipe(ROOT)


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_wipe(dir + "/" + d)
	DirAccess.remove_absolute(dir)


## The errors (warnings are fine: names missing in some languages, cards without pictures).
func _bad(c: PackCheck) -> Array:
	return c.items.filter(func(it): return it.level == PackCheck.ERROR).map(func(it): return "%s:%d %s" % [it.file, it.line, it.text])


## The game of the test: the template's Knight and five cards of its own (a Taunt minion, a Battlecry, a
## Deathrattle that summons a token, a spell, a weapon), two decks of ten.
func _game() -> StudioProject:
	var p := StudioProject.create("test-game", "Test Game")
	var wall := p.add_card("MINION")
	p.card(wall).merge({"cost": 2, "attack": 1, "health": 4, "keywords": [p.mechanic_name("GUARD")]}, true)
	p.set_text(wall, "en", "Shield Wall", "<b>Taunt</b>")
	var archer := p.add_card("MINION", "KNIGHT")
	p.card(archer).merge({"cost": 2, "attack": 2, "health": 2}, true)
	p.set_effect(archer, {"blocks": [{"when": "play", "target": "chosen_enemy_minion", "do": "damage", "n": 1}], "lua": ""})
	p.set_text(archer, "en", "Archer", "<b>Battlecry:</b> Deal 1 damage to an enemy minion.")
	var cub := p.add_card("MINION")
	p.card(cub).merge({"set": "token", "collectible": false}, true)
	p.card(cub).erase("rarity")
	p.set_text(cub, "en", "Cub", "")
	var wolf := p.add_card("MINION")
	p.card(wolf).merge({"cost": 3, "attack": 3, "health": 2}, true)
	p.set_effect(wolf, {"blocks": [{"when": "deathrattle", "target": "my_hero", "do": "summon", "card": cub, "n": 1}], "lua": ""})
	p.set_text(wolf, "en", "Wolf", "<b>Deathrattle:</b> Summon a 1/1 Cub.")
	var bolt := p.add_card("SPELL", "KNIGHT")
	p.card(bolt).cost = 2
	p.set_effect(bolt, {"blocks": [{"when": "play", "target": "chosen_any", "do": "damage", "n": 3}], "lua": ""})
	p.set_text(bolt, "en", "Bolt", "Deal $3 damage.")
	var sword := p.add_card("WEAPON", "KNIGHT")
	p.card(sword).merge({"cost": 2, "attack": 2, "durability": 2}, true)
	p.set_text(sword, "en", "Sword", "")
	p.rules.limits.deck_size = 10
	var deck := [wall, wall, archer, archer, wolf, wolf, bolt, bolt, sword, sword]
	p.decks["1_first"] = {"name": "First", "champion": "knight_hero", "cards": deck}
	p.decks["2_second"] = {"name": "Second", "champion": "knight_hero", "cards": deck.duplicate()}
	var img := Image.create(64, 48, false, Image.FORMAT_RGB8)
	img.fill(Color.CORNFLOWER_BLUE)
	eq(p.set_art(wolf, img), "", "a picture")
	p.set_framing(wolf, 0.1, -0.05, 1.3)
	return p


func test_a_game_with_a_class_and_five_cards_exports_a_pack_the_checks_and_the_engine_accept() -> void:
	_fresh()
	var p := _game()
	eq(p.deck_problem("1_first"), "", "the deck is legal")
	var c := p.build(true, 2)
	eq(_bad(c), [], "no errors")
	eq(c.count(PackCheck.PASS), 3, "the engine loaded it and two bot games ended")
	var bytes := c.pack_bytes()
	var again := PackCheck.open_file(bytes, c.file_name())
	again.check()
	eq(_bad(again), [], "the .cardpack checks clean as it is")
	eq(c.file_name(), "test-game-0.1.0.cardpack", "its file name")
	var file := ROOT + "/" + c.file_name()
	var f := FileAccess.open(file, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var pack := Pack.open(file, "imported")
	eq(pack.id(), "test-game", "the pack's id")
	eq(pack.problems(), [], "the game may use it")
	eq(pack.json("art/main/framing.json"), {p.cards[-3].id: {"x": 0.1, "y": -0.05, "zoom": 1.3}}, "the picture's framing")
	check(pack.has("art/main/%s.png" % p.cards[-3].id), "the picture")
	eq(pack.manifest.art_sets, [{"id": "main", "default": true}], "its art set")
	check(pack.json("cards.json").any(func(x): return x.id == p.cards[-5].id and x.get("keywords") == ["BATTLECRY"]),
		"the Battlecry block names the mechanic: " + str(pack.json("cards.json")))
	check(str(pack.read("scripts/studio.lua").get_string_from_utf8()).contains("battlecry"), "the blocks' script")
	pack.close()
	_pack_py_check(file)
	var r := Packs.install(bytes, "imported")
	var installed: Pack = r.get("pack")
	check(installed != null, "it installs: " + str(r))
	if installed:
		eq(Rules.can_play(installed), "", "the game can play it")
		Packs.remove(installed)


## tools/pack.py check finds nothing either (where the tools are: a source checkout with python3).
func _pack_py_check(file: String) -> void:
	var tool := ProjectSettings.globalize_path("res://tools/pack.py")
	if not FileAccess.file_exists(tool):
		return
	var out := []
	var code := OS.execute("python3", [tool, "check", ProjectSettings.globalize_path(file)], out, true)
	if code == -1:
		return
	eq(code, 0, "tools/pack.py check: " + "".join(out))


func test_a_new_game_has_its_class_hero_power_and_eight_languages() -> void:
	_fresh()
	var p := StudioProject.create("fresh", "Fresh")
	eq(StudioProject.id_problem("fresh"), "A project with this id exists", "the id is taken")
	check(StudioProject.id_problem("Bad Id") != "", "a bad id")
	eq(StudioProject.list().map(func(e): return e.id), ["fresh"], "listed")
	var again := StudioProject.open("fresh")
	eq(again.manifest.locales, StudioProject.LANGS, "eight languages")
	eq(again.card("knight_hero").power, "knight_power", "the hero's power")
	eq(again.rules.default_power, "knight_power", "the default power")
	eq(again.text("knight_power", "ru").name, "Поднять щит", "its name in Russian")
	eq(again.locales.de.mechanics.TAUNT.name, "Spott", "Classic's mechanic names")
	check(again.keyword_choices("en").any(func(k): return k.id == "TAUNT" and k.tip != ""), "keywords to choose, with tips")
	eq(again.add_class("MAGE", "3d8bff"), "", "a second class")
	check(again.card("mage_hero").get("power") == "mage_power" and again.card("mage_power").type == "POWER", "its hero and power")
	again.remove_class("MAGE")
	check(again.card("mage_hero").is_empty() and again.card("mage_power").is_empty(), "removed with its hero and power")
	var c := again.build(true)
	eq(_bad(c), [], "it checks clean")


func test_a_deck_being_made_does_not_stop_a_test_game() -> void:
	_fresh()
	var p := StudioProject.create("half-deck", "Half Deck")
	var cid := p.add_card("MINION")
	p.decks["mine"] = {"name": "Mine", "champion": "knight_hero", "cards": [cid]}
	var c := p.build(true)
	check(c.errors() > 0, "the deck is too small: an error")
	eq(StudioProject.blocking(c), 0, "but not one that stops a game")
	check(c.rules_hash != "", "the engine loaded it")
	var r := Packs.install(c.pack_bytes(), "imported")
	check(r.has("pack"), "it installs for a test game: " + str(r))
	if r.has("pack"):
		Packs.remove(r.pack)


func test_effects_name_their_mechanics_and_a_card_renames_everywhere() -> void:
	_fresh()
	var p := StudioProject.create("renames", "Renames")
	var cid := p.add_card("MINION", "KNIGHT")
	p.set_effect(cid, {"blocks": [{"when": "deathrattle", "target": "enemy_hero", "do": "damage", "n": 2}], "lua": ""})
	eq(p.card(cid).get("keywords"), ["DEATHRATTLE"], "Deathrattle")
	p.set_effect(cid, {"blocks": [{"when": "play", "target": "enemy_hero", "do": "damage", "n": 2}], "lua": ""})
	eq(p.card(cid).get("keywords"), ["BATTLECRY"], "Battlecry instead")
	p.set_effect(cid, {"blocks": [], "lua": ""})
	eq(p.card(cid).get("keywords"), null, "none")
	p.set_effect(cid, {"blocks": [], "lua": "battlecry = function(g, me) g.draw(g.ctrl(me)) end,"})
	p.set_text(cid, "ru", "Тест", "")
	p.set_art(cid, Image.create(8, 8, false, Image.FORMAT_RGB8))
	p.set_framing(cid, 0.2, 0, 1)
	p.decks["d"] = {"name": "D", "champion": "knight_hero", "cards": [cid]}
	eq(p.rename_card(cid, "bad id"), "Use Latin letters, digits and underscores", "a bad id")
	eq(p.rename_card(cid, "drawer"), "", "renamed")
	eq(p.text("drawer", "ru").name, "Тест", "its texts")
	check(p.effects.has("drawer") and not p.effects.has(cid), "its effect")
	check(p.art_path("drawer") != "", "its picture")
	eq(p.framing("drawer"), Vector3(0.2, 0, 1), "its framing")
	eq(p.decks.d.cards, ["drawer"], "the decks")
	p.set_text("drawer", "en", "Drawer", "Draw a card.")
	var view := p.preview_pack(["drawer"])
	check(view != null and view.has("art/main/framing.json") and view.find("art/main", "drawer", ["png"]) != "", "the preview has the picture")
	CardDb.begin(view)
	eq(CardText.name("drawer"), "Drawer", "the preview pack draws the card as it is now")
	eq(CardText.name("drawer", "ru"), "Тест", "in each language")
	CardDb.end()
	CardDb.forget(view)
	p.save()
	check(FileAccess.get_file_as_string(p.pack_dir() + "/scripts/studio.lua").contains("drawer"), "the script")
	eq(p.card("drawer").script, "scripts/studio.lua#drawer", "the card points at it")


func test_an_installed_pack_opens_as_a_copy_with_a_new_id() -> void:
	_fresh()
	var neon := Pack.open("res://packs/neon.cardpack")
	var p := StudioProject.from_pack(neon, "my-neon")
	neon.close()
	check(p != null, "copied")
	if p == null:
		return
	eq(p.manifest.id, "my-neon", "the new id")
	check(str(p.manifest.name.en).ends_with("(copy)"), "named a copy")
	eq(p.manifest.art_sets.map(func(s): return s.id), ["default"], "only the default art set")
	var c := p.build(true, 1)
	eq(c.errors(), 0, "it builds: " + str(_bad(c)))
	eq(StudioProject.from_pack(neon, "my-neon"), null, "the id is taken now")
