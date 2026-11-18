extends TestCase
## The table shows each effect where it happens: a hit and its freeze land together (and the frost spreads
## over the portrait), a card shuffled into a deck flies from its source into that deck, a card added to a hand
## comes from where it was made, the numbers of hand cards, Hero Powers and weapons turn green or red, End Turn
## turns over with the turn, a Joust shows whose card is which, a Start of Game card shows what it does, a
## targeted spell aims as its light (a card again when it goes back), a Secret going off shows over its place.

const YETI := "VAN_CS2_182"
const FROSTBOLT := "VAN_CS2_024"
const BLIZZARD := "VAN_CS2_028"
const WATER_ELEMENTAL := "VAN_CS2_033"
const FIREBALL := "VAN_CS2_029"
const EXPLOSIVE := "VAN_EX1_610"
const AXE := "VAN_CS2_106"  # Fiery War Axe 3/2


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _view(p0: Dictionary, p1 := {"hero": "HERO_01"}, bots := [false, false]) -> MatchView:
	var v := MatchView.new()
	root().add_child(v)
	v.bind(H.scene(p0, p1, 0, bots))
	return v


## Player 0 plays its card_id (at target), applied without the table seeing it: the batch.
func _batch(v: MatchView, card_id: String, target := -1) -> Dictionary:
	var m := v.controller
	var card: GameView.Ent = m.game.players[0].hand.filter(func(e): return e.card_id == card_id)[0]
	var r := m._apply({"type": "play", "player": 0, "entity": card.id, "target": target,
		"pos": m.game.players[0].board.size() if card.is_minion() else -1, "choice": -1})
	check(r.ok, "played " + card_id)
	return {"events": r.events, "snap": m.game.snapshot, "hist": m.game.history.size()}


## A batch of made-up events on the game as it is (what a pack's card would log).
static func _fake(v: MatchView, evs: Array) -> Dictionary:
	return {"events": evs, "snap": v.controller.game.snapshot, "hist": v.controller.game.history.size()}


static func _kinds(steps: Array) -> Array:
	return steps.map(func(s): return s.k)


func test_frostbolt_hits_and_freezes_at_once() -> void:
	var v := _view({"hero": "HERO_08", "hand": [FROSTBOLT]}, {"hero": "HERO_01", "board": [YETI]})
	var yeti: int = v.g.players[1].board[0].id
	var item := _batch(v, FROSTBOLT, yeti)
	var steps := MatchView.steps(item.events)
	eq(_kinds(steps), ["play", "aim", "hit", "spell_done"], "one hit step")
	eq(steps[2].evs.map(func(e): return e.type), ["damage", "freeze"], "the hit and the freeze land together")
	v._begin_batch(item)
	for st in steps.slice(0, 3):
		v._step_apply(st)
	var mv: MinionView = v._views[yeti]
	eq([mv.s.health(), mv.s.has("FROZEN")], [2, true], "hit and frozen in the same step")
	mv._process(0.0)
	check(mv.frost != null and mv.frost.color.a == 1.0, "the frost covers it")
	v._end_batch()
	v.free()


func test_blizzard_hits_and_freezes_everything_together() -> void:
	var v := _view({"hero": "HERO_08", "hand": [BLIZZARD]}, {"hero": "HERO_01", "board": [YETI, YETI, YETI]})
	var steps := MatchView.steps(_batch(v, BLIZZARD).events)
	eq(_kinds(steps), ["play", "hit", "spell_done"], "one hit step for the three")
	eq(steps[1].evs.size(), 6, "three hits and three freezes")
	v.free()


func test_water_elemental_freezes_with_its_blow() -> void:
	var v := _view({"hero": "HERO_08", "board": [WATER_ELEMENTAL]}, {"hero": "HERO_01", "board": [YETI]})
	var m := v.controller
	var r := m._apply({"type": "attack", "player": 0, "attacker": m.game.players[0].board[0].id, "defender": m.game.players[1].board[0].id})
	check(r.ok, "attacked")
	var steps := MatchView.steps(r.events)
	eq(_kinds(steps), ["attack"], "the blow and the freeze are one moment")
	check(steps[0].evs.any(func(e): return e.type == "freeze"), "the freeze lands with the blow")
	v.free()


