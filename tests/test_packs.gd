extends TestCase
## Game packs (game/pack.gd, game/packs.gd): the built-in ones, hashes, installing and
## removing, and the whole client showing the active pack's content.


func _pack(id: String) -> Pack:
	for p: Pack in Packs.all():
		if p.id() == id:
			return p
	return null


func _with(id: String, f: Callable) -> void:
	Packs.set_active(_pack(id))
	f.call()
	Packs.set_active(_pack(Packs.CLASSIC))


func test_canonical_json_and_hashes_match_the_pack_tool() -> void:
	# the values tools/pack.py gives for the same input (docs/packs/format.md, "Hashes")
	var v := {"b": 1.0, "a": [true, null, "x\n\"é\u0001"], "c": {"z": -5.0, "y": "\\"}}
	var c := Pack.canonical(v)
	eq(c, "{\"a\":[true,null,\"x\\n\\\"é\\u0001\"],\"b\":1,\"c\":{\"y\":\"\\\\\",\"z\":-5}}", "canonical JSON")
	eq(Pack.digest("cardpack-content/1", [["b.txt", "hello".to_utf8_buffer()], ["a/x.json", c.to_utf8_buffer()]]),
		"962893eadc08764502beddd156d4ad924a658567ac8c7843b344d9c15b954dfc", "content digest")
	var files := {"cards.json": "[{\"id\":\"A\",\"fx\":{\"cast\":\"bolt\"},\"cost\":1}]", "rules.json": "{\"x\": 1}",
		"scripts/a.lua": "﻿return {}\r\n", "README.md": "x"}
	var items := []
	for f in files:
		if Pack.is_rules_file(f):
			items.append([f, Pack.normalized(f, files[f].to_utf8_buffer())])
	eq(Pack.digest("cardpack-rules/1", items), "53c298c05eb9314f81d2f6e1a545f47e99447ca7c9a9909d93bec7816750dd38", "rules digest")


func test_built_in_packs_are_whole_and_classic_is_active() -> void:
	var ids := Packs.all().map(func(p): return p.id())
	eq(ids.slice(0, 3), [Packs.CLASSIC, "naxx-2014", "neon"], "Classic first, then the others by id")
	eq(Packs.active().id(), Packs.CLASSIC, "Classic by default")
	for id in ["classic-2014", "naxx-2014", "neon"]:
		var p := _pack(id)
		eq(p.problems(), [], id + " is a valid pack")
		eq(p.computed_rules_hash(), p.rules_hash(), id + ": the files match the manifest")
		check(p.builtin(), id + " is built in")
		eq(Packs.content_hash(p).length(), 64, id + " has a content hash")
	check(not Packs.remove(_pack("neon")), "a built-in pack can't be deleted")


func test_classic_cards_are_the_cards_the_game_always_had() -> void:
	var j := JSON.new()
	j.parse(FileAccess.get_file_as_string("res://data/cards.json"))
	var want := {}
	for c in j.data:
		want[c.id] = c
	eq(CardDb.all_ids().size(), want.size(), "every card")
	# what the pack source changes on purpose (the cards as in June 2014): its patch's
	# stats (null takes a field away) and its locales' 2014 names and texts
	var patch: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://packs/classic/cards.patch.json"))
	var texts := {}
	for lang in CardLayout.LANGS:
		var l: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://packs/classic/locales/%s.json" % lang))
		texts[CardDb.HS[lang]] = l.get("cards", {})
	var bad := []
	for id in want:
		var have := CardDb.card(id).duplicate()
		for k in ["fx", "power", "sounds", "voice"]:  # presentation fields the pack adds
			have.erase(k)
		var w: Dictionary = want[id].duplicate(true)
		for k in patch.get(id, {}):
			if not CardDb.FIELDS.has(k) or k in ["fx", "power", "sounds", "voice"]:
				continue
			if patch[id][k] == null:
				w.erase(CardDb.FIELDS[k])
			else:
				w[CardDb.FIELDS[k]] = patch[id][k]
		for hs in texts:
			for f in texts[hs].get(id, {}):
				w[f][hs] = texts[hs][id][f]
		for f in ["name", "text"]:  # the game's eight languages
			for lang in w.get(f, {}).keys():
				if not CardDb.HS.values().has(lang):
					w[f].erase(lang)
		for k in CardDb.INT_FIELDS:
			if w.has(k):
				w[k] = int(w[k])
		if JSON.stringify(have, "", true) != JSON.stringify(w, "", true):
			bad.append(id)
	eq(bad, [], "cards that differ from data/cards.json")
	for lang in CardLayout.LANGS:
		var l := JSON.new()
		l.parse(FileAccess.get_file_as_string("res://data/card_layout/%s.json" % lang))
		eq(JSON.stringify(CardLayout._lang(lang), "", true), JSON.stringify(l.data, "", true), "layout " + lang)


