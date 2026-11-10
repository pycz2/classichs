extends TestCase
## The pack tools (game/pack_check.gd, ui/pack_tools.gd): a pack built from a source folder,
## checked, loaded into the engine, played by bots, installed; broken packs reported.

const DIR := "user://test_pack_tools"

## Tiny Duel of site/dev/en/packs.md (English only).
const TINY := {
	"manifest.json": """{"format": 1, "id": "tiny-duel", "version": "0.1.0", "engine": "0.28.0",
 "name": {"en": "Tiny Duel"}, "description": {"en": "Sun against Moon."}, "authors": ["Tests"],
 "license": "CC BY 4.0", "redistributable": true, "default_locale": "en", "locales": ["en"],
 "art_sets": [], "sound_sets": [], "music_sets": [],
 "colors": {"classes": {"SUN": "f59f00", "MOON": "5c7cfa", "NEUTRAL": "868e96"}}}
""",
	"rules.json": """{
  "format": 1,
  "limits": {"champion_health": 20, "max_mana": 10, "hand": 10, "board": 7, "deck_size": 8, "copies": 2},
  "start": {"first_player": "random", "hand": [3, 4], "coin": "spark", "mulligan": true},
  "bot": {"trap": 2},
  "fatigue": {"enabled": true, "first": 1, "step": 1},
  "timers": {"turn": 75, "fuse": 15, "mulligan": 45},
  "default_power": "sunbeam",
  "classes": [{"id": "SUN", "champion": "sun_queen"}, {"id": "MOON", "champion": "moon_king"}, {"id": "NEUTRAL", "neutral": true}],
  "rarities": [{"id": "COMMON", "tier": "common"}, {"id": "RARE", "tier": "rare"}],
  "sets": ["core", "token"],
  "mechanics": {"WALL": {"engine": "GUARD"}, "CRY": {"engine": "ON_PLAY"}, "LAST_WORD": {"engine": "ON_DEATH"}, "AMBUSH": {"engine": "TRAP"}},
  "modes": {"constructed": {"sets": ["core"], "class_cards": "own_and_neutral"}}
}
""",
	"cards.json": """[
{"id": "sun_queen", "type": "CHAMPION", "class": "SUN", "set": "core", "health": 20, "power": "sunbeam"},
{"id": "sunbeam", "type": "POWER", "class": "SUN", "set": "core", "cost": 2, "script": "scripts/sun.lua#sunbeam"},
{"id": "moon_king", "type": "CHAMPION", "class": "MOON", "set": "core", "health": 20, "power": "moonlight"},
{"id": "moonlight", "type": "POWER", "class": "MOON", "set": "core", "cost": 2, "script": "scripts/moon.lua#moonlight"},
{"id": "spark", "type": "SPELL", "class": "NEUTRAL", "set": "token", "cost": 0, "script": "scripts/neutral.lua#spark"},
{"id": "squire", "type": "MINION", "class": "NEUTRAL", "rarity": "COMMON", "set": "core", "collectible": true, "cost": 1, "attack": 2, "health": 1},
{"id": "shield_bearer", "type": "MINION", "class": "NEUTRAL", "rarity": "COMMON", "set": "core", "collectible": true, "cost": 2, "attack": 1, "health": 4, "keywords": ["WALL"]},
{"id": "archer", "type": "MINION", "class": "SUN", "rarity": "COMMON", "set": "core", "collectible": true, "cost": 2, "attack": 2, "health": 2, "keywords": ["CRY"], "script": "scripts/sun.lua#archer"},
{"id": "banner", "type": "MINION", "class": "SUN", "rarity": "RARE", "set": "core", "collectible": true, "cost": 3, "attack": 2, "health": 3, "script": "scripts/sun.lua#banner"},
{"id": "moon_wolf", "type": "MINION", "class": "MOON", "rarity": "COMMON", "set": "core", "collectible": true, "cost": 3, "attack": 3, "health": 2, "keywords": ["LAST_WORD"], "script": "scripts/moon.lua#moon_wolf"},
{"id": "cub", "type": "MINION", "class": "MOON", "set": "token", "cost": 1, "attack": 1, "health": 1},
{"id": "ambush", "type": "SPELL", "class": "MOON", "rarity": "RARE", "set": "core", "collectible": true, "cost": 2, "keywords": ["AMBUSH"], "script": "scripts/moon.lua#ambush"}
]
""",
	"scripts/sun.lua": """local cards = {}

cards.sunbeam = {
  target = "any",
  hero_power = function(g, me, t) g.damage(me, t, g.hp_dmg(me, 1)) end,
}

cards.archer = {
  target = "enemy_minion",
  battlecry = function(g, me, t) g.damage(me, t, 1) end,
}

cards.banner = {
  aura = function(g, me)
    for _, m in ipairs(g.others(me)) do g.aura_add(m, 1, 0) end
  end,
}

return cards
""",
	"scripts/moon.lua": """local cards = {}

cards.moonlight = {
  target = "any",
  hero_power = function(g, me, t) g.heal(me, t, g.heal_amt(me, 2)) end,
}

cards.moon_wolf = {
  deathrattle = function(g, me) g.summon(g.ctrl(me), "cub", g.died_pos(me)) end,
}

cards.ambush = {
  secret = {
    event = "after_summon",
    cond = function(g, me, ev) return ev.played and not g.mine(me, ev) end,
    effect = function(g, me, ev) g.damage(me, ev.entity, g.spell_dmg(me, 2)) end,
  },
}

return cards
""",
	"scripts/neutral.lua": """local cards = {}
cards.spark = { spell = function(g, me) g.add_mana(g.ctrl(me), 1) end }
return cards
""",
	"locales/en.json": """{
  "cards": {
    "sun_queen": {"name": "Sun Queen"}, "sunbeam": {"name": "Sunbeam", "text": "Deal 1 damage."},
    "moon_king": {"name": "Moon King"}, "moonlight": {"name": "Moonlight", "text": "Restore #2 Health."},
    "spark": {"name": "Spark", "text": "Gain 1 Mana this turn only."}, "squire": {"name": "Squire"},
    "shield_bearer": {"name": "Shield Bearer", "text": "<b>Wall</b>"},
    "archer": {"name": "Archer", "text": "<b>Cry:</b> Deal 1 damage to an enemy minion."},
    "banner": {"name": "Banner", "text": "Your other minions have +1 Attack."},
    "moon_wolf": {"name": "Moon Wolf", "text": "<b>Last Word:</b> Summon a 1/1 Cub."}, "cub": {"name": "Cub"},
    "ambush": {"name": "Ambush", "text": "<b>Ambush:</b> When your opponent plays a minion, deal $2 damage to it."}
  },
  "mechanics": {
    "WALL": {"name": "Wall", "tip": "Enemies must attack minions with Wall first."},
    "CRY": {"name": "Cry", "tip": "Does something when you play it from your hand."},
    "LAST_WORD": {"name": "Last Word", "tip": "Does something when it dies."},
    "AMBUSH": {"name": "Ambush", "tip": "Hidden until your opponent does what it waits for."}
  },
  "classes": {"SUN": "Sun", "MOON": "Moon", "NEUTRAL": "Neutral"},
  "rarities": {"COMMON": "Common", "RARE": "Rare"}
}
""",
	"decks/1_dawn.json": """{"name": "Dawn", "champion": "sun_queen",
 "cards": ["squire", "squire", "shield_bearer", "shield_bearer", "archer", "archer", "banner", "banner"]}
""",
	"decks/2_dusk.json": """{"name": "Dusk", "champion": "moon_king",
 "cards": ["squire", "squire", "shield_bearer", "shield_bearer", "moon_wolf", "moon_wolf", "ambush", "ambush"]}
""",
}