func test_frost_melts_when_it_thaws() -> void:
	var v := _view({"hero": "HERO_08", "board": [YETI]})
	var mv: MinionView = v._views[v.g.players[0].board[0].id]
	var hv: HeroView = v._views[v.g.hero(1).id]
	mv.s.tags["FROZEN"] = true
	hv.s.tags["FROZEN"] = true
	mv._process(0.0)
	hv._process(0.0)
	check(mv.frost != null and hv.frost != null, "both frozen")
	check(mv.frost.material == MinionView._frost_material(), "one material for every minion")
	mv.s.tags.erase("FROZEN")
	mv._process(0.0)
	check(mv.frost == null, "thawed: the frost goes")
	v.free()


func test_a_card_shuffled_into_a_deck_flies_from_its_source_into_that_deck() -> void:
	var v := _view({"hero": "HERO_08", "board": [YETI], "hand": [FIREBALL]})
	var yeti: int = v.g.players[0].board[0].id
	var held: int = v.g.players[0].hand[0].id
	var evs := [{"type": "add_to_deck", "player": 1, "entity": 500, "card": "", "by": YETI, "by_id": yeti},
		{"type": "add_to_deck", "player": 0, "entity": 501, "card": "", "by": YETI, "by_id": yeti},
		{"type": "to_deck", "player": 0, "entity": held, "card": FIREBALL, "by": YETI, "by_id": yeti}]
	var item := _fake(v, evs)
	var steps := MatchView.steps(evs)
	eq(_kinds(steps), ["shuffle"], "one step for the run")
	var at := v._center_of(yeti)
	var from_hand := v._center_of(held)
	v._begin_batch(item)
	var plan := v._shuffle_plan(steps[0])
	eq(plan.map(func(f): return f.from), [at, at, from_hand], "from the Yeti; the card from the hand from where it was")
	eq(plan.map(func(f): return f.to), [v._pile_center(1), v._pile_center(0), v._pile_center(0)], "into the deck of each one's player")
	check(v._pile_of(1) != v._pile_of(0), "two decks")
	eq(plan.map(func(f): return f.card), ["", "", FIREBALL], "a hidden card flies as a back")
	v._step_apply(steps[0])
	check(not v._views.has(held), "the card left the hand")
	v._end_batch()
	v.free()


func test_a_deck_swap_comes_from_the_other_deck() -> void:
	var v := _view({"hero": "HERO_08", "deck": [YETI, YETI]})
	var evs := [{"type": "to_deck", "player": 1, "entity": 7, "card": "", "by": "", "by_id": -1}]
	v._begin_batch(_fake(v, evs))
	v._was_hidden[7] = true  # (it was in player 0's deck)
	eq(v._shuffle_plan(MatchView.steps(evs)[0])[0].from, v._pile_center(0), "out of the other deck")
	v._end_batch()
	v.free()


func test_a_card_added_to_a_hand_comes_from_its_maker() -> void:
	var v := _view({"hero": "HERO_08", "board": [YETI]})
	var yeti: int = v.g.players[0].board[0].id
	eq(v._hand_origin({"type": "add_to_hand", "player": 0, "entity": 600, "card": YETI, "by": YETI, "by_id": yeti}), v._center_of(yeti), "from the minion")
	eq(v._hand_origin({"type": "add_to_hand", "player": 1, "entity": 602, "card": "", "by": "", "by_id": -1}), v._center_of(v.g.hero(1).id),
		"made by nothing on the table: from its player's hero")
	v.free()


func test_a_buff_on_cards_in_the_hand_shows_over_the_hand() -> void:
	var v := _view({"hero": "HERO_08", "hand": [YETI, YETI]})
	var ids: Array = v.g.players[0].hand.map(func(e): return e.id)
	var evs := ids.map(func(id): return {"type": "buff", "target": id, "atk": 1, "hp": 1, "by": "", "by_id": -1})
	eq(v._place_of(evs[0]), "hand 0", "a card in the hand")
	eq(v._place_of({"type": "buff", "target": 900, "atk": 1, "hp": 1, "by_id": -1, "player": 1}), "deck 1", "a card the view does not know: a deck")
	var steps := MatchView.steps(evs)
	eq(_kinds(steps), ["hit"], "the hand at once")
	v._begin_batch(_fake(v, evs))
	v._step_apply(steps[0])
	eq(ids.map(func(id): return v._views[id].flashes), [1, 1], "each card lights up")
	v._end_batch()
	v.free()


