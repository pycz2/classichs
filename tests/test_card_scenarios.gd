extends TestCase
## The debug tools' scenario library (game/card_scenarios.gd): generic scenarios for every card of every pack
## build in the engine, follow the card's mechanics and play; the hand-written tricky interactions
## (data/card_tests/tricky*.json) play to their checks in their pack; the marks are kept and exported; the
## Interaction test tab walks a pack.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## Makes a pack file (built-in or of build/packs: tools/build_packs.sh) the active one for this test; false without it.
func _use(name: String) -> bool:
	for f in _pack_files():
		if f.get_file().get_basename() == name:
			Packs._active = Pack.open(f, "imported")
			Packs._changed()
			return true
	check(false, "no pack %s (tools/build_packs.sh)" % name)
	return false


static func _pack_files() -> Array:
	var out := []
	for dir in ["res://packs", ProjectSettings.globalize_path("res://build/packs")]:
		for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else []:
			if f.ends_with(".cardpack"):
				out.append(dir.path_join(f))
	return out


func _classic() -> void:
	Packs._active = null
	Packs._changed()


func _kinds(id: String) -> Array:
	return CardScenarios.generic(id).map(func(t): return t.key)


func test_every_generic_scene_builds_in_every_pack() -> void:
	var files := _pack_files()
	check(files.size() >= 3, "the packs are there: %d" % files.size())
	for f in files:
		Packs._active = Pack.open(f, "imported")
		Packs._changed()
		var bad := []
		var n := 0
		for id in CardDb.all_ids():
			for t in CardScenarios.generic(id):
				n += 1
				var why := Rules.scenario_error(t.scene)
				if why != "" and bad.size() < 5:
					bad.append("%s %s: %s" % [id, t.key, why])
		eq(bad, [], "%s: every scene of %d builds" % [f.get_file(), n])
		check(n > 0, "%s: %d scenarios" % [f.get_file(), n])
	_classic()


func test_generic_scenarios_follow_the_mechanics() -> void:
	var archer := _kinds("VAN_CS2_189")  # Elven Archer: Battlecry, a target
	for k in ["play", "targets", "attack_minion", "attack_hero", "damage", "death", "silence", "return", "copy", "transform",
			"steal", "freeze", "secret_play", "secret_attack", "champion", "adjacent:0", "adjacent:3"]:
		check(archer.has(k), "Elven Archer: " + k)
	var druid := _kinds("VAN_EX1_165")  # Druid of the Claw: Choose One
	check(druid.has("choice:0") and druid.has("choice:1") and not druid.has("play"), "an option each: %s" % [druid])
	check(_kinds("VAN_EX1_162").has("own_aura:2"), "Dire Wolf Alpha: its aura at each place")
	check(_kinds("VAN_EX1_287").has("secret_trigger"), "a Secret goes off")
	check(_kinds("VAN_CS2_029").has("secret_spell") and _kinds("VAN_CS2_029").has("spell_damage"), "Fireball: Counterspell, Spell Damage")
	check(not _kinds("VAN_CS2_029").has("death"), "a spell does not die")
	check(_kinds("VAN_EX1_134").has("combo"), "SI:7 Agent: Combo")
	check(_kinds("VAN_CS2_106").has("attack_minion"), "a weapon attacks")
	check(_kinds("VAN_EX1_556").has("death"), "Harvest Golem dies")
	var golem: Dictionary = CardScenarios.generic("VAN_EX1_556").filter(func(t): return t.key == "death")[0]
	var r := CardTests.run(golem.merged({"check": [{"at": {"side": 0, "zone": "board", "index": 0}, "card": "VAN_skele21"}]}))
	if r.match:
		r.match.free()
	eq(r.error, "", "Twisting Nether kills it; its Deathrattle leaves a Damaged Golem")


