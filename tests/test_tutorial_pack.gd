extends TestCase
## The tutorial lives in its pack (tutorial.json, locales "tutorial" / "missions" / "hints",
## docs/packs/format.md §12): Classic and Neonfall have one each, a pack without tutorial.json none;
## scene effects by name.


func _pack(id: String) -> Pack:
	for p: Pack in Packs.all():
		if p.id() == id:
			return p
	return null


func test_classic_tutorial_comes_from_its_pack() -> void:
	var p := Packs.active()
	eq(p.id(), Packs.CLASSIC, "Classic is active")
	check(p.has_tutorial(), "Classic has a tutorial")
	eq(Missions.ids(), [1, 2, 3, 4, 5, 6], "six missions in order")
	eq(Missions.next(1), 2, "1 -> 2")
	eq(Missions.next(6), 0, "6 is the last")
	eq(Missions.get_mission(1).intro, p.text(["missions", "1", "intro"], "en"), "the intro is the pack's text")
	Locale.set_language("ru")
	var intro := TutorialIntro.make(1)
	var page: Dictionary = intro.panels()[0]
	eq(page.title, p.locale("ru").tutorial["minion_card.title"], "a page title in Russian from the pack")
	check(page.title != p.locale("en").tutorial["minion_card.title"], "translated")
	eq(Missions.get_mission(1).lines.start, p.locale("ru").missions["1"].lines.start, "boss line in Russian")
	intro.free()
	Locale.set_language("en")


func test_note_arrows_stop_at_the_card_parts() -> void:
	var intro := TutorialIntro.make(1)
	var note: Dictionary = intro.panels()[0].items[1]  # "Mana cost" -> the cost gem of the card at (520, 150), scale 2
	var want := TutorialIntro.part(Vector2(520, 150), 2.0, "cost", note.box.get_center(), 36.0)
	check(note.to.distance_to(want) < 0.01, "arrow to the gem's edge: %s" % str(note.to))
	intro.free()


