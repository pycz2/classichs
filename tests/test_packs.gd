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
	var bad := []
	for id in want:
		var have := CardDb.card(id).duplicate()
		for k in ["fx", "power", "sounds", "voice"]:  # presentation fields the pack adds
			have.erase(k)
		var w: Dictionary = want[id].duplicate(true)
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
		eq(DeckStore.starter().size(), 3, "its three ready decks")
		check(DeckStore.starter().all(func(d: Deck): return d.cards.size() == 30), "full decks")
		eq(Sound.battle_tracks(), ["battle_1", "battle_2"], "its playlist")
		var e := GameView.Ent.new()
		e.set_from(1, {"card": "sentry_drone", "zone": "TRAP", "tags": {"GUARD": 1}, "aura": {"tags": {"BARRIER": 1}}})
		check(e.has("TAUNT") and e.has("DIVINE_SHIELD") and e.zone == "SECRET", "snapshots in the pack's words read as the client's"))
	eq(Decks.classes().size(), 9, "back to Classic")
	eq(CardBacks.current(), "classic", "the Classic back again")
	check(CardDb.has("VAN_CS2_029"), "Classic cards again")


func test_sets_are_chosen_per_pack() -> void:
	var classic := _pack(Packs.CLASSIC)
	eq(Packs.choice(classic, "music"), "generated", "default")
	Packs.set_choice(classic, "music", "open")
	eq(Settings.data.music_set, "open", "Classic keeps the old setting")
	eq(Packs.choice(_pack("neon"), "music"), "default", "another pack keeps its own")
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
	(v.find_child("Activate", true, false) as Button).pressed.emit()
	eq(Packs.active(), v.selected, "made active")
	(v.find_child("DeletePack", true, false) as Button).pressed.emit()
	(v.find_child("ConfirmDelete", true, false) as Button).pressed.emit()
	eq(Packs.active().id(), Packs.CLASSIC, "deleting the active pack falls back to Classic")
	eq(v.find_children("Pack_*", "Button", true, false).size(), 2, "its tile is gone")
	v.select(_pack("neon"))
	check(v.find_child("DeletePack", true, false) == null, "a built-in pack can't be deleted")
	v.free()


## The pack's files with some added or replaced, zipped again.
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
	var data := FileAccess.get_file_as_bytes(out)
	DirAccess.remove_absolute(src)
	DirAccess.remove_absolute(out)
	return data


func test_games_screen_shows_and_downloads_a_servers_games() -> void:
	var l := FakeLink.new()
	l.url = "ws://h.test:7377"
	(Engine.get_main_loop() as SceneTree).root.add_child(l)
	var v := GamesView.new()
	v.links = [l]
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	check(v.find_child("Get_*", true, false) == null, "logged out: no games listed")
	l.dispatch({"t": "auth", "ok": true, "token": "x", "me": {"user": "me"}})
	var bytes := _repacked(FileAccess.get_file_as_bytes("res://packs/neon.cardpack"), {"README.md": "server copy".to_utf8_buffer()})
	var h := Pack.sha256(bytes)
	l.dispatch({"t": "packs", "server": [{"id": "neon", "name": {"en": "Neonfall"}, "version": "1.0.0", "rules_hash": "not yet the same",
		"content_hash": h, "size": bytes.size(), "url": "/packs/%s.cardpack" % h}], "mine": []})
	var get := v.find_child("Get_" + h.left(12), true, false) as Button
	check(get != null and get.text == tr("Download"), "the server's game, to download")
	get.pressed.emit()
	eq(l.http.size(), 1, "downloading")
	l.http[0].done.call(200, bytes)
	check(str(v.message.text).begins_with("Added"), "installed: " + v.message.text)
	get = v.find_child("Get_" + h.left(12), true, false) as Button
	eq(get.text, tr("Use"), "now it can be used")
	get.pressed.emit()
	eq(Packs.active().origin, "downloaded", "made active")
	Packs.remove(Packs.active())
	v.free()
	l.free()
