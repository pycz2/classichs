extends SceneTree
## Screenshots of the game for the site and the README, taken from the real
## screens: media/screens/<lang>/<name>.png (1280x720). Needs a window.
## Usage: godot --path . --script res://tools/screenshots.gd -- <lang> [<lang> ...]

const SCENE := {"current": 0, "turn": 9, "seed": 4, "players": [
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
	Settings.path = "user://screenshots_settings.json"
	Progress.path = "user://screenshots_progress.json"
	DeckStore.path = "user://screenshots_decks.json"
	for p in [DeckStore.path, Progress.path]:
		DirAccess.remove_absolute(p)
	for lang in langs:
		steps.append([_open.bind(lang), "menu"])
		steps.append([func(): m.screen.show_play(), ""])
		steps.append([_match, "match"])
		steps.append([_moves, ""])
		for i in 4:
			steps.append([func(): pass, ""])  # the moves' animations
		steps.append([_history, "history"])
		steps.append([_tracker, "tracker"])
		steps.append([func(): m.show_collection(), ""])
		steps.append([func(): m.screen.edit_deck(16), "collection"])
		steps.append([func(): m.show_tutorial(), "tutorial"])
		steps.append([func(): m.show_tutorial_intro(4), "intro"])
		steps.append([func():
			m.show_online()
			m.screen.show_stage("kind"), "online"])
		steps.append([func(): m.show_settings(), "settings"])
		steps.append([func(): m.show_debug_table(), "debug"])
		steps.append([_arena_rules, "rules"])
		steps.append([_arena_draft, "arena"])
		steps.append([_arena_lobby, "lobby"])
		steps.append([_arena_game, ""])
		steps.append([_arena_win, ""])
		steps.append([func(): pass, "result"])  # the losing hero shatters first


## A fresh game in this language, at the menu.
func _open(lang: String) -> void:
	_drop_arena()
	if m:
		m.free()
	Settings.load_settings()
	Settings.data.language = lang
	Settings.data.tracker = false
	Settings.save()
	m = load("res://ui/main.tscn").instantiate()
	root.add_child(m)


func _match() -> void:
	m.start_match(Scenario.build(SCENE).game, [false, false], false)


## A few moves so the history and the tracker have something to show.
func _moves() -> void:
	var v: MatchView = m.screen
	var g := v.g
	var me := g.players[0]
	var foe := g.players[1]
	v.controller.submit({"type": "play", "player": 0, "entity": me.hand[1].id, "target": foe.board[2].id, "pos": -1, "choice": -1})
	v.controller.submit({"type": "attack", "player": 0, "attacker": me.board[2].id, "defender": foe.board[3].id})
	v.controller.submit({"type": "end_turn", "player": 0})
	v.controller.submit({"type": "play", "player": 1, "entity": foe.hand[1].id, "target": -1, "pos": -1, "choice": -1})  # Whirlwind
	v.controller.submit({"type": "play", "player": 1, "entity": foe.hand[1].id, "target": -1, "pos": -1, "choice": -1})  # Fiery War Axe
	v.controller.submit({"type": "end_turn", "player": 1})


func _history() -> void:
	var strip: HistoryStrip = m.screen._strip
	for i in strip._items.size():
		if strip._items[i].size() > 2 and strip._items[i][0] == "VAN_CS2_024":
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
	h.setup(tr[0], true, "Jaina", 21)
	g.setup(tr[1], false, "Garrosh", 22)
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
		for p in [Settings.path, DeckStore.path, Progress.path]:
			DirAccess.remove_absolute(p)
		quit()
		return true
	steps[at][0].call()
	at += 1
	return false
