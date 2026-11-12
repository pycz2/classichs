extends TestCase
## A pack with a sound set of its own card sounds and recorded voice (the owner's local Classic pack,
## tools/fetch_original_sounds.py + tools/pack.py --sound-set/--voice): the table plays each card's
## sound and line at its step, the heroes say their emotes and errors, the generated sounds stay
## where the set has none.

const LEEROY := "VAN_EX1_116"
const FIREBALL := "VAN_CS2_029"
const PYROBLAST := "VAN_EX1_279"
const YETI := "VAN_CS2_182"
const MISSILES := "VAN_EX1_277"
const FIREBLAST := "VAN_HERO_08bp"
const EXPLOSIVE := "VAN_EX1_610"
const JUGGLER := "VAN_NEW1_019"
const FROSTBOLT := "VAN_CS2_024"
## The card sounds of each role (format.md, "Art, sounds, music, voice") the set has.
const ROLES := [FIREBALL + "_play", FIREBALL + "_missile", FIREBALL + "_aim", MISSILES + "_hit", MISSILES + "_hit_2",
	MISSILES + "_hit_3", FIREBLAST + "_play", FIREBLAST + "_hit", EXPLOSIVE + "_reveal", JUGGLER + "_trigger"]

var _pack: Pack
var _sound: Sound
var _locale := ""


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _classic() -> Pack:
	return Packs.all().filter(func(p): return p.id() == Packs.CLASSIC and p.builtin())[0]


## Classic plus a local sound set "original" and voice in en and ru (any small .opus as every file).
func _install() -> void:
	_locale = TranslationServer.get_locale()
	var classic := _classic()
	var clip := classic.read("sounds/generated/click.opus")
	var manifest: Dictionary = classic.manifest.duplicate(true)
	manifest.sound_sets.append({"id": "original", "local": true})
	var change := {"manifest.json": JSON.stringify(manifest).to_utf8_buffer()}
	for f in ["%s_play" % LEEROY, "%s_attack" % LEEROY, "%s_death" % LEEROY, "%s_music" % LEEROY, "%s_hit" % FIREBALL,
			"summon", "spell_fire", "hit_fire", "attack", "draw"] + ROLES:
		change["sounds/original/%s.opus" % f] = clip
	for f in ["en/%s_trigger" % JUGGLER, "en/%s_play" % LEEROY, "ru/%s_play" % LEEROY, "en/%s_attack" % LEEROY, "en/%s_death" % LEEROY,
			"en/HERO_08_greetings", "en/HERO_08_error_need_mana", "en/HERO_08_error_summon_sickness",
			"en/HERO_08_start", "en/HERO_01_start"]:
		change["voice/%s.opus" % f] = clip
	var bytes := _repacked(FileAccess.get_file_as_bytes(classic.path), change)
	_pack = Packs.install(bytes, "imported").get("pack")
	check(_pack != null, "the local pack installs")
	Packs.set_active(_pack)
	Packs.set_choice(_pack, "sound", "original")
	_sound = Sound.new()
	root().add_child(_sound)


func _uninstall() -> void:
	_sound.free()
	Packs.set_choice(_pack, "sound", "generated")
	Packs.set_active(_classic())
	Packs.remove(_pack)
	TranslationServer.set_locale(_locale)


func _repacked(bytes: PackedByteArray, change: Dictionary) -> PackedByteArray:
	var src := "user://test_sounds_src_%d.zip" % OS.get_process_id()  # (two test runs at once keep apart)
	var out := "user://test_sounds_out_%d.zip" % OS.get_process_id()
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


