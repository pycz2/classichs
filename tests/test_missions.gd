extends TestCase


func test_six_missions_in_original_order() -> void:
	eq(Missions.count(), 6, "six")
	var bosses := range(1, 7).map(func(n): return Missions.get_mission(n).boss)
	eq(bosses, ["TU4a_001", "TU4b_001", "TU4f_001", "TU4c_001", "TU4d_001", "TU4e_001"], "Hogger, Millhouse, Cho, Mukla, Hemet, Illidan")


## A mission's game comes from the engine (`new` with `mission`): its rules are the engine's.
func test_every_mission_builds() -> void:
	var health := [10, 20, 25, 26, 20, 30]
	for n in range(1, 7):
		var m := Match.new()
		eq(m.setup({"mission": n}, [false, true]), "", "mission %d builds" % n)
		var g := m.game
		eq(g.hero(0).card_id, "HERO_08", "Jaina")
		eq(g.hero(1).card_id, Missions.get_mission(n).boss, "boss %d" % n)
		eq(g.current, 0, "Jaina goes first")
		eq(g.phase, "PLAY", "no mulligan")
		var locked: bool = n < 5
		eq(g.players[0].hero_power.has("LOCKED"), locked, "Jaina's power locked in %d" % n)
		eq(g.hero(1).max_health(), health[n - 1], "boss health in mission %d" % n)
		m.free()


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