func test_the_pack_gives_the_doubling_scenarios() -> void:
	if not _use("dal"):
		return
	check(_kinds("VAN_CS2_189").has("doubled:LOE_077"), "a Battlecry doubled by Brann: %s" % [_kinds("VAN_CS2_189")])
	check(_kinds("VAN_EX1_556").has("doubled:FP1_031"), "a Deathrattle doubled by Rivendare")
	check(_kinds("VAN_EX1_287").has("doubled:DAL_573"), "a Secret doubled by Commander Rhyssa")
	check(_kinds("VAN_EX1_165").any(func(k): return k.begins_with("doubled:")), "Choose One with Fandral Staghelm")
	check(_kinds("BOT_020").has("magnetic") and _kinds("BOT_020").has("rush"), "Skaterbot: Magnetic, Rush")
	var brann: Dictionary = CardScenarios.generic("VAN_CS2_189").filter(func(t): return t.key == "doubled:LOE_077")[0]
	var r := CardTests.run(brann)
	if r.match:
		r.match.free()
	eq(r.error, "", "Elven Archer with Brann shoots twice")
	var sd: Dictionary = CardScenarios.generic("VAN_CS2_029").filter(func(t): return t.key == "spell_damage")[0]
	r = CardTests.run(sd)
	eq(r.error, "", "Fireball with Spell Damage +2 plays")
	if r.match:
		eq(r.match.game.players[0].spell_damage, 2, "a tag with a number: Spell Damage +2")
		r.match.free()
	_classic()


## Every tricky*.json plays to its checks in its pack: tricky.json in Rise of Shadows, tricky_<pack>.json in that pack.
func test_tricky_interactions_play_to_their_checks() -> void:
	var files := Array(DirAccess.get_files_at(CardTests.DIR)).filter(func(f): return f.begins_with("tricky") and f.ends_with(".json"))
	check(files.has("tricky.json"), "the first tricky interactions")
	var n := 0
	for f in files:
		var pack: String = "dal" if f == "tricky.json" else f.trim_prefix("tricky_").trim_suffix(".json")
		if not _use(pack):
			continue
		var tests := CardTests.load_all(f)
		var bad := []
		for id in tests:
			for t in tests[id]:
				n += 1
				var r := CardTests.run(t)
				if r.match:
					r.match.free()
				if r.error != "":
					bad.append("%s %s: step %d: %s" % [id, t.title, r.step, r.error])
		eq(bad, [], f + " in " + pack)
		check(not tests.is_empty(), f + ": all its cards are in " + pack)
	check(n >= 11, "%d tricky interactions" % n)
	_classic()


func test_marks_are_kept_and_exported() -> void:
	CardScenarios.path = "user://test_card_marks.json"
	DirAccess.remove_absolute(CardScenarios.path)
	CardScenarios.reset()
	var key: String = CardScenarios.generic("VAN_CS2_189")[0].key
	CardScenarios.set_mark("VAN_CS2_189", key, "failed", "no sound")
	CardScenarios.set_check("VAN_CS2_189", "Sounds", "failed")
	CardScenarios.reset()  # read back from the file
	eq(CardScenarios.card_marks("VAN_CS2_189").s[key], {"mark": "failed", "note": "no sound"}, "kept")
	eq(CardScenarios.card_marks("VAN_CS2_189").check, {"Sounds": "failed"}, "the checklist too")
	var out = JSON.parse_string(CardScenarios.export())
	eq(out.format, "classichs-card-marks/1", "the format")
	eq(out.pack, Packs.CLASSIC, "the pack")
	var card: Dictionary = out.cards[0]
	eq(card.id, "VAN_CS2_189", "the marked card")
	eq(card.scenarios[0].mark, "failed", "its mark")
	check(card.scenarios[0].scene.has("players") and not card.scenarios[0].steps.is_empty(), "with the scene and the steps to play it again")
	CardScenarios.set_mark("VAN_CS2_189", key, "")
	check(not CardScenarios.card_marks("VAN_CS2_189").s.has(key), "a mark cleared")
	DirAccess.remove_absolute(CardScenarios.path)
	CardScenarios.path = CardScenarios.DEFAULT_PATH
	CardScenarios.reset()


