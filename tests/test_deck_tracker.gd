extends TestCase


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _deck() -> Array:
	var d := []
	for i in 15:
		d.append("VAN_CS2_182" if i == 0 else "VAN_CS2_029" if i == 1 else "VAN_CS2_120")
	d.append_array(d)  # two copies of each line: 2 Yeti, 2 Fireball, 26 River Crocolisk
	return d


func _decks(seed := 7) -> Match:
	return H.decks({"hero": "HERO_08", "cards": _deck()}, {"hero": "HERO_01", "cards": _deck()}, seed, 0)


func _consistent(g: GameView, what: String) -> void:
	var start := 0
	var still := 0
	for r in DeckTracker.deck_view(g, 0):
		start += r.total
		still += r.left
		eq(is_equal_approx(r.chance, float(r.left) / g.players[0].deck.size()), true, "chance of %s (%s)" % [r.card, what])
	eq(start, 30, "whole starting deck (%s)" % what)
	eq(still, g.players[0].deck.size(), "left = cards in the deck (%s)" % what)


func test_deck_view_counts_and_chances() -> void:
	var m := _decks()
	_consistent(m.game, "dealt")
	var hand: Array = m.game.players[0].hand.map(func(e): return e.id)
	hand.sort()
	m.submit({"type": "mulligan", "player": 0, "replace": hand})  # all back into the deck, new ones drawn
	_consistent(m.game, "after the mulligan")


## 2 Yeti on the top of 18 River Crocolisk, nothing dealt yet.
func _twenty() -> Match:
	var d := []
	for i in 18:
		d.append("VAN_CS2_120")
	d.append_array(["VAN_CS2_182", "VAN_CS2_182"])  # (a scenario's deck: the last card is the top)
	var m := H.scene({"hero": "HERO_08", "deck": d}, {"hero": "HERO_01", "deck": d.duplicate()})
	m.game.start_decks = [d, d]  # a scenario has no deck lists: these are the tracker's
	return m


## Player 0 draws its top card (a turn of each side).
func _draw(m: Match) -> void:
	var lists: Array = m.game.start_decks
	H.end_turn(m)
	H.end_turn(m)
	m.game.start_decks = lists


func _row(g: GameView, card: String) -> Dictionary:
	for r in DeckTracker.deck_view(g, 0):
		if r.card == card:
			return r
	return {}


func test_deck_view_follows_draws() -> void:
	var m := _twenty()
	var g := m.game
	eq(_row(g, "VAN_CS2_182").chance, 0.1, "2 of 20 cards: 10%")
	_draw(m)
	eq([_row(g, "VAN_CS2_182").left, _row(g, "VAN_CS2_182").total], [1, 2], "one copy drawn")
	eq(is_equal_approx(_row(g, "VAN_CS2_182").chance, 1.0 / 19), true, "1 of 19")
	eq(_row(g, "GAME_005"), {}, "a card not from the deck is not in the deck list")


func test_opponent_played_hides_unrevealed_secrets() -> void:
	var m := H.game(["VAN_CS2_120", "VAN_EX1_609"], ["VAN_CS2_182"])
	var g := m.game
	H.play(m, g.players[0].hand[0])
	H.play(m, g.players[0].hand[0])
	H.end_turn(m)
	eq(DeckTracker.opponent_played(g, 1), ["VAN_CS2_120", ""], "minion shown, secret hidden")
	H.play(m, g.players[1].hand[0])  # Chillwind Yeti: Snipe goes off
	eq(DeckTracker.opponent_played(g, 1), ["VAN_CS2_120", "VAN_EX1_609"], "revealed secret shown")
	eq(DeckTracker.opponent_played(g, 0), ["VAN_CS2_182"], "the other side sees its opponent")


func test_opponent_counts_group_copies_in_play_order() -> void:
	var m := H.game([], ["VAN_CS2_120", "VAN_CS2_182", "VAN_CS2_120"])
	H.end_turn(m)
	for i in 3:
		H.play(m, m.game.players[1].hand[0])
	eq(DeckTracker.opponent_counts(m.game, 0), [{"card": "VAN_CS2_120", "count": 2}, {"card": "VAN_CS2_182", "count": 1}], "×2 for a second copy")


func _view() -> MatchView:
	Settings.data = Settings.DEFAULTS.duplicate(true)
	var v := MatchView.new()
	root().add_child(v)
	var m := H.decks({"hero": "HERO_08", "cards": _deck()}, {"hero": "HERO_01", "cards": _deck()}, 7, 0, [false, true])
	v.bind(m)
	return v


