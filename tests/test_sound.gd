extends TestCase


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _sound() -> Sound:
	Settings.data = Settings.DEFAULTS.duplicate()
	Settings.data.language = "en"
	var s := Sound.new()
	root().add_child(s)
	return s


func _done(s: Sound) -> void:
	s.free()
	Settings.load_settings()
	Settings.data.language = "en"
	Settings.apply()


func test_every_effect_event_has_a_sound_file() -> void:
	var g := H.scene({"hero": "HERO_08", "hand": ["VAN_CS2_029"]})
	for type in Sound.EVENTS:
		var name: String = Sound.EVENTS[type]
		check(ResourceLoader.exists("res://audio/%s.wav" % name), "file for " + type)
	for name in ["spell", "victory", "defeat", "click"]:
		check(ResourceLoader.exists("res://audio/%s.wav" % name), "file " + name)
	var fireball := g.players[0].hand[0]
	eq(Sound.sound_for({"type": "play", "player": 0, "entity": fireball.id}, g, 0), "spell", "spell sound")
	eq(Sound.sound_for({"type": "game_over", "winner": 0}, g, 0), "victory", "victory")
	eq(Sound.sound_for({"type": "game_over", "winner": 0}, g, 1), "defeat", "defeat")
	eq(Sound.sound_for({"type": "draw", "player": 0}, g, 0), "", "no sound for draw")


func test_every_music_track_has_a_file() -> void:
	for name in ["menu"] + Sound.BATTLE_TRACKS:
		check(ResourceLoader.exists("res://audio/%s.wav" % name), "music file " + name)
	eq(Sound.BATTLE_TRACKS.size(), 3, "three battle tracks")


func test_each_match_gets_a_battle_track_other_than_the_last() -> void:
	var s := _sound()
	var last := ""
	for i in 20:
		Sound.music("battle")
		check(s.music_file in Sound.BATTLE_TRACKS, "battle track: " + s.music_file)
		check(s.music_file != last, "%s repeats the previous match" % s.music_file)
		last = s.music_file
		Sound.music("menu")
		eq(s.music_file, "menu", "menu between matches")
	_done(s)


func test_battle_playlist_moves_on_and_menu_loops() -> void:
	var s := _sound()
	Sound.music("battle")
	for i in 10:
		var was := s.music_file
		s._music.finished.emit()
		check(s.music_file in Sound.BATTLE_TRACKS and s.music_file != was, "%s follows %s" % [s.music_file, was])
	Sound.music("menu")
	s._music.finished.emit()
	eq(s.music_file, "menu", "menu loops")
	check(s._music.playing, "menu plays again")
	_done(s)


func test_play_uses_sfx_bus_and_zero_volume_is_silent() -> void:
	var s := _sound()
	Sound.play("attack")
	var p := s.last_player()
	check(p != null and p.playing and p.bus == "SFX", "attack plays on SFX bus")
	Settings.data.sfx = 0.0
	Settings.apply()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "sfx 0 mutes the bus")
	_done(s)


func test_without_sound_node_everything_is_silent() -> void:
	Sound.play("attack")
	Sound.music("menu")
	check(Sound.instance == null, "no node: nothing plays, nothing fails")
