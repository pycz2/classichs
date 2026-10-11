class_name Sound
extends Node
## Music, event sounds and speech. Main adds one instance; without it every call
## is silent (tests, tools). Sounds come from audio/*.wav (tools/gen_audio.py).

## Event type -> sound file.
const EVENTS := {"play": "play_card", "attack": "attack", "damage": "damage", "death": "death",
	"hero_power": "hero_power", "turn_start": "turn_start", "heal": "heal", "armor": "armor",
	"equip": "equip", "secret_revealed": "secret", "freeze": "freeze", "divine_shield_lost": "shield"}
const POOL := 6
## Sound.music("battle") plays these as a shuffled playlist.
const BATTLE_TRACKS := ["battle_1", "battle_2", "battle_3"]

static var instance: Sound
static var default_speaker := func(text: String, voice: String, volume: int) -> void:
	DisplayServer.tts_speak(text, voice, volume, 1.0, 1.0, 0, true)
static var default_voices := func(lang: String) -> PackedStringArray:
	return DisplayServer.tts_get_voices_for_language(lang)
## Replaceable in tests.
static var speaker: Callable = default_speaker
static var voices: Callable = default_voices

var _music := AudioStreamPlayer.new()
var _track := ""
## The music file playing now (a battle track while _track is "battle").
var music_file := ""
var _last_battle := ""
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _streams := {}
var _voice := AudioStreamPlayer.new()  # minions' and heroes' lines: one at a time


func _ready() -> void:
	instance = self
	Settings.apply()  # makes sure the Music and SFX buses exist
	_music.bus = "Music"
	_music.finished.connect(_on_music_finished)
	add_child(_music)
	_voice.bus = "SFX"
	add_child(_voice)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		_pool.append(p)
		add_child(p)


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _stream(file: String) -> AudioStream:
	if not _streams.has(file):
		var path := "res://audio/%s.wav" % file
		_streams[file] = load(path) if ResourceLoader.exists(path) else null
	return _streams[file]


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


## The player that started the last sound (tests).
func last_player() -> AudioStreamPlayer:
	return _pool[(_next - 1 + POOL) % POOL]


## Loops track; "battle" starts a battle track other than the last one (a new one
## every match) and moves on to another when it ends.
static func music(track: String) -> void:
	if instance == null or (instance._track == track and track != "battle"):
		return
	instance._track = track
	instance._start(instance._next_battle() if track == "battle" else track)


func _next_battle() -> String:
	var others := BATTLE_TRACKS.filter(func(f): return f != _last_battle)
	_last_battle = others.pick_random()
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


## Plays what a card says (VoiceLines) at the voice volume; true when a clip played.
## A new line cuts the one before (the newest event matters most).
static func voice(card_id: String, kind: String) -> bool:
	if instance == null or Settings.data.voice <= 0.0:
		return false
	var s := VoiceLines.clip(card_id, kind)
	if s == null:
		return false
	instance._voice.stream = s
	instance._voice.volume_db = linear_to_db(Settings.data.voice)
	instance._voice.play()
	return true


## Speaks text with a voice of the interface language; silent when speech is off,
## the voice volume is 0 or the system has no voice for the language.
static func speak(text: String) -> void:
	if instance == null or text == "" or not Settings.data.tts or Settings.data.voice <= 0.0:
		return
	var list: PackedStringArray = voices.call(Settings.language().get_slice("_", 0))
	if list.is_empty():
		return
	speaker.call(text, list[0], int(round(Settings.data.voice * 100)))


## The sound for an engine event as seen by viewer ("" = none).
static func sound_for(ev: Dictionary, g: Game, viewer: int) -> String:
	match ev.type:
		"play":
			var e := g.ent(ev.entity)
			if e and CardDb.card(e.card_id).get("type") == "SPELL":
				return "spell"
		"game_over":
			if ev.winner == viewer:
				return "victory"
			return "defeat"
	return EVENTS.get(ev.type, "")
