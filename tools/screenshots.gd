extends SceneTree
## Screenshots of the game for the site and the README, taken from the real
## screens: media/screens/<lang>/<name>.png (1280x720). Neonfall is the active game (its
## tutorial too: the mission list and an intro page); the last shot (classic) is Classic's. Needs a window.
## Every user file goes to user://uitest_shots_* (never the player's own).
## Usage: godot --path . --script res://tools/screenshots.gd -- <lang> [<lang> ...]

const NEON := "neon"
const CLASSIC := "classic-2014"
## Neonfall: Iris Null (the viewer) against Mother Rust.
const SCENE := {"current": 0, "turn": 9, "seed": 4, "players": [
	{"hero": "iris_null", "mana": 7, "max_mana": 9, "damage": 9,
		"hand": ["zero_day", "firmware_rot", "packet_storm", "cache_raid", "compiler_wyrm", "lattice_diver"],
		"board": [{"card": "sable"}, "signal_leech", "bitrot_daemon", "recursive_hound"],
		"deck": ["ghostwalk", "static_lock", "corrupt", "root_access", "neon_moth", "neon_moth", "rooftop_sniper", "glasshound_runner"]},
	{"hero": "mother_rust", "max_mana": 7, "damage": 13, "armor": 4, "weapon": "chain_whip",
		"hand": ["back_alley_bomb", "scrap_bruiser", "hydraulic_maul", "ramraider"],
		"board": ["vulka", {"card": "stim_junkie", "damage": 1}, "knockoff_mech", "hot_courier"],
		"deck": ["nitro_shot", "chrome_up", "pawn_shark"]}]}
## Classic: Jaina against Garrosh.
const CLASSIC_SCENE := {"current": 0, "turn": 9, "seed": 4, "players": [
	{"hero": "HERO_08", "mana": 7, "max_mana": 9, "damage": 9, "secrets": ["VAN_EX1_289"],
		"hand": ["VAN_CS2_029", "VAN_CS2_024", "VAN_CS2_032", "VAN_CS2_033", "VAN_EX1_559", "VAN_CS2_023"],
		"board": [{"card": "VAN_EX1_067"}, "VAN_CS2_033", "VAN_CS2_179", "VAN_EX1_559"],
		"deck": ["VAN_CS2_023", "VAN_CS2_029", "VAN_CS2_032", "VAN_EX1_279", "VAN_CS2_182", "VAN_CS2_182", "VAN_EX1_295", "VAN_CS2_022"]},
	{"hero": "HERO_01", "damage": 13, "armor": 4, "weapon": "VAN_CS2_106",
		"hand": ["VAN_CS2_108", "VAN_EX1_400", "VAN_CS2_106", "VAN_EX1_604"],
		"board": ["VAN_EX1_298", {"card": "VAN_EX1_393", "damage": 1}, "VAN_EX1_110", "VAN_CS2_182"],
		"deck": ["VAN_CS2_108", "VAN_EX1_400", "VAN_CS2_106"]}]}

var langs: Array = []
var m: Node
var steps: Array = []  # [callable, shot name or ""]
var at := 0
var since := 0  # msec of the last step
var arena: Array = []  # [host session, guest session, transports] of the Arena shots


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_factor = 1.0
	langs = OS.get_cmdline_user_args()
	Settings.path = "user://uitest_shots_settings.json"
	Progress.path = "user://uitest_shots_progress.json"
	DeckStore.path = "user://uitest_shots_decks.json"
	Profile.path = "user://uitest_shots_profile.json"
	ServerLink.session_path = "user://uitest_shots_session.json"
	Replay.dir = "user://uitest_shots_replays"  # never the player's replays
	Packs.user_dir = "user://uitest_shots_packs"
	_clean()
	for lang in langs:
		steps.append([_open.bind(lang, NEON), "menu"])
		steps.append([func(): m.show_library(), "games"])
		steps.append([func(): m.enter_game(Packs.active()), ""])
		steps.append([_match, "match"])
		steps.append([_moves, ""])
		for i in 4:
			steps.append([func(): pass, ""])  # the moves' animations
		steps.append([_history, "history"])
		steps.append([_tracker, "tracker"])
		steps.append([func():  # the player's decks: the pack's templates (a list starts empty)
			DeckStore.write(DeckStore.file(), Decks.templates().map(func(t): return t.deck.to_dict().merged({"name": t.name}, true)))
			m.show_collection(), ""])
		steps.append([func(): m.screen.edit_deck(0), "collection"])
		steps.append([func():
			m.show_online()
			m.screen.show_stage("kind"), "online"])
		steps.append([func(): m.show_settings(), "settings"])
		steps.append([func(): m.show_tutorial(), "tutorial"])
		steps.append([func(): m.show_tutorial_intro(4), "intro"])  # Firewall, the first page of mission 4
		steps.append([func():
			DebugTable.last_scene = JSON.stringify(SCENE, "  ")
			m.show_debug_table(), "debug"])
		steps.append([_arena_rules, "rules"])
		steps.append([_arena_draft, "arena"])
		steps.append([_arena_lobby, "lobby"])
		steps.append([_arena_game, ""])
		steps.append([_arena_win, ""])
		steps.append([func(): pass, "result"])  # the losing hero shatters first
		steps.append([_open.bind(lang, CLASSIC), ""])
		steps.append([func(): m.start_match({"scenario": CLASSIC_SCENE}, [false, false], false), "classic"])


