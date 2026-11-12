extends TestCase


func _all_lines(g: GameView, viewer: int) -> Array:
	var out := []
	for entry in g.history:
		out.append_array(HistoryText.lines(entry, g, viewer, "en"))
	return out


func test_play_attack_and_death() -> void:
	var m := H.scene({"hero": "HERO_08", "hand": ["VAN_CS2_120"], "board": ["VAN_CS2_120"]}, {"hero": "HERO_01", "board": [H.WISP]})
	var g := m.game
	H.play(m, g.players[0].hand[0])
	H.attack(m, g.players[0].board[0], g.players[1].board[0])
	var text := "\n".join(_all_lines(g, 0))
	check(text.contains("You play River Crocolisk"), text)
	check(text.contains("River Crocolisk attacks Wisp"), text)
	check(text.contains("Wisp dies"), text)


func test_opponent_draw_is_hidden_own_draw_shown() -> void:
	var m := H.game()
	H.end_turn(m)  # opponent draws a Wisp
	var mine := "\n".join(_all_lines(m.game, 0))
	var theirs := "\n".join(_all_lines(m.game, 1))
	check(mine.contains("Opponent draws a card"), mine)
	check(not mine.contains("Opponent draws Wisp"), "hidden from me")
	check(theirs.contains("You draw Wisp"), theirs)


func test_fatigue_and_burn() -> void:
	var m := H.scene({"hero": "HERO_08"}, {"hero": "HERO_01"})
	H.end_turn(m)
	var text := "\n".join(_all_lines(m.game, 0))
	check(text.contains("Opponent takes 1 fatigue damage"), text)
	var hand: Array = []
	for i in 10:
		hand.append(H.WISP)
	var m2 := H.game([], hand)
	H.end_turn(m2)
	check("\n".join(_all_lines(m2.game, 0)).contains("Opponent burns Wisp"), "burned card is revealed")


func test_every_event_type_has_text() -> void:
	var m := H.decks("MAGE", "HUNTER", 4, 0, [true, true])
	m.start()
	check(m.game.game_over, "the bots played a whole game")
	for entry in m.game.history:
		for ev in entry.events:
			var lines := HistoryText.event_lines(ev, m.game, 0, "en")
			if not HistoryText.SILENT.has(ev.type):
				check(not lines.is_empty(), "no text for " + ev.type)


func test_turn_header() -> void:
	var m := H.game()
	H.end_turn(m)
	check("\n".join(_all_lines(m.game, 0)).contains("Turn 2: Opponent"), "header")


func test_tracking_discards_hidden_from_opponent() -> void:
	var m := H.scene({"hero": "HERO_05", "hand": ["VAN_DS1_184"], "deck": [H.WISP, "VAN_CS2_182", "VAN_CS2_120"]})
	H.play(m, m.game.players[0].hand[0])
	m.submit(m.legal().filter(func(a): return a.type == "choose")[0])
	var theirs := "\n".join(_all_lines(m.game, 1))
	check(not theirs.contains("Chillwind Yeti") and not theirs.contains("River Crocolisk") and not theirs.contains("Wisp"), theirs)
	check(theirs.contains("Opponent discards a card"), "hidden discard")


## The pop-up rows of the newest entry as "from|name|text" strings.
func _fx(g: GameView, viewer := 0) -> Array:
	return HistoryText.effects(g.history[-1], g, viewer, "en").map(func(r): return "%s|%s|%s" % [r.from, r.name, r.text])


func test_effects_of_a_battlecry() -> void:
	var m := H.scene({"hero": "HERO_08", "hand": ["VAN_CS2_189"]}, {"hero": "HERO_01", "board": [H.WISP]})
	var g := m.game
	H.play(m, g.players[0].hand[0], g.players[1].board[0])
	eq(_fx(g), ["|Wisp|-1 Health", "|Wisp|Dies"], "Elven Archer hits the Wisp")
	eq(HistoryText.title(g.history[-1], g, 0, "en"), "You play Elven Archer on Wisp", "who did it")


func test_effects_of_a_spell_with_several_targets() -> void:
	var m := H.scene({"hero": "HERO_06", "hand": ["VAN_CS2_012"]}, {"hero": "HERO_01", "board": ["VAN_CS2_182", "VAN_CS2_182"]})
	H.play(m, m.game.players[0].hand[0], m.game.hero(1))
	eq(_fx(m.game), ["|Garrosh Hellscream|-4 Health", "|Chillwind Yeti|-1 Health", "|Chillwind Yeti|-1 Health"], "Swipe")


