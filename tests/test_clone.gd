extends TestCase


func test_clone_matches_original_after_same_action() -> void:
	var res := Sim.play_random(17, 60)
	var g: Game = res.game
	var c := g.clone()
	eq(c.state_hash(), g.state_hash(), "same state")
	var a: Dictionary = g.legal_actions().filter(func(x): return x.type != "concede")[0]
	check(g.apply(a).ok and c.apply(a).ok, "both apply")
	eq(c.state_hash(), g.state_hash(), "same state after the same action")


func test_clone_is_independent() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	var before := g.state_hash()
	var c := g.clone()
	c.damage(c.hero(1), c.ent(w.id), 5)
	c.resolve()
	c.players[0].mana = 0
	eq(g.state_hash(), before, "original untouched")
	eq(w.zone, "PLAY", "original minion alive")


func test_clone_keeps_rng_sequence() -> void:
	var g := H.game(9)
	g.rng.randi()
	var c := g.clone()
	eq(c.rng.randi(), g.rng.randi(), "same next random number")


func test_clone_is_a_game() -> void:
	var c := H.game().clone()
	check(c is Game, "Game subclass")
	check(not c.legal_actions().is_empty(), "playable")