func test_a_pack_without_a_tutorial_shows_none() -> void:
	var neon := _pack("neon")
	neon._json["tutorial.json"] = null  # as if Neonfall had no tutorial.json
	Packs.set_active(neon)
	check(not Packs.active().has_tutorial(), "no tutorial")
	eq(Missions.count(), 0, "no missions")
	check(not Progress.unlocked(1), "nothing to open")
	var m: Node = load("res://ui/main.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(m)
	(m.screen.find_child("Play", true, false) as Button).pressed.emit()
	check(m.screen.find_child("Tutorial", true, false) == null, "no Tutorial in the Play menu")
	m.free()
	var t := TutorialView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(t)
	check(t.find_child("Mission1", true, false) == null, "an empty list")
	t.free()
	neon._json.erase("tutorial.json")
	Packs.set_active(_pack(Packs.CLASSIC))
	check(Packs.active().has_tutorial(), "back to Classic")


## Neonfall's own tutorial (packs/neon/tutorial.json): six missions, its champions, its bosses.
func test_neonfall_has_a_tutorial() -> void:
	Packs.set_active(_pack("neon"))
	check(Packs.active().has_tutorial(), "Neonfall has a tutorial")
	eq(Missions.ids(), [1, 2, 3, 4, 5, 6], "six missions in order")
	var bosses := Missions.ids().map(func(n): return Missions.get_mission(n).boss)
	eq(bosses, ["boss_brick", "boss_sharkey", "boss_mira", "boss_varga", "boss_archon", "director_vale"], "its bosses")
	eq(Missions.get_mission(1).pages.size(), 3, "three intro pages before mission 1")
	var t := TutorialView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(t)
	check(t.find_child("Mission6", true, false) != null, "the list shows its missions")
	t.free()
	Packs.set_active(_pack(Packs.CLASSIC))


## Its missions are the engine's games: the mission's champion, boss and rules.
func test_neonfall_missions_build() -> void:
	Packs.set_active(_pack("neon"))
	var heroes := ["mother_rust", "iris_null", "director_vale", "mother_rust", "iris_null", "mother_rust"]
	var health := [10, 20, 25, 26, 20, 30]
	for n in range(1, 7):
		var m := Match.new()
		eq(m.setup({"mission": n}, [false, true]), "", "mission %d builds" % n)
		var g := m.game
		eq(g.hero(0).card_id, heroes[n - 1], "the player's champion in %d" % n)
		eq(g.hero(1).card_id, Missions.get_mission(n).boss, "boss %d" % n)
		eq(g.hero(1).max_health(), health[n - 1], "boss health in %d" % n)
		eq(g.phase, "PLAY", "no mulligan")
		eq(g.players[0].hero_power.has("LOCKED"), n < 5, "powers locked until mission 5 (%d)" % n)
		m.free()
	Packs.set_active(_pack(Packs.CLASSIC))


## Mission 1 played by a fixed line: attack the boss with every minion, play what can be played,
## end the turn. The rules of the mission keep the turn open while a card can be played.
func test_neonfall_mission_1_is_won_by_a_line_of_play() -> void:
	Packs.set_active(_pack("neon"))
	var m := Match.new()
	m.bot_delay = 0.0
	eq(m.setup({"mission": 1}, [false, true]), "", "builds")
	check(m.end_turn_block(0) != "", "the turn can't end while Hound Shard can be played")
	var g := m.game
	for step in 200:
		if g.game_over:
			break
		var mine: Array = m.legal().filter(func(a): return a.player == 0)
		var act: Dictionary = {}
		for a in mine:
			if a.type == "attack" and a.defender == g.hero(1).id:
				act = a
				break
		if act.is_empty():
			for a in mine:
				if a.type in ["attack", "play"]:
					act = a
					break
		if act.is_empty():
			act = {"type": "end_turn", "player": 0}
		check(m.submit(act).ok, "move %d" % step)
	check(g.game_over and g.winner == 0, "Brick is beaten (turn %d)" % g.turn)
	m.free()
	Packs.set_active(_pack(Packs.CLASSIC))


## Every text the tutorial shows is written in each of the pack's languages (not the English fallback).
func test_neonfall_tutorial_in_every_language() -> void:
	var p := _pack("neon")
	var t := p.tutorial()
	var keys := []
	for ms in t.missions:
		for page in ms.get("intro", []):
			keys.append_array([page.title, page.text])
			for it in page.items:
				if it.has("note"):
					keys.append(it.note)
	eq(p.manifest.locales.size(), 8, "eight languages")
	for lang in p.manifest.locales:
		var loc := p.locale(lang)
		for k in keys:
			check(str(loc.get("tutorial", {}).get(k, "")) != "", "%s: tutorial.%s" % [lang, k])
		for ms in t.missions:
			var n := str(int(ms.id))
			var m: Dictionary = loc.get("missions", {}).get(n, {})
			check(str(m.get("intro", "")) != "" and str(m.get("reward_line", "")) != "", "%s: mission %s" % [lang, n])
			for k in ["start", "hurt", "defeat"]:
				check(str(m.get("lines", {}).get(k, "")) != "", "%s: mission %s line %s" % [lang, n, k])
			var mission: Dictionary = p.json("missions/%s.json" % n)
			check(str(loc.get("cards", {}).get(mission.boss, {}).get("name", "")) != "", "%s: boss %s" % [lang, mission.boss])
			for h in mission.hints:
				check(str(loc.get("hints", {}).get(h, "")) != "", "%s: hint %s" % [lang, h])


func test_scene_effects_by_name() -> void:
	for name in SceneFx.NAMES:
		var fx := SceneFx.make(name)
		check(fx is CPUParticles2D, name)
		fx.free()
	var base := SceneFx.make("snow")
	var more := SceneFx.make({"effect": "snow", "intensity": 2.0})
	eq(more.amount, base.amount * 2, "intensity scales the amount")
	var red := SceneFx.make({"effect": "embers", "colors": ["ff0000"]})
	check(red.color_ramp.get_color(1).r > 0.99 and red.color_ramp.get_color(1).g < 0.01, "the pack's colours")
	for none in ["none", "fog", null, {}]:
		eq(SceneFx.make(none), null, "no effect for %s" % str(none))
	for p in [base, more, red]:
		p.free()
