extends TestCase
## A batch of events plays as steps, one after another (MatchView.steps): a card played,
## its arrow, each hit, each death at its own event; the table shows the game between them.

const MISSILES := "VAN_EX1_277"
const FIREBALL := "VAN_CS2_029"
const ARCHER := "VAN_CS2_189"  # Elven Archer: Battlecry, 1 damage
const YETI := "VAN_CS2_182"
const FLAMESTRIKE := "VAN_CS2_032"


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _view(p0: Dictionary, p1 := {"hero": "HERO_01"}) -> MatchView:
	var v := MatchView.new()
	root().add_child(v)
	v.bind(H.scene(p0, p1, 0, [false, false]))
	return v


## Player 0 plays its card_id (at target), applied without the table seeing it: the batch.
func _batch(v: MatchView, card_id: String, target := -1) -> Dictionary:
	var m := v.controller
	var card: GameView.Ent = m.game.players[0].hand.filter(func(e): return e.card_id == card_id)[0]
	var r := m._apply({"type": "play", "player": 0, "entity": card.id, "target": target,
		"pos": m.game.players[0].board.size() if card.is_minion() else -1, "choice": -1})
	check(r.ok, "played " + card_id)
	return {"events": r.events, "snap": m.game.snapshot, "hist": m.game.history.size()}


static func _kinds(steps: Array) -> Array:
	return steps.map(func(s): return s.k)


func test_arcane_missiles_hit_one_after_another() -> void:
	var v := _view({"hero": "HERO_08", "hand": [MISSILES]})
	var item := _batch(v, MISSILES)
	var steps := MatchView.steps(item.events)
	eq(_kinds(steps), ["play", "hit", "hit", "hit", "spell_done"], "three hits, each its own step")
	var hero: int = v.g.hero(1).id
	var health := []
	v._begin_batch(item)
	for st in steps:
		v._step_apply(st)
		health.append(v._views[hero].s.health())
	v._end_batch()
	eq(health, [30, 29, 28, 27, 27], "the hero's health goes down hit by hit")
	eq(v._views[hero].s.health(), 27, "the end matches the game")
	v.free()


func test_flamestrike_hits_everything_at_once() -> void:
	var v := _view({"hero": "HERO_08", "hand": [FLAMESTRIKE]}, {"hero": "HERO_01", "board": [H.WISP, H.WISP, H.WISP]})
	var steps := MatchView.steps(_batch(v, FLAMESTRIKE).events)
	eq(_kinds(steps), ["play", "hit", "death", "spell_done"], "one hit step, one death phase")
	eq(steps[1].evs.size(), 3, "the three minions burn together")
	eq(steps[2].evs.size(), 3, "and die together")
	v.free()


func test_a_battlecry_lands_then_aims_then_hits() -> void:
	var v := _view({"hero": "HERO_08", "hand": [ARCHER]}, {"hero": "HERO_01", "board": [YETI]})
	var yeti: int = v.g.players[1].board[0].id
	var item := _batch(v, ARCHER, yeti)
	var steps := MatchView.steps(item.events)
	eq(_kinds(steps), ["play", "summon", "aim", "hit"], "the card, the minion on the board, its arrow, the hit")
	var archer: int = item.events[0].entity
	eq([steps[2].src, steps[2].to], [archer, yeti], "the arrow goes from the Archer to the Yeti")
	v._begin_batch(item)
	v._step_apply(steps[0])
	check(not v._views.has(archer), "the card left the hand")
	v._step_apply(steps[1])
	check(v._views.get(archer) is MinionView, "the Archer stands on the board")
	eq(v._views[yeti].s.health(), 5, "the Yeti is not hit yet")
	v._step_apply(steps[2])
	v._step_apply(steps[3])
	eq(v._views[yeti].s.health(), 4, "now it is")
	v._end_batch()
	v.free()


func test_a_minion_dies_at_its_death_event() -> void:
	var v := _view({"hero": "HERO_08", "hand": [FIREBALL]}, {"hero": "HERO_01", "board": [YETI]})
	var yeti: int = v.g.players[1].board[0].id
	var item := _batch(v, FIREBALL, yeti)
	var steps := MatchView.steps(item.events)
	eq(_kinds(steps), ["play", "aim", "hit", "death", "spell_done"], "the card, its arrow, the hit, the death")
	v._begin_batch(item)
	for i in 3:
		v._step_apply(steps[i])
		check(v._views.has(yeti), "the Yeti is still there after %s" % steps[i].k)
	eq(v._views[yeti].s.health(), -1, "hit for 6")
	v._step_apply(steps[3])
	check(not v._views.has(yeti), "gone at its death")
	v._end_batch()
	v.free()


func test_hero_power_shows_before_its_effect() -> void:
	var v := _view({"hero": "HERO_08"}, {"hero": "HERO_01", "board": [YETI]})
	var yeti: int = v.g.players[1].board[0].id
	var r := v.controller._apply({"type": "hero_power", "player": 0, "target": yeti})
	eq(_kinds(MatchView.steps(r.events)), ["power", "aim", "hit"], "the power, its arrow, the ping (the engine logs the ping first)")
	v.free()


func test_each_batch_shows_its_own_game() -> void:
	var v := _view({"hero": "HERO_08", "hand": [H.WISP, FIREBALL]})
	var first := _batch(v, H.WISP)
	_batch(v, FIREBALL, v.controller.game.hero(1).id)  # already in the game, still to be shown
	v._busy = true  # the table animates
	v._begin_batch(first)
	eq(v.g.hero(1).health(), 30, "the Fireball of the next batch has not hit yet on the table")
	check(v.g.players[0].hand.any(func(e): return e.card_id == FIREBALL), "and is still in the hand")
	v._end_batch()
	v._busy = false
	v.refresh()
	eq(v.g.hero(1).health(), 24, "then the table catches up")
	v.free()


func test_mulligan_cards_go_down_in_the_order_shown() -> void:
	var m := H.decks("MAGE", "WARRIOR", 5, 0, [false, true])  # the bot chooses at once
	var v := MatchView.new()
	root().add_child(v)
	v.bind(m)
	var ov := v._overlay
	var views: Array = ov.find_children("*", "CardView", true, false)
	var ids := [views[0].entity_id, views[2].entity_id]
	ov.set_meta("views", views)  # what Confirm does before it sends the choice
	ov.set_meta("replaced", ids)
	ov.set_meta("slots", {})
	v._mull_wait = 0
	var r := m._apply({"type": "mulligan", "player": 0, "replace": ids})
	v._animate({"events": r.events, "snap": m.game.snapshot, "hist": m.game.history.size()})
	var shown: Array = ov.get_meta("shown").map(func(pair): return pair[0])
	var hand: Array = v.g.players[0].hand.map(func(e): return e.id)
	eq(shown.size(), views.size(), "every place holds a card")
	eq(shown[1], views[1].entity_id, "the kept card stays in its place")
	eq(hand.slice(0, shown.size()), shown, "the hand has the cards in the order they stood")
	check(v._overlay == null, "the mulligan screen is closed")
	check(hand.all(func(id): return v._views.has(id)), "all in the hand")
	v.free()
