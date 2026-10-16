class_name Sound
extends Node
## Music and event sounds from the active pack: sounds/<set>/<name>.(ogg|wav|mp3) and
## music/<set>/<name> (menu, battle_1 … battle_N), the sets chosen per pack
## (Packs.choice "sound", "music"). Main adds one instance; without it every call is
## silent (tests, tools).

## Event type -> sound name.
const EVENTS := {"play": "play_card", "attack": "attack", "damage": "damage", "death": "death",
	"hero_power": "hero_power", "turn_start": "turn_start", "heal": "heal", "armor": "armor",
	"equip": "equip", "secret_revealed": "secret", "freeze": "freeze", "divine_shield_lost": "shield"}
const POOL := 6
const AUDIO := ["ogg", "wav", "mp3"]

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


## The sound of an engine event: a card's own (its `sounds` play, attack, death) or the event's.
static func sound_for(ev: Dictionary, g: GameView, viewer: int) -> String:
	var own := func(id, slot: String) -> String:
		var e := g.ent(int(id)) if id != null else null
		return str(e.card().get("sounds", {}).get(slot, "")) if e and e.card().get("sounds") is Dictionary else ""
	match ev.type:
		"play":
			var e := g.ent(ev.entity)
			var mine: String = own.call(ev.entity, "play")
			if mine != "":
				return mine
			if e and CardDb.card(e.card_id).get("type") == "SPELL":
				return "spell"
		"attack":
			var mine: String = own.call(ev.get("attacker"), "attack")
			if mine != "":
				return mine
		"death":
			var mine: String = own.call(ev.get("entity"), "death")
			if mine != "":
				return mine
		"game_over":
			if ev.winner == viewer:
				return "victory"
			return "defeat"
	return EVENTS.get(ev.type, "")
