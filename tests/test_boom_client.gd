extends TestCase
## The Boomsday Project on the client: Magnetic (its keyword box; a Magnetic minion held left of a Mech lights that
## Mech; played there it flies into it, never landing, and the Mech gets its numbers and keywords), Whizbang the
## Wonderful (a deck of that card alone: the deck builder, the start of the game, its history line), Dr. Boom's
## changing Hero Power, the Bomb shuffled into the opponent's deck and going off when drawn, and the set's name and
## mark. The pack is built from packs/boom (tools/pack.py) and installed into this run's user dir; the tests that
## need it make it the active pack and give Classic back at their end.

const YETI := "VAN_CS2_182"
const GOLEM := "VAN_EX1_556"  # Harvest Golem: a 2/3 Mech
const ANNOY := "BOT_911"  # Annoy-o-Module: Magnetic, Divine Shield, Taunt, 2/4
const WHIZBANG := "BOT_914"
const BOMBER := "BOT_511"  # Seaforium Bomber
const BOMB := "BOT_511t"
const BOOM_POWER := "BOT_238p1"
const STORE := "user://test_boom_decks.json"

static var _pack: Pack


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _boom() -> bool:
	# Built once per process; installed again for each test (each test starts with the built-in packs only).
	if _pack == null or not Packs.all().has(_pack):
		var out := OS.get_user_data_dir() + "/boom_test.cardpack"
		if not FileAccess.file_exists(out):
			var log := []
			var code := OS.execute("python3", [ProjectSettings.globalize_path("res://tools/pack.py"), "build",
				ProjectSettings.globalize_path("res://packs/boom"), "-o", out], log, true)
			if code != 0:
				check(false, "packs/boom builds: " + "".join(log).right(600))
				return false
		var r := Packs.install_file(out)
		if r.has("error"):
			check(false, "packs/boom installs: " + str(r.error))
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


func test_magnetic_has_its_keyword_box() -> void:
	if not _boom():
		return
	var tips := KeywordTips.make(ANNOY)
	check(tips.find_child("TitleMODULAR", true, false) != null, "the Magnetic box")
	check(tips.find_child("TitleTAUNT", true, false) != null, "and its other keywords'")
	tips.free()
	eq(KeywordTips.name_of("MODULAR"), "Magnetic", "the pack's name")
	_classic()


## Annoy-o-Module played at place 0 of a board with a Harvest Golem, applied without the table seeing it.
func _fuse_batch(v: MatchView) -> Dictionary:
	var m := v.controller
	var annoy: GameView.Ent = m.game.players[0].hand[0]
	var r := m._apply({"type": "play", "player": 0, "entity": annoy.id, "target": -1, "pos": 0, "choice": -1})
	check(r.ok, "played")
	return {"events": r.events, "snap": m.game.snapshot, "hist": m.game.history.size()}


func test_a_magnetic_minion_held_left_of_a_mech_lights_it() -> void:
	if not _boom():
		return
	var v := _view({"hero": "HERO_08", "hand": [ANNOY, YETI], "board": [GOLEM, YETI]})
	var annoy: GameView.Ent = v.g.players[0].hand[0]
	var golem: int = v.g.players[0].board[0].id
	check(annoy.has("MODULAR"), "the card has the keyword (the engine's FUSE)")
	eq(v._fuse_host(annoy, 0), golem, "left of the Mech: it fuses")
	eq(v._fuse_host(annoy, 1), -1, "left of the Yeti: no")
	eq(v._fuse_host(annoy, 2), -1, "at the end: no")
	eq(v._fuse_host(v.g.players[0].hand[1], 0), -1, "a Yeti does not fuse")
	v._sel = {"id": annoy.id, "actions": v._actions_for(annoy.id)}
	v._gap = 0
	v._apply_glows()
	eq(v._views[golem].glow, Palette.COMBO, "the Mech lights up")
	v._gap = 1
	v._apply_glows()
	check(v._views[golem].glow != Palette.COMBO, "not when held elsewhere")
	v._sel = {}
	v._gap = -1
	v.free()
	_classic()