func test_hand_card_numbers_are_green_or_red() -> void:
	var v := _view({"hero": "HERO_08", "hand": [YETI]})
	var e: GameView.Ent = v.g.players[0].hand[0]
	var cv := CardView.make(YETI)
	var c := e.copy()
	cv.show_entity(c, v.g)
	eq([cv.attack_color(), cv.health_color(), cv.cost_color()], [Color.WHITE, Color.WHITE, Color.WHITE], "as printed")
	c._atk += 2
	c._max_health -= 1
	c._cost -= 1
	cv.show_entity(c, v.g)
	eq([cv.attack_color(), cv.health_color(), cv.cost_color()], [Frames.BUFFED, Frames.DAMAGED, Frames.BUFFED], "buffed Attack green, less Health red, cheaper green")
	c._cost += 3
	cv.show_entity(c, v.g)
	eq(cv.cost_color(), Frames.DAMAGED, "dearer: red")
	cv.free()
	v.free()


func test_hero_power_and_weapon_show_their_changes() -> void:
	var v := _view({"hero": "HERO_08", "weapon": {"card": AXE, "durability": 2}})
	var pe: GameView.Ent = v.g.players[0].hero_power
	var pv: PowerView = v._views[pe.id]
	eq(pv.cost_color(), Color.WHITE, "as printed")
	pe._cost = 0
	pv.sync()
	eq([pv.cost_color(), pv.flashes], [Frames.BUFFED, 1], "cheaper: green, and it lights up")
	var w: GameView.Ent = v.g.players[0].weapon
	w._atk = 1
	eq(Frames.stat_color(w._atk, 3), Frames.DAMAGED, "a weapon's Attack below its card's: red")
	v.free()


func test_end_turn_turns_over_with_the_turn() -> void:
	var v := _view({"hero": "HERO_08"})
	eq([v._end_turn.text, v._end_turn.get_meta("side")], [tr("End Turn"), "own"], "own turn")
	v._play_step({"k": "turn", "evs": [{"type": "turn_start", "player": 1, "turn": 2}], "at": 0})
	eq([v._end_turn.text, v._end_turn.get_meta("side")], [tr("Enemy Turn"), "enemy"], "the opponent's turn")
	Anim.instant = false
	v._set_end_side(true)
	check(v._end_turn.has_meta("flip"), "it turns over")
	eq(v._end_turn.text, tr("Enemy Turn"), "the new side shows half-way through the turn")
	Anim.instant = true
	v.free()


func test_a_joust_shows_both_cards_with_their_owners() -> void:
	var v := _view({"hero": "HERO_08"})
	var shown := v._joust_cards({"type": "joust", "player": 1, "card": YETI, "foe_card": H.WISP, "won": true})
	eq(shown.map(func(c): return c.owner), [1, 0], "the jouster's card and the other one")
	eq(shown.map(func(c): return c.label.text), [v._side_name(1), v._side_name(0)], "each labelled with whose it is")
	eq(shown.map(func(c): return c.won), [true, false], "the winner")
	eq(shown.map(func(c): return c.cost), [4, 0], "their costs compared")
	check(shown[0].view.position.y < shown[1].view.position.y, "the opponent's card on their side (top)")
	for c in shown:
		c.view.free()
		c.label.free()
	v.free()


func test_start_of_game_shuffles_come_from_its_card() -> void:
	var v := _view({"hero": "HERO_08"})
	var evs := [{"type": "start_of_game", "player": 0, "card": "VAN_EX1_116"}]
	for i in 5:
		evs.append({"type": "add_to_deck", "player": 0, "entity": 700 + i, "card": "", "by": "", "by_id": -1})
	var steps := MatchView.steps(evs)
	eq(_kinds(steps), ["reveal", "shuffle"], "the card, then the five")
	v._begin_batch(_fake(v, evs))
	v._play_step(steps[0])
	check(v._sog_cards.has(0), "the card stays while they fly from it")
	var cv: CardView = v._sog_cards[0]
	eq(v._shuffle_plan(steps[1])[0].from, cv.position + cv.size * cv.scale / 2.0, "from the Start of Game card")
	v._end_batch()
	check(v._sog_cards.is_empty(), "gone at the end")
	v.free()


