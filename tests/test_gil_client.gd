extends TestCase
## The Witchwood on the client: Echo (the mark in the hand, the ghostly copy, its fade at the end of the turn), Rush
## (its keyword box, a minion that may attack minions looks ready), Start of Game shown to both players, Shudderwock's
## repeated Battlecries, the worgen changing in the hand, and the Enrage box gone from the cards whose text no longer
## names it. The pack is built from packs/gil (tools/pack.py) and installed into this run's user dir; the tests that
## need it make it the active pack and give Classic back at their end.

const YETI := "VAN_CS2_182"
const RABID := "GIL_113"  # Rabid Worgen: Rush
const ANGLER := "GIL_678"  # Ghost Light Angler: Echo
const PHANTOM := "GIL_207"  # Phantom Militia: Echo, Taunt
const WASP := "GIL_155"  # Redband Wasp: Rush, "Has +3 Attack while damaged." (ENRAGED)
const GLINDA := "GIL_618"  # Glinda Crowskin: minions in your hand have Echo
const BAKU := "GIL_826"
const RETIRED := "TEST_RETIRED_ENRAGE"

static var _pack: Pack


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _gil() -> bool:
	if _pack == null:
		var out := OS.get_user_data_dir() + "/gil_test.cardpack"
		var log := []
		var code := OS.execute("python3", [ProjectSettings.globalize_path("res://tools/pack.py"), "build",
			ProjectSettings.globalize_path("res://packs/gil"), "-o", out], log, true)
		if code != 0:
			check(false, "packs/gil builds: " + "".join(log).right(600))
			return false
		var r := Packs.install_file(out)
		if r.has("error"):
			check(false, "packs/gil installs: " + str(r.error))
			return false
		_pack = r.pack
	Packs.set_active(_pack)
	return true


func _classic() -> void:
	Packs.set_active(Packs.all().filter(func(p): return p.id() == Packs.CLASSIC and p.builtin())[0])


func _view(p0: Dictionary, p1 := {"hero": "HERO_01"}) -> MatchView:
	var v := MatchView.new()
	root().add_child(v)
	v.bind(H.scene(p0, p1, 0, [false, false]))
	return v


static func _rows(g: GameView, evs: Array, viewer: int) -> Array:
	return HistoryText.rows({"turn": 1, "player": 0, "action": {"type": "end_turn"}, "events": evs}, g, viewer, "en").map(func(r): return r.text)


static func _kinds(steps: Array) -> Array:
	return steps.map(func(s): return s.k)


func test_history_lines_of_the_new_events() -> void:
	var m := H.game([YETI])
	var g := m.game
	var yeti: int = g.players[0].hand[0].id
	var hero: int = g.hero(1).id
	var faded := {"type": "faded", "player": 0, "entity": yeti, "card": YETI}
	eq(_rows(g, [faded], 0), ["Chillwind Yeti fades from your hand"], "an Echo copy goes")
	eq(_rows(g, [faded], 1), ["Chillwind Yeti fades from Opponent's hand"], "the opponent's")
	eq(_rows(g, [faded.merged({"card": ""}, true)], 1), [], "hidden: no line")
	var start := {"type": "start_of_game", "player": 1, "card": YETI}
	eq(_rows(g, [start], 0), ["Start of Game: Opponent's Chillwind Yeti"], "Start of Game, the opponent's")
	eq(_rows(g, [start.merged({"player": 0}, true)], 0), ["Start of Game: your Chillwind Yeti"], "mine")
	var again := {"type": "battlecry", "player": 0, "entity": yeti, "card": "VAN_CS2_189", "target": hero}
	eq(_rows(g, [again], 0), ["Chillwind Yeti repeats the Battlecry of Elven Archer on " + CardText.name(g.hero(1).card_id, "en")],
		"Shudderwock, a target")
	eq(_rows(g, [again.merged({"target": -1}, true)], 0), ["Chillwind Yeti repeats the Battlecry of Elven Archer"], "no target")
	m.free()


func test_steps_of_the_new_events() -> void:
	var fades := [{"type": "turn_end", "player": 0}, {"type": "faded", "player": 0, "entity": 40, "card": YETI},
		{"type": "faded", "player": 0, "entity": 41, "card": YETI}, {"type": "turn_start", "player": 1, "turn": 2}]
	var steps := MatchView.steps(fades)
	eq(_kinds(steps), ["fade", "turn"], "the copies fade together")
	eq(steps[0].evs.size(), 2, "both")
	eq(_kinds(MatchView.steps([{"type": "start_of_game", "player": 1, "card": YETI}])), ["reveal"], "Start of Game: the card shown")
	var replays := MatchView.steps([{"type": "battlecry", "player": 0, "entity": 9, "card": "VAN_CS2_189", "target": 3},
		{"type": "damage", "target": 3, "amount": 1, "source": 9, "by": YETI, "by_id": 9},
		{"type": "battlecry", "player": 0, "entity": 9, "card": YETI, "target": -1}])
	eq(_kinds(replays), ["replay", "aim", "hit", "replay"], "each repeated Battlecry: its card, its arrow, its effect")
	eq([replays[1].src, replays[1].to], [9, 3], "the arrow from Shudderwock")
	var swap := MatchView.steps([{"type": "turn_start", "player": 0, "turn": 3},
		{"type": "transform", "from": 20, "entity": 21, "player": 0, "card": YETI}])
	eq(_kinds(swap), ["turn", "hit"], "a worgen changing in the hand at the turn's start: its own step (smoke on it)")


