extends TestCase


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _deck() -> Array:
	var d := []
	for i in 15:
		d.append("VAN_CS2_182" if i == 0 else "VAN_CS2_029" if i == 1 else "VAN_CS2_120")
	d.append_array(d)  # two copies of each line: 2 Yeti, 2 Fireball, 26 River Crocolisk
	return d


func test_remaining_cards_and_chances() -> void:
	var g := Game.new({"hero": "HERO_08", "deck": _deck()}, {"hero": "HERO_01", "deck": _deck()}, 7, 0)
	var left := DeckTracker.remaining(g, 0)
	var total := 0
	for r in left:
		total += r.count
		eq(is_equal_approx(r.chance, float(r.count) / g.players[0].deck.size()), true, "chance of " + r.card)
	eq(total, g.players[0].deck.size(), "every card in the deck is listed")
	var own := DeckTracker.deck_view(g, 0)
	var start := 0
	var still := 0
	for r in own:
		start += r.total
		still += r.left
	eq(start, 30, "whole starting deck")
	eq(still, g.players[0].deck.size(), "left = cards in the deck")


func test_opponent_played_hides_unrevealed_secrets() -> void:
	var g := H.game()
	var croc := H.hand(g, 0, "VAN_CS2_120")
	H.play(g, croc)
	var snipe := H.hand(g, 0, "VAN_EX1_609")
	H.play(g, snipe)
	H.end_turn(g)
	eq(DeckTracker.opponent_played(g, 1), ["VAN_CS2_120", ""], "minion shown, secret hidden")
	H.play(g, H.hand(g, 1, "VAN_CS2_182"))
	eq(DeckTracker.opponent_played(g, 1), ["VAN_CS2_120", "VAN_EX1_609"], "revealed secret shown")
	eq(DeckTracker.opponent_played(g, 0), ["VAN_CS2_182"], "the other side sees its opponent")


func test_tracker_panel_toggles_and_remembers_views() -> void:
	Settings.data = Settings.DEFAULTS.duplicate()
	var v := MatchView.new()
	root().add_child(v)
	var m := Match.new()
	m.bot_delay = 0.0
	m.setup(Game.new({"hero": "HERO_08", "deck": _deck()}, {"hero": "HERO_01", "deck": _deck()}, 7, 0), [false, true])
	v.bind(m)
	var panel := v.find_child("DeckTracker", true, false) as Control
	eq(panel.visible, false, "hidden at first")
	(v.find_child("TrackerButton", true, false) as Button).pressed.emit()
	eq(panel.visible, true, "shown")
	eq(Settings.data.tracker, true, "remembered")
	var left := panel.find_child("LeftList", true, false) as Control
	check(left.get_child_count() > 0, "cards left listed")
	(panel.find_child("LeftHeader", true, false) as Button).pressed.emit()
	eq(left.visible, false, "view hidden")
	eq(Settings.data.tracker_left, false, "view choice remembered")
	v.free()
	Settings.data = Settings.DEFAULTS.duplicate()
	Settings.data.language = "en"