func test_history_says_malchezaar_and_hidden_buffs() -> void:
	var v := _view({"hero": "HERO_08"})
	var rows := HistoryText.lines({"turn": 1, "player": 0, "action": {"type": "end_turn"}, "events": [
		{"type": "start_of_game", "player": 0, "card": "VAN_EX1_116"},
		{"type": "buff", "target": 901, "atk": 1, "hp": 1, "by_id": -1, "player": 1},
		{"type": "buff", "target": 902, "atk": 1, "hp": 1, "by_id": -1, "player": 1}]}, v.g, 0, "en")
	eq(rows.size(), 2, "one line for the Start of Game, one for the two buffs")
	check(rows[0].begins_with("Start of Game"), rows[0])
	eq(rows[1], "2 cards in Opponent's deck get +1/+1", "the deck's cards, hidden")
	v.free()


func test_a_targeted_spell_aims_as_its_light_and_comes_back_as_a_card() -> void:
	var v := _view({"hero": "HERO_08", "hand": [FIREBALL]}, {"hero": "HERO_01"}, [false, true])
	var fb: int = v.g.players[0].hand[0].id
	v._press = {"id": fb, "at": Vector2(640, 650)}
	v._start_drag()
	v._drag_to(Vector2(640, 250))
	check(v._orb.visible and v._orb_card == fb, "aiming: the card is a light where the arrow starts")
	eq(v._views[fb].modulate.a, 0.0, "the card itself is gone")
	eq(v._orb.position, v._orb_at(), "at the arrow's start")
	eq(v._arrow.from, v._orb_at(), "the arrow starts there")
	v._drag_to(Vector2(640, 690))
	check(not v._orb.visible, "back over the hand: a card again")
	eq(v._views[fb].modulate.a, 1.0, "the card shows")
	v._drag_to(Vector2(640, 250))
	v._press = {}
	v._dragging = false
	v._drop_at(Vector2(640, 690), fb)
	check(not v._orb.visible and v._orb_card == -1, "dropped in the hand: no light")
	check(v._views[fb] is CardView and v._views[fb].modulate.a == 1.0, "the card is back in the hand")
	eq(v.g.players[0].hand.size(), 1, "nothing played")
	v.free()


func test_the_opponent_sees_no_spell_light() -> void:
	var v := _view({"hero": "HERO_08"}, {"hero": "HERO_01", "hand": [FIREBALL]}, [false, true])
	var theirs: int = v.g.players[1].hand[0].id
	v.apply_intent({"k": "aim", "from": theirs, "to": v.g.hero(0).id, "x": 600.0, "y": 300.0})
	check(v._opp_arrow.visible, "their arrow shows")
	check(not v._orb.visible, "no light, no card")
	check(not (v._views[theirs] as CardView).face_up, "their card stays a back")
	v.free()


func test_a_secret_going_off_shows_over_its_place() -> void:
	var v := _view({"hero": "HERO_08", "board": [YETI]}, {"hero": "HERO_05", "secrets": [EXPLOSIVE]})
	var secret: int = v.g.players[1].secrets[0].id
	var at := v._center_of(secret)
	var ev := {"type": "secret_revealed", "entity": secret, "player": 1, "card": EXPLOSIVE}
	var cv := v._secret_card(ev, at)
	var mid: Vector2 = cv.position + cv.size / 2.0
	eq(mid.x, at.x, "over the Secret")
	check(cv.position.y >= 0.0 and cv.position.y + cv.size.y <= 720.0, "on the table")
	check(cv.face_up and cv.card_id == EXPLOSIVE, "the card shown")
	eq(Sound.sound_for(ev, v.g, 0) != "", true, "with its reveal sound")
	cv.free()
	v.free()