func test_effects_of_a_deathrattle_name_it() -> void:
	var m := H.scene({"hero": "HERO_08", "board": [{"card": "VAN_CS2_182", "exhausted": false}]}, {"hero": "HERO_01", "board": ["VAN_EX1_029"]})
	H.attack(m, m.game.players[0].board[0], m.game.players[1].board[0])
	var fx := _fx(m.game)
	check(fx.has("|Leper Gnome|Dies"), str(fx))
	check(fx.has("Deathrattle: Leper Gnome|Jaina Proudmoore|-2 Health"), str(fx))


func test_effects_of_a_weapon_and_a_heal() -> void:
	var m := H.scene({"hero": "HERO_01", "damage": 5, "hand": ["VAN_CS2_106", "VAN_EX1_011"]})
	var g := m.game
	H.play(m, g.players[0].hand[0])
	eq(_fx(g), ["|Garrosh Hellscream|Equips Fiery War Axe"], "weapon goes to the hero")
	H.play(m, g.players[0].hand[0], g.hero(0))
	eq(_fx(g), ["|Garrosh Hellscream|+2 Health"], "Voodoo Doctor heals the hero")


func test_effects_hide_the_opponents_draws() -> void:
	var m := H.scene({"hero": "HERO_08"}, {"hero": "HERO_08", "hand": ["VAN_CS2_023"], "deck": [H.WISP, H.WISP]}, 1)
	H.play(m, m.game.players[1].hand[0])
	eq(_fx(m.game, 0), ["||Opponent draws a card", "||Opponent draws a card"], "hidden from me")
	eq(_fx(m.game, 1), ["|Wisp|Drawn", "|Wisp|Drawn"], "shown to the one who draws")


func test_whispers_of_the_old_gods_events() -> void:
	var m := H.game([H.WISP])
	var g := m.game
	var line := func(ev: Dictionary, viewer: int) -> String: return HistoryText.event_lines(ev, g, viewer, "en")[0]
	var cthun := {"type": "cthun", "player": 0, "atk": 10, "health": 12}
	eq(line.call(cthun, 0), "Your C'Thun is now 10/12", "a ritual")
	eq(line.call(cthun, 1), "Opponent's C'Thun is now 10/12", "both players see it")
	eq(line.call({"type": "fizzle", "player": 0, "entity": -1, "card": "VAN_CS2_029"}, 0), "Fireball fizzles", "no target")
	var hero: int = g.players[0].hero.id
	eq(line.call({"type": "retarget", "from": -1, "to": hero}, 0), "The target is chosen at random: Jaina Proudmoore",
		"Mayor Noggenfogger")
	eq(line.call({"type": "cast", "random": true, "player": 0, "by_id": hero, "card": "VAN_CS2_029", "target": hero}, 0),
		"Jaina Proudmoore casts Fireball on Jaina Proudmoore", "Yogg-Saron's spell")
	var wisp: int = g.players[0].hand[0].id
	var shift := {"type": "transform", "from": wisp, "entity": wisp, "player": 0, "card": "VAN_CS2_182"}
	eq(line.call(shift, 0), "Your Wisp becomes Chillwind Yeti", "a card in the hand changes")
	eq(line.call(shift.merged({"card": ""}, true), 1), "A card of Opponent's changes", "hidden from the opponent")
	eq(line.call({"type": "to_hand", "player": 0, "entity": wisp, "card": "VAN_CS2_231"}, 0), "Wisp is put into your hand", "")
	eq(line.call({"type": "to_hand", "player": 0, "entity": wisp, "card": ""}, 1), "A card is put into Opponent's hand", "")
	var shuffled := {"type": "add_to_deck", "player": 0, "entity": wisp, "card": ""}
	eq(line.call(shuffled, 0), "A card is shuffled into your deck", "Prince Malchezaar's Legendaries: hidden from both")
	eq(line.call(shuffled, 1), "A card is shuffled into Opponent's deck", "")
	eq(line.call(shuffled.merged({"card": "VAN_CS2_231"}, true), 0), "Wisp is shuffled into your deck", "")
	check(HistoryText.event_lines({"type": "game_start"}, g, 0, "en").is_empty(), "the game's start says nothing")