## The Interaction test tab: a card's scenarios with what should happen, the marks, the checklist, the walk, the export.
func test_the_walk_marks_and_exports() -> void:
	CardScenarios.path = "user://test_card_marks.json"
	DirAccess.remove_absolute(CardScenarios.path)
	CardScenarios.reset()
	DebugTable.last_test = ["", 0]
	var d := DebugTable.new()
	d.tab = DebugTable.TESTS
	root().add_child(d)
	d.pick_test_card("VAN_CS2_189")
	check(d.test_list.item_count > 10, "hand-written and generic scenarios: %d" % d.test_list.item_count)
	var steps := (d.find_child("Steps", true, false) as Label).text
	check(steps.contains("What to do:"), steps)
	var generic := -1
	for i in d.scenarios.size():
		if d.scenarios[i].get("generic", false):
			generic = i
			break
	d.test_list.select(generic)
	d._show_steps()
	check((d.find_child("Steps", true, false) as Label).text.contains("What should happen:"), "its expectation")
	(d.find_child("Note", true, false) as LineEdit).text = "the line is cut"
	(d.find_child("Mark_failed", true, false) as Button).pressed.emit()
	eq(CardScenarios.card_marks("VAN_CS2_189").s[d.scenarios[generic].key].note, "the line is cut", "marked with the note")
	check(d.test_list.get_item_text(generic).contains("Failed"), "the list shows it")
	(d.find_child("Check_Enter", true, false) as Button).pressed.emit()
	eq(CardScenarios.card_marks("VAN_CS2_189").check.get("Enter"), "passed", "a checklist item: passed")
	(d.find_child("Check_Enter", true, false) as Button).pressed.emit()
	eq(CardScenarios.card_marks("VAN_CS2_189").check.get("Enter"), "failed", "then failed")
	var at := d.walk.find("VAN_CS2_189")
	(d.find_child("WalkNext", true, false) as Button).pressed.emit()
	eq(d.test_card, d.walk[at + 1], "the next card of the walk")
	(d.find_child("WalkPrev", true, false) as Button).pressed.emit()
	eq(d.test_card, "VAN_CS2_189", "and back")
	(d.find_child("WalkUnmarked", true, false) as Button).pressed.emit()
	check(d.test_card != "VAN_CS2_189" and not CardScenarios.marks().has(d.test_card), "the next unmarked card")
	(d.find_child("ExportMarks", true, false) as Button).pressed.emit()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(DebugTable.EXPORT_PATH))
	eq(saved.cards[0].id, "VAN_CS2_189", "exported for an agent")
	check((d.find_child("WalkInfo", true, false) as Label).text != "", "says where")
	d.free()
	DirAccess.remove_absolute(CardScenarios.path)
	DirAccess.remove_absolute(DebugTable.EXPORT_PATH)
	CardScenarios.path = CardScenarios.DEFAULT_PATH
	CardScenarios.reset()


## A library scenario played in a match: what should happen is shown, and passed / failed mark it there.
func test_a_scenario_is_marked_from_the_match() -> void:
	CardScenarios.path = "user://test_card_marks.json"
	DirAccess.remove_absolute(CardScenarios.path)
	CardScenarios.reset()
	var m: Node = load("res://ui/main.tscn").instantiate()
	root().add_child(m)
	var t: Dictionary = CardScenarios.generic("VAN_EX1_556").filter(func(x): return x.key == "death")[0]
	var v: MatchView = m.start_card_test(t)
	check((v.find_child("RunExpect", true, false) as Label).text == t.expect, "what should happen")
	check((v.find_child("RunStatus", true, false) as Label).text.begins_with("Done"), "played")
	(v.find_child("Run_passed", true, false) as Button).pressed.emit()
	eq(CardScenarios.card_marks("VAN_EX1_556").s[t.key].mark, "passed", "marked")
	m.free()
	DirAccess.remove_absolute(CardScenarios.path)
	CardScenarios.path = CardScenarios.DEFAULT_PATH
	CardScenarios.reset()