## Writes Tiny Duel with changes (path -> new text, or null: no such file) into a folder; its path.
static func source(name: String, changes := {}) -> String:
	var dir := DIR + "/" + name
	_wipe(dir)
	var all := TINY.duplicate()
	all.merge(changes, true)
	for p: String in all:
		if all[p] == null:
			continue
		DirAccess.make_dir_recursive_absolute((dir + "/" + p).get_base_dir())
		var f := FileAccess.open(dir + "/" + p, FileAccess.WRITE)
		f.store_string(all[p])
		f.close()
	return dir


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_wipe(dir + "/" + d)
	DirAccess.remove_absolute(dir)


## Builds, checks, loads and plays a source as the screen does: the PackCheck.
static func run(dir: String, games := 2) -> PackCheck:
	var c := PackCheck.open_folder(dir)
	c.check()
	if c.load_engine():
		for i in games:
			c.trial(i)
	return c


func _find(c: PackCheck, level: String, words: String) -> Dictionary:
	for it in c.items:
		if it.level == level and words in it.text:
			return it
	return {}


func _bad(c: PackCheck) -> Array:
	return c.items.filter(func(it): return it.level != PackCheck.PASS).map(func(it): return "%s:%d %s" % [it.file, it.line, it.text])


func test_tiny_duel_builds_checks_loads_and_plays() -> void:
	var c := run(source("tiny"))
	eq(_bad(c), [], "no errors and no warnings")
	eq(c.count(PackCheck.PASS), 3, "the engine loaded it and two games ended")
	check(not _find(c, PackCheck.PASS, "3 scripts compile").is_empty(), "the scripts compile")
	var man: Dictionary = JSON.parse_string(c.files["manifest.json"].get_string_from_utf8())
	eq(man.rules_hash, c.computed_rules_hash(), "the build writes rules_hash")
	eq(man.rules_hash, c.rules_hash, "the engine's rules hash is the same")
	eq(man.format, 1.0, "whole numbers stay whole")
	# the .cardpack: a ready pack checks clean as it is, and installs
	var again := PackCheck.open_file(c.pack_bytes(), "tiny.cardpack")
	again.check()
	eq(_bad(again), [], "the built .cardpack checks clean")
	eq(again.file_name(), "tiny-duel-0.1.0.cardpack", "its file name")
	var r := Packs.install(c.pack_bytes(), "imported")
	var p: Pack = r.get("pack")
	check(p != null, "it installs: " + str(r))
	if p:
		eq(p.id(), "tiny-duel", "the installed pack")
		check(Packs.all().has(p), "in the library")
		eq(Rules.can_play(p), "", "the game can play it")
		Packs.remove(p)


