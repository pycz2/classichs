extends TestCase
## The end of a match: the result from the local player's side (Victory!, Defeat,
## Draw) over a picture of that result, and a draw when both heroes die at once.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _view(m: Match, bots: Array, remote := -1) -> MatchView:
	var v := MatchView.new()
	root().add_child(v)
	m.bots = bots
	m.remote = remote
	v.bind(m)
	return v


func _title(v: MatchView) -> String:
	var l := v.find_child("ResultTitle", true, false) as Label
	return l.text if l else ""


func _kind(v: MatchView) -> String:
	var art := v.find_child("ResultArt", true, false)
	return art.get_meta("kind", "") if art else ""


## Both heroes at 3 health; Hellfire deals 3 to every character.
func _hellfire_game() -> Match:
	return H.scene({"hero": "HERO_07", "damage": 27, "hand": ["VAN_CS2_062"]}, {"hero": "HERO_01", "damage": 27})


func test_hellfire_on_both_heroes_is_a_draw() -> void:
	var v := _view(_hellfire_game(), [false, true])
	var g := v.g
	v.controller.submit({"type": "play", "player": 0, "entity": g.players[0].hand[0].id, "target": -1, "pos": -1, "choice": -1})
	check(g.game_over, "the game is over")
	eq(g.winner, -1, "nobody wins")
	v.refresh()
	eq(_title(v), "Draw", "the result says Draw")
	eq(_kind(v), "draw", "the draw picture")
	v.free()


func test_both_heroes_shatter_on_a_draw() -> void:
	var v := _view(_hellfire_game(), [false, true])
	var g := v.g
	v.controller.submit({"type": "play", "player": 0, "entity": g.players[0].hand[0].id, "target": -1, "pos": -1, "choice": -1})
	eq(v.losers(), [0, 1], "both heroes break")
	v.free()


func test_training_victory_and_defeat() -> void:
	var v := _view(H.scene({"hero": "HERO_08"}), [false, true])
	v.controller.submit({"type": "concede", "player": 1})
	v.refresh()
	eq(_title(v), "Victory!", "the bot conceded")
	eq(_kind(v), "victory", "the victory picture")
	eq(v.losers(), [1], "only the bot's hero breaks")
	v.free()
	v = _view(H.scene({"hero": "HERO_08"}), [false, true])
	v.controller.submit({"type": "concede", "player": 0})
	v.refresh()
	eq(_title(v), "Defeat", "the player conceded")
	eq(_kind(v), "defeat", "the defeat picture")
	v.free()


func test_online_result_is_from_the_local_side() -> void:
	# the local player is 1 (the remote one is 0): a win of player 1 is a Victory here
	var v := _view(H.scene({"hero": "HERO_08"}), [false, false], 0)
	# a concede comes without a state check (both players may concede at once)
	eq(v.controller.submit_remote({"type": "concede", "player": 0}, ""), "", "the opponent's concede is accepted")
	v.refresh()
	eq(_title(v), "Victory!", "not \"Player 2 wins\"")
	v.free()
	v = _view(H.scene({"hero": "HERO_08"}), [false, false], 0)
	v.controller.submit({"type": "concede", "player": 1})
	v.refresh()
	eq(_title(v), "Defeat", "the local player conceded")
	v.free()


func test_hot_seat_names_the_winner() -> void:
	var v := _view(H.scene({"hero": "HERO_08"}), [false, false])
	v.controller.submit({"type": "concede", "player": 0})
	v.refresh()
	eq(_title(v), "Player 2 wins", "two people at one screen: no single side")
	eq(_kind(v), "victory", "a win picture")
	v.free()
