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
	eq(_kinds(steps), ["play", "summon", "aim", "hit"], "the card, the minion on the board, its arrow, the hit (then nothing: it stands there)")
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


## A card drawn by a card's effect (Novice Engineer) comes from the deck, not from the minion.
func test_a_drawn_card_comes_from_the_deck() -> void:
	var evs := [{"type": "play", "player": 0, "entity": 5, "kind": "minion", "target": -1},
		{"type": "summon", "player": 0, "entity": 5},
		{"type": "draw", "player": 0, "entity": 9, "by_id": 5},
		{"type": "after_summon", "entity": 5}]
	eq(MatchView.steps(evs).map(func(s): return s.k), ["play", "summon", "card"])
	var src := FileAccess.get_file_as_string("res://ui/match_view.gd")
	check(src.contains('ev.type == "add_to_hand" and _views.has(ev.get("by_id", -1))'), "only a made card comes from the card that made it")
	var plain := [{"type": "play", "player": 0, "entity": 5, "kind": "minion", "target": -1},
		{"type": "summon", "player": 0, "entity": 5}, {"type": "after_summon", "entity": 5}]
	eq(MatchView.steps(plain).map(func(s): return s.k), ["play", "summon"])


## A minion the player puts down stands in its slot from then on: while the game plays it (a
## server answers later), as its Battlecry aims and after; no big card, no move back to the hand.
func test_a_minion_put_down_stands_in_its_place() -> void:
	var v := _view({"hero": "HERO_08", "hand": [ARCHER], "board": [YETI, YETI]}, {"hero": "HERO_01", "board": [YETI]})
	var archer: int = v.g.players[0].hand[0].id
	var enemy: int = v.g.players[1].board[0].id
	var slot0 := func() -> bool:
		var av = v._views.get(archer)
		return av is MinionView and is_equal_approx(v._home_of(archer).x, TableLayout.board_x(0, 3) + MinionView.SIZE.x / 2.0)
	v._placed[archer] = 0  # put down, the game not played yet (an online answer on its way)
	v.refresh()
	check(slot0.call(), "it stands in slot 0 at once")
	check(not v.g.players[0].hand.is_empty() and not v._views.get(archer) is CardView, "not in the hand")
	v._placed.clear()
	v.refresh()
	v._select(archer)
	v.click_board(0)
	check(slot0.call(), "waiting for its target: in slot 0")
	v.click_entity(enemy)
	check(slot0.call() and v._placed.is_empty(), "played: still in slot 0")
	eq(v.g.ent(enemy).health(), 4, "the Battlecry hit")
	v.free()


# --- attacks: what happens on the way plays at the middle of the leap (0.51) -------------

const EXPLOSIVE := "VAN_EX1_610"
const FREEZING := "VAN_EX1_611"
const MISDIRECTION := "VAN_EX1_533"
const NOBLE := "VAN_EX1_130"
const VAPORIZE := "VAN_EX1_594"
const TRUESILVER := "VAN_CS2_097"
const SQUIRE := "VAN_EX1_008"  # Argent Squire: 1/1 Divine Shield


## Player 0's first minion (its hero when it has none) attacks player 1's hero (or first minion):
## the batch (its action is in the history).
func _attack(v: MatchView, at_hero := true) -> Dictionary:
	var m := v.controller
	var b0: Array = m.game.players[0].board
	var a: int = b0[0].id if not b0.is_empty() else m.game.hero(0).id
	var d: int = m.game.hero(1).id if at_hero else m.game.players[1].board[0].id
	var r := m._apply({"type": "attack", "player": 0, "attacker": a, "defender": d})
	check(r.ok, "attacked")
	return {"events": r.events, "snap": m.game.snapshot, "hist": m.game.history.size(), "a": a, "d": d}


func test_a_plain_attack_is_one_step() -> void:
	var v := _view({"hero": "HERO_08", "board": [YETI]}, {"hero": "HERO_01", "board": [YETI]})
	var steps := MatchView.steps(_attack(v, false).events)
	eq(_kinds(steps), ["attack"], "the leap and both hits")
	eq(steps[0].evs.size(), 3, "the attack and its two hits")
	check(not steps[0].get("pause", false), "no stop on the way")
	v.free()