func test_install_find_and_remove_a_pack() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://packs/neon.cardpack")
	var r := Packs.install(bytes, "imported")
	var p: Pack = r.get("pack")
	check(p != null, "installed: " + str(r.get("error", "")))
	check(p.builtin(), "the same content as a built-in pack: that one is used")
	var other := _repacked(bytes, {"README.md": "a copy".to_utf8_buffer()})
	r = Packs.install(other, "imported")
	p = r.get("pack")
	check(p != null and not p.builtin(), "a different file is installed: " + str(r.get("error", "")))
	check(FileAccess.file_exists(Packs.user_dir + "/" + Packs.content_hash(p) + ".cardpack"), "stored by content hash")
	eq(p.rules_hash(), _pack("neon").rules_hash(), "the same rules")
	Packs.rescan()
	var again := Packs.find(Packs.content_hash(p))
	check(again != null and again.origin == "imported", "listed again after a restart (the index)")
	eq(Packs.install(other, "imported").get("pack"), again, "installing it twice keeps one")
	check(Packs.remove(again), "removed")
	eq(Packs.find(Packs.content_hash(p)), null, "gone")
	check(not FileAccess.file_exists(again.path), "its file is gone")


func test_damaged_or_foreign_files_are_refused() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://packs/neon.cardpack")
	check(Packs.install("not a zip".to_utf8_buffer(), "imported").has("error"), "not a zip")
	var cards := _pack("neon").read("cards.json").get_string_from_utf8().replace("\"cost\": 1,", "\"cost\": 0,")
	var r := Packs.install(_repacked(bytes, {"cards.json": cards.to_utf8_buffer()}), "imported")
	check(str(r.get("detail", "")).contains("rules_hash"), "changed rules without a new rules_hash: " + str(r))
	r = Packs.install(_repacked(bytes, {"../evil.txt": "x".to_utf8_buffer()}), "imported")
	check(r.has("error"), "a path out of the pack")
	r = Packs.install(_repacked(bytes, {"README.md": "x".to_utf8_buffer()}), "p2p", {}, "0".repeat(64))
	check(str(r.get("detail", "")).contains("differs"), "not the pack that was offered")
	eq(Array(DirAccess.get_files_at(Packs.user_dir)).filter(func(f): return f.ends_with(".tmp")), [], "nothing left behind")


## An install in the background (PackInstall): the stages one after another, a check in a thread
## of its own (one read of each file: the progress grows to the file's size), one check at a time.
func test_an_install_runs_in_the_background_one_check_at_a_time() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://packs/neon.cardpack")
	var a := PackInstall.of_bytes(_repacked(bytes, {"README.md": "a".to_utf8_buffer()}), "a.cardpack", "imported").start()
	var b := PackInstall.of_bytes(_repacked(bytes, {"README.md": "b".to_utf8_buffer()}), "b.cardpack", "imported").start()
	eq([a.stage, b.stage, PackInstall.jobs], ["checking", "checking", [a, b]], "both wait, in order")
	var stages := []
	var progress := []
	a.changed.connect(func(): stages.append(a.stage); progress.append(a.done))
	var ended := []
	a.finished.connect(func(r): ended.append(r))
	for i in 3000:
		if a.stage == "done":
			break
		PackInstall._tick()
		check(b._scan == null, "the second waits for the first")
		OS.delay_msec(1)
	eq(stages.filter(func(x): return x != "checking"), ["storing", "done"], "checking, storing, done")
	check(progress.max() > 0 and progress.max() <= a.total, "the progress of the check: %s of %d" % [progress.max(), a.total])
	check(ended.size() == 1 and ended[0].get("pack") is Pack and ended[0].pack.origin == "imported", "installed: %s" % [ended])
	eq(PackInstall.jobs, [b], "the next one is up")
	H.installs()
	check(b.result.get("pack") is Pack and b.result.pack != a.result.pack, "and installed too")
	eq(a.text(), "Done…", "the stage in words")
	for j in [a, b]:
		Packs.remove(j.result.pack)


