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
	eq(ids.slice(0, 2), [Packs.CLASSIC, "neon"], "Classic first, then Neonfall")
	eq(Packs.active().id(), Packs.CLASSIC, "Classic by default")
	for id in ["classic-2014", "neon"]:
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
	check(not FileAccess.file_exists(Packs.user_dir + "/incoming.tmp"), "nothing left behind")


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
	v.import_bytes(other, "mine.cardpack")
	var tiles := v.find_children("Pack_*", "Button", true, false)
	eq(tiles.size(), 3, "a tile per pack")
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
	eq(v.find_children("Pack_*", "Button", true, false).size(), 2, "its tile is gone")
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
	var changed := _repacked(bytes, {"rules.json": JSON.stringify(rules).to_utf8_buffer()})
	manifest.rules_hash = _hashes(changed)[0]
	return _repacked(changed, {"manifest.json": JSON.stringify(manifest).to_utf8_buffer()})


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
	check(str((v.find_child("Note", true, false) as Label).text).begins_with("Downloaded"), "installed")
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


## A file is read in parts with a progress bar, then checked and added.
func test_importing_a_file_shows_progress_and_adds_it() -> void:
	var path := "user://test_import.cardpack"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(_repacked(FileAccess.get_file_as_bytes("res://packs/neon.cardpack"), {"README.md": "x".to_utf8_buffer()}))
	f.close()
	var v := GamesView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	var bar := v._progress("Adding a game", "test_import.cardpack")
	check(v.find_child("Bar", true, false) is ProgressBar, "a progress bar")
	v._progress_set(bar, "Reading", 0.3)
	eq((v.find_child("What", true, false) as Label).text, "Reading", "what happens now")
	await v.import_file(path)
	eq(v.selected.origin, "imported", "added and selected")
	check(v.find_child("Progress", true, false) == null, "the progress box closed")
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
	l.dispatch({"t": "packs", "server": [entry.call(neon), entry.call(_pack(Packs.CLASSIC))], "mine": []})
	var h := ServerHome.new()
	h.link = l
	(Engine.get_main_loop() as SceneTree).root.add_child(h)
	h.show_upload()
	var offered := func() -> Array:
		return h.find_child("UploadPanel", true, false).find_children("Upload_*", "Button", true, false)
	eq(offered.call().size(), 1, "only the pack with other files")
	h.find_child("UploadPanel", true, false).free()
	l.dispatch({"t": "packs", "server": [entry.call(neon), entry.call(_pack(Packs.CLASSIC))], "mine": [entry.call(own)]})
	h.show_upload()
	eq(offered.call().size(), 0, "uploaded: no longer offered")
	h.free()
	l.free()
	Packs.remove(own)
