extends TestCase


func test_six_missions_in_original_order() -> void:
	eq(Missions.count(), 6, "six")
	var bosses := range(1, 7).map(func(n): return Missions.get_mission(n).boss)
	eq(bosses, ["TU4a_001", "TU4b_001", "TU4f_001", "TU4c_001", "TU4d_001", "TU4e_001"], "Hogger, Millhouse, Cho, Mukla, Hemet, Illidan")


func test_every_mission_builds() -> void:
	for n in range(1, 7):
		var r := Missions.build(n)
		eq(r.error, "", "mission %d builds" % n)
		var g: Game = r.game
		eq(g.hero(0).card_id, "HERO_08", "Jaina")
		eq(g.hero(1).card_id, Missions.get_mission(n).boss, "boss %d" % n)
		eq(g.current, 0, "Jaina goes first")
		eq(g.phase, "PLAY", "no mulligan")
		var locked: bool = n < 5
		eq(g.players[0].hero_power.has("LOCKED"), locked, "Jaina's power locked in %d" % n)
		eq(g.players[1].hero_power.has("LOCKED"), locked, "boss power locked in %d" % n)


func test_boss_health_matches_the_original() -> void:
	var expected := [10, 20, 25, 26, 20, 30]
	for n in range(1, 7):
		eq(Missions.build(n).game.hero(1).max_health(), expected[n - 1], "mission %d" % n)


func test_deck_order_is_scripted() -> void:
	var a: Game = Missions.build(1).game
	var b: Game = Missions.build(1).game
	eq(a.players[0].deck.map(func(e): return e.card_id), b.players[0].deck.map(func(e): return e.card_id), "same order every time")
	eq(a.players[0].deck.back().card_id, Missions.get_mission(1).player_deck[0], "first listed card is drawn first")


func test_progress_saved() -> void:
	Progress.path = "user://test_progress.json"
	DirAccess.remove_absolute(Progress.path)
	eq(Progress.completed(), [], "nothing yet")
	check(Progress.unlocked(1) and not Progress.unlocked(2), "only the first mission")
	Progress.complete(1)
	check(Progress.unlocked(2), "next unlocked")
	eq(Progress.completed(), [1], "saved")
	Progress.complete(1)
	eq(Progress.completed(), [1], "no duplicates")
	DirAccess.remove_absolute(Progress.path)
	Progress.path = Progress.DEFAULT_PATH
