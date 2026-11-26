extends TestCase
## Orders given while the table still animates wait in a queue and are carried
## out one by one after the animations, in order; what can be ordered next is
## checked against the state after the queued orders.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _view(m: Match, bots := [false, true]) -> MatchView:
	var v := MatchView.new()
	root().add_child(v)
	m.bots = bots
	v.bind(m)
	return v


## Mage with Fireball (4) and Frostbolt (2), 6 mana; a Chillwind Yeti that can attack.
func _game() -> Match:
	return H.scene({"hero": "HERO_08", "mana": 6, "max_mana": 6, "hand": ["VAN_CS2_029", "VAN_CS2_024"],
		"board": ["VAN_CS2_182"]}, {"hero": "HERO_01"})


func _play(v: MatchView, card_id: String, target: int) -> Dictionary:
	for a in v._legal():
		if a.type == "play" and v.g.ent(a.entity).card_id == card_id and a.get("target", -1) == target:
			return a
	return {}


func test_orders_wait_while_the_table_animates() -> void:
	var m := _game()
	var g := m.game
	var v := _view(m)
	var foe: int = g.players[1].hero.id
	v._busy = true  # an animation is running
	v._act(_play(v, "VAN_CS2_029", foe))
	eq(v._pending_acts.size(), 1, "Fireball waits")
	eq(g.players[1].hero.damage, 0, "nothing happened yet")
	eq(g.players[0].hand.size(), 2, "the card is still in the hand")
	check(_play(v, "VAN_CS2_029", foe).is_empty(), "the queued Fireball can't be ordered twice")
	check(not _play(v, "VAN_CS2_024", foe).is_empty(), "Frostbolt still fits the 2 mana left")
	v._act(_play(v, "VAN_CS2_024", foe))
	eq(v._pending_acts.size(), 2, "two orders wait")
	check(v._legal().all(func(a): return a.type != "play"), "no mana left for more cards")
	var yeti: int = g.players[0].board[0].id
	v._act({"type": "attack", "player": 0, "attacker": yeti, "defender": foe})
	eq(v._pending_acts.size(), 3, "the attack waits too")
	eq(v._views[yeti].glow, Palette.SELECTED, "an ordered attacker is marked")
	v._busy = false  # the animation ended
	v._release_orders()
	eq(v._pending_acts.size(), 0, "all carried out")
	eq(g.players[1].hero.damage, 6 + 3 + 4, "Fireball, Frostbolt and the Yeti, in order")
	eq(g.players[0].hand.size(), 0, "both cards played")
	v.free()


func test_end_turn_can_be_ordered_too() -> void:
	var m := _game()
	var g := m.game
	var v := _view(m)
	v._busy = true
	v._act(_play(v, "VAN_CS2_024", g.players[1].hero.id))
	v._on_end_turn()
	eq(v._pending_acts.size(), 2, "the end of the turn waits after the Frostbolt")
	check(v._legal().all(func(a): return a.type == "concede"), "nothing more this turn but conceding")
	v._busy = false
	v._release_orders()
	check(g.turn > 1 or g.current != 0, "the turn ended after the Frostbolt")
	check(not g.players[0].hand.any(func(e): return e.card_id == "VAN_CS2_024"), "the Frostbolt was played first")
	check(g.players[1].hero.damage >= 3, "and hit (then fatigue on an empty deck)")
	v.free()


func test_an_order_that_became_impossible_is_dropped() -> void:
	var m := _game()
	var g := m.game
	var v := _view(m, [false, false])  # two people: the turn stays with the other one
	v._busy = true
	v._act(_play(v, "VAN_CS2_029", g.players[1].hero.id))
	v._act(_play(v, "VAN_CS2_024", g.players[1].hero.id))
	v.controller.submit({"type": "end_turn", "player": 0})  # e.g. the turn timer ran out
	v._busy = false
	v._release_orders()
	eq(v._pending_acts.size(), 0, "the queue is cleared")
	eq(g.players[0].hand.size(), 2, "nothing was played on the opponent's turn")
	check(v._hint.text != "", "the player is told")
	v.free()


func test_no_waiting_orders_without_an_animation() -> void:
	var m := _game()
	var g := m.game
	var v := _view(m)
	v._act(_play(v, "VAN_CS2_024", g.players[1].hero.id))
	eq(v._pending_acts.size(), 0, "carried out at once")
	eq(g.players[1].hero.damage, 3, "done")
	v.free()


## The opponent's turn is over in the game but the table still plays it out: our side shows nothing of our turn
## (no playable or attack glow, End Turn on the opponent's side and off, no orders taken) until every queued
## batch and the turn change have played; then it all lights up at once.
func test_our_turn_lights_up_only_after_the_opponents_turn_played_out() -> void:
	var m := H.scene({"hero": "HERO_08", "mana": 3, "max_mana": 3, "hand": ["VAN_CS2_024"], "board": ["VAN_CS2_182"]},
		{"hero": "HERO_01", "mana": 3, "max_mana": 3, "hand": [H.WISP, H.WISP]}, 0, [false, true])
	var v := MatchView.new()
	root().add_child(v)
	v.bind(m)
	var bolt: int = m.game.players[0].hand[0].id
	var yeti: int = m.game.players[0].board[0].id
	v._busy = true  # (as if an animation ran: the batches queue)
	Anim.instant = false
	m.submit({"type": "end_turn", "player": 0})  # the bot plays its whole turn at once
	Anim.instant = true
	eq([m.game.current, m.actor()], [0, 0], "in the game our turn has begun")
	check(v._queue.size() >= 3, "the table has the opponent's turn still to show: %d batches" % v._queue.size())
	while v._queue.size() > 1:
		v._animate(v._queue.pop_front())
		check(not v.my_action(), "no move of ours yet")
		eq([v._views[bolt].glow, v._views[yeti].glow], [Color.TRANSPARENT, Color.TRANSPARENT], "no glow in our hand or board")
		check(v._end_turn.disabled, "End Turn off")
		eq(v._end_turn.get_meta("side"), "enemy", "End Turn shows the opponent's turn")
	v.click_entity(bolt)
	check(v._sel.is_empty(), "a click takes no order")
	v._play_queue()  # the last batch: our turn begins on the table
	check(v.my_action(), "now we move")
	eq(v._end_turn.get_meta("side"), "own", "End Turn turns over")
	check(not v._end_turn.disabled, "and is on")
	eq([v._views[bolt].glow, v._views[yeti].glow], [Palette.PLAYABLE, Palette.PLAYABLE], "the Frostbolt and the Yeti light up")
	v.free()
