extends TestCase


func test_random_games() -> void:
	var n := int(OS.get_environment("SIM_GAMES")) if OS.has_environment("SIM_GAMES") else 20
	for seed in n:
		var res := Sim.play_random(seed + 1)
		check(not res.actions.is_empty(), "seed %d made no moves" % (seed + 1))


func test_replay_gives_same_hashes() -> void:
	for seed in [7, 42, 1234]:
		var res := Sim.play_random(seed)
		var g0: Game = res.game
		var p0 := g0.players[0]
		var p1 := g0.players[1]
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var heroes := Sim.CLASSES.keys()
		var h0: String = heroes[rng.randi_range(0, 8)]
		var h1: String = heroes[rng.randi_range(0, 8)]
		var g := Game.new({"hero": h0, "deck": Sim.random_deck(rng, Sim.CLASSES[h0])},
			{"hero": h1, "deck": Sim.random_deck(rng, Sim.CLASSES[h1])}, seed)
		for i in res.actions.size():
			var r := g.apply(res.actions[i])
			check(r.ok, "replay step %d failed: %s" % [i, r.error])
			if g.state_hash() != res.hashes[i]:
				failures.append("seed %d: hash differs at step %d" % [seed, i])
				break
		eq(p0.hero.card_id, g.players[0].hero.card_id, "same heroes")
		eq(p1.hero.card_id, g.players[1].hero.card_id, "same heroes")
