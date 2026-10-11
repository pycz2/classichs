extends TestCase


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _view(p0: Dictionary, bots := [false, true]) -> MatchView:
	var v := MatchView.new()
	root().add_child(v)
	var m := Match.new()
	m.bot_delay = 0.0
	m.setup(H.scene(p0), bots)
	v.bind(m)
	return v


func test_right_click_own_hero_opens_emotes() -> void:
	var v := _view({"hero": "HERO_08"})
	var wheel := v.find_child("EmoteWheel", true, false) as Control
	eq(wheel.visible, false, "closed")
	v._on_right_click(v._views[v.g.hero(0).id])
	eq(wheel.visible, true, "open on right click")
	eq(wheel.find_children("Emote_*", "Button", false, false).size(), 6, "6 emotes")
	(wheel.find_child("Emote_wow", false, false) as Button).pressed.emit()
	eq(v.bubble_text(0), "Wow!", "emote said")
	eq(wheel.visible, false, "closed after choosing")
	v.free()


func test_menu_holds_settings_tracker_and_concede() -> void:
	var v := _view({"hero": "HERO_08"})
	var menu := v.find_child("GameMenu", true, false) as Control
	eq(menu.visible, false, "closed")
	(v.find_child("MenuButton", true, false) as Button).pressed.emit()
	eq(menu.visible, true, "opens from the gear")
	for n in ["SettingsButton", "TrackerButton", "Concede", "HistoryButton"]:
		check(menu.find_child(n, true, false) != null, n)
	v.free()


func test_deck_pile_shows_count_on_hover() -> void:
	var v := _view({"hero": "HERO_08", "deck": ["VAN_CS2_120", "VAN_CS2_120", "VAN_CS2_120"]})
	var pile := v.find_child("Deck0", true, false) as DeckPile
	eq(pile.count, 3, "count")
	eq(pile.tooltip_text, "Cards in deck: 3", "exact number on hover")
	v.free()


func test_hovered_hand_card_rises_and_others_stay() -> void:
	var v := _view({"hero": "HERO_08", "hand": ["VAN_CS2_120", "VAN_CS2_182", "VAN_CS2_029"]})
	var hand := v.g.players[0].hand
	var mid: CardView = v._views[hand[1].id]
	var top := func(c: CardView) -> float: return c.position.y + c.pivot_offset.y * (1.0 - c.scale.y)
	var y0: float = top.call(mid)
	v._hover_hand = hand[1].id
	v.refresh()
	check(v._views[hand[1].id] == mid, "the same view moves")
	check(top.call(mid) < y0 - 100 and mid.scale.x > 1.0, "rises and grows: %s -> %s" % [y0, top.call(mid)])
	v.free()


func test_played_minion_keeps_other_views() -> void:
	var v := _view({"hero": "HERO_08", "hand": ["VAN_CS2_120"], "board": ["VAN_CS2_182"]})
	var yeti_view = v._views[v.g.players[0].board[0].id]
	var croc := v.g.players[0].hand[0]
	v.controller.submit({"type": "play", "player": 0, "entity": croc.id, "target": -1, "pos": 1, "choice": -1})
	check(v._views[v.g.players[0].board[0].id] == yeti_view, "existing minion view kept")
	check(v._views[croc.id] is MinionView, "the card became a minion view")
	v.free()


func _drag(v: MatchView, id: int, to: Vector2) -> void:
	v._press = {"id": id, "at": Vector2(640, 650)}
	v._start_drag()
	v._drag_to(to)
	v._press = {}
	v._dragging = false
	v._drop_at(to, id)


func _center(v: MatchView, id: int) -> Vector2:
	var view: EntityView = v._views[id]
	return view.position + view.size * view.scale / 2.0


func test_drag_minion_between_two_opens_a_gap_and_plays_there() -> void:
	var v := _view({"hero": "HERO_08", "hand": ["VAN_CS2_120"], "board": ["VAN_CS2_182", "VAN_CS2_182"]})
	var board := v.g.players[0].board
	var left := board[0]
	var right := board[1]
	var x0: float = v._views[left.id].position.x
	var croc := v.g.players[0].hand[0]
	var mid := (_center(v, left.id) + _center(v, right.id)) / 2.0
	v._press = {"id": croc.id, "at": Vector2(640, 650)}
	v._start_drag()
	v._drag_to(mid)
	eq(v._gap, 1, "gap between them")
	check(v._views[left.id].position.x < x0, "left minion moves aside")
	v._press = {}
	v._dragging = false
	v._drop_at(mid, croc.id)
	eq(v.g.players[0].board.find(croc), 1, "played in the middle")
	eq(v._gap, -1, "gap closed")
	v.free()


func test_drag_attacker_onto_enemy_hero() -> void:
	var v := _view({"hero": "HERO_08", "board": [{"card": "VAN_CS2_182", "exhausted": false}]})
	var yeti := v.g.players[0].board[0]
	_drag(v, yeti.id, _center(v, v.g.hero(1).id))
	eq(v.g.hero(1).health(), 26, "attacked the hero")
	v.free()


func test_drag_spell_onto_target_and_back_to_hand() -> void:
	var v := _view({"hero": "HERO_08", "hand": ["VAN_CS2_029", "VAN_CS2_029"]}, [false, false])
	var fb := v.g.players[0].hand[0]
	_drag(v, fb.id, Vector2(640, 690))
	eq(v.g.players[0].hand.size(), 2, "dropped back in the hand: nothing played")
	_drag(v, fb.id, _center(v, v.g.hero(1).id))
	eq(v.g.hero(1).health(), 24, "Fireball dropped on the enemy hero")
	v.free()
