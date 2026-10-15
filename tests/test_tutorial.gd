extends TestCase
## The tutorial's hints and boss lines (GDScript) over a mission game in the engine;
## the missions' rules (Jaina's safety net, turn-end blocks) are the engine's.


func _start(n: int) -> Array:
	var m := Match.new()
	m.bot_delay = 0.0
	eq(m.setup({"mission": n}, [false, true]), "", "mission %d starts" % n)
	return [m, Tutorial.new(n, m)]


func test_end_turn_blocked_with_cards_to_play() -> void:
	var s := _start(1)
	var m: Match = s[0]
	check(m.end_turn_block(0) != "", "a 1-mana minion in hand blocks the turn end")
	H.play(m, m.game.players[0].hand[0])
	eq(m.end_turn_block(0), "", "nothing left: may end the turn")
	m.free()


func test_hints_in_order() -> void:
	var s := _start(1)
	var m: Match = s[0]
	var t: Tutorial = s[1]
	eq(t.next_hint(m.game, 0), Missions.get_mission(1).intro, "intro first")
	check(t.next_hint(m.game, 0).contains("card"), "then how to play a card")
	eq(t.next_hint(m.game, 0), "", "each hint once")
	m.free()


func test_boss_lines() -> void:
	var s := _start(1)
	var m: Match = s[0]
	var t: Tutorial = s[1]
	eq(t.boss_line(m.game), Missions.get_mission(1).lines.start, "start line")
	eq(t.boss_line(m.game), "", "once")
	m.game.hero(1).damage = 6  # (the view only: the line follows what the table shows)
	eq(t.boss_line(m.game), Missions.get_mission(1).lines.hurt, "hurt line at half health")
	m.free()


## Plays a mission with the engine's bot as Jaina under the real tutorial rules
## (end of turn refused while the block applies). Returns [match, tutorial].
func _play_by_the_rules(n: int) -> Array:
	var s := _start(n)
	var m: Match = s[0]
	var t: Tutorial = s[1]
	m.start()
	var steps := 0
	while not m.game.game_over and steps < 600:
		var a: Dictionary = Rules.request({"op": "bot", "game": m.id, "player": 0}).action
		t.next_hint(m.game, 0)
		if a.type == "end_turn" and m.end_turn_block(0) != "":
			a = m.legal().filter(func(x): return x.player == 0 and x.type in ["play", "attack"])[0]
		var r := m.submit(a)
		if not r.ok:
			failures.append("mission %d: %s" % [n, r.error])
			break
		steps += 1
	return [m, t]


func test_bot_wins_every_mission_under_the_rules() -> void:
	for n in range(1, 7):
		var s := _play_by_the_rules(n)
		var m: Match = s[0]
		eq([m.game.game_over, m.game.winner], [true, 0], "mission %d won by Jaina" % n)
		for key in Missions.get_mission(n).hints:
			check(s[1]._shown.has(key), "mission %d: hint '%s' never appeared" % [n, key])
		m.free()