## A broken file in the background: the rules engine's reason, translated where shown; the file goes.
func test_a_broken_file_is_refused_in_the_background() -> void:
	var j := PackInstall.of_bytes("not a zip".to_utf8_buffer(), "x.cardpack", "imported").start()
	H.installs()
	eq(j.result.get("error"), Packs.ERRORS[2], "not a pack")
	var bytes := _repacked(FileAccess.get_file_as_bytes("res://packs/neon.cardpack"), {"../evil.txt": "x".to_utf8_buffer()})
	j = PackInstall.of_bytes(bytes, "evil.cardpack", "imported").start()
	H.installs()
	eq(j.result.get("error"), Packs.ERRORS[3], "damaged")
	check(str(j.result.get("detail")).contains("may not have"), "the engine's reason: " + str(j.result))
	check(not FileAccess.file_exists(j.file), "its file is gone")
	Locale.set_language("ru")
	check(PackInstallsView.result_text(j).begins_with(tr(Packs.ERRORS[3])) and tr(Packs.ERRORS[3]) != Packs.ERRORS[3],
		"in the interface's language: " + PackInstallsView.result_text(j))
	Locale.set_language("en")


## The box over every screen: a row per install with its stage and a bar, then how it ended.
func test_the_installs_box_shows_the_stage_then_the_result() -> void:
	var v := PackInstallsView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	v._process(0.0)
	check(not v.visible, "nothing to show")
	var j := PackInstall.of_bytes(_repacked(FileAccess.get_file_as_bytes("res://packs/neon.cardpack"), {"README.md": "v".to_utf8_buffer()}),
		"v.cardpack", "imported").start()
	v._process(0.0)
	var stage := v.find_child("Stage", true, false) as Label
	check(v.visible and stage != null and stage.text.begins_with("Checking"), "the stage: " + (stage.text if stage else "none"))
	H.installs()
	v._process(0.1)
	check(stage.text.begins_with("Added: "), "the result: " + stage.text)
	v._process(PackInstallsView.RESULT_SECONDS)
	v._process(0.0)
	check(not v.visible, "then it goes")
	Packs.remove(j.result.pack)
	v.free()


func test_the_active_pack_drives_the_whole_client() -> void:
	_with("neon", func():
		eq(Decks.classes(), ["GHOST", "CHROME", "EXEC"], "the pack's classes")
		eq(Decks.hero("GHOST"), "iris_null", "its champions")
		eq(CardDb.card("iris_null").type, "HERO", "a champion is a hero to the client")
		check(CardDb.card("sentry_drone").get("mechanics", []).has("TAUNT"), "GUARD reads as TAUNT")
		eq(CardDb.collectible().size(), 60, "60 collectible cards")
		eq(CardText.name("iris_null", "ruRU"), _pack("neon").locale("ru").cards.iris_null.name, "names in Russian")
		eq(CardText.race("sentry_drone"), "Drone", "its races")
		eq(KeywordTips._keywords().TAUNT.name.en, "Firewall", "its mechanic names")
		eq(Palette.of_class("GHOST"), Color("1098ad"), "its class colours")
		eq(MatchView.timer("fuse"), 15.0, "its fuse")
		check(Art.texture("iris_null") != null, "its art")
		check(Packs.picture("logo") != null and Packs.picture("board") != null, "its logo and board")
		eq(CardBacks.current(), "pack", "its card back")
		check(DeckStore.file() != DeckStore.path, "its own decks file")
		eq(Decks.templates().size(), 3, "its three deck templates")
		check(Decks.templates().all(func(t): return t.deck.cards.size() == 30 and t.description != ""), "full decks, described")
		eq(Sound.battle_tracks(), ["battle_1", "battle_2"], "its playlist")
		var e := GameView.Ent.new()
		e.set_from(1, {"card": "sentry_drone", "zone": "TRAP", "tags": {"GUARD": 1}, "aura": {"tags": {"BARRIER": 1}}})
		check(e.has("TAUNT") and e.has("DIVINE_SHIELD") and e.zone == "SECRET", "snapshots in the pack's words read as the client's"))
	eq(Decks.classes().size(), 9, "back to Classic")
	eq(CardBacks.current(), Settings.data.card_back, "the back of the settings again")
	check(CardDb.has("VAN_CS2_029"), "Classic cards again")


