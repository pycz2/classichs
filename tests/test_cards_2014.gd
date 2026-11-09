extends TestCase
## Classic cards as in 2014 (patch 1.0.0.5834, before Naxxramas) where the 2021 Classic data
## differs: names and texts in every language, and on the table Sacrificial Pact on Lord
## Jaraxxus and Nozdormu's 15-second turns in a local game. The rules: rust/engine/tests/cards_2014.rs.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _view(p0: Dictionary, p1: Dictionary, current := 0, bots := [false, true]) -> MatchView:
	var v := MatchView.new()
	root().add_child(v)
	v.bind(H.scene(p0, p1, current, bots))
	return v


func _deck() -> Array:
	var d := []
	for i in 10:
		d.append(H.WISP)
	return d


func test_renamed_cards_have_their_2014_names() -> void:
	var want := {
		"VAN_EX1_306": {"enUS": "Succubus", "ruRU": "Суккуб", "deDE": "Sukkubus", "frFR": "Succube", "esES": "Súcubo",
			"ptBR": "Súcubo", "itIT": "Succube", "plPL": "Sukkub"},
		"VAN_EX1_finkle": {"enUS": "Finkle Einhorn", "ruRU": "Айс Вентурон"},
		"VAN_EX1_154a": {"enUS": "Wrath", "ruRU": "Гнев"},
		"VAN_EX1_614": {"ruRU": "Иллидан Ярость Бури"},
		"VAN_EX1_298": {"ruRU": "Рагнарос"},
		"VAN_EX1_091": {"ruRU": "Темная жрица"},
	}
	for id in want:
		for loc in want[id]:
			eq(CardText.name(id, loc), want[id][loc], "%s %s" % [id, loc])


func test_changed_texts_are_the_2014_ones() -> void:
	check(CardText.text("VAN_EX1_320", "enUS").begins_with("Deal 2 damage"), "Bane of Doom: 2 damage")
	check(CardText.text("VAN_EX1_320", "ruRU").contains("2 ед."), "and in Russian")
	check(CardText.text("VAN_EX1_577", "enUS").contains("Finkle Einhorn"), "The Beast gives Finkle Einhorn")
	eq(CardText.text("VAN_NEW1_023", "enUS"), "Can't be targeted by Spells or Hero Powers.", "Faerie Dragon: no Elusive yet")
	check(CardText.text("VAN_EX1_110", "ruRU").contains("4/5"), "Cairne's Baine is 4/5 in Russian too")
	check(not CardText.text("VAN_EX1_536", "ruRU").contains("ваш"), "Eaglehorn Bow: any Secret, not only yours")
	eq(CardText.text("VAN_HERO_02bp", "enUS"), "Hero Power\nSummon a random Totem.", "Totemic Call")


func test_2014_stats() -> void:
	eq([int(CardDb.card("VAN_EX1_131").attack), int(CardDb.card("VAN_EX1_131").health)], [2, 2], "Defias Ringleader")
	eq(int(CardDb.card("VAN_DREAM_01").cost), 3, "Laughing Sister")
	eq(int(CardDb.card("VAN_EX1_finkle").cost), 2, "Finkle Einhorn")
	eq(str(CardDb.card("VAN_EX1_556").get("race", "")), "", "Harvest Golem: no Mech tribe yet")


func test_sacrificial_pact_on_lord_jaraxxus_at_the_table(drag := false) -> void:
	var v := _view({"hero": "HERO_07", "hand": ["VAN_NEW1_003"], "deck": _deck()},
		{"hero": "HERO_07", "hand": ["VAN_EX1_323"], "deck": _deck()}, 1, [false, false])
	var m := v.controller
	var jar: GameView.Ent = v.g.players[1].hand[0]
	eq(H.play(m, jar).get("ok"), true, "Lord Jaraxxus played")
	H.end_turn(m)
	v.refresh()
	var lord: GameView.Ent = v.g.hero(1)
	eq(lord.card_id, "EX1_323h", "the enemy hero is Lord Jaraxxus")
	check(v._views.has(lord.id), "the table shows the new hero")
	var pact: GameView.Ent = v.g.players[0].hand[0]
	if drag:
		var view: EntityView = v._views[lord.id]
		var at := view.position + view.size * view.scale / 2.0
		v._press = {"id": pact.id, "at": Vector2(640, 650)}
		v._start_drag()
		v._drag_to(at)
		v._press = {}
		v._dragging = false
		v._drop_at(at, pact.id)
	else:
		v.click_entity(pact.id)
		v.click_entity(lord.id)
	check(v.g.game_over and v.g.winner == 0, "Lord Jaraxxus destroyed: the game is won")
	v.free()


func test_sacrificial_pact_dragged_onto_lord_jaraxxus() -> void:
	test_sacrificial_pact_on_lord_jaraxxus_at_the_table(true)


func test_nozdormu_times_the_turns_of_a_game_against_the_bot() -> void:
	var v := _view({"hero": "HERO_08", "board": ["VAN_EX1_560"], "deck": _deck()}, {"hero": "HERO_01", "deck": _deck()})
	eq(v.timer_enabled, false, "no turn timer against the bot")
	eq(v.g.turn_seconds, 15, "Nozdormu asks for 15 seconds")
	var rope := v.find_child("Rope", true, false) as Control
	v.tick(1.0)
	check(rope.visible, "the rope burns from the start of a 15-second turn")
	v.tick(0.0)
	check(v._clock.text.contains("Turn 0:14"), "the turn clock: " + v._clock.text)
	var turn := v.g.turn
	v.tick(14.5)
	check(v.g.turn > turn, "the turn ended on time")
	v.free()


func test_the_usual_time_comes_back_when_nozdormu_leaves() -> void:
	var v := _view({"hero": "HERO_08", "hand": ["VAN_CS2_076"], "deck": _deck()}, {"hero": "HERO_01", "board": ["VAN_EX1_560"], "deck": _deck()})
	var rope := v.find_child("Rope", true, false) as Control
	v.tick(5.0)
	check(rope.visible, "a short turn")
	H.play(v.controller, v.g.players[0].hand[0], v.g.players[1].board[0])  # Assassinate
	eq(v.g.turn_seconds, 0, "Nozdormu is gone")
	var turn := v.g.turn
	v.tick(30.0)
	eq(v.g.turn, turn, "no limit any more in a local game")
	check(not rope.visible, "no rope")
	v.free()


func test_online_a_short_turn_gets_its_time_back() -> void:
	var v := _view({"hero": "HERO_08", "hand": ["VAN_CS2_076"], "deck": _deck()}, {"hero": "HERO_01", "board": ["VAN_EX1_560"], "deck": _deck()})
	v.timer_enabled = true
	v.tick(5.0)
	check(absf(v._time_left - 10.0) < 0.01, "15 - 5 seconds left: %s" % v._time_left)
	H.play(v.controller, v.g.players[0].hand[0], v.g.players[1].board[0])
	v.tick(1.0)
	check(absf(v._time_left - (MatchView.TURN_SECONDS - 6.0)) < 0.01, "75 - 6 seconds left: %s" % v._time_left)
	v.free()
