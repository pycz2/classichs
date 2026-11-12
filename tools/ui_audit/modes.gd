extends RefCounted
## The game modes' screens: the training setup, the tutorial (missions, every intro page, a mission's table with
## its hints, its win and loss windows), code play (every stage, the codes, the pack offer), the code-play Arena
## (two sessions in one process over LoopbackTransport), the replays list and the replay player, the debug tools.

const LONG_DECK := "Колода жреца на воскрешениях, дешёвых заклинаниях и легендарках"
const NAMES := ["Александра Константинова", "Bartholomew_Featherstone"]  # 24 characters each (Profile.NAME_MAX)

var a
var m: Node


func run(audit) -> void:
	a = audit
	if _want("training"):
		await _training()
	if _want("tutorial"):
		await _tutorial()
	if _want("code"):
		await _code_play()
	if _want("arena"):
		await _arena()
	if _want("replay"):
		await _replays()
	if _want("debug"):
		await _debug()


## Some shot of this part is wanted (a run with --only skips the rest).
func _want(prefix: String) -> bool:
	if not a.job.has("only"):
		return true
	for n in a.job.only:
		if str(n).begins_with(prefix):
			return true
	return false


## The table ignores the real mouse (its hand card would rise under the player's cursor in the shot).
func _no_hover(v: Node) -> void:
	if v is MatchView and v.find_child("SettingsView", false, false) == null:
		var d := Control.new()
		d.name = "SettingsView"  # (MatchView._track_hand_hover stops while one is open)
		d.visible = false
		v.add_child(d)


func _t(s: String) -> String:
	return TranslationServer.translate(s)


func _pack(id: String) -> Pack:
	for p: Pack in Packs.all():
		if p.id() == id:
			return p
	a.error("no pack " + id)
	return null


## The pack's ready decks, a long-named one first and an unfinished one last.
func _decks() -> void:
	var list: Array = Decks.templates().map(func(t): return t.deck.to_dict().merged({"name": t.name}, true))
	var long: Dictionary = list[0].duplicate(true)
	long.name = LONG_DECK
	var half: Dictionary = list[1].duplicate(true)
	half.name = "Недоделанная колода" if a.lang == "ru" else "Unfinished deck"
	half.cards = half.cards.slice(0, 7)
	DeckStore.write(DeckStore.file(), [long] + list + [half])


# --- training ------------------------------------------------------------------------------------

func _training() -> void:
	m = await a.open_game()
	_decks()
	m.show_training_setup()
	await a.settle()
	await a.shot("training_decks", "Training, step 1: the player's decks (a long name, an unfinished deck)")
	var t: TrainingSetup = m.screen
	t.chooser.find_children("*", "ScrollContainer", true, false)[0].scroll_vertical = 100000
	await a.wait(0.3)
	await a.shot("training_decks_end", "Training, step 1: the deck list scrolled to its end")
	t.choose_deck(t.chooser.decks[0])
	await a.settle()
	await a.shot("training_opponents", "Training, step 2: the opponents and the bot's level (the long deck name above)")
	(t.find_child("Level_superhard", true, false) as Button).button_pressed = true
	await a.wait(0.3)
	await a.shot("training_superhard", "Training, step 2: the hardest bot level chosen")
	DeckStore.write(DeckStore.file(), [])
	m.show_training_setup()
	await a.settle()
	await a.shot("training_no_decks", "Training without any deck of the game")


# --- tutorial ------------------------------------------------------------------------------------

func _tutorial() -> void:
	for id in ["classic-2014", "neon"]:
		var p := _pack(id)
		if p == null:
			continue
		m = await a.open_game(p)
		var key: String = id.get_slice("-", 0)
		DirAccess.remove_absolute(Progress.path)
		Progress.complete(Missions.ids()[0])
		Progress.complete(Missions.ids()[1])
		m.show_tutorial()
		await a.settle(1.0)
		await a.shot("tutorial_%s_list" % key, "The tutorial's missions: two done, the third up next, the rest locked (%s)" % p.title())
		for n in Missions.ids():
			m.show_tutorial_intro(n)
			await a.settle(0.6)
			var intro: TutorialIntro = m.screen
			for i in intro._panels.size():
				intro._show(i)
				await a.wait(0.5)
				await a.shot("tutorial_%s_intro%d_p%d" % [key, n, i + 1], "Mission %d's intro, page %d (%s)" % [n, i + 1, p.title()])
		if key != "classic":
			continue
		for n in Missions.ids():
			Progress.complete(n)
		m.show_tutorial()
		await a.settle(0.8)
		await a.shot("tutorial_classic_list_done", "The tutorial's missions, all done")
		await _mission(1, 1, "win")
		await _mission(2, 0, "loss")
		await _mission(Missions.ids()[-1], 1, "win_last")


