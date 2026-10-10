extends TestCase


func _all_lines(g: GameState, viewer: int) -> Array:
	var out := []
	for entry in g.history:
		out.append_array(HistoryText.lines(entry, g, viewer, "en"))
	return out


func test_play_attack_and_death() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_120"))
	var w := H.board(g, 1, H.WISP)
	var croc: Entity = g.players[0].board[0]
	croc.tags.erase("EXHAUSTED")
	H.attack(g, croc, w)
	var text := "\n".join(_all_lines(g, 0))
	check(text.contains("You play River Crocolisk"), text)
	check(text.contains("River Crocolisk attacks Wisp"), text)
	check(text.contains("Wisp dies"), text)


func test_opponent_draw_is_hidden_own_draw_shown() -> void:
	var g := H.game()
	H.end_turn(g)  # opponent draws a Wisp
	var mine := "\n".join(_all_lines(g, 0))
	var theirs := "\n".join(_all_lines(g, 1))
	check(mine.contains("Opponent draws a card"), mine)
	check(not mine.contains("Opponent draws Wisp"), "hidden from me")
	check(theirs.contains("You draw Wisp"), theirs)


func test_fatigue_and_burn() -> void:
	var g := H.game()
	g.players[1].deck.clear()
	H.end_turn(g)
	var text := "\n".join(_all_lines(g, 0))
	check(text.contains("Opponent takes 1 fatigue damage"), text)
	var g2 := H.game()
	for i in 10:
		H.hand(g2, 1, H.WISP)
	H.end_turn(g2)
	check("\n".join(_all_lines(g2, 0)).contains("Opponent burns Wisp"), "burned card is revealed")


func test_every_event_type_has_text() -> void:
	var res := Sim.play_random(4, 300)
	var g: Game = res.game
	for entry in g.history:
		for ev in entry.events:
			var lines := HistoryText.event_lines(ev, g, 0, "en")
			if not HistoryText.SILENT.has(ev.type):
				check(not lines.is_empty(), "no text for " + ev.type)


func test_turn_header() -> void:
	var g := H.game()
	H.end_turn(g)
	check("\n".join(_all_lines(g, 0)).contains("Turn 2: Opponent"), "header")


func test_tracking_discards_hidden_from_opponent() -> void:
	var g := H.scene({"hero": "HERO_05", "hand": ["VAN_DS1_184"], "deck": [H.WISP, "VAN_CS2_182", "VAN_CS2_120"]})
	H.play(g, g.players[0].hand[0])
	g.apply(g.legal_actions().filter(func(a): return a.type == "choose")[0])
	var theirs := "\n".join(_all_lines(g, 1))
	check(not theirs.contains("Chillwind Yeti") and not theirs.contains("River Crocolisk") and not theirs.contains("Wisp"), theirs)
	check(theirs.contains("Opponent discards a card"), "hidden discard")