func test_a_ghostly_copy_fades_out_of_the_hand() -> void:
	var v := _view({"hero": "HERO_08", "hand": [YETI, H.WISP]})
	var snap: Dictionary = v.controller.game.snapshot.duplicate(true)
	var copy: int = v.g.players[0].hand[0].id
	var ents: Dictionary = snap.entities
	var k = str(copy) if ents.has(str(copy)) else copy
	ents[k].zone = "SETASIDE"
	snap.players[0].hand = [v.g.players[0].hand[1].id]
	var item := {"events": [{"type": "faded", "player": 0, "entity": copy, "card": YETI}], "snap": snap,
		"hist": v.controller.game.history.size()}
	v._begin_batch(item)
	check(v._views.has(copy), "the copy is in the hand before its step")
	for st in MatchView.steps(item.events):
		v._step_apply(st)
	check(not v._views.has(copy), "gone after it")
	v._end_batch()
	v.free()


func test_a_text_that_no_longer_names_enrage_has_no_enrage_box() -> void:
	CardDb.has(RETIRED)  # loaded
	CardDb._cards[RETIRED] = {"id": RETIRED, "type": "MINION", "cardClass": "NEUTRAL", "set": "VANILLA", "cost": 2,
		"attack": 2, "health": 3, "name": {"enUS": "Amani Berserker"}, "text": {"enUS": "Has +3 Attack while damaged."},
		"mechanics": ["ENRAGED"]}
	var tips := KeywordTips.make(RETIRED)
	check(tips.find_child("TitleENRAGED", true, false) == null, "no Enrage box")
	check(KeywordTips.keywords_of(RETIRED).has("ENRAGED"), "the keyword stays (the damaged look)")
	tips.free()
	tips = KeywordTips.make("VAN_EX1_393")  # Classic's Amani Berserker: "<b>Enrage:</b> +3 Attack"
	check(tips.find_child("TitleENRAGED", true, false) != null, "Classic's text names it: its box stays")
	tips.free()
	CardDb._cards.erase(RETIRED)


func test_the_witchwood_keyword_boxes() -> void:
	if not _gil():
		return
	var titles := func(id: String) -> Array:
		var tips := KeywordTips.make(id)
		var out := []
		for m in ["RUSH", "ECHO", "TAUNT", "ENRAGED", "START_OF_GAME"]:
			if tips.find_child("Title" + m, true, false):
				out.append(m)
		tips.free()
		return out
	eq(titles.call(RABID), ["RUSH"], "Rush")
	eq(titles.call(PHANTOM), ["ECHO", "TAUNT"], "Echo")
	eq(titles.call(WASP), ["RUSH"], "Redband Wasp: Rush, no Enrage box (its text no longer names it)")
	check(KeywordTips.keywords_of(WASP).has("ENRAGED"), "but it still has the damaged look")
	eq(titles.call("VAN_EX1_393"), [], "Amani Berserker in this pack: no Enrage box either")
	eq(titles.call(BAKU), ["START_OF_GAME"], "Start of Game")
	eq(KeywordTips.name_of("ECHO"), "Echo", "the pack's name")
	_classic()


func test_echo_marks_and_the_ghostly_copy() -> void:
	if not _gil():
		return
	var v := _view({"hero": "HERO_08", "hand": [ANGLER, YETI], "board": [GLINDA]})
	var hand: Array = v.g.players[0].hand
	var angler: CardView = v._views[hand[0].id]
	var yeti: CardView = v._views[hand[1].id]
	check(angler.echo, "an Echo card in the hand has the mark")
	check(hand[1].has("ECHO") and yeti.echo, "a minion in the hand under Glinda Crowskin's aura too (the snapshot's aura tags)")
	eq(yeti.self_modulate, Color.WHITE, "not ghostly")
	v.controller.submit({"type": "play", "player": 0, "entity": hand[0].id, "target": -1, "pos": 1, "choice": -1})
	var copy: GameView.Ent = v.g.players[0].hand.filter(func(e): return e.card_id == ANGLER)[0]
	check(copy.has("GHOSTLY"), "the copy is GHOSTLY")
	var cv: CardView = v._views[copy.id]
	check(cv.echo and cv.self_modulate.a < 1.0, "it looks ghostly: see-through")
	var hist := v.controller.game.history.size()
	v.controller.submit({"type": "end_turn", "player": 0})
	var evs: Array = []
	for i in range(hist, v.controller.game.history.size()):
		evs.append_array(v.controller.game.history[i].events)
	var faded := evs.filter(func(e): return e.type == "faded")
	eq(faded.map(func(e): return e.entity), [copy.id], "it fades at the end of the turn")
	check(not v._views.has(copy.id), "and leaves the hand")
	v.free()
	_classic()


func test_a_rush_minion_looks_ready_and_aims_at_minions_only() -> void:
	if not _gil():
		return
	var v := _view({"hero": "HERO_08", "hand": [RABID]}, {"hero": "HERO_01", "board": [YETI]})
	var rabid: int = v.g.players[0].hand[0].id
	v.controller.submit({"type": "play", "player": 0, "entity": rabid, "target": -1, "pos": 0, "choice": -1})
	var mv: MinionView = v._views[rabid]
	check(mv.s.has("RUSH") and mv.s.has("EXHAUSTED"), "a Rush minion the turn it comes")
	check(not mv._sleeping(), "no sleeping z's")
	check(mv.glow.a > 0.0, "it glows: it can attack")
	eq(v._targets(v._actions_for(rabid).filter(func(a): return a.type == "attack")), [v.g.players[1].board[0].id],
		"its targets: the minion, not the hero")
	v.free()
	_classic()
