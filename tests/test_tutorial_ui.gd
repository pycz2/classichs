extends TestCase


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _store() -> void:
	Progress.path = "user://test_progress_ui.json"
	DirAccess.remove_absolute(Progress.path)


func _restore() -> void:
	DirAccess.remove_absolute(Progress.path)
	Progress.path = Progress.DEFAULT_PATH


func _view(n: int) -> MatchView:
	var r := Tutorial.start(n)
	var v := MatchView.new()
	v.tutorial = r.tutorial
	root().add_child(v)
	var m := Match.new()
	m.bot_delay = 0.0
	m.setup(r.game, [false, true])
	v.bind(m)
	return v


func test_mission_list_unlocks() -> void:
	_store()
	var t := TutorialView.new()
	root().add_child(t)
	check(not (t.find_child("Mission1", true, false) as Button).disabled, "1 open")
	check((t.find_child("Mission2", true, false) as Button).disabled, "2 locked")
	t.free()
	Progress.complete(1)
	t = TutorialView.new()
	root().add_child(t)
	check(not (t.find_child("Mission2", true, false) as Button).disabled, "2 open after winning 1")
	t.free()
	_restore()


func test_mission_tiles_have_portraits() -> void:
	_store()
	var t := TutorialView.new()
	root().add_child(t)
	for n in range(1, Missions.count() + 1):
		var b := t.find_child("Mission%d" % n, true, false) as Button
		check(b != null, "tile %d" % n)
		check(b.find_child("Picture", true, false) != null, "tile %d has a picture" % n)
		check(Art.texture(Missions.get_mission(n).boss) != null, "boss %d has a portrait" % n)
	eq((t.find_child("Mission1", true, false).find_child("Status", true, false) as Label).text,
		str(TranslationServer.translate("Up next")), "mission 1 is next")
	eq((t.find_child("Mission2", true, false).find_child("Status", true, false) as Label).text,
		str(TranslationServer.translate("Locked")), "mission 2 locked")
	t.free()
	_restore()


func test_locked_mission_does_not_start() -> void:
	_store()
	var t := TutorialView.new()
	root().add_child(t)
	var started := []
	t.start.connect(func(n): started.append(n))
	(t.find_child("Mission2", true, false) as Button).pressed.emit()
	check(t.find_child("Intro", true, false) == null, "no intro for a locked mission")
	eq(started, [], "nothing started")
	t.free()
	_restore()


func test_mission_intro_then_start() -> void:
	_store()
	var t := TutorialView.new()
	root().add_child(t)
	var started := []
	t.start.connect(func(n): started.append(n))
	(t.find_child("Mission1", true, false) as Button).pressed.emit()
	var intro := t.find_child("Intro", true, false) as TutorialIntro
	check(intro != null and intro.number == 1, "mission 1's intro shown")
	eq(started, [], "not started before the intro is read")
	var next := intro.find_child("Next", true, false) as Button
	for i in intro.panels().size() - 1:
		next.pressed.emit()
	eq(next.text, str(TranslationServer.translate("Play")), "last panel: Play")
	next.pressed.emit()
	eq(started, [1], "the intro's end starts the mission")
	t.free()
	_restore()


func test_intro_skip_and_back() -> void:
	var t := TutorialView.new()
	root().add_child(t)
	var started := []
	t.start.connect(func(n): started.append(n))
	var intro := t.show_intro(3)
	(intro.find_child("Skip", true, false) as Button).pressed.emit()
	eq(started, [3], "skip starts the mission")
	intro = t.show_intro(2)
	(intro.find_child("Back", true, false) as Button).pressed.emit()
	check(intro.is_queued_for_deletion(), "back closes the intro")
	eq(started, [3], "back starts nothing")
	t.free()


func test_every_mission_has_intro_panels() -> void:
	for n in range(1, Missions.count() + 1):
		var intro := TutorialIntro.make(n)
		var panels := intro.panels()
		check(panels.size() >= 1, "mission %d has panels" % n)
		for p in panels:
			check(p.title != "" and p.text != "", "mission %d: titled and explained" % n)
			check(p.items.any(func(it): return it.has("card") or it.has("hero")), "mission %d: a picture" % n)
			for it in p.items:
				if it.has("card"):
					check(not CardDb.card(it.card).is_empty(), "real card " + it.card)
		intro.free()


