class_name Sound
extends Node
## Music and event sounds from the active pack: sounds/<set>/<name>.(ogg|wav|mp3) and
## music/<set>/<name> (menu, battle_1 … battle_N), the sets chosen per pack
## (Packs.choice "sound", "music"). The client's own screens (Packs.shell) play one neutral
## menu track of the client (SHELL_MENU), never a pack's. Main adds one instance; without it
## every call is silent (tests, tools).

## Event type -> sound name.
const EVENTS := {"play": "play_card", "attack": "attack", "damage": "damage", "death": "death",
	"hero_power": "hero_power", "turn_start": "turn_start", "heal": "heal", "armor": "armor",
	"equip": "equip", "secret_revealed": "secret", "freeze": "freeze", "divine_shield_lost": "shield"}
const POOL := 6
const AUDIO := ["ogg", "wav", "mp3"]
## The client's own menu music (the main menu, the settings, the library, the connections).
const SHELL_MENU := "res://audio/shell/menu.wav"

static var instance: Sound

var _music := AudioStreamPlayer.new()
var _track := ""
## The music file playing now (a battle track while _track is "battle").
var music_file := ""
var _last_battle := ""
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _streams := {}
## The player of spoken lines: one at a time, a new line cuts the last.
var _voice := AudioStreamPlayer.new()
## The player of a card's play music (a legendary's stinger); the music ducks to DUCK_DB under it.
var _stinger := AudioStreamPlayer.new()
const DUCK_DB := -14.0
var _ducking: Tween
## The recording said last and the last sounds played, oldest first (tests, the driver).
var said := ""
var heard: Array[String] = []


func _ready() -> void:
	instance = self
	Settings.apply()  # makes sure the Music and SFX buses exist
	_music.bus = "Music"
	_music.finished.connect(_on_music_finished)
	add_child(_music)
	_voice.bus = "SFX"
	add_child(_voice)
	_stinger.bus = "Music"
	_stinger.finished.connect(func(): _duck(0.0, 0.8))
	add_child(_stinger)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		_pool.append(p)
		add_child(p)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## The pack file of a sound or a music track ("" when the pack has none): the chosen
## set first, then the pack's default set.
static func path_for(file: String, p: Pack = null) -> String:
	p = p if p else Packs.active()
	if p == null:
		return ""
	var kind := "music" if file == "menu" or file.begins_with("battle_") else "sound"
	var folder := "music" if kind == "music" else "sounds"
	for set_id in [Packs.choice(p, kind), p.default_set(kind)]:
		var f := p.find("%s/%s" % [folder, set_id], file, AUDIO)
		if f != "":
			return f
	return ""


## The battle tracks of the chosen music set (battle_1 … battle_N), a shuffled playlist.
static func battle_tracks(p: Pack = null) -> Array:
	var out := []
	for n in range(1, 21):
		if path_for("battle_%d" % n, p) == "":
			break
		out.append("battle_%d" % n)
	return out


func _stream(file: String) -> AudioStream:
	if file == "shell":
		return load(SHELL_MENU)
	var path := path_for(file)
	if not _streams.has(path):
		_streams[path] = Packs.active().stream(path) if path != "" else null
	return _streams[path]


## The pack or its sound or music set changed: sounds load again, the music starts again.
static func reset() -> void:
	if instance:
		instance._streams = {}
		instance._last_battle = ""
		restart_music()


## The music set changed: the track playing now starts again from the new set.
static func restart_music() -> void:
	if instance and instance.music_file != "":
		if instance._track == "battle" and not battle_tracks().has(instance.music_file):
			instance._start(instance._next_battle())
		else:
			instance._start(instance.music_file)


static func play(file: String) -> void:
	if instance == null or file == "":
		return
	var s := instance._stream(file)
	if s == null:
		return
	var p := instance._pool[instance._next]
	instance._next = (instance._next + 1) % POOL
	p.stream = s
	p.play()
	instance.heard.append(file)
	if instance.heard.size() > 50:
		instance.heard.pop_front()


## The player that started the last sound (tests).
func last_player() -> AudioStreamPlayer:
	return _pool[(_next - 1 + POOL) % POOL]


## Loops track; "battle" starts a battle track other than the last one (a new one
## every match) and moves on to another when it ends.
static func music(track: String) -> void:
	if track == "menu" and Packs.shell:
		track = "shell"
	if instance == null or (instance._track == track and track != "battle"):
		return
	instance._track = track
	instance._start(instance._next_battle() if track == "battle" else track)


func _next_battle() -> String:
	var tracks := battle_tracks()
	var others := tracks.filter(func(f): return f != _last_battle)
	_last_battle = others.pick_random() if not others.is_empty() else (tracks[0] if not tracks.is_empty() else "menu")
	return _last_battle


func _start(file: String) -> void:
	music_file = file
	_music.stream = _stream(file)
	if _music.stream:
		_music.play()


func _on_music_finished() -> void:
	if _track == "battle":
		_start(_next_battle())
	else:
		_music.play()