## A tutorial mission's table (its first hint), then a concede by `quits` and its result window.
func _mission(n: int, quits: int, what: String) -> void:
	var v: MatchView = m.start_tutorial(n)
	_no_hover(v)
	await a.settle(2.5)
	await a.shot("tutorial_match%d" % n, "Mission %d's table at its start (the hint bubble)" % n)
	await a.wait(4.0)
	await a.shot("tutorial_match%d_later" % n, "Mission %d's table a few seconds later (the boss's line, the next hint)" % n)
	var r: Dictionary = v.controller.submit({"type": "concede", "player": quits})
	if not r.get("ok", false):
		a.error("tutorial concede: %s" % r)
	await a.settle(5.0)
	await a.shot("tutorial_result_" + what, "Mission %d's result window (%s)" % [n, what])


# --- code play -----------------------------------------------------------------------------------

func _code_play() -> void:
	m = await a.open_game()
	_decks()
	Profile.save_name(NAMES[0])
	m.show_online()
	await a.settle()
	var v: OnlineView = m.screen
	await a.shot("code_name", "Code play: the player's name (24 characters)")
	v.show_stage("kind")
	await a.settle(0.4)
	await a.shot("code_kind", "Code play: a normal game or the Arena")
	v.choose_kind("game")
	await a.settle(0.4)
	await a.shot("code_deck", "Code play: the deck")
	v.choose_deck(v.chooser.decks[0])
	v.show_stage("mode")
	await a.settle(0.4)
	await a.shot("code_mode", "Code play: create or join")
	v.host_game()
	var t0 := Time.get_ticks_msec()
	while v.code_out.text == "" and Time.get_ticks_msec() - t0 < 15000:
		await a.wait(0.2)
	await a.settle(0.3)
	await a.shot("code_host", "Code play, host: the invite code and the answer field")
	var invite := v.code_out.text
	v.finish("")
	await a.wait(0.3)
	await a.shot("code_host_connecting", "Code play, host: Connect pressed with an empty answer")
	v.step_back()
	v.show_stage("join")
	await a.settle(0.3)
	await a.shot("code_join_empty", "Code play, guest: the invite field")
	v.join_game("")
	await a.wait(0.3)
	await a.shot("code_join_no_code", "Code play, guest: Join without a code (its message)")
	if invite != "":
		v.code_in.text = invite
		v.join_game(invite)
		t0 = Time.get_ticks_msec()
		while v.code_out.text == "" and Time.get_ticks_msec() - t0 < 15000:
			await a.wait(0.2)
		await a.settle(0.3)
		await a.shot("code_join_answer", "Code play, guest: the answer code to send back, waiting")
	v._pack_dialog(_t("Your opponent plays %s %s (%s). Download it and play?") % [a.main_pack.title(), "1.0.0", Packs.size_text(176216437)],
		[[_t("Download"), "PackDownload", func(): pass], [_t("No"), "PackNo", func(): pass]])
	await a.wait(0.4)
	await a.shot("code_pack_offer", "Code play, guest: the host's game is not here, download it?")
	v._pack_dialog(_t("Receiving the game: %s / %s") % [Packs.size_text(61234567), Packs.size_text(176216437)],
		[[_t("Cancel"), "PackCancel", func(): pass]], true)
	v._pack_bar.value = 35
	await a.wait(0.4)
	await a.shot("code_pack_receiving", "Code play, guest: receiving the host's game")
	v._close_pack_dialog()
	v.step_back()
	v.show_stage("kind")
	v.choose_kind("arena")
	await a.settle(0.4)
	await a.shot("code_arena_mode", "Code play, the Arena chosen: create or join")
	v.step_back()
	m.show_game_menu()
	await a.settle(0.5)


