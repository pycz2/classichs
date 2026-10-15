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
