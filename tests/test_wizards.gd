extends TestCase
## The step-by-step Training and Online setup screens.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _press(parent: Node, button_name: String) -> void:
	var b := parent.find_child(button_name, true, false) as Button
	check(b != null and b.is_visible_in_tree(), button_name + " shown")
	if b:
		b.pressed.emit()


func test_deck_chooser_lists_decks_and_buttons() -> void:
	var c := DeckChooser.new()
	root().add_child(c)
	eq(c.rows.size(), TrainingSetup.available_decks().size(), "a tile per deck")
	var got := []
	c.chosen.connect(func(d): got.append(d))
	c.edit_decks.connect(func(): got.append("edit"))
	c.back.connect(func(): got.append("back"))
	c.rows[0].pressed.emit()
	_press(c, "EditDecks")
	_press(c, "Back")
	eq(got, [c.decks[0], "edit", "back"], "chosen at once, edit, back")
	c.free()


func test_training_steps() -> void:
	var t := TrainingSetup.new()
	root().add_child(t)
	var got := []
	t.start.connect(func(d, bot): got.append([d, bot]))
	t.back.connect(func(): got.append("back"))
	t.edit_decks.connect(func(): got.append("edit"))
	eq(t.step, 1, "starts on the deck")
	var mage: Deck = t.chooser.decks.filter(func(d): return d.hero == Decks.hero("MAGE"))[0]
	t.chooser.pick(mage)
	eq(t.step, 2, "a deck goes on to the opponent")
	check(t.find_child("DeckChooser", true, false).is_visible_in_tree() == false, "deck list hidden")
	var grid := t.find_child("Opponents", true, false)
	eq(grid.get_child_count(), 9, "nine opponents")
	check(grid.get_child(0) is TrainingSetup.HeroTile, "hero tiles")
	(t.find_child("bot_PRIEST", true, false) as Button).button_pressed = true
	_press(t.find_child("Step2", true, false), "Back")
	eq(t.step, 1, "Back returns to the deck")
	eq(got, [], "nothing emitted yet")
	t.chooser.pick(mage)
	_press(t, "Play")
	eq(got, [[mage, "PRIEST"]], "Play starts with the deck and the chosen class")
	_press(t.find_child("Step2", true, false), "Back")
	t.chooser.edit_decks.emit()
	t.chooser.back.emit()
	eq(got.slice(1), ["edit", "back"], "edit decks and Back on the first step")
	t.free()


func test_online_stages() -> void:
	Profile.path = "user://test_profile_wizard.json"
	var pair := FakeRtc.fake_pair()
	var o := OnlineView.new()
	o.transport_factory = func(): return pair[0]
	root().add_child(o)
	eq(o.stage, "via", "directly or through a server first")
	_press(o, "ViaCodes")
	eq(o.stage, "name", "then the name")
	o.name_edit.text_submitted.emit("Alice")
	eq(o.stage, "kind", "Enter goes on to a normal game or the Arena")
	_press(o.find_child("Stage_kind", true, false), "Back")
	eq(o.stage, "name", "Back from the kind")
	_press(o.find_child("Stage_name", true, false), "Next")
	_press(o, "KindGame")
	eq(o.stage, "deck", "a normal game needs a deck")
	o.chooser.back.emit()
	eq(o.stage, "kind", "Back from the deck")
	_press(o, "KindGame")
	o.chooser.rows[2].pressed.emit()
	eq(o.stage, "mode", "a deck goes on to create or join")
	eq(o.deck, o.chooser.decks[2], "the chosen deck")
	_press(o.find_child("Stage_mode", true, false), "Back")
	eq(o.stage, "deck", "Back from create or join")
	o.chooser.rows[2].pressed.emit()
	_press(o, "Join")
	eq(o.stage, "join", "join stage")
	check(o.code_in.is_visible_in_tree(), "invite field shown")
	check(not o.code_out.is_visible_in_tree(), "no answer code yet")
	_press(o.find_child("Stage_join", true, false), "Back")
	eq(o.stage, "mode", "Back from join")
	_press(o, "Host")
	eq(o.stage, "host", "create stage")
	eq(o.state, "code", "invite made")
	check(o.code_out.is_visible_in_tree() and o.code_in.is_visible_in_tree(), "both fields shown")
	var row := o.code_out.get_parent()
	var copy := row.find_child("Copy", false, false)
	check(row is HBoxContainer and copy != null and copy.get_index() == o.code_out.get_index() + 1, "Copy sits right beside the code")
	check(o.code_in.get_parent().find_child("Finish", false, false).is_visible_in_tree(), "Connect beside the answer field")
	_press(o.find_child("Stage_host", true, false), "Back")
	eq([o.stage, o.state, o.session], ["mode", "idle", null], "Back from create drops the game")
	var left := []
	o.back.connect(func(): left.append(true))
	_press(o.find_child("Stage_mode", true, false), "Back")
	o.chooser.back.emit()
	_press(o.find_child("Stage_kind", true, false), "Back")
	_press(o.find_child("Stage_name", true, false), "Back")
	eq(o.stage, "via", "Back from the name")
	_press(o.find_child("Stage_via", true, false), "Back")
	eq(left.size(), 1, "Back on the first step leaves")
	o.show_stage("kind")
	_press(o, "KindArena")
	eq(o.stage, "mode", "the Arena has no deck step")
	_press(o.find_child("Stage_mode", true, false), "Back")
	eq(o.stage, "kind", "Back from create or join in the Arena")
	o.free()
	for t in pair:
		if is_instance_valid(t):
			t.free()
	DirAccess.remove_absolute(Profile.path)
	Profile.path = Profile.DEFAULT_PATH


func test_guest_waits_longer_than_the_host() -> void:
	Profile.path = "user://test_profile_wizard2.json"
	var pair := FakeRtc.fake_pair()
	var g := OnlineView.new()
	g.transport_factory = func(): return pair[1]
	var h := OnlineView.new()
	h.transport_factory = func(): return pair[0]
	root().add_child(h)
	root().add_child(g)
	h.host_game()
	g.join_game(h.code_out.text)
	eq(g.state, "code", "answer shown")
	for i in int(OnlineView.CONNECT_TIMEOUT / 0.5) + 2:
		g._process(0.5)
	eq(g.state, "code", "still waiting for the host after the host's timeout")
	check(g.status.text.ends_with("…"), "a calm waiting text: " + g.status.text)
	for i in int(OnlineView.GUEST_WAIT / 0.5) + 2:
		g._process(0.5)
	eq(g.state, "failed", "gives up in the end")
	h.free()
	g.free()
	DirAccess.remove_absolute(Profile.path)
	Profile.path = Profile.DEFAULT_PATH