func test_a_magnetic_minion_flies_into_the_mech() -> void:
	if not _boom():
		return
	var v := _view({"hero": "HERO_08", "hand": [ANNOY], "board": [GOLEM]})
	var annoy: int = v.g.players[0].hand[0].id
	var golem: int = v.g.players[0].board[0].id
	var item := _fuse_batch(v)
	var steps := MatchView.steps(item.events)
	check(_kinds(steps).has("fuse") and not _kinds(steps).has("summon"), "played, then fused, never summoned: %s" % [_kinds(steps)])
	v._begin_batch(item)
	for st in steps:
		v._play_step(st)
		if st.k == "play":
			check(v._flying.has(annoy), "the card shows big")
	check(not v._flying.has(annoy) and not v._views.has(annoy), "it went into the Mech: no card, no minion")
	var mv: MinionView = v._views[golem]
	eq([mv.s.atk(), mv.s.health()], [4, 7], "the Mech has its numbers before the batch ends")
	check(mv.s.has("TAUNT") and mv.s.has("DIVINE_SHIELD"), "and its keywords")
	v._end_batch()
	eq(v.g.players[0].board.map(func(e): return e.id), [golem], "one minion on the board")
	eq(v._views[golem].s.atk(), 4, "the game agrees")
	var changes := KeywordTips.changes(v.g.ent(golem))
	check(changes.has("+2/+4"), "its Changes box: %s" % [changes])
	eq(_rows(v.g, item.events.filter(func(e): return e.type == "play"), 0), ["You play Annoy-o-Module"], "a play line")
	v.free()
	_classic()


func test_a_magnetic_minion_put_down_by_the_player_leaves_its_place() -> void:
	if not _boom():
		return
	var v := _view({"hero": "HERO_08", "hand": [ANNOY], "board": [GOLEM]})
	var annoy: int = v.g.players[0].hand[0].id
	var golem: int = v.g.players[0].board[0].id
	v._placed[annoy] = 0  # (dropped while the table was busy: it stands where it was put)
	var item := _fuse_batch(v)
	v._begin_batch(item)
	var steps := MatchView.steps(item.events)
	v._play_step(steps[0])
	check(v._views.has(annoy) and v._views[annoy] is MinionView, "it stands in its place after the play step")
	for st in steps.slice(1):
		v._play_step(st)
	check(not v._views.has(annoy) and v._placed.is_empty(), "the fuse takes it from its place")
	v._end_batch()
	eq(v._views[golem].s.health(), 7, "into the Mech")
	v.free()
	_classic()


func test_whizbang_is_a_whole_deck_in_the_deck_builder() -> void:
	if not _boom():
		return
	DeckStore.path = STORE
	DeckStore.save_all([])
	var v := DeckListView.new()
	root().add_child(v)
	var d := v.new_deck("HERO_08")
	var c := v.browser
	c.click_card(YETI)
	var asked := []
	c.whole_deck.connect(func(id): asked.append(id))
	c.click_card(WHIZBANG)
	eq(asked, [WHIZBANG], "a deck with other cards: it asks")
	eq(d.cards, [YETI] as Array[String], "nothing changed yet")
	check(v.find_child("ConfirmWholeDeck", true, false) != null, "the question")
	(v.find_child("ConfirmWholeDeck", true, false) as Button).pressed.emit()
	eq(d.cards, [WHIZBANG] as Array[String], "Whizbang takes their place")
	eq(d.goal(), 1, "the deck is complete with one card")
	eq(d.validate(), "", "legal")
	eq(v._count.text, "1 / 1", "the counter")
	c.click_card(YETI)
	eq(d.cards.size(), 1, "nothing goes with it")
	eq(c._hint.text, "This card is a whole deck: it goes alone", "and why")
	check(Rules.MESSAGES.has(c._hint.text), "a translated engine message")
	v.remove_card(WHIZBANG)
	eq(d.goal(), Deck.SIZE, "an empty deck: 30 again")
	eq(d.add(WHIZBANG), "", "Whizbang into an empty deck")
	v.free()
	DirAccess.remove_absolute(STORE)
	DeckStore.path = DeckStore.DEFAULT_PATH
	_classic()