func test_card_sounds_come_from_the_set_with_the_generated_ones_behind() -> void:
	_install()
	var m := H.scene({"hero": "HERO_08", "hand": [LEEROY, YETI, FIREBALL, PYROBLAST]})
	var g := m.game
	var id := func(c: String) -> int: return g.players[0].hand.filter(func(e): return e.card_id == c)[0].id
	eq(Sound.sound_for({"type": "play", "entity": id.call(LEEROY)}, g, 0), "play_card", "a minion leaves the hand")
	eq(Sound.sound_for({"type": "summon", "entity": id.call(LEEROY)}, g, 0), LEEROY + "_play", "and lands with its own sound")
	eq(Sound.sound_for({"type": "summon", "entity": id.call(YETI)}, g, 0), "summon", "one without: the set's summon")
	eq(Sound.sound_for({"type": "death", "entity": id.call(LEEROY)}, g, 0), LEEROY + "_death", "its death")
	eq(Sound.sound_for({"type": "death", "entity": id.call(YETI)}, g, 0), "death", "a death without its own")
	eq(Sound.sound_for({"type": "play", "entity": id.call(PYROBLAST)}, g, 0), "spell_fire", "a fire spell's cast")
	eq(Sound.sound_for({"type": "damage", "by": FIREBALL, "target": 1}, g, 0), FIREBALL + "_hit", "Fireball's own impact")
	eq(Sound.sound_for({"type": "damage", "by": PYROBLAST, "target": 1}, g, 0), "hit_fire", "its element's impact")
	eq(Sound.sound_for({"type": "damage", "by": YETI, "target": 1}, g, 0), "damage", "a minion's blow: the event's")
	eq(Sound.sound_for({"type": "heal", "target": 1}, g, 0), "heal", "no source: the event's")
	eq(Sound.path_for("heal"), "sounds/generated/heal.opus", "a sound the set lacks: the generated one")
	eq(Sound.line_for({"type": "summon", "entity": id.call(LEEROY)}, g), [LEEROY, "play"], "it says its play line")
	eq(Sound.line_for({"type": "death", "entity": id.call(LEEROY)}, g), [LEEROY, "death"], "and its death line")
	eq(Sound.line_for({"type": "damage", "target": 1}, g), [], "a hit says nothing")
	eq(Sound.card_sound(LEEROY, "music"), LEEROY + "_music", "a legendary's play music")
	check(not Sound.card_music(YETI) and not Sound.music_for({"type": "summon", "entity": id.call(LEEROY)}, g), "none for others, only when played")
	check(Sound.music_for({"type": "play", "entity": id.call(LEEROY)}, g), "played: it plays")
	Packs.set_choice(_pack, "sound", "generated")
	eq(Sound.sound_for({"type": "summon", "entity": id.call(LEEROY)}, g, 0), "summon", "the generated set: no card sounds")
	eq(Sound.path_for("summon"), "", "(and no summon sound: silent)")
	_uninstall()


func test_voice_in_the_players_language_else_the_default() -> void:
	_install()
	TranslationServer.set_locale("ru")
	eq(Sound.voice_path(LEEROY, "play"), "voice/ru/%s_play.opus" % LEEROY, "Russian")
	eq(Sound.voice_path(LEEROY, "attack"), "voice/en/%s_attack.opus" % LEEROY, "no Russian one: English")
	TranslationServer.set_locale("de")
	eq(Sound.voice_path(LEEROY, "play"), "voice/en/%s_play.opus" % LEEROY, "German: English")
	eq(Sound.voice_path(YETI, "play"), "", "a card that says nothing")
	check(Sound.say(LEEROY, "play"), "said")
	eq(_sound.said, "voice/en/%s_play.opus" % LEEROY, "the line")
	check(_sound._voice.playing and _sound._voice.bus == "SFX", "on the SFX bus")
	check(not Sound.say(YETI, "attack"), "nothing to say")
	_uninstall()