## The sound of an engine event at its step: a minion's or weapon's own sound when it comes into play
## (its `<card id>_play`), a spell's cast (its own, else its element's `spell_<element>`, else
## `spell`), a spell's hit (its own `_hit`, else `hit_<element>`), a death (its own `_death`), else the
## event's. An attack's own sound comes as the attacker leaps (attack_start); here is its impact.
static func sound_for(ev: Dictionary, g: GameView, viewer: int) -> String:
	var id_of := func(key: String) -> String:
		var e := g.ent(int(ev.get(key, -1)))
		return e.card_id if e else str(ev.get("card", ""))
	match ev.type:
		"play":
			var id: String = id_of.call("entity")
			if CardDb.card(id).get("type") == "SPELL":
				return _first([card_sound(id, "play"), _element(id, "spell"), "spell"])
			return "play_card"  # a minion or a weapon leaves the hand; its own sound when it lands
		"summon":
			return _first([card_sound(id_of.call("entity"), "play"), "summon"])
		"equip":
			return _first([card_sound(id_of.call("entity"), "play"), "equip"])
		"death":
			return _first([card_sound(id_of.call("entity"), "death"), "death"])
		"damage", "heal", "buff", "freeze", "silence", "destroy":
			var by := str(ev.get("by", ""))
			if by != "" and CardDb.card(by).get("type") == "SPELL":
				var own := _first([card_sound(by, "hit"), _element(by, "hit")])
				if own != "":
					return own
		"game_over":
			if ev.winner == viewer:
				return "victory"
			return "defeat"
	return EVENTS.get(ev.type, "")


## A card's own sound for slot (play, attack, death, hit): what its `sounds` field names, else the
## chosen set's file `<card id>_<slot>`; "" when it has none.
static func card_sound(card_id: String, slot: String) -> String:
	if card_id == "":
		return ""
	var named = CardDb.card(card_id).get("sounds", {}) if CardDb.has(card_id) else {}
	if named is Dictionary and str(named.get(slot, "")) != "":
		return str(named[slot])
	var own := "%s_%s" % [card_id, slot]
	return own if path_for(own) != "" else ""


## `<kind>_<element>` of a card's element (its fx.element) when the set has it, else "".
static func _element(card_id: String, kind: String) -> String:
	var el := TableFx.named(card_id, "element")
	var f := "%s_%s" % [kind, el]
	return f if el != "" and path_for(f) != "" else ""


static func _first(names: Array) -> String:
	for n in names:
		if n != "":
			return n
	return ""


## A card's play music (a legendary's stinger: its `sounds.music`, else the set's `<card id>_music`) when
## it is played from the hand ("play" event), over the music, which ducks meanwhile. True when it plays.
static func music_for(ev: Dictionary, g: GameView) -> bool:
	if ev.get("type") != "play":
		return false
	var e := g.ent(int(ev.get("entity", -1)))
	return card_music(e.card_id if e else str(ev.get("card", "")))


static func card_music(card_id: String) -> bool:
	if instance == null:
		return false
	var file := card_sound(card_id, "music")
	var s := instance._stream(file) if file != "" else null
	if s == null:
		return false
	instance._stinger.stream = s
	instance._stinger.play()
	instance._duck(DUCK_DB, 0.25)
	instance.heard.append(file)
	return true


## Turns the music down (a stinger plays) or back up (0 dB), over secs.
func _duck(db: float, secs: float) -> void:
	if _ducking:
		_ducking.kill()
	_ducking = create_tween()
	_ducking.tween_property(_music, "volume_db", db, secs)


## The attacker's own sound and line as it leaps (the impact is sound_for's "attack").
static func attack_start(attacker: String) -> void:
	play(card_sound(attacker, "attack"))
	say(attacker, "attack")


## What a step's event makes its card say: [card id, kind] for a minion or a weapon coming into play
## and for a death, [] for nothing.
static func line_for(ev: Dictionary, g: GameView) -> Array:
	var kind: String = {"summon": "play", "equip": "play", "death": "death", "hero_replaced": "play"}.get(ev.type, "")  # (a hero card: its line as it takes over)
	var e := g.ent(int(ev.get("entity", -1)))
	var id: String = e.card_id if e else str(ev.get("card", ""))
	return [id, kind] if kind != "" and id != "" else []


## The recording of a card's line (voice/<lang>/<who>_<kind>.ogg|wav|mp3): the interface language
## first, then the pack's default; "" when the pack has none. `who` is the card's `voice` (whose lines
## it speaks), else its id.
static func voice_path(card_id: String, kind: String, p: Pack = null) -> String:
	p = p if p else Packs.active()
	if p == null or card_id == "" or kind == "":
		return ""
	var who: String = str(CardDb.card(card_id).get("voice", card_id)) if CardDb.has(card_id) else card_id
	for lang in [p.lang_for(TranslationServer.get_locale()), p.default_locale()]:
		var f := p.find("voice/" + lang, "%s_%s" % [who, kind], AUDIO)
		if f != "":
			return f
	return ""


## Says a card's line (a minion's, a weapon's, a hero's emote or error); a new line cuts the one
## before. False when the pack has no recording of it (or no Sound node runs).
static func say(card_id: String, kind: String) -> bool:
	if instance == null:
		return false
	var path := voice_path(card_id, kind)
	if path == "":
		return false
	if not instance._streams.has(path):
		instance._streams[path] = Packs.active().stream(path)
	if instance._streams[path] == null:
		return false
	instance._voice.stream = instance._streams[path]
	instance._voice.play()
	instance.said = path
	return true