## The scene editor: hero cards and Hero Powers, Quests in the Secrets zone, a card's tags (with a number),
## damage, buffs and a given Deathrattle; the scene still builds.
func test_scene_editor_knows_the_packs_mechanics() -> void:
	if not _use("dal"):
		return
	DebugTable.last_scene = ""
	var d := DebugTable.new()
	root().add_child(d)
	check(DebugTable.hero_choices().has("ICC_833"), "a hero card (Frost Lich Jaina) can be the hero")
	d._set_value(0, "hero", "ICC_833")
	eq(d.scene.players[0].get("hero_power"), "ICC_833h", "with its own Hero Power")
	eq(d.error.text, "", "it builds")
	d.add_card(0, "secrets", "UNG_942")
	check((d.scene.players[0].secrets as Array).has("UNG_942"), "a Quest goes into the Secrets zone: " + d.error.text)
	d.add_card(0, "board", "VAN_CS2_182")
	var i: int = (d.scene.players[0].board as Array).size() - 1
	d.edit_item(0, "board", i)
	var ed := d.find_child("ItemEditor", true, false)
	(ed.find_child("TagValue", true, false) as SpinBox).value = 3
	(ed.find_child("Tag_SPELLPOWER", true, false) as Button).button_pressed = true
	(ed.find_child("Tag_POISONOUS", true, false) as Button).button_pressed = true
	(ed.find_child("Item_damage", true, false) as SpinBox).value = 2
	(ed.find_child("Item_atk", true, false) as SpinBox).value = 1
	var dr := ed.find_child("Item_deathrattle", true, false) as LineEdit
	dr.text_submitted.emit("Harvest Golem")
	var yeti: Dictionary = d.scene.players[0].board[i]
	eq(yeti.tags, [{"SPELLPOWER": 3}, {"POISONOUS": 3}], "tags with the number")
	eq(int(yeti.damage), 2, "damage")
	check(yeti.enchantments.has({"debug": true, "atk": 1}) and yeti.enchantments.has({"deathrattle": "VAN_EX1_556"}), str(yeti.enchantments))
	eq(d.error.text, "", "the scene builds")
	var m := Match.new()
	eq(m.setup({"scenario": d.scene}, [false, false]), "", "and plays")
	var e: GameView.Ent = m.game.players[0].board[i]
	eq([e.atk(), e.health(), m.game.players[0].spell_damage], [5, 3, 3], "4/5 +1 Attack, 2 damage, Spell Damage +3")
	m.free()
	d.free()
	_classic()


## The effects lab: every tag of the pack and every kind of card (a Hero Power, a Quest, a hero card) in play and in hand.
func test_effects_on_every_card_type() -> void:
	if not _use("dal"):
		return
	var lab := EffectsLab.new()
	root().add_child(lab)
	var keys := EffectsLab.effects().map(func(x): return x[0])
	for k in ["RUSH", "LIFESTEAL", "POISONOUS", "ECHO", "UNTOUCHABLE", "MODULAR", "TWINSPELL", "OVERKILL", "base", "deathrattle"]:
		check(keys.has(k), "the lab has " + k)
	for c in [["ICC_833", "Hero"], ["ICC_833h", "Power"], ["UNG_942", "Quest"], ["VAN_EX1_287", "Secret"], ["VAN_CS2_106", "Weapon"], ["BOT_020", "Minion"]]:
		lab.show_card(c[0])
		lab.set_effect("LIFESTEAL", true)
		check(lab.find_child(c[1], true, false) != null, "%s in play as a %s" % c)
		check(lab.find_child("Card", true, false) != null, c[0] + " as a card")
		lab.set_effect("LIFESTEAL", false)
	lab.show_card("VAN_CS2_182")
	lab.tag_value = 2
	lab.set_effect("SPELLPOWER", true)
	var s := (lab.find_child("Minion", true, false) as MinionView).s
	eq(s.spellpower(), 2, "Spell Damage +2")
	lab.free()
	_classic()