func test_divine_shield_pops_with_the_hit() -> void:
	var v := _view({"hero": "HERO_08", "board": [SQUIRE]}, {"hero": "HERO_01", "board": [YETI]})
	var steps := MatchView.steps(_attack(v, false).events)
	eq(_kinds(steps), ["attack"], "one moment")
	eq(steps[0].evs.map(func(e): return e.type), ["attack", "damage", "divine_shield_lost"], "the shield goes with the blow")
	var v2 := _view({"hero": "HERO_08", "board": [YETI]}, {"hero": "HERO_01", "board": [SQUIRE]})
	steps = MatchView.steps(_attack(v2, false).events)
	eq(steps[0].evs.map(func(e): return e.type), ["attack", "divine_shield_lost", "damage"], "the defender's shield too")
	v.free()
	v2.free()


func test_explosive_trap_goes_off_half_way() -> void:
	var v := _view({"hero": "HERO_08", "board": [YETI]}, {"hero": "HERO_05", "secrets": [EXPLOSIVE]})
	var item := _attack(v)
	var steps := MatchView.steps(item.events, v._aimed(item))
	eq(_kinds(steps), ["attack", "secret", "hit", "strike"], "the leap stops, the Secret, its blast, then the blow")
	check(steps[0].pause, "the attack stops on its way")
	eq(steps[0].aimed, item.d, "towards the hero")
	eq(steps[2].evs.size(), 2, "the blast hits both at once")
	eq(steps[3].evs.size(), 1, "the Yeti's blow")
	var health := []
	v._begin_batch(item)
	for st in steps:
		v._step_apply(st)
		health.append(v._views[item.a].s.health())
	v._end_batch()
	eq(health, [5, 5, 3, 3], "the Yeti is burnt half-way")
	v.free()


func test_freezing_trap_sends_the_attacker_back_from_half_way() -> void:
	var v := _view({"hero": "HERO_08", "board": [YETI]}, {"hero": "HERO_05", "secrets": [FREEZING]})
	var item := _attack(v)
	var steps := MatchView.steps(item.events)
	eq(_kinds(steps), ["attack", "secret", "bounce", "strike"], "no blow: the strike step only ends the leap")
	check(steps[3].evs.is_empty(), "nothing lands")
	v.free()


func test_vaporize_destroys_it_on_its_way() -> void:
	var v := _view({"hero": "HERO_08", "board": [YETI]}, {"hero": "HERO_08", "secrets": [VAPORIZE]})
	var item := _attack(v)
	eq(_kinds(MatchView.steps(item.events)), ["attack", "secret", "death", "strike"])
	v.free()


func test_noble_sacrifice_takes_the_blow() -> void:
	var v := _view({"hero": "HERO_08", "board": [YETI]}, {"hero": "HERO_04", "secrets": [NOBLE]})
	var item := _attack(v)
	var steps := MatchView.steps(item.events, v._aimed(item))
	eq(_kinds(steps), ["attack", "secret", "summon", "strike", "death"], "the Defender comes, takes the blow, dies")
	eq(steps[0].aimed, item.d, "it set off at the hero")
	var defender: int = steps[2].evs[0].entity
	eq(steps[3].defender, defender, "and strikes the Defender")
	v._begin_batch(item)
	for i in 3:
		v._step_apply(steps[i])
	check(v._views.get(defender) is MinionView, "the Defender stands there before the blow")
	v._end_batch()
	v.free()


func test_misdirection_turns_the_attack() -> void:
	var v := _view({"hero": "HERO_08", "board": [YETI, YETI]}, {"hero": "HERO_05", "secrets": [MISDIRECTION], "board": [YETI]})
	var item := _attack(v)
	var steps := MatchView.steps(item.events, v._aimed(item))
	eq(_kinds(steps), ["attack", "secret", "strike"])
	eq(steps[0].aimed, item.d, "it set off at the hero (the order: the event has the new target)")
	check(steps[2].defender != item.d, "the blow goes elsewhere")
	v.free()


