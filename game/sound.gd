class_name Sound
extends Node
## Music and event sounds. Main adds one instance; without it every call
## is silent (tests, tools). Sounds come from audio/*.wav (tools/gen_audio.py);
## the music is the generated set (audio/*.wav) or the open one (audio/open/*.ogg,
## tools/fetch_open_music.py), as chosen in the settings.

## Event type -> sound file.
const EVENTS := {"play": "play_card", "attack": "attack", "damage": "damage", "death": "death",
	"hero_power": "hero_power", "turn_start": "turn_start", "heal": "heal", "armor": "armor",
	"equip": "equip", "secret_revealed": "secret", "freeze": "freeze", "divine_shield_lost": "shield"}
const POOL := 6
## Sound.music("battle") plays these as a shuffled playlist.
const BATTLE_TRACKS := ["battle_1", "battle_2", "battle_3"]
const MUSIC_SETS := ["generated", "open"]

static var instance: Sound

var _music := AudioStreamPlayer.new()
var _track := ""
## The music file playing now (a battle track while _track is "battle").
var music_file := ""
var _last_battle := ""
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _streams := {}


func _ready() -> void:
	instance = self
	Settings.apply()  # makes sure the Music and SFX buses exist
	_music.bus = "Music"
	_music.finished.connect(_on_music_finished)
	add_child(_music)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		_pool.append(p)
		add_child(p)


func _exit_tree() -> void:
	if instance == self:
		instance = null


## The file of a sound or a music track: the music comes from the chosen set.
static func path_for(file: String, music_set: String) -> String:
	if music_set == "open" and (file == "menu" or BATTLE_TRACKS.has(file)):
		return "res://audio/open/%s.ogg" % file
	return "res://audio/%s.wav" % file


func _stream(file: String) -> AudioStream:
	var path := path_for(file, Settings.data.get("music_set", "generated"))
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


## The music set changed: the track playing now starts again from the new set.
static func restart_music() -> void:
	if instance and instance.music_file != "":
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


static func sound_for(ev: Dictionary, g: GameView, viewer: int) -> String:
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
