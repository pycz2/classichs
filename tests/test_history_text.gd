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


## The pop-up rows of the newest entry as "from|name|text" strings.
func _fx(g: GameState, viewer := 0) -> Array:
	return HistoryText.effects(g.history[-1], g, viewer, "en").map(func(r): return "%s|%s|%s" % [r.from, r.name, r.text])


func test_effects_of_a_battlecry() -> void:
	var g := H.scene({"hero": "HERO_08", "hand": ["VAN_CS2_189"]}, {"hero": "HERO_01", "board": [H.WISP]})
	H.play(g, g.players[0].hand[0], g.players[1].board[0])
	eq(_fx(g), ["|Wisp|-1 Health", "|Wisp|Dies"], "Elven Archer hits the Wisp")
	eq(HistoryText.title(g.history[-1], g, 0, "en"), "You play Elven Archer on Wisp", "who did it")


func test_effects_of_a_spell_with_several_targets() -> void:
	var g := H.scene({"hero": "HERO_06", "hand": ["VAN_CS2_012"]}, {"hero": "HERO_01", "board": ["VAN_CS2_182", "VAN_CS2_182"]})
	H.play(g, g.players[0].hand[0], g.hero(1))
	eq(_fx(g), ["|Garrosh Hellscream|-4 Health", "|Chillwind Yeti|-1 Health", "|Chillwind Yeti|-1 Health"], "Swipe")


func test_effects_of_a_deathrattle_name_it() -> void:
	var g := H.scene({"hero": "HERO_08", "board": [{"card": "VAN_CS2_182", "exhausted": false}]}, {"hero": "HERO_01", "board": ["VAN_EX1_029"]})
	H.attack(g, g.players[0].board[0], g.players[1].board[0])
	var fx := _fx(g)
	check(fx.has("|Leper Gnome|Dies"), str(fx))
	check(fx.has("Deathrattle: Leper Gnome|Jaina Proudmoore|-2 Health"), str(fx))


func test_effects_of_a_weapon_and_a_heal() -> void:
	var g := H.scene({"hero": "HERO_01", "damage": 5, "hand": ["VAN_CS2_106", "VAN_EX1_011"]})
	H.play(g, g.players[0].hand[0])
	eq(_fx(g), ["|Garrosh Hellscream|Equips Fiery War Axe"], "weapon goes to the hero")
	H.play(g, g.players[0].hand[0], g.hero(0))
	eq(_fx(g), ["|Garrosh Hellscream|+2 Health"], "Voodoo Doctor heals the hero")


func test_effects_hide_the_opponents_draws() -> void:
	var g := H.scene({"hero": "HERO_08"}, {"hero": "HERO_08", "hand": ["VAN_CS2_023"], "deck": [H.WISP, H.WISP]}, 1)
	H.play(g, g.players[1].hand[0])
	eq(_fx(g, 0), ["||Opponent draws a card", "||Opponent draws a card"], "hidden from me")
	eq(_fx(g, 1), ["|Wisp|Drawn", "|Wisp|Drawn"], "shown to the one who draws")
