extends TestCase


func _build(sc: Dictionary) -> Game:
	var r := Scenario.build(sc)
	check(r.error == "", "build error: " + str(r.error))
	return r.game


func test_minimal_scenario() -> void:
	var g := _build({"players": [{"hero": "HERO_08"}, {"hero": "HERO_01"}]})
	eq(g.phase, "PLAY", "play phase")
	eq(g.current, 0, "player 0 to move")
	eq(g.players[0].hand.size(), 0, "no opening draw")
	eq(g.players[0].hero.health(), 30, "full health")
	eq(g.players[1].hero_power.card_id, "VAN_HERO_01bp", "default hero power")


func test_full_player_fields() -> void:
	var g := _build({"current": 1, "turn": 7, "players": [
		{"hero": "HERO_08", "damage": 12, "armor": 3, "mana": 4, "max_mana": 6,
		 "hand": ["VAN_CS2_029"], "deck": ["VAN_CS2_231", "VAN_CS2_120"],
		 "weapon": {"card": "VAN_CS2_106", "durability": 1}, "secrets": ["VAN_EX1_287"]},
		{"hero": "HERO_01", "hero_power_used": true}]})
	var p := g.players[0]
	eq([g.current, g.turn], [1, 7], "turn state")
	eq(p.hero.health(), 18, "damage")
	eq(int(p.hero.tags.ARMOR), 3, "armor")
	eq([p.mana, p.max_mana], [4, 6], "mana")
	eq(p.hand[0].card_id, "VAN_CS2_029", "hand")
	eq(p.deck.back().card_id, "VAN_CS2_120", "top card is last")
	eq(int(p.weapon.tags.DURABILITY), 1, "weapon durability")
	eq(p.secrets[0].zone, "SECRET", "secret zone")
	check(g.players[1].hero_power.has("USED"), "power used")


func test_board_entry_options() -> void:
	var g := _build({"players": [
		{"hero": "HERO_08", "board": ["VAN_CS2_120",
			{"card": "VAN_CS1_042", "damage": 1, "tags": ["FROZEN"], "enchantments": [{"atk": 2.0, "hp": 2.0}]},
			{"card": "VAN_CS2_231", "exhausted": true}]},
		{"hero": "HERO_01"}]})
	var b := g.players[0].board
	check(not b[0].has("EXHAUSTED"), "ready by default")
	eq([b[1].atk(), b[1].max_health(), b[1].health()], [3, 4, 3], "buffed and damaged")
	check(b[1].has("TAUNT") and b[1].has("FROZEN"), "card tags kept, extra tag added")
	check(b[2].has("EXHAUSTED"), "exhausted on request")


func test_errors_name_the_field() -> void:
	var r := Scenario.build({"players": [{"hero": "HERO_08", "board": ["VAN_CS2_120", "NOPE"]}, {"hero": "HERO_01"}]})
	eq(r.game, null, "no game")
	eq(r.error, "players[0].board[1]: unknown card NOPE", "error path")
	r = Scenario.build({"players": [{"hero": "HERO_08", "board": ["VAN_CS2_029"]}, {"hero": "HERO_01"}]})
	eq(r.error, "players[0].board[0]: VAN_CS2_029 is not a minion", "type check")
	r = Scenario.build({"players": [{"hero": "HERO_08"}]})
	eq(r.error, "players: need exactly 2", "player count")


func test_scenario_is_playable() -> void:
	var g := _build({"players": [
		{"hero": "HERO_08", "board": ["VAN_CS2_120"], "hand": ["VAN_CS2_029"], "mana": 10, "max_mana": 10},
		{"hero": "HERO_01", "board": ["VAN_CS2_231"]}]})
	var croc := g.players[0].board[0]
	var wisp := g.players[1].board[0]
	check(g.apply({"type": "attack", "player": 0, "attacker": croc.id, "defender": wisp.id}).ok, "attack")
	eq(wisp.zone, "GRAVEYARD", "wisp died")


func test_dump_build_roundtrip_after_random_play() -> void:
	for seed in [3, 9, 27]:
		var g: Game = Sim.play_random(seed, 80).game
		if g.game_over:
			continue
		var d1 := Scenario.dump(g)
		var d2 := Scenario.dump(_build(d1))
		eq(d2, d1, "seed %d roundtrip" % seed)


func test_json_text_roundtrip() -> void:
	var g: Game = Sim.play_random(5, 60).game
	var text := JSON.stringify(Scenario.dump(g))
	var r := Scenario.build(JSON.parse_string(text))
	eq(r.error, "", "built from text")


func test_example_file_loads() -> void:
	var sc = JSON.parse_string(FileAccess.get_file_as_string("res://tests/scenarios/example.json"))
	eq(Scenario.build(sc).error, "", "example scenario")