func test_tracker_button_under_the_gear_toggles_the_panel() -> void:
	var v := _view()
	var gear := v.find_child("MenuButton", true, false) as Button
	var button := v.find_child("TrackerButton", true, false) as Button
	eq(button.position.x, gear.position.x, "in line with the gear")
	check(button.position.y > gear.get_rect().end.y and button.position.y - gear.get_rect().end.y < 12, "just under the gear")
	var mana: Control = v._mana[1]  # the opponent's crystals at the top
	check(not button.get_global_rect().intersects(mana.get_global_rect()), "clear of the opponent's mana")
	check((v.find_child("GameMenu", true, false) as Control).find_child("TrackerButton", true, false) == null, "no longer in the menu")
	var panel := v.find_child("DeckTracker", true, false) as Control
	eq(panel.visible, false, "hidden at first")
	button.pressed.emit()
	eq(panel.visible, true, "shown")
	eq(Settings.data.tracker, true, "remembered")
	check(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(panel.get_rect()), "fits the 1280x720 table")
	check(not panel.get_rect().intersects((v.find_child("EndTurn", true, false) as Control).get_rect()), "End Turn stays free")
	check(panel.get_rect().end.y <= TableLayout.HAND_Y, "above the hand")
	check((panel.find_child("DeckList", true, false) as Control).get_child_count() > 0, "your deck listed")
	var deck_scroll := panel.find_child("DeckScroll", true, false) as Control
	(panel.find_child("DeckHeader", true, false) as Button).pressed.emit()
	eq(deck_scroll.visible, false, "section folded")
	eq(Settings.data.tracker_deck, false, "fold remembered")
	button.pressed.emit()
	eq(panel.visible, false, "hidden again")
	eq(Settings.data.tracker, false, "remembered closed")
	v.free()
	Settings.data = Settings.DEFAULTS.duplicate(true)
	Settings.data.language = "en"


func _panel() -> DeckTrackerPanel:
	Settings.data = Settings.DEFAULTS.duplicate(true)
	var p := DeckTrackerPanel.new()
	root().add_child(p)
	return p


func test_your_deck_rows_dim_and_drop_the_copies_mark() -> void:
	var p := _panel()
	var m := _twenty()
	var g := m.game
	var tile := func() -> DeckTiles.DeckTile: return p.find_child("Entry_VAN_CS2_182", true, false)
	var chance := func() -> String: return (p.find_child("Row_VAN_CS2_182", true, false).get_node("Chance") as Label).text
	p.update_from(g, 0)
	eq([tile.call().copies, chance.call(), tile.call().modulate.a], [2, "10%", 1.0], "×2, 2 of 20 = 10%")
	_draw(m)
	p.update_from(g, 0)
	eq([tile.call().copies, chance.call()], [1, "5%"], "one left: no ×, 1 of 19 = 5%")
	_draw(m)
	p.update_from(g, 0)
	eq([tile.call().copies, chance.call()], [0, ""], "none left: no chance")
	check(tile.call().modulate.a < 1.0, "dimmed")
	eq((p.find_child("Row_VAN_CS2_120", true, false).get_node("Chance") as Label).text, "100%", "18 of 18")
	p.free()


func test_opponent_list_grows_and_marks_a_second_copy() -> void:
	var p := _panel()
	var m := H.game([], ["VAN_CS2_120", "VAN_CS2_182", "VAN_CS2_120"])
	var g := m.game
	H.end_turn(m)
	var list := p.find_child("OpponentList", true, false) as Control
	p.update_from(g, 0)
	eq(list.get_child_count(), 0, "nothing played yet")
	H.play(m, g.players[1].hand[0])
	p.update_from(g, 0)
	eq(list.get_children().map(func(t): return [t.card_id, t.copies]), [["VAN_CS2_120", 1]], "first card")
	H.play(m, g.players[1].hand[0])
	H.play(m, g.players[1].hand[0])
	p.update_from(g, 0)
	eq(list.get_children().map(func(t): return [t.card_id, t.copies]), [["VAN_CS2_120", 2], ["VAN_CS2_182", 1]], "grows; ×2 for the second copy")
	p.free()


func test_opponent_secret_stays_hidden_in_the_panel() -> void:
	var p := _panel()
	var m := H.game(["VAN_EX1_609"])
	H.play(m, m.game.players[0].hand[0])
	H.end_turn(m)
	p.update_from(m.game, 1)
	var list := p.find_child("OpponentList", true, false) as Control
	eq(list.get_child_count(), 1, "one row")
	eq(str(list.get_child(0).name), "Entry_Secret", "a hidden Secret")
	check(p.find_child("Entry_VAN_EX1_609", true, false) == null, "the Secret's name is not shown")
	p.free()