## Removes every file of the run (the driver's own user files and its packs folder).
func _clean() -> void:
	for p in [Settings.path, DeckStore.path, Progress.path, Profile.path, ServerLink.session_path]:
		DirAccess.remove_absolute(p)
	if DirAccess.dir_exists_absolute(Packs.user_dir):
		for f in DirAccess.get_files_at(Packs.user_dir):
			DirAccess.remove_absolute(Packs.user_dir + "/" + f)
		DirAccess.remove_absolute(Packs.user_dir)


## A fresh game in this language with this game pack active, at its game menu.
func _open(lang: String, pack_id: String) -> void:
	_drop_arena()
	if m:
		m.free()
	Settings.load_settings()
	Settings.data.language = lang
	Settings.data.tracker = false
	Settings.save()
	for p: Pack in Packs.all():
		if p.id() == pack_id:
			Packs.set_active(p)
	m = load("res://ui/main.tscn").instantiate()
	root.add_child(m)
	m.show_library()
	m.enter_game(Packs.active())


func _match() -> void:
	m.start_match({"scenario": SCENE}, [false, false], false)


## A few moves so the history and the tracker have something to show.
func _moves() -> void:
	var v: MatchView = m.screen
	var g := v.g
	var me := g.players[0]
	var foe := g.players[1]
	v.controller.submit({"type": "play", "player": 0, "entity": me.hand[1].id, "target": foe.board[2].id, "pos": -1, "choice": -1})
	v.controller.submit({"type": "attack", "player": 0, "attacker": me.board[2].id, "defender": foe.board[3].id})
	v.controller.submit({"type": "end_turn", "player": 0})
	v.controller.submit({"type": "play", "player": 1, "entity": foe.hand[1].id, "target": -1, "pos": -1, "choice": -1})  # Scrap Bruiser
	v.controller.submit({"type": "play", "player": 1, "entity": foe.hand[1].id, "target": -1, "pos": -1, "choice": -1})  # Hydraulic Maul
	v.controller.submit({"type": "end_turn", "player": 1})


func _history() -> void:
	var strip: HistoryStrip = m.screen._strip
	for i in strip._items.size():
		if strip._items[i].size() > 2 and strip._items[i][0] == "firmware_rot":
			strip.hover(i)


func _tracker() -> void:
	m.screen._strip.hover(-1)
	(m.screen.find_child("TrackerButton", true, false) as Button).pressed.emit()


## The Arena against a second, local session: the host's screen is shown.
func _arena_rules() -> void:
	Settings.data.tracker = false  # the result picture without the tracker over it
	var tr := LoopbackTransport.pair()
	var h := ArenaSession.new()
	var g := ArenaSession.new()
	h.setup(tr[0], true, "Iris", 21)
	g.setup(tr[1], false, "Rust", 22)
	arena = [h, g, tr]
	h.say_hello()
	g.say_hello()
	LoopbackTransport.pump(tr)
	var v: ArenaView = m.show_arena(h)
	v._rules_pick = "each"
	v._rebuild()
	(v.find_child("MayKeep", true, false) as CheckBox).button_pressed = true


func _arena_draft() -> void:
	var h: ArenaSession = arena[0]
	var g: ArenaSession = arena[1]
	var tr: Array = arena[2]
	(m.screen.find_child("StartArena", true, false) as Button).pressed.emit()
	LoopbackTransport.pump(tr)
	h.draft.choose_hero(1)
	for i in 13:
		h.draft.pick(i % 3)
	g.draft.choose_hero(0)
	for i in 7:
		g.draft.pick(0)
	for s in [h, g]:
		s.send_status()
	LoopbackTransport.pump(tr)
	m.screen._refresh()


func _arena_lobby() -> void:
	for s: ArenaSession in arena.slice(0, 2):
		while not s.draft.done():
			s.draft.pick(0)
		s.send_status()
	for s: ArenaSession in arena.slice(0, 2):  # a game won by the host already, on both sides
		s.games = 1
		s.record(0)
		s.keep_deck()
	LoopbackTransport.pump(arena[2])
	m.screen._rebuild()


func _arena_game() -> void:
	arena[0].set_ready()
	arena[1].set_ready()
	LoopbackTransport.pump(arena[2])


func _arena_win() -> void:
	var gm: Match = arena[1].game.match_
	gm.submit({"type": "concede", "player": gm.viewer()})
	LoopbackTransport.pump(arena[2])


func _drop_arena() -> void:
	if arena.is_empty():
		return
	var g: ArenaSession = arena[1]
	if g.game and is_instance_valid(g.game.match_):
		g.game.match_.free()
	g.end_game()
	g.free()
	arena[2][1].free()  # the host's side goes with the main scene
	arena = []


func _process(_d: float) -> bool:
	if not arena.is_empty():
		LoopbackTransport.pump(arena[2])  # the Arena game's moves
	if Time.get_ticks_msec() - since < 1600:  # let animations (and the turn banner) end
		return false
	since = Time.get_ticks_msec()
	root.warp_mouse(Vector2(300, 330))  # the mouse on the empty table, not over a card
	if at > 0 and steps[at - 1][1] != "":
		var lang: String = Settings.data.language
		DirAccess.make_dir_recursive_absolute("res://media/screens/" + lang)
		var shot := root.get_texture().get_image()
		shot.save_png("res://media/screens/%s/%s.png" % [lang, steps[at - 1][1]])
		if lang == "en" and steps[at - 1][1] == "match":
			shot.save_jpg("res://site/og.jpg", 0.85)  # the site's link preview
		print("saved ", lang, "/", steps[at - 1][1])
	if at >= steps.size():
		_drop_arena()
		m.free()
		_clean()
		quit()
		return true
	steps[at][0].call()
	at += 1
	return false
