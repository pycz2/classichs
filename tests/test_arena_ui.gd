extends TestCase
## The Arena screen: hero choice, the draft (three cards, the deck list, the mana
## curve, the opponent's progress), the lobby (ready, score, concede, exit).


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## Two connected Arena sessions and a view of the host's. Returns [view, host, guest, transports].
func _setup() -> Array:
	var tr := LoopbackTransport.pair()
	var h := ArenaSession.new()
	var g := ArenaSession.new()
	h.setup(tr[0], true, "Host", 11)
	g.setup(tr[1], false, "Guest", 12)
	h.say_hello()
	g.say_hello()
	LoopbackTransport.pump(tr)
	var v := ArenaView.new()
	v.session = h
	root().add_child(v)
	return [v, h, g, tr]


func _free(p: Array) -> void:
	p[0].free()
	for s in [p[1], p[2]]:
		if s.game and is_instance_valid(s.game.match_):
			s.game.match_.free()
		s.end_game()
	for t in p[3]:
		t.free()
	p[1].free()
	p[2].free()


func _press(v: Control, name: String) -> void:
	var b := v.find_child(name, true, false) as BaseButton
	check(b != null, name + " exists")
	if b:
		b.pressed.emit()


func _offer(v: ArenaView, i: int) -> CardView:
	return v.find_child("Offer%d" % i, true, false) as CardView


func test_hero_choice_then_draft() -> void:
	var p := _setup()
	var v: ArenaView = p[0]
	eq(v.stage, "hero", "the hero comes first")
	var cls := Decks.card_class(p[1].draft.heroes[1])
	_press(v, "Hero_" + cls)
	eq(p[1].draft.hero, p[1].draft.heroes[1], "the hero is taken")
	eq(v.stage, "draft", "then the draft")
	for i in 3:
		check(_offer(v, i) != null, "offer %d shown" % i)
	LoopbackTransport.pump(p[3])
	eq(p[2].remote.hero, true, "the guest sees that a hero is chosen")
	_free(p)


func test_a_pick_goes_to_the_deck_list_and_the_curve() -> void:
	var p := _setup()
	var v: ArenaView = p[0]
	_press(v, "Hero_" + Decks.card_class(p[1].draft.heroes[0]))
	var id := _offer(v, 2).card_id
	_offer(v, 2).clicked.emit(_offer(v, 2))
	eq(p[1].draft.cards, [id] as Array[String], "the card is in the deck")
	check(v.find_child("Entry_" + id, true, false) != null, "and in the list on the right")
	eq((v.find_child("Picks", true, false) as Label).text, "1 / 30", "the count")
	var cost := mini(int(CardDb.card(id).get("cost", 0)), 7)
	eq(v.curve.counts[cost], 1, "the curve has it")
	LoopbackTransport.pump(p[3])
	eq(p[2].remote.cards, 1, "the guest sees 1 card")
	_free(p)


func test_opponent_progress_is_shown() -> void:
	var p := _setup()
	var v: ArenaView = p[0]
	var status := v.find_child("OpponentStatus", true, false) as Label
	eq(status.text, "Choosing a hero", "at first")
	p[2].draft.choose_hero(0)
	for i in 5:
		p[2].draft.pick(0)
	p[2].send_status()
	LoopbackTransport.pump(p[3])
	eq(status.text, "Drafting: 5 / 30 cards", "while drafting")
	_free(p)


func _full_draft(v: ArenaView, s: ArenaSession) -> void:
	_press(v, "Hero_" + Decks.card_class(s.draft.heroes[0]))
	while not s.draft.done():
		_offer(v, 0).clicked.emit(_offer(v, 0))


func test_lobby_ready_starts_the_game() -> void:
	var p := _setup()
	var v: ArenaView = p[0]
	_full_draft(v, p[1])
	eq(v.stage, "lobby", "the lobby after 30 cards")
	var started := []
	v.play.connect(func(s, m): started.append(m))
	_press(v, "Ready")
	check((v.find_child("Ready", true, false) as Button).disabled, "waiting for the opponent")
	p[2].draft.choose_hero(0)
	while not p[2].draft.done():
		p[2].draft.pick(0)
	p[2].set_ready()
	LoopbackTransport.pump(p[3])
	eq(started.size(), 1, "the game starts")
	_free(p)


func test_concede_and_exit() -> void:
	var p := _setup()
	var v: ArenaView = p[0]
	_full_draft(v, p[1])
	_press(v, "ConcedeArena")
	_press(v, "ConfirmConcedeArena")
	check(p[1].over, "the Arena is over")
	eq((v.find_child("ArenaResult", true, false) as Label).text, "You lost the Arena", "the result")
	var left := []
	v.exit.connect(func(): left.append(true))
	_press(v, "ExitArena")
	eq(left.size(), 1, "exit to the menu")
	_free(p)


func test_score_and_win_are_shown() -> void:
	var p := _setup()
	var v: ArenaView = p[0]
	_full_draft(v, p[1])
	p[1].record(0)
	eq((v.find_child("Score", true, false) as Label).text, "1 : 0", "the score")
	p[1].record(0)
	p[1].record(0)
	eq((v.find_child("ArenaResult", true, false) as Label).text, "You won the Arena!", "three wins")
	_free(p)


func test_main_runs_an_arena_game_and_comes_back() -> void:
	var p := _setup()
	p[0].free()
	var m: Node = load("res://ui/main.tscn").instantiate()
	root().add_child(m)
	var a: ArenaView = m.show_arena(p[1])
	check(m.screen is ArenaView, "the Arena screen")
	_full_draft(a, p[1])
	p[2].draft.choose_hero(0)
	while not p[2].draft.done():
		p[2].draft.pick(0)
	p[1].set_ready()
	p[2].set_ready()
	LoopbackTransport.pump(p[3])
	check(m.screen is MatchView, "the game is on")
	var v: MatchView = m.screen
	check(v.arena == p[1], "an Arena game")
	var guest_match: Match = p[2].game.match_
	guest_match.submit({"type": "concede", "player": guest_match.viewer()})
	LoopbackTransport.pump(p[3])
	v.refresh()
	eq(p[1].score, [1, 0], "the host won game 1")
	var line := v.find_child("ArenaScore", true, false) as Label
	check(line != null and line.text.contains("1 : 0"), "the score on the result: " + (line.text if line else "none"))
	check(v.find_child("BackToMenu", true, false) == null, "no way to the menu from here")
	(v.find_child("BackToArena", true, false) as Button).pressed.emit()
	check(m.screen is ArenaView, "back in the Arena")
	eq((m.screen.find_child("Score", true, false) as Label).text, "1 : 0", "the lobby shows the score")
	check(p[1].game == null, "the game is closed")
	check(p[1].connected and p[1].failure == "", "the connection is still there")
	m.free()  # the host's session and connection went with it
	if p[2].game and is_instance_valid(p[2].game.match_):
		p[2].game.match_.free()
	p[2].end_game()
	p[3][1].free()
	p[2].free()
