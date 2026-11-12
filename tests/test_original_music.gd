extends TestCase
## A pack whose music set has the optional tracks (the owner's local packs: tools/fetch_original_music.py +
## tools/pack.py --music-set original=…): the mulligan's track, then the battle playlist, the result's jingle once,
## the Arena's track. A set without them (the generated one) keeps today's music.

var _pack: Pack
var _sound: Sound


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _classic() -> Pack:
	return Packs.all().filter(func(p): return p.id() == Packs.CLASSIC and p.builtin())[0]


## Classic plus a local music set "original" with every slot (any small .opus as every file).
func _install(choose := "original") -> void:
	var classic := _classic()
	var clip := classic.read("sounds/generated/click.opus")
	var manifest: Dictionary = classic.manifest.duplicate(true)
	manifest.music_sets.append({"id": "original", "local": true})
	var change := {"manifest.json": JSON.stringify(manifest).to_utf8_buffer()}
	for f in ["menu", "battle_1", "battle_2", "battle_3", "mulligan", "victory", "defeat", "arena"]:
		change["music/original/%s.opus" % f] = clip
	_pack = Packs.install(_repacked(FileAccess.get_file_as_bytes(classic.path), change), "imported").get("pack")
	check(_pack != null, "the local pack installs")
	Packs.set_active(_pack)
	Packs.set_choice(_pack, "music", choose)
	_sound = Sound.new()
	root().add_child(_sound)


func _uninstall() -> void:
	_sound.free()
	Packs.set_choice(_pack, "music", "generated")
	Packs.set_active(_classic())
	Packs.remove(_pack)


func _repacked(bytes: PackedByteArray, change: Dictionary) -> PackedByteArray:
	var src := "user://test_music_src.zip"
	var out := "user://test_music_out.zip"
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


func test_the_optional_tracks_come_only_from_the_chosen_set() -> void:
	_install()
	for slot in Sound.EXTRA_MUSIC:
		eq(Sound.music_path(slot), "music/original/%s.opus" % slot, slot)
	eq(Sound.path_for("victory"), "sounds/generated/victory.opus", "the victory sound stays a sound")
	eq(Sound.path_for("battle_3"), "music/original/battle_3.opus", "the set's own playlist")
	Packs.set_choice(_pack, "music", "generated")
	for slot in Sound.EXTRA_MUSIC:
		eq(Sound.music_path(slot), "", "the generated set has no " + slot)
	_uninstall()


func test_mulligan_then_the_battle_playlist_then_the_jingle_once() -> void:
	_install()
	Sound.music("battle")  # (as the table starts)
	Sound.music("mulligan")
	eq(_sound.music_file, "mulligan", "the mulligan's track")
	Sound.mulligan_done()
	check(_sound.music_file in Sound.battle_tracks(), "then a battle track: " + _sound.music_file)
	var was := _sound.music_file
	Sound.mulligan_done()
	eq(_sound.music_file, was, "the battle track goes on")
	Sound.music("victory")
	eq(_sound.music_file, "victory", "the victory jingle in place of the battle music")
	_sound._music.finished.emit()
	eq(_sound.music_file, "victory", "once: no next battle track")
	Sound.music("arena")
	eq(_sound.music_file, "arena", "the Arena's track")
	Sound.music("menu")
	eq(_sound.music_file, "menu", "the menu")
	_uninstall()


func test_without_the_tracks_the_music_is_as_before() -> void:
	_install("generated")
	Sound.music("menu")
	Sound.music("arena")
	eq(_sound.music_file, "menu", "no Arena track: the menu goes on")
	Sound.music("battle")
	var was := _sound.music_file
	Sound.music("mulligan")
	eq(_sound.music_file, was, "no mulligan track: the battle track plays on")
	Sound.mulligan_done()
	eq(_sound.music_file, was, "and goes on after the mulligan")
	Sound.music("defeat")
	eq(_sound.music_file, was, "no jingle: the battle music goes on")
	_uninstall()


## The table: the mulligan's track while the player chooses, a battle track after it, the jingle on the result.
func test_the_table_plays_them_at_their_moments() -> void:
	_install()
	var m := H.decks("MAGE", "WARRIOR", 5, 0, [false, true])
	var v := MatchView.new()
	root().add_child(v)
	v.bind(m)
	eq(_sound.music_file, "mulligan", "the mulligan")
	(v.find_child("Confirm", true, false) as Button).pressed.emit()
	eq(m.game.phase, "PLAY", "the game started")
	check(_sound.music_file in Sound.battle_tracks(), "a battle track: " + _sound.music_file)
	m.submit({"type": "concede", "player": 0})
	check(v.find_child("GameOver", true, false) != null, "the result shows")
	eq(_sound.music_file, "defeat", "the defeat jingle")
	v.free()
	_uninstall()