# --- the code-play Arena ---------------------------------------------------------------------------

var _arena_parts: Array = []  # [host, guest, transports]


func _pump(seconds := 0.6) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		LoopbackTransport.pump(_arena_parts[2])
		await a.wait(0.05)


func _arena() -> void:
	m = await a.open_game()
	var pair := LoopbackTransport.pair()
	var h := ArenaSession.new()
	var g := ArenaSession.new()
	h.setup(pair[0], true, NAMES[0], 21)
	g.setup(pair[1], false, NAMES[1], 22)
	_arena_parts = [h, g, pair]
	h.say_hello()
	g.say_hello()
	await _pump(0.2)
	var v: ArenaView = m.show_arena(h)
	await a.settle()
	await a.shot("arena_rules", "The Arena, host: the rules")
	v._rules_pick = "each"
	v._rebuild()
	var keep := v.find_child("MayKeep", true, false) as CheckBox
	if keep:
		keep.button_pressed = true
	await a.wait(0.3)
	await a.shot("arena_rules_each", "The Arena, host: a new deck every game, may keep the last one")
	(v.find_child("StartArena", true, false) as Button).pressed.emit()
	await _pump()
	await a.settle()
	await a.shot("arena_hero", "The Arena: choose a hero")
	v.choose_hero(1)
	g.draft.choose_hero(0)
	g.send_status()
	await _pump()
	await a.settle(0.8)
	await a.shot("arena_draft1", "The Arena: the first pick")
	for k in 3:
		for i in 6:
			v.pick(i % 3)
		for i in 4:
			if not g.draft.done():
				g.draft.pick(0)
		g.send_status()
		await _pump(0.3)
		await a.settle(0.8)
		await a.shot("arena_draft%d" % (k + 2), "The Arena: a later pick (%d of 30 chosen)" % h.draft.cards.size())
	var offer := v.find_child("Offer0", true, false) as CardView
	if offer:
		v._on_hover(offer, true)
		await a.wait(0.4)
		await a.shot("arena_draft_tips", "The Arena: a card offered, its keyword tips")
		v._on_hover(offer, false)
	while not h.draft.done():
		h.draft.pick(0)
	while not g.draft.done():
		g.draft.pick(0)
	h.send_status()
	g.send_status()
	await _pump()
	v._rebuild()
	await a.settle()
	await a.shot("arena_lobby", "The Arena's lobby: the deck, the score, Ready")
	v._confirm_concede()
	await a.wait(0.4)
	await a.shot("arena_concede", "The Arena's lobby: concede the Arena?")
	v._rebuild()
	h.set_ready()
	g.set_ready()
	await _pump(0.1)
	_no_hover(m.screen)
	await _pump(0.9)
	await a.settle(1.5)
	if m.screen is MatchView:
		await a.shot("arena_game", "An Arena game: its start (the mulligan)")
		var gm: Match = g.game.match_
		gm.submit({"type": "concede", "player": gm.viewer()})
		await _pump(1.0)
		await a.settle(5.0)
		await a.shot("arena_game_result", "An Arena game won: the result window with the score")
		(m.screen as MatchView)._leave()  # Back to the Arena
		await _pump()
		await a.settle()
		await a.shot("arena_after_game", "The Arena after a game (a new deck or keep it)")
	else:
		a.error("the Arena game did not start")
	g.over = false
	m.show_arena(g)  # the guest's side: the opponent's progress line
	await a.settle()
	await a.shot("arena_guest", "The Arena, the guest's side")
	h.over = true
	h.winner = 0
	m.show_arena(h)
	await a.settle()
	await a.shot("arena_end_won", "The Arena's end: won")
	h.winner = 1
	m.show_arena(h)
	await a.settle()
	await a.shot("arena_end_lost", "The Arena's end: lost")
	h.over = false
	h.failure = _t(ArenaSession.SAME_GAME)
	m.show_arena(h)
	await a.settle()
	await a.shot("arena_end_broken", "The Arena's end: broken (why)")
	for s: Node in [h, g]:
		s.queue_free()
	for x: Node in pair:
		x.queue_free()
	m.show_game_menu()
	await a.settle(0.3)