func test_sets_are_chosen_per_pack() -> void:
	var classic := _pack(Packs.CLASSIC)
	eq(Packs.choice(classic, "music"), "generated", "default")
	Packs.set_choice(classic, "music", "open")
	eq(Settings.data.pack_sets[Packs.CLASSIC].music, "open", "kept per game")
	eq(Packs.choice(_pack("neon"), "music"), "default", "another pack keeps its own")
	Packs.server_sets = {"music": "generated"}
	eq(Packs.choice(classic, "music"), "generated", "a server game: the server's choice")
	Packs.server_sets = {}
	Packs.set_choice(classic, "music", "generated")


func test_games_screen_lists_selects_activates_and_deletes() -> void:
	var other := _repacked(FileAccess.get_file_as_bytes("res://packs/neon.cardpack"), {"README.md": "mine".to_utf8_buffer()})
	var v := GamesView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	v.import_bytes(other, "mine.cardpack").run_now()
	var tiles := v.find_children("Pack_*", "Button", true, false)
	eq(tiles.size(), 4, "a tile per pack")
	eq(v.selected.origin, "imported", "the imported pack is selected")
	check(v.find_child("DeletePack", true, false) != null, "it can be deleted")
	var entered := []
	v.entered.connect(func(p): entered.append(p))
	(v.find_child("Activate", true, false) as Button).pressed.emit()
	eq(entered, [v.selected], "Play this game opens it")
	Packs.set_active(v.selected)
	DeckStore.save_all([Decks.templates()[0].deck])  # a deck made in it
	Packs.set_active(_pack(Packs.CLASSIC))
	(v.find_child("DeletePack", true, false) as Button).pressed.emit()
	eq(v.find_child("DecksGoToo", true, false) == null, true, "another pack of its id keeps the decks: no warning")
	(v.find_child("ConfirmDelete", true, false) as Button).pressed.emit()
	eq(Packs.active().id(), Packs.CLASSIC, "Classic stays active")
	eq(DeckStore.count_local("neon"), 1, "the built-in Neonfall keeps the decks of its id")
	eq(v.find_children("Pack_*", "Button", true, false).size(), 3, "its tile is gone")
	v.select(_pack("neon"))
	check(v.find_child("DeletePack", true, false) == null, "a built-in pack can't be deleted")
	v.free()


func test_a_pack_without_music_opens_in_the_games_screen_and_settings() -> void:
	var manifest: Dictionary = _pack("neon").manifest.duplicate(true)
	manifest.id = "no-music"
	manifest.music_sets = []
	var bytes := _repacked(FileAccess.get_file_as_bytes("res://packs/neon.cardpack"),
		{"manifest.json": JSON.stringify(manifest).to_utf8_buffer(), "drop": "music/"})
	var p: Pack = Packs.install(bytes, "imported").get("pack")
	check(p != null and p.sets("music").is_empty(), "installed, no music")
	var v := GamesView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	v.select(p)
	eq((v.find_child("MusicSet", true, false) as OptionButton).item_count, 0, "an empty music picker")
	v.activate(p)
	v.free()
	var s := SettingsView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	s.free()
	Packs.set_active(_pack(Packs.CLASSIC))
	Packs.remove(p)