func test_the_built_in_packs_check_clean_as_with_the_pack_tool() -> void:
	for f in ["classic", "neon", "naxx"]:
		var c := PackCheck.open_file(FileAccess.get_file_as_bytes("res://packs/%s.cardpack" % f), f + ".cardpack")
		c.check()
		eq(_bad(c), [], f + ": tools/pack.py check finds nothing either")
		check(c.load_engine(), f + " loads")
		check(c.trial(0), f + " plays")


func test_a_zipped_source_folder_is_built_too() -> void:
	var c := PackCheck.open_folder(source("zipped"))
	var files := {}
	for f: String in c.files:  # one folder at the top, as a zip of the folder has it
		files["tiny/" + f] = c.files[f]
	files["tiny/recipe.json"] = "{\"steps\": []}".to_utf8_buffer()
	var z := PackCheck.open_file(PackCheck.zip(files), "tiny.zip")
	check(z.from_source, "a .zip is a source")
	eq(z.files.keys().filter(func(f): return f.begins_with("tiny/")), [], "the top folder is dropped")
	check(not _find(z, PackCheck.WARNING, "recipe.json").is_empty(), "a recipe is not run, and it says so")
	z.check()
	eq(z.errors(), 0, "it checks clean")


func test_a_broken_manifest_says_where() -> void:
	var c := run(source("manifest", {"manifest.json": "{\"format\": 1,\n \"id\": \"tiny-duel\"\n \"version\": \"0.1.0\"}\n"}))
	var it := _find(c, PackCheck.ERROR, "not JSON")
	eq(it.get("file"), "manifest.json", "the file")
	eq(it.get("line"), 3, "the line")
	c = run(source("manifest2", {"manifest.json": TINY["manifest.json"].replace("\"engine\": \"0.28.0\",", "\"engine\": \"0.28.0\", \"colour\": 1,")}))
	it = _find(c, PackCheck.ERROR, "unknown field 'colour'")
	eq([it.get("file"), it.get("line")], ["manifest.json", 1], "a schema error and its line")


func test_a_lua_syntax_error_has_its_file_and_line() -> void:
	var c := run(source("lua", {"scripts/moon.lua": TINY["scripts/moon.lua"].replace("deathrattle = function(g, me)", "deathrattle = function(g, me")}))
	var it := _find(c, PackCheck.ERROR, "the engine refuses the pack")
	eq(it.get("file"), "scripts/moon.lua", "the file: " + str(it))
	eq(it.get("line"), 9, "the line: " + str(it))
	eq(c.count(PackCheck.PASS), 0, "no trial games")


func test_a_script_failing_in_a_game_is_caught() -> void:
	var c := run(source("lua_run", {"scripts/sun.lua": TINY["scripts/sun.lua"].replace("g.damage(me, t, 1)", "g.damge(me, t, 1)")}), 4)
	var it := _find(c, PackCheck.ERROR, "a card script failed")
	eq(it.get("file"), "scripts/sun.lua", "the file: " + str(it))
	eq(it.get("line"), 10, "the line: " + str(it))