## Each sound at its step: the minion's line when it lands (not when it leaves the hand), the
## attacker's as it leaps, the death line at the death step.
func test_lines_come_at_their_steps() -> void:
	_install()
	var v := MatchView.new()
	root().add_child(v)
	v.bind(H.scene({"hero": "HERO_08", "hand": [LEEROY]}, {"hero": "HERO_01", "board": [YETI]}))
	var m := v.controller
	var leeroy: GameView.Ent = m.game.players[0].hand[0]
	var r := m._apply({"type": "play", "player": 0, "entity": leeroy.id, "target": -1, "pos": 0, "choice": -1})
	var item := {"events": r.events, "snap": m.game.snapshot, "hist": m.game.history.size()}
	var steps := MatchView.steps(item.events)
	v._begin_batch(item)
	_sound.said = ""
	v._play_step(steps[0])  # the card leaves the hand
	eq(_sound.said, "", "no line while it is shown")
	check(_sound.heard.has("play_card"), "the card's whoosh")
	eq(_sound.heard.back(), LEEROY + "_music", "and the legendary's play music")
	check(_sound._stinger.playing and _sound._stinger.bus == "Music", "on the music bus")
	check(_sound._ducking != null and _sound._ducking.is_running(), "the music ducks under it")
	v._play_step(steps[1])  # it lands
	eq(steps[1].k, "summon", "(the summon step)")
	eq(_sound.said, "voice/en/%s_play.opus" % LEEROY, "Leeroy shouts as he lands")
	check(_sound.heard.has(LEEROY + "_play"), "with his own sound")
	v._end_batch()
	# the attack: his line and sound as he leaps, before the blow lands
	var yeti: GameView.Ent = m.game.players[1].board[0]
	r = m._apply({"type": "attack", "player": 0, "attacker": leeroy.id, "defender": yeti.id})
	item = {"events": r.events, "snap": m.game.snapshot, "hist": m.game.history.size()}
	steps = MatchView.steps(item.events)
	v._begin_batch(item)
	_sound.said = ""
	_sound.heard.clear()
	v._play_step(steps[0])
	eq(steps[0].k, "attack", "(the attack step)")
	eq(_sound.said, "voice/en/%s_attack.opus" % LEEROY, "his attack line as he leaps")
	eq(_sound.heard, [LEEROY + "_attack"], "his own attack sound, the blow not yet")
	v.free()
	_uninstall()


func test_heroes_say_emotes_errors_and_their_start() -> void:
	_install()
	var v := MatchView.new()
	root().add_child(v)
	v.bind(H.scene({"hero": "HERO_08", "hand": ["VAN_EX1_116"], "mana": 1, "max_mana": 1}, {"hero": "HERO_01", "board": [YETI]}))
	v.show_emote(0, "greetings")
	eq(_sound.said, "voice/en/HERO_08_greetings.opus", "Jaina says hello")
	v._select(v.g.players[0].hand[0].id)
	eq(_sound.said, "voice/en/HERO_08_error_need_mana.opus", "not enough mana")
	var yeti: GameView.Ent = v.g.players[1].board[0]
	eq(MatchView.error_of(yeti), "error_generic", "a minion that may not attack for no reason known")
	v._start_lines()
	eq(_sound.said, "voice/en/HERO_08_start.opus", "her opening line first")
	v._enemy_start_line()
	eq(_sound.said, "voice/en/HERO_01_start.opus", "then Garrosh's")
	v.free()
	_uninstall()


func _view(p0: Dictionary, p1 := {"hero": "HERO_01"}) -> MatchView:
	var v := MatchView.new()
	root().add_child(v)
	v.bind(H.scene(p0, p1))
	return v


func _play(v: MatchView, card_id: String, target := -1) -> Dictionary:
	var e: GameView.Ent = v.controller.game.players[0].hand.filter(func(x): return x.card_id == card_id)[0]
	var pos := v.controller.game.players[0].board.size() if e.is_minion() else -1
	return {"type": "play", "player": 0, "entity": e.id, "target": target, "pos": pos, "choice": -1}


## The action applied and played on the table step by step (the animated path): the sounds heard.
func _played(v: MatchView, action: Dictionary) -> Array[String]:
	var m := v.controller
	var r := m._apply(action)
	check(r.ok, "applied %s" % action.type)
	_sound.heard.clear()
	v._animate({"events": r.events, "snap": m.game.snapshot, "hist": m.game.history.size()})
	return _sound.heard.duplicate()