func test_intro_hint_and_boss_line() -> void:
	var v := _view(1)
	eq(v._hint.text, Missions.get_mission(1).intro, "intro shown")
	check(v.bubble_text(1).contains("Hogger"), "boss speaks: " + v.bubble_text(1))
	v.free()


func test_end_turn_blocked_with_hint() -> void:
	var v := _view(1)
	(v.find_child("EndTurn", true, false) as Button).pressed.emit()
	eq(v.g.current, 0, "turn not ended")
	check(v._hint.text.begins_with("Not yet"), v._hint.text)
	v.free()


func test_locked_power_hidden_and_no_emotes() -> void:
	var v := _view(1)
	check(not v._views.has(v.g.players[0].hero_power.id), "Jaina's locked power not shown")
	check(not v._views.has(v.g.players[1].hero_power.id), "boss power not shown")
	check(not v.emotes_allowed(), "emotes off")
	v.free()
	var v5 := _view(5)
	check(v5._views.has(v5.g.players[0].hero_power.id), "mission 5: Fireblast shown")
	v5.free()


func test_win_shows_reward_and_saves_progress() -> void:
	_store()
	var v := _view(1)
	v.g.damage(v.g.hero(0), v.g.hero(1), 10)
	v.g.resolve()
	v.refresh()
	var ov := v.find_child("GameOver", true, false)
	check(ov != null, "game over overlay")
	var cards := ov.find_children("*", "CardView", true, false)
	check(cards.size() == 1 and cards[0].card_id == "VAN_CS2_023", "reward card shown")
	check(ov.find_child("NextMission", true, false) != null, "next mission button")
	eq(Progress.completed(), [1], "progress saved")
	var next := []
	v.tutorial_next.connect(func(n): next.append(n))
	(ov.find_child("NextMission", true, false) as Button).pressed.emit()
	var intros := v.find_children("*", "TutorialIntro", true, false)
	check(intros.size() == 1 and intros[0].number == 2, "mission 2's intro first")
	eq(next, [], "not started yet")
	(intros[0].find_child("Skip", true, false) as Button).pressed.emit()
	eq(next, [2], "then mission 2")
	v.free()
	_restore()


func test_boss_bubble_is_wide_and_boss_is_named() -> void:
	var v := _view(1)
	var bubble: Control = v._bubbles[1]
	check(bubble.get_combined_minimum_size().x > 150, "readable width: %s" % str(bubble.get_combined_minimum_size()))
	check(v._names[1].text.begins_with("Hogger"), v._names[1].text)
	v.free()



func test_hints_wait_their_turn() -> void:
	var v := _view(4)
	eq(v._hint.text, Missions.get_mission(4).intro, "intro first")
	v._process(8.0)  # the intro has been read
	var tooltip := str(TranslationServer.translate(Tutorial.HINTS.tooltip))
	eq(v._hint.text, tooltip, "next hint after the intro")
	v.click_entity(v.g.players[0].hand[0].id)  # Goldshire Footman
	v.click_board(0)
	eq(v._hint.text, tooltip, "not overwritten by the next hint at once")
	v.free()


func test_tutorial_hint_does_not_replace_target_prompt() -> void:
	var v := _view(3)
	v._process(8.0)
	v._process(8.0)
	v.click_entity(v.g.players[0].hand[0].id)  # Voodoo Doctor: battlecry with a target
	if v._sel.get("stage", "") == "position":
		v.click_board(0)
	check(v._hint.text == str(TranslationServer.translate("Choose a target")) or v._sel.is_empty(), "prompt kept: " + v._hint.text)
	v.free()


func test_no_mute_in_tutorial_and_done_marker_is_text() -> void:
	var v := _view(1)
	check(not (v.find_child("MuteButton", true, false) as Button).visible, "no mute")
	v.free()
	_store()
	Progress.complete(1)
	var t := TutorialView.new()
	root().add_child(t)
	check(not (t.find_child("Mission1", true, false) as Button).text.contains("✓"), "no special glyph")
	t.free()
	_restore()
