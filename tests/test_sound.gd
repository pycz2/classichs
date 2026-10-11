extends TestCase


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


var spoken: Array = []


func _sound() -> Sound:
	spoken.clear()
	Settings.data = Settings.DEFAULTS.duplicate()
	Settings.data.language = "en"
	var s := Sound.new()
	root().add_child(s)
	Sound.speaker = func(text, voice, volume): spoken.append([text, voice, volume])
	Sound.voices = func(lang): return ["voice-" + lang]
	return s


func _done(s: Sound) -> void:
	s.free()
	Sound.speaker = Sound.default_speaker
	Sound.voices = Sound.default_voices
	Settings.load_settings()
	Settings.data.language = "en"
	Settings.apply()


func test_every_effect_event_has_a_sound_file() -> void:
	var g := H.scene({"hero": "HERO_08", "hand": ["VAN_CS2_029"]})
	for type in Sound.EVENTS:
		var name: String = Sound.EVENTS[type]
		check(ResourceLoader.exists("res://audio/%s.wav" % name), "file for " + type)
	for name in ["spell", "victory", "defeat", "click", "menu", "battle"]:
		check(ResourceLoader.exists("res://audio/%s.wav" % name), "file " + name)
	var fireball := g.players[0].hand[0]
	eq(Sound.sound_for({"type": "play", "player": 0, "entity": fireball.id}, g, 0), "spell", "spell sound")
	eq(Sound.sound_for({"type": "game_over", "winner": 0}, g, 0), "victory", "victory")
	eq(Sound.sound_for({"type": "game_over", "winner": 0}, g, 1), "defeat", "defeat")
	eq(Sound.sound_for({"type": "draw", "player": 0}, g, 0), "", "no sound for draw")


func test_play_uses_sfx_bus_and_zero_volume_is_silent() -> void:
	var s := _sound()
	Sound.play("attack")
	var p := s.last_player()
	check(p != null and p.playing and p.bus == "SFX", "attack plays on SFX bus")
	Settings.data.sfx = 0.0
	Settings.apply()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "sfx 0 mutes the bus")
	_done(s)


func test_speech_uses_language_voice_and_settings() -> void:
	var s := _sound()
	Settings.data.language = "ru"
	Settings.data.voice = 0.5
	Sound.speak("Рагнарос")
	eq(spoken, [["Рагнарос", "voice-ru", 50]], "spoken with the ru voice")
	spoken.clear()
	Settings.data.tts = false
	Sound.speak("x")
	Settings.data.tts = true
	Settings.data.voice = 0.0
	Sound.speak("x")
	Settings.data.voice = 0.8
	Sound.voices = func(_lang): return []
	Sound.speak("x")
	eq(spoken, [], "silent: tts off, voice 0, no voice for the language")
	_done(s)


func test_without_sound_node_everything_is_silent() -> void:
	spoken.clear()
	Sound.speaker = func(text, voice, volume): spoken.append(text)
	Sound.play("attack")
	Sound.music("menu")
	Sound.speak("x")
	eq(spoken, [], "no node, no speech")
	Sound.speaker = Sound.default_speaker


func test_match_speaks_legendary_names_and_emotes() -> void:
	var s := _sound()
	var v := MatchView.new()
	root().add_child(v)
	var m := Match.new()
	m.bot_delay = 0.0
	m.setup(H.scene({"hero": "HERO_08", "hand": ["VAN_EX1_298"]}), [false, false])
	v.bind(m)
	var rag: int = m.game.players[0].hand[0].id
	m.submit({"type": "play", "player": 0, "entity": rag, "pos": 0, "target": -1, "choice": -1})
	check(spoken.any(func(x): return x[0] == "Ragnaros the Firelord"), "legendary name spoken: %s" % [spoken])
	v.send_emote("greetings")
	check(spoken.any(func(x): return x[0] == "Greetings!"), "emote spoken")
	v.free()
	_done(s)