## A spell at its target: its cast, its bolt, its impact, in that order; Arcane Missiles' hits take its
## impacts in turn; a card without sounds of its own keeps the event's.
func test_a_spell_casts_flies_and_hits() -> void:
	_install()
	var v := _view({"hero": "HERO_08", "hand": [FIREBALL, MISSILES, FROSTBOLT]})
	var hero: int = v.g.hero(1).id
	var heard := _played(v, _play(v, FIREBALL, hero))
	var at := [FIREBALL + "_play", FIREBALL + "_missile", FIREBALL + "_hit"].map(func(f): return heard.find(f))
	check(at[0] >= 0 and at[0] < at[1] and at[1] < at[2], "cast, bolt, impact in order: %s" % [heard])
	heard = _played(v, _play(v, MISSILES))
	eq(heard.filter(func(f): return f.begins_with(MISSILES)), [MISSILES + "_hit", MISSILES + "_hit_2", MISSILES + "_hit_3"],
		"each missile its own impact, in turn")
	eq(Sound.hit_sound(MISSILES, 4), MISSILES + "_hit", "(a fourth starts again)")
	heard = _played(v, _play(v, FROSTBOLT, hero))
	check(heard.has("spell") and heard.has("damage") and not heard.any(func(f): return f.begins_with(FROSTBOLT)),
		"none of its own: the event's sounds: %s" % [heard])
	v.free()
	_uninstall()


## The aim loop plays while the player's arrow comes from a targeted spell; cancelled or cast, it stops.
func test_aiming_loops_until_cancelled_or_cast() -> void:
	_install()
	check(not Sound.aim_start(YETI) and Sound.aiming() == "", "a card without an aim sound: quiet")
	check(Sound.aim_start(FIREBALL), "Fireball's aim")
	check(_sound._aim.playing and _sound._aim.bus == "SFX", "on the SFX bus")
	Sound.aim_stop()
	eq(Sound.aiming(), "", "stopped")
	var v := _view({"hero": "HERO_08", "hand": [FIREBALL]})
	var fireball: int = v.g.players[0].hand[0].id
	v._select(fireball)  # click mode: the arrow follows the mouse
	v._aim_click_mode()
	v._sync_aim()
	eq(Sound.aiming(), FIREBALL, "aiming with Fireball: its loop")
	v.cancel()
	eq(Sound.aiming(), "", "cancelled: quiet")
	v._select(fireball)
	v._aim_click_mode()
	v._sync_aim()
	eq(Sound.aiming(), FIREBALL, "aiming again")
	v.click_entity(v.g.hero(1).id)
	eq(Sound.aiming(), "", "cast: quiet")
	eq(v.controller.game.hero(1).health(), 24, "(the Fireball went)")
	v.free()
	_uninstall()


## A Secret revealed, a hero power used, a minion's trigger: their own sounds, else the event's.
func test_secret_power_and_trigger_sounds() -> void:
	_install()
	var v := _view({"hero": "HERO_08", "board": [YETI]}, {"hero": "HERO_05", "secrets": [EXPLOSIVE]})
	eq(v.g.players[0].hero_power.card_id, FIREBLAST, "(Jaina's power)")
	var m := v.controller
	var r := m._apply({"type": "attack", "player": 0, "attacker": v.g.players[0].board[0].id, "defender": v.g.hero(1).id})
	var item := {"events": r.events, "snap": m.game.snapshot, "hist": m.game.history.size()}
	v._begin_batch(item)
	_sound.heard.clear()
	for st in MatchView.steps(item.events, v._aimed(item)).filter(func(s): return s.k == "secret"):
		v._play_step(st)  # (the attack's leap waits for its animation: only the Secret's step here)
	v._end_batch()
	eq(_sound.heard, [EXPLOSIVE + "_reveal"], "the Secret's own reveal")
	eq(Sound.sound_for({"type": "secret_revealed", "entity": -1, "card": "VAN_EX1_611"}, v.g, 0), "secret", "one without: the event's")
	var heard := _played(v, {"type": "hero_power", "player": 0, "target": v.g.hero(1).id})
	check(heard.find(FIREBLAST + "_play") >= 0 and heard.find(FIREBLAST + "_play") < heard.find(FIREBLAST + "_hit"),
		"the power used, then its impact: %s" % [heard])
	eq(Sound.sound_for({"type": "hero_power", "entity": v.g.players[1].hero_power.id}, v.g, 0), "hero_power", "Rexxar's: the event's")
	v.free()
	var w := _view({"hero": "HERO_08", "board": [JUGGLER], "hand": [H.WISP]})
	heard = _played(w, _play(w, H.WISP))
	check(heard.has(JUGGLER + "_trigger") and not heard.has("trigger"), "the Juggler's own trigger: %s" % [heard])
	eq(_sound.said, "voice/en/%s_trigger.opus" % JUGGLER, "and its line")
	w.free()
	_uninstall()