## The pack's files with some added or replaced, zipped again.
## [rules_hash, content_hash] of a pack's bytes (docs/packs/format.md).
func _hashes(bytes: PackedByteArray) -> Array:
	var at := "user://test_packs_hash.zip"
	var f := FileAccess.open(at, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var p := Pack.open(at)
	var out := [p.computed_rules_hash(), p.content_hash()]
	p.close()
	DirAccess.remove_absolute(at)
	return out


## The pack with other rules (another game for the server's list), its manifest's rules_hash right.
func _other_rules(bytes: PackedByteArray) -> PackedByteArray:
	var at := "user://test_packs_rules.zip"
	var f := FileAccess.open(at, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var p := Pack.open(at)
	var rules: Dictionary = p.rules()
	rules.limits.queue_steps = int(rules.limits.get("queue_steps", 5000)) + 1
	var manifest: Dictionary = p.manifest.duplicate()
	p.close()
	DirAccess.remove_absolute(at)
	var changed := _repacked(bytes, {"rules.json": Pack.canonical(rules).to_utf8_buffer()})  # (whole numbers: no fractions in a pack)
	manifest.rules_hash = _hashes(changed)[0]
	return _repacked(changed, {"manifest.json": JSON.stringify(manifest).to_utf8_buffer()})


## Naxxramas as a pack with versions (docs/packs/format.md §13): "a" as it is, "b" with Leeroy Jenkins at 5, 3 stars
## at rank 25 and its own name of rank 25 (packs/eras/ranked.json) (the default, so also at the top); as tools/pack.py
## builds packs/eras.
func _with_versions() -> PackedByteArray:
	var naxx := _pack("naxx-2014")
	var cards: Array = naxx.cards().duplicate(true)
	for c in cards:
		if c.id == "VAN_EX1_116":
			c.cost = 5
	var b_cards := Pack.canonical(cards).to_utf8_buffer()
	var b_rules: Dictionary = naxx.rules().duplicate(true)
	b_rules.ranked.ranks[0].stars = 3
	var b_en: Dictionary = naxx.locale("en").duplicate(true)
	b_en.ranks = {"25": "Brave Chicken"}
	var b_files := {"cards.json": b_cards, "rules.json": Pack.canonical(b_rules).to_utf8_buffer(),
		"locales/en.json": Pack.canonical(b_en).to_utf8_buffer()}
	var change := {}
	var items := []
	for f in naxx.files():
		if Pack.is_version_file(f):
			change["versions/a/" + f] = naxx.read(f)
			change["versions/b/" + f] = b_files.get(f, naxx.read(f))
			if b_files.has(f):
				change[f] = b_files[f]
			if Pack.is_rules_file(f):
				items.append([f, Pack.normalized(f, b_files.get(f, naxx.read(f)))])
	var hb := Pack.digest("cardpack-rules/1", items)
	var man := naxx.manifest.duplicate(true)
	man.id = "test.versions"
	man.rules_hash = hb
	man.default_version = "b"
	man.versions = [{"id": "a", "dir": "versions/a", "rules_hash": naxx.rules_hash(), "name": {"en": "A"}},
		{"id": "b", "dir": "versions/b", "rules_hash": hb, "name": {"en": "B"}}]
	change["manifest.json"] = Pack.canonical(man).to_utf8_buffer()
	return _repacked(Packs.bytes_of(naxx), change)


func test_a_pack_with_versions_plays_its_chosen_version() -> void:
	var r := Packs.install(_with_versions(), "imported")
	var p: Pack = r.get("pack")
	check(p != null, "installed: " + str(r))
	if p == null:
		return
	eq(p.versions().map(func(v): return v.id), ["a", "b"], "its versions")
	eq(p.default_version(), "b", "the default")
	var a := p.version_view("a")
	eq([a.version_id, a.rules_hash(), a.computed_rules_hash()], ["a", _pack("naxx-2014").rules_hash(), _pack("naxx-2014").rules_hash()],
		"version a is Naxxramas")
	var b := p.version_view("b")
	eq(b.computed_rules_hash(), b.rules_hash(), "the view's rules hash is its version's")
	eq(b.rules_hash(), p.rules_hash(), "the top is the default version")
	var leeroy := func(v: Pack): return v.cards().filter(func(c): return c.id == "VAN_EX1_116")[0].cost
	eq([leeroy.call(a), leeroy.call(b)], [4.0, 5.0], "Leeroy Jenkins of each version")
	check(a.has("art/simple/VAN_EX1_116.webp") and not a.has("versions/a/cards.json") and a.has("locales/ru.json"),
		"the shared pictures, the version's own files at the top")
	eq(a.content_hash(), Packs.content_hash(p), "a view's content hash is its pack's")
	eq(p.version_view("z"), null, "no such version")
	eq([Rules.can_play(a), Rules.engine_pack(a)], ["", a.rules_hash()], "the engine takes a version's view as a pack")
	Packs.set_active(p)
	eq([Packs.active().whole(), Packs.active().version_id], [p, "b"], "the default version is played")
	check(Packs.is_active(p) and Packs.is_active(b) and not Packs.is_active(a), "is_active")
	eq(CardDb.card("VAN_EX1_116").cost, 5, "the client's cards are the version's")
	var lang: String = Settings.data.language
	Settings.data.language = "en"
	eq([ServerView.stars_needed(25), ServerView.rank_name(25)], [3, "Brave Chicken"], "the version's ladder and rank names")
	Packs.set_version(p, "a")
	eq([Packs.active().version_id, Packs.active().rules_hash()], ["a", a.rules_hash()], "another version")
	eq(CardDb.card("VAN_EX1_116").cost, 4, "its cards")
	eq([ServerView.stars_needed(25), ServerView.rank_name(25)], [2, CardText.name("VAN_EX1_009")], "its ladder and names")
	Settings.data.language = lang
	eq(Settings.data.pack_versions.get("test.versions"), "a", "remembered per pack")
	Packs.rescan()
	eq(Packs.active().version_id, "a", "after a restart")
	eq(Packs.find_rules(b.rules_hash()).version_id, "b", "found by a version's rules hash")
	Packs.set_active(Packs.find_rules(b.rules_hash()))
	eq(Packs.active().version_id, "b", "activated as a version view")
	Packs.set_active(_pack(Packs.CLASSIC))
	Settings.data.pack_versions.erase("test.versions")
	check(Packs.remove(Packs.find(Packs.content_hash(p))), "removed")


func _repacked(bytes: PackedByteArray, change: Dictionary) -> PackedByteArray:
	var src := "user://test_packs_src.zip"
	var out := "user://test_packs_out.zip"
	var f := FileAccess.open(src, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var r := ZIPReader.new()
	r.open(src)
	var w := ZIPPacker.new()
	w.open(out)
	for name in r.get_files():
		if not change.has(name) and not (change.has("drop") and name.begins_with(change.drop)):
			w.start_file(name)
			w.write_file(r.read_file(name))
			w.close_file()
	for name in change:
		if name == "drop":  # "drop": a path prefix whose files are left out
			continue
		w.start_file(name)
		w.write_file(change[name])
		w.close_file()
	w.close()
	r.close()
	var data := FileAccess.get_file_as_bytes(out)
	DirAccess.remove_absolute(src)
	DirAccess.remove_absolute(out)
	return data


## Deleting the last pack of an id deletes its decks on this device (the confirmation warns).
func test_deleting_a_game_deletes_its_decks() -> void:
	var manifest: Dictionary = _pack("neon").manifest.duplicate(true)
	manifest.id = "neon-copy"
	var p: Pack = Packs.install(_repacked(FileAccess.get_file_as_bytes("res://packs/neon.cardpack"),
		{"manifest.json": JSON.stringify(manifest).to_utf8_buffer()}), "imported").get("pack")
	check(p != null, "installed")
	Packs.set_active(p)
	DeckStore.save_all([Decks.templates()[0].deck])
	Packs.set_active(_pack(Packs.CLASSIC))
	eq(DeckStore.count_local("neon-copy"), 1, "a deck made in it")
	var v := GamesView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	v.select(p)
	(v.find_child("DeletePack", true, false) as Button).pressed.emit()
	check(v.find_child("DecksGoToo", true, false) != null, "the confirmation says its decks go too")
	(v.find_child("ConfirmDelete", true, false) as Button).pressed.emit()
	eq(DeckStore.count_local("neon-copy"), 0, "its decks are gone")
	check(not FileAccess.file_exists(DeckStore.file("neon-copy")), "the file too")
	v.free()


## A long description scrolls in the details; Play this game and Delete stay in the window under it.
func test_a_long_description_scrolls_and_the_buttons_stay_in_the_window() -> void:
	var manifest: Dictionary = _pack("neon").manifest.duplicate(true)
	manifest.id = "neon-long"
	var long := " ".join(range(120).map(func(_i): return "A very long description of this game."))
	manifest.description = {"en": long, "ru": long}
	var p: Pack = Packs.install(_repacked(FileAccess.get_file_as_bytes("res://packs/neon.cardpack"),
		{"manifest.json": JSON.stringify(manifest).to_utf8_buffer()}), "imported").get("pack")
	var v := GamesView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	v.select(p)
	for i in 3:  # (the layout, now: tests do not wait a frame)
		for c in [v._panel] + v._panel.find_children("*", "Container", true, false):
			c.notification(Container.NOTIFICATION_SORT_CHILDREN)
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	for b in ["Activate", "DeletePack"]:
		var r := (v.find_child(b, true, false) as Control).get_global_rect()
		check(screen.encloses(r), "%s in the window: %s" % [b, r])
	var scroll := v.find_child("DetailsScroll", true, false) as ScrollContainer
	check(scroll != null and scroll.is_ancestor_of(v.find_child("PackName", true, false)), "the text scrolls")
	check(scroll != null and not scroll.is_ancestor_of(v.find_child("Activate", true, false)), "the buttons do not")
	v.free()
	Packs.remove(p)


func test_server_home_shows_and_downloads_a_servers_games() -> void:
	var l := FakeLink.new()
	l.url = "ws://h.test:7377"
	(Engine.get_main_loop() as SceneTree).root.add_child(l)
	l.dispatch({"t": "auth", "ok": true, "token": "x", "me": {"user": "me"}})
	var v := ServerHome.new()
	v.link = l
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	check(v.find_child("Game_classic-2014", true, false) != null, "no games of its own yet: its built-in Classic")
	var bytes := _other_rules(FileAccess.get_file_as_bytes("res://packs/neon.cardpack"))
	var hs := _hashes(bytes)
	var h: String = hs[1]
	l.dispatch({"t": "packs", "server": [{"id": "neon", "name": {"en": "Neonfall"}, "version": "1.0.0", "rules_hash": hs[0],
		"content_hash": h, "size": bytes.size(), "url": "/packs/%s.cardpack" % h}], "mine": []})
	var row := v.find_child("Game_neon", true, false)
	var dl := row.find_child("Download", true, false) as Button
	check(dl != null, "the server's game, to download")
	dl.pressed.emit()
	eq(l.http.size(), 1, "downloading")
	l.http[0].done.call(200, bytes)
	l._process(0.0)
	var label := v.find_child("Game_neon", true, false).find_child("Progress", true, false) as Label
	check(label != null and label.text.begins_with("Checking"), "downloaded, now checked: " + (label.text if label else "no label"))
	H.installs()
	check(str((v.find_child("Note", true, false) as Label).text).begins_with("Downloaded"), "installed: " + (v.find_child("Note", true, false) as Label).text)
	var entered := []
	v.entered.connect(func(p): entered.append(p))
	(v.find_child("Game_neon", true, false).find_child("Play", true, false) as Button).pressed.emit()
	eq(entered.size(), 1, "now it can be played")
	eq(entered[0].origin, "downloaded", "the downloaded one")
	Packs.remove(entered[0])
	v.free()
	l.free()


## A local picture set (tools/pack.py --art-set: the builder's own pictures) of an imported pack can be
## chosen when its pictures are in the pack, and not when they are not.
func test_a_local_art_set_with_its_pictures_can_be_chosen() -> void:
	var neon := _pack("neon")
	var manifest: Dictionary = neon.manifest.duplicate(true)
	manifest.art_sets.append({"id": "mine", "local": true})
	manifest.art_sets.append({"id": "gone", "local": true})
	var pic: String = neon.files().filter(func(f: String): return f.begins_with("art/") and f.ends_with(".webp"))[0]
	var bytes := _repacked(FileAccess.get_file_as_bytes("res://packs/neon.cardpack"),
		{"manifest.json": JSON.stringify(manifest).to_utf8_buffer(), "art/mine/" + pic.get_file(): neon.read(pic)})
	var r := Packs.install(bytes, "imported")
	check(not r.has("error"), str(r))
	var p: Pack = r.pack
	check(p.set_usable("art", {"id": "mine", "local": true}), "its pictures came along")
	check(not p.set_usable("art", {"id": "gone", "local": true}), "no pictures: not offered")
	var pick := GamesView.set_picker(p, "art", "default", func(_v): pass)
	var items := range(pick.item_count).map(func(i): return pick.get_item_text(i))
	check(items.size() == p.sets("art").size() - 1, "every set but the empty local one: %s" % [items])
	pick.free()
	Packs.remove(p)


## A file is installed in the background, then selected.
func test_importing_a_file_adds_it_in_the_background() -> void:
	var path := "user://test_import.cardpack"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(_repacked(FileAccess.get_file_as_bytes("res://packs/neon.cardpack"), {"README.md": "x".to_utf8_buffer()}))
	f.close()
	var v := GamesView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	var j := v.import_file(path)
	eq([j.stage, PackInstall.jobs.has(j), j.title], ["checking", true, "test_import.cardpack"], "copied in, checked in turn")
	H.installs()
	eq(v.selected.origin, "imported", "added and selected")
	Packs.remove(v.selected)
	v.free()
	DirAccess.remove_absolute(path)


## Upload a game offers an imported pack with the server's rules but other files (its own
## pictures); a built-in pack of rules the server has, or a file it has, is not offered.
func test_a_pack_with_the_servers_rules_and_other_pictures_can_be_uploaded() -> void:
	var neon := _pack("neon")
	var r := Packs.install(_repacked(FileAccess.get_file_as_bytes("res://packs/neon.cardpack"), {"README.md": "mine".to_utf8_buffer()}), "imported")
	check(not r.has("error"), str(r))
	var own: Pack = r.pack
	var l := FakeLink.new()
	l.url = "ws://localhost:1"
	l.dispatch({"t": "auth", "ok": true, "token": "x", "me": {"name": "A"}})
	var entry := func(p: Pack) -> Dictionary:
		return {"id": p.id(), "name": {"en": p.id()}, "version": "1", "rules_hash": p.rules_hash(), "content_hash": Packs.content_hash(p), "size": 1}
	l.dispatch({"t": "packs", "server": [entry.call(neon), entry.call(_pack(Packs.CLASSIC)), entry.call(_pack("naxx-2014"))], "mine": []})
	var h := ServerHome.new()
	h.link = l
	(Engine.get_main_loop() as SceneTree).root.add_child(h)
	h.show_upload()
	# (the names only: a pack another test of this process left installed may be offered too)
	var offered := func() -> Array:
		return h.find_child("UploadPanel", true, false).find_children("Upload_*", "Button", true, false).map(func(b): return str(b.name)) \
			.filter(func(n): return n in ["Upload_" + own.id().replace(".", "_"), "Upload_" + Packs.CLASSIC.replace(".", "_"), "Upload_naxx-2014"])
	eq(offered.call(), ["Upload_" + own.id().replace(".", "_")], "only the pack with other files")
	h.find_child("UploadPanel", true, false).free()
	l.dispatch({"t": "packs", "server": [entry.call(neon), entry.call(_pack(Packs.CLASSIC)), entry.call(_pack("naxx-2014"))], "mine": [entry.call(own)]})
	h.show_upload()
	eq(offered.call(), [], "uploaded: no longer offered")
	h.free()
	l.free()
	Packs.remove(own)
