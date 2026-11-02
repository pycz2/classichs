extends TestCase
## The tutorial lives in its pack (tutorial.json, locales "tutorial" / "missions" / "hints",
## docs/packs/format.md §12): Classic has one, Neonfall none; scene effects by name.


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
	Packs.set_active(_pack("neon"))
	check(not Packs.active().has_tutorial(), "Neonfall has no tutorial")
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
	Packs.set_active(_pack(Packs.CLASSIC))
	check(Packs.active().has_tutorial(), "back to Classic")


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