func test_whizbang_shows_as_the_game_starts() -> void:
	if not _boom():
		return
	var m := H.decks({"hero": "HERO_08", "cards": [WHIZBANG]}, "WARRIOR")
	var start: Array = m.game.history[0].events.filter(func(e): return e.type == "deck_recipe")
	eq(start.size(), 1, "the engine logs the recipe")
	eq([start[0].player, start[0].card, start[0].hero], [0, WHIZBANG, m.game.hero(0).id], "Whizbang, the new hero")
	eq(m.game.players[0].deck_count + m.game.players[0].hand.size(), 30, "a whole deck of 30")
	eq(_rows(m.game, start, 0), ["Whizbang the Wonderful picks one of its decks for you"], "the history line")
	eq(_rows(m.game, start, 1), ["Whizbang the Wonderful picks one of its decks for Opponent"], "the opponent's")
	var was := Anim.instant
	Anim.instant = false
	var v := MatchView.new()
	root().add_child(v)
	v.bind(m)
	var cv := v._fx.find_child("Recipe0", true, false)
	Anim.instant = was
	check(cv is CardView and (cv as CardView).card_id == WHIZBANG, "its card shows")
	check(v._fx.find_child("Recipe1", true, false) == null, "the other player has none")
	v.free()
	_classic()


func test_dr_boom_power_and_the_bomb() -> void:
	if not _boom():
		return
	var v := _view({"hero": "HERO_08", "board": [BOMBER]})
	var bomber: int = v.g.players[0].board[0].id
	var power: int = v.g.players[0].hero_power.id
	var changed := [{"type": "hero_power_changed", "player": 0, "entity": power, "card": BOOM_POWER}]
	eq(_kinds(MatchView.steps(changed)), ["power_changed"], "Dr. Boom's new power each turn: its own step")
	eq(_rows(v.g, changed, 1), ["Opponent's Hero Power becomes " + CardText.name(BOOM_POWER, "en")], "and line")
	var shuffled := [{"type": "add_to_deck", "player": 1, "entity": 300, "card": "", "by": BOMBER, "by_id": bomber}]
	var steps := MatchView.steps(shuffled)
	eq(_kinds(steps), ["shuffle"], "the Bomb flies")
	var at := v._center_of(bomber)
	v._begin_batch({"events": shuffled, "snap": v.controller.game.snapshot, "hist": v.controller.game.history.size()})
	var plan := v._shuffle_plan(steps[0])
	eq([plan[0].from, plan[0].to, plan[0].card], [at, v._pile_center(1), ""], "from the Bomber into the opponent's deck, as the view shows it")
	v._end_batch()
	var drawn := [{"type": "draw", "player": 1, "entity": 300, "card": BOMB}, {"type": "cast_when_drawn", "player": 1, "entity": 300, "card": BOMB},
		{"type": "damage", "target": v.g.hero(1).id, "amount": 5, "source": 300, "by": BOMB, "by_id": 300}]
	eq(_kinds(MatchView.steps(drawn)), ["topdeck", "hit"], "drawn, it goes off")
	eq(_rows(v.g, drawn.slice(0, 2), 0), ["Opponent draws " + CardText.name(BOMB, "en") + ": it casts itself"], "the line")
	v.free()
	_classic()


func test_seaforium_bomber_shuffles_a_bomb_from_itself() -> void:
	if not _boom():
		return
	var v := _view({"hero": "HERO_08", "hand": [BOMBER]}, {"hero": "HERO_01", "deck": [YETI, YETI]})
	var m := v.controller
	var card: int = m.game.players[0].hand[0].id
	var r := m._apply({"type": "play", "player": 0, "entity": card, "target": -1, "pos": 0, "choice": -1})
	check(r.ok, "played")
	var item := {"events": r.events, "snap": m.game.snapshot, "hist": m.game.history.size()}
	var steps := MatchView.steps(r.events)
	var k := _kinds(steps).find("shuffle")
	check(k > _kinds(steps).find("summon"), "the Bomb flies after the Bomber lands: %s" % [_kinds(steps)])
	v._begin_batch(item)
	for st in steps.slice(0, k):
		v._play_step(st)
	var plan := v._shuffle_plan(steps[k])
	eq([plan[0].from, plan[0].to], [v._center_of(card), v._pile_center(1)], "from the Bomber into the opponent's deck")
	v._play_step(steps[k])
	v._end_batch()
	eq(v.g.players[1].deck_count, 3, "the Bomb is in")
	v.free()
	_classic()


func test_the_set_has_its_name_and_mark() -> void:
	if not _boom():
		return
	check(CollectionView.set_keys().has("BOOMSDAY"), "the set filter lists it")
	eq(CardText.term("sets", "BOOMSDAY"), "The Boomsday Project", "its name")
	check(Packs.set_mark("BOOMSDAY") != null, "its mark")
	eq(CardText.set_key(ANNOY), "BOOMSDAY", "a card of it")
	_classic()