func test_a_missing_default_power_is_an_error() -> void:
	var c := run(source("power", {"rules.json": TINY["rules.json"].replace("  \"default_power\": \"sunbeam\",\n", "")}))
	check(not _find(c, PackCheck.ERROR, "default_power is missing").is_empty(), "the file check: " + str(_bad(c)))
	check(not _find(c, PackCheck.ERROR, "the engine refuses the pack").is_empty(), "the engine agrees")


func test_missing_art_and_other_references() -> void:
	var man: String = TINY["manifest.json"].replace("\"art_sets\": []", "\"art_sets\": [{\"id\": \"painted\", \"default\": true}], \"logo\": \"ui/logo.png\"")
	var c := run(source("art", {"manifest.json": man}))
	var it := _find(c, PackCheck.ERROR, "logo ui/logo.png is not in the pack")
	eq([it.get("file"), it.get("line")], ["manifest.json", 4], "a missing picture and its line")
	check(not _find(c, PackCheck.ERROR, "art_sets painted has no files in art/painted/").is_empty(), "an art set without pictures")
	c = run(source("art2", {"manifest.json": man.replace(", \"logo\": \"ui/logo.png\"", ""), "art/painted/squire.png": "png", "art/painted/nobody.png": "png"}))
	eq(c.errors(), 0, "pictures: " + str(_bad(c)))
	check(not _find(c, PackCheck.WARNING, "no picture for 11 cards").is_empty(), "cards without pictures: a warning")
	check(not _find(c, PackCheck.WARNING, "1 pictures of no card (nobody)").is_empty(), "a picture of no card: a warning")
	c = run(source("refs", {"cards.json": TINY["cards.json"].replace("\"class\": \"MOON\", \"set\": \"token\"", "\"class\": \"STAR\", \"set\": \"token\""),
		"decks/2_dusk.json": TINY["decks/2_dusk.json"].replace("\"ambush\", \"ambush\"", "\"ambush\""), "locales/ru.json": "{}"}))
	it = _find(c, PackCheck.ERROR, "cub: unknown class STAR")
	eq([it.get("file"), it.get("line")], ["cards.json", 12], "a card's error at its line")
	check(not _find(c, PackCheck.ERROR, "illegal deck: a deck needs exactly 8 cards").is_empty(), "an illegal deck")
	check(not _find(c, PackCheck.ERROR, "ru is not in manifest.json locales").is_empty(), "a stray locale")
	check(not _find(c, PackCheck.ERROR, "does not start").is_empty(), "the trial game with that deck does not start")


func test_schema_subset_matches_the_pack_tool() -> void:
	var s := {"type": "object", "required": ["a"], "additionalProperties": false,
		"properties": {"a": {"type": "integer", "minimum": 1}, "b": {"anyOf": [{"type": "string"}, {"type": "null"}]}}}
	eq(PackCheck.validate({"a": 2.0, "b": null}, s), [], "fine")
	eq(PackCheck.validate({"a": 0.5, "c": 1}, s), ["$.a: expected integer, got number", "$: unknown field 'c'"], "errors")
	eq(PackCheck.validate({"b": 1}, s), ["$: missing 'a'", "$.b: matches none of the allowed forms"], "more errors")
	eq(PackCheck.locate("bad pack: scripts/x/y.lua:12: unexpected symbol"), ["scripts/x/y.lua", 12], "file:line of an engine message")


func test_the_screen_shows_the_findings() -> void:
	var v := PackTools.new()
	Engine.get_main_loop().root.add_child(v)
	var bad := source("screen_bad", {"rules.json": TINY["rules.json"].replace("  \"default_power\": \"sunbeam\",\n", "")})
	v.open_folder(bad)
	var rows := v.find_children("Item*", "", true, false)
	check(rows.size() >= 2, "a row a finding")
	check(v.find_child("Install", true, false).disabled, "an error: no Install")
	v.open_folder(source("screen_good"))
	check(not v.find_child("Install", true, false).disabled, "a good pack can be installed")
	check(not v.find_child("PlayTest", true, false).disabled, "and played")
	var played := []
	v.play.connect(func(p: Pack): played.append(p))
	v.find_child("PlayTest", true, false).pressed.emit()
	eq(played.size(), 1, "a test game with the installed pack")
	if not played.is_empty():
		eq(played[0].id(), "tiny-duel", "this pack")
		Packs.remove(played[0])
	v.queue_free()
	_wipe(DIR)