# --- replays ---------------------------------------------------------------------------------------

## A bot-vs-bot game of the pack's ready decks, as a replay.
func _game(seed: int, d0: int, d1: int) -> Replay:
	var ts := Decks.templates()
	var mt := Match.new()
	mt.bot_delay = 0.0
	var why := mt.setup({"decks": [{"hero": ts[d0].deck.hero, "cards": Array(ts[d0].deck.cards)},
		{"hero": ts[d1].deck.hero, "cards": Array(ts[d1].deck.cards)}], "seed": seed}, [true, true])
	if why != "":
		a.error("replay game: " + why)
		mt.free()
		return null
	mt.start()
	var r := Replay.from_match(mt, NAMES, "training", 0)
	mt.free()
	return r


func _replays() -> void:
	m = await a.open_game()
	for f in DirAccess.get_files_at(Replay.dir) if DirAccess.dir_exists_absolute(Replay.dir) else []:
		DirAccess.remove_absolute(Replay.dir.path_join(f))
	m.show_replays()
	await a.settle()
	await a.shot("replays_empty", "The replays: none yet")
	var games: Array = []
	var now := int(Time.get_unix_time_from_system())
	var modes := ["training", "code", "hotseat", "arena", "ranked", "tournament"]
	for i in 3:
		var r := _game(100 + i, i, (i + 3) % Decks.templates().size())
		if r:
			games.append(r)
	if games.is_empty():
		return
	for i in modes.size():
		var r := Replay.from_data(games[i % games.size()].data.duplicate(true))
		r.data.mode = modes[i]
		r.data.game = "audit-%d" % i
		r.data.me = i % 2
		r.data.ended = now - i * 3600 * 7
		Replay.keep(r)
	var gone := Replay.from_data(games[0].data.duplicate(true))
	gone.data.game = "audit-gone"
	gone.data.pack = "0000"
	gone.data.pack_id = "gil-2018"
	gone.data.pack_name = "Ведьмин лес 2018" if a.lang == "ru" else "The Witchwood 2018"
	gone.data.ended = now - 3600 * 50
	Replay.keep(gone)
	m.show_replays()
	await a.settle()
	await a.shot("replays_list", "The replays: six games (long names, every mode) and one of a game not here")
	var rv: ReplaysView = m.screen
	rv._scroll.scroll_vertical = 100000
	await a.wait(0.3)
	await a.shot("replays_list_end", "The replays scrolled to the end")
	m.show_replay(Replay.kept()[-1])
	await a.wait(0.6)
	await a.shot("replays_missing_pack", "Watch on a replay whose game is not here: the message")
	var r: Replay = Replay.kept()[0]
	var view: ReplayView = m.show_replay(r)
	_no_hover(view.view)
	await a.settle(1.5)
	await a.shot("replay_start", "The replay player at its start (paused)")
	view._show_at(r.size() / 2)
	_no_hover(view.view)
	await a.settle(1.5)
	await a.shot("replay_middle", "The replay player moved to the middle")
	view.toggle_play()
	await a.wait(2.5)
	await a.shot("replay_playing", "The replay player playing")
	view._pause()
	view._show_at(r.size())
	_no_hover(view.view)
	await a.settle(4.0)
	await a.shot("replay_end", "The replay player at the end of the game")
	m.show_game_menu()
	await a.settle(0.3)


# --- the debug tools -------------------------------------------------------------------------------

func _debug() -> void:
	m = await a.open_game()
	m.show_debug_table()
	await a.settle()
	await a.shot("debug_scene", "The debug tools: the scene")
	var d: DebugTable = m.screen
	d.load_example()
	await a.settle(0.4)
	await a.shot("debug_scene_example", "The debug tools: the scene with the example loaded")
	for i in range(1, DebugTable.TABS.size()):
		d.show_tab(i)
		await a.settle(0.8)
		await a.shot("debug_tab%d" % i, "The debug tools: the tab " + DebugTable.TABS[i])