func test_truesilver_heals_half_way() -> void:
	var v := _view({"hero": "HERO_04", "weapon": TRUESILVER, "hero_state": {"damage": 10}}, {"hero": "HERO_05", "board": [YETI]})
	var item := _attack(v, false)
	var steps := MatchView.steps(item.events)
	eq(_kinds(steps), ["attack", "hit", "strike"], "the leap stops, the heal, the blow")
	eq(steps[1].evs[0].type, "heal")
	v.free()


## An online game: the server's events have the new target; the attack sent keeps the one asked.
func test_an_online_attack_keeps_its_target_in_the_history() -> void:
	var m := H.scene({"hero": "HERO_08"})
	m._sent = {"type": "attack", "player": 0, "attacker": 5, "defender": 3}
	m.on_state({"view": m.game.snapshot, "events": [{"type": "attack", "attacker": 5, "defender": 1, "player": 0}]})
	eq(m.game.history.back().action.defender, 3, "the target asked for")
	check(m._sent.is_empty(), "used once")


## Mind Vision's copy comes out of the opponent's hand (the top of the table), not a deck.
func test_a_copied_card_comes_from_the_opponents_hand() -> void:
	var v := _view({"hero": "HERO_06", "hand": ["VAN_CS2_003"]}, {"hero": "HERO_01", "hand": [YETI, YETI, YETI]})
	var item := _batch(v, "VAN_CS2_003")
	var ev: Dictionary = item.events.filter(func(e): return e.type == "add_to_hand")[0]
	v._begin_batch(item)
	var at = v._copy_origin(ev)
	var mid: int = v.g.players[1].hand[1].id
	eq(at, v._center_of(mid), "from the middle of the opponent's hand (its cards are hidden)")
	check(v._copy_origin({"type": "add_to_hand", "player": 0, "entity": 99, "by": ARCHER}) == null, "a card that copies nothing: no")
	v._end_batch()
	v.free()


## The looks of 0.51: a used weapon's Durability is red, a Spell Damage minion sparkles (a
## shader), sleeping z's are green.
func test_table_looks() -> void:
	var bow := {"durability": 2}
	eq([Frames.durability_color(1, bow), Frames.durability_color(2, bow), Frames.durability_color(3, bow)],
		[Frames.DAMAGED, Color.WHITE, Frames.BUFFED], "below the card's Durability: red")
	check(MinionView.SLEEP_Z.g > 0.8 and MinionView.SLEEP_Z.r < 0.6, "green z's")
	var v := _view({"hero": "HERO_08", "board": ["VAN_CS2_142", YETI]})  # Kobold Geomancer: Spell Damage +1
	var kobold: MinionView = v._views[v.g.players[0].board[0].id]
	var yeti: MinionView = v._views[v.g.players[0].board[1].id]
	kobold._process(0.0)
	yeti._process(0.0)
	check(kobold.get_node_or_null("Arcane") is ColorRect and kobold.get_node("Arcane").material is ShaderMaterial, "the arcane shader")
	check(yeti.get_node_or_null("Arcane") == null, "not on a minion without Spell Damage")
	kobold.s.silenced = true
	kobold._process(0.0)
	check(kobold._arcane == null, "silenced: gone")
	v.free()


## A discarded card leaves the hand by itself, face up, and burns (it rises: see _discard).
func test_a_discarded_card_rises_and_burns() -> void:
	var v := _view({"hero": "HERO_07", "hand": ["VAN_EX1_308", YETI]}, {"hero": "HERO_01"})
	var yeti: int = v.g.players[0].hand[1].id
	var item := _batch(v, "VAN_EX1_308", v.g.hero(1).id)
	var steps := MatchView.steps(item.events)
	eq(_kinds(steps), ["play", "aim", "hit", "discard", "spell_done"], "Soulfire: the hit, then the discard")
	v._begin_batch(item)
	for i in 3:
		v._step_apply(steps[i])
	v._discard(steps[3])
	check(not v._views.has(yeti), "out of the hand")
	var burning: Array = v._fx.get_children().filter(func(c): return c is CardView and c.card_id == YETI)
	check(burning.size() == 1 and burning[0].face_up and burning[0].material is ShaderMaterial, "shown and burning")
	v._end_batch()
	v.free()
