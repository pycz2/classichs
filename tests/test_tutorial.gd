extends TestCase


func _start(n: int) -> Array:
	var r := Tutorial.start(n)
	return [r.game, r.tutorial]


func test_jaina_cannot_lose_in_missions_1_and_2() -> void:
	for n in [1, 2]:
		var s := _start(n)
		var g: Game = s[0]
		g.damage(g.hero(1), g.hero(0), 100)
		g.players[0].deck.clear()
		g.players[0].fatigue = 50
		g.draw(0)
		g.resolve()
		eq([g.hero(0).health(), g.game_over], [1, false], "mission %d: still alive" % n)
	var g3: Game = _start(3)[0]
	g3.damage(g3.hero(1), g3.hero(0), 100)
	g3.resolve()
	check(g3.game_over, "mission 3 can be lost")


func test_end_turn_blocked_with_cards_to_play() -> void:
	var s := _start(1)
	var g: Game = s[0]
	var t: Tutorial = s[1]
	check(t.end_turn_block(g, 0) != "", "a 1-mana minion in hand blocks the turn end")
	H.play(g, g.players[0].hand[0])
	eq(t.end_turn_block(g, 0), "", "nothing left: may end the turn")


func test_end_turn_not_blocked_by_unaffordable_card() -> void:
	var s := _start(1)
	var g: Game = s[0]
	var t: Tutorial = s[1]
	g.players[0].mana = 0
	eq(t.end_turn_block(g, 0), "", "no mana: no block")


func test_end_turn_blocked_with_attacks_until_mission_4() -> void:
	for n in [3, 4]:
		var s := _start(n)
		var g: Game = s[0]
		var t: Tutorial = s[1]
		g.players[0].hand.clear()
		H.board(g, 0, "VAN_CS2_120")
		eq(t.end_turn_block(g, 0) != "", n == 3, "mission %d" % n)


func test_hints_in_order() -> void:
	var s := _start(1)
	var g: Game = s[0]
	var t: Tutorial = s[1]
	eq(t.next_hint(g, 0), Missions.get_mission(1).intro, "intro first")
	check(t.next_hint(g, 0).contains("card"), "then how to play a card")
	eq(t.next_hint(g, 0), "", "each hint once")


func test_boss_lines() -> void:
	var s := _start(1)
	var g: Game = s[0]
	var t: Tutorial = s[1]
	eq(t.boss_line(g), Missions.get_mission(1).lines.start, "start line")
	eq(t.boss_line(g), "", "once")
	g.hero(1).damage = 6
	eq(t.boss_line(g), Missions.get_mission(1).lines.hurt, "hurt line at half health")


## Plays a mission with the bot as Jaina under the real tutorial rules
## (end of turn refused while the block applies). Returns [game, tutorial].
func _play_by_the_rules(n: int) -> Array:
	var s := _start(n)
	var g: Game = s[0]
	var t: Tutorial = s[1]
	var steps := 0
	while not g.game_over and steps < 600:
		var p: int = g.current if g.pending.is_empty() else g.pending.player
		var a := Bot.choose(g, p)
		if p == 0:
			t.next_hint(g, 0)
			if a.type == "end_turn" and t.end_turn_block(g, 0) != "":
				var other: Array = g.legal_actions().filter(func(x): return x.player == 0 and x.type in ["play", "attack"])
				a = other[0]
		var r := g.apply(a)
		if not r.ok:
			failures.append("mission %d: %s" % [n, r.error])
			break
		steps += 1
	return [g, t]


func test_bot_wins_every_mission_under_the_rules() -> void:
	for n in range(1, 7):
		var g: Game = _play_by_the_rules(n)[0]
		eq([g.game_over, g.winner], [true, 0], "mission %d won by Jaina" % n)


func test_every_hint_can_appear() -> void:
	for n in range(1, 7):
		var t: Tutorial = _play_by_the_rules(n)[1]
		for key in Missions.get_mission(n).hints:
			check(t._shown.has(key), "mission %d: hint '%s' never appeared" % [n, key])


func test_transcendence_needs_minions() -> void:
	var g := H.scene({"hero": "HERO_08"}, {"hero": "TU4f_001", "hero_power": "VAN_HERO_08bp", "hand": ["TU4f_006"]}, 1)
	check(not g.legal_actions().any(func(a): return a.type == "play"), "not playable without minions")
