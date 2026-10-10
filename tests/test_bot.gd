extends TestCase


static func bot_game(seed: int, c0 := "MAGE", c1 := "WARRIOR") -> Game:
	return Game.new({"hero": Decks.hero(c0), "deck": Decks.basic(c0)},
		{"hero": Decks.hero(c1), "deck": Decks.basic(c1)}, seed)


func test_takes_lethal() -> void:
	var g := H.scene({"hero": "HERO_08", "board": ["VAN_CS2_120"], "hand": ["VAN_CS2_182"]},
		{"hero": "HERO_01", "damage": 28})
	var a := Bot.choose(g, 0)
	eq([a.type, a.get("defender", -1)], ["attack", g.hero(1).id], "attacks the hero for the win")


func test_plays_a_card_with_mana() -> void:
	var g := H.scene({"hero": "HERO_08", "hand": ["VAN_CS2_182"], "mana": 4, "max_mana": 4})
	eq(Bot.choose(g, 0).type, "play", "plays the yeti")


func test_ends_turn_when_nothing_helps() -> void:
	var g := H.scene({"hero": "HERO_08", "mana": 0, "max_mana": 0, "hand": ["VAN_CS2_182"]})
	g.players[0].hero_power.give_tag("USED")
	eq(Bot.choose(g, 0).type, "end_turn", "nothing to do")


func test_mulligan_replaces_expensive_cards() -> void:
	var g := bot_game(3)
	var p := g.players[0]
	var a := Bot.choose(g, 0)
	eq(a.type, "mulligan", "mulligan")
	var expected: Array = p.hand.filter(func(e): return g.cost(e) > 3).map(func(e): return e.id)
	expected.sort()
	eq(a.replace, expected, "cost > 3 replaced")


func test_choice_is_made() -> void:
	var g := H.scene({"hero": "HERO_05", "hand": ["VAN_DS1_184"], "deck": [H.WISP, "VAN_CS2_182", "VAN_CS2_120"]})
	H.play(g, g.players[0].hand[0])
	var a := Bot.choose(g, 0)
	eq(a.type, "choose", "answers the pending choice")
	check(g.legal_actions().has(a), "legal")


func test_actions_are_always_legal() -> void:
	for seed in [2, 5, 8]:
		var g: Game = Sim.play_random(seed, 40).game
		if g.game_over:
			continue
		var a := Bot.choose(g, g.current)
		check(g.legal_actions().has(a), "seed %d: %s" % [seed, str(a)])


func test_bot_vs_bot_finishes() -> void:
	var n := int(OS.get_environment("BOT_GAMES")) if OS.has_environment("BOT_GAMES") else 2
	for seed in n:
		var g := bot_game(seed + 1, ["MAGE", "PRIEST", "ROGUE"][seed % 3], ["WARRIOR", "HUNTER", "DRUID"][seed % 3])
		var steps := 0
		while not g.game_over and steps < 600:
			var p: int = g.current
			if g.phase == "MULLIGAN":
				p = 0 if not g.players[0].mulliganed else 1
			elif not g.pending.is_empty():
				p = g.pending.player
			var r := g.apply(Bot.choose(g, p))
			check(r.ok, "seed %d step %d: %s" % [seed, steps, r.error])
			if not r.ok:
				break
			steps += 1
		check(g.game_over, "seed %d finished in %d steps" % [seed, steps])
