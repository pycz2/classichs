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


func test_history_strip_shows_played_cards_newest_first() -> void:
	var v := _view({"hero": "HERO_08", "hand": ["VAN_CS2_120", "VAN_CS2_182"]}, [false, false])
	for e in v.g.players[0].hand.duplicate():
		v.controller.submit({"type": "play", "player": 0, "entity": e.id, "target": -1, "pos": 0, "choice": -1})
	var strip := v.find_child("HistoryStrip", true, false) as HistoryStrip
	eq(strip.card_at(5), "VAN_CS2_182", "newest on top")
	eq(strip.card_at(HistoryStrip.TILE + 10), "VAN_CS2_120", "then the earlier one")
	v.free()


func test_right_click_during_a_drag_cancels_it_cleanly() -> void:
	var v := _view({"hero": "HERO_08", "board": [{"card": "VAN_CS2_182", "exhausted": false}]})
	var yeti := v.g.players[0].board[0]
	v._press = {"id": yeti.id, "at": Vector2(640, 400)}
	v._start_drag()
	v.cancel()
	v._drag_to(Vector2(600, 200))  # the next mouse move after the right click
	eq([v._dragging, v._press, v._arrow.visible], [false, {}, false], "drag fully cancelled")
	v.free()


func test_menus_and_screens_draw_above_hand_cards() -> void:
	var v := _view({"hero": "HERO_08", "hand": ["VAN_CS2_120", "VAN_CS2_120", "VAN_CS2_120"]})
	v.open_settings()
	var s := v.find_child("SettingsView", true, false) as Control
	var top := 0
	for c in v._views.values():
		top = maxi(top, c.z_index)
	check(s.z_index > top + 20, "settings above the hand (z %d vs %d)" % [s.z_index, top])
	for n in ["GameMenu", "EmoteWheel", "EnemyMenu"]:
		check((v.find_child(n, true, false) as Control).z_index > top + 20, n)
	v._open_overlay("x")
	check(v._overlay.z_index > top + 20, "dimming overlays (mulligan, game over) above the hand")
	v.free()


func test_bounced_minion_becomes_a_card_where_it_stood() -> void:
	var v := _view({"hero": "HERO_08", "board": ["VAN_CS2_182"]})
	var yeti := v.g.players[0].board[0]
	var at: Vector2 = v._center(yeti.id) if v.has_method("_center") else v._center_of(yeti.id)
	Anim.instant = false
	v.g.return_to_hand(yeti)
	var events: Array = v.g.event_log.duplicate()
	v._effects_now(events)
	var card := v.g.players[0].hand[0]
	var cv: Control = v._views[card.id]
	var start: Vector2 = cv.position + cv.size * cv.scale / 2.0
	Anim.instant = true
	check(start.distance_to(at) < 60.0, "the card starts at the minion's place, not at the deck: %s vs %s" % [start, at])
	v.free()


func test_turn_timer_does_not_end_a_new_turn_while_animating() -> void:
	var v := _view({"hero": "HERO_08"}, [false, false])
	v.timer_enabled = true
	v._time_left = -1.0  # the old turn's timer ran out
	v._turn_key = "old"
	v._busy = true  # the opponent's last move is still animating
	var turn := v.g.turn
	v.tick(0.1)
	v._busy = false
	eq(v.g.turn, turn, "the new turn was not ended by the old turn's timer")
	v.free()


func test_repeated_intents_do_not_rebuild_the_table() -> void:
	var v := _view({"hero": "HERO_08"}, [false, false])
	v.apply_intent({"k": "hover", "i": 1})
	var builds: int = v._layouts
	for i in 50:
		v.apply_intent({"k": "hover", "i": 1})
	eq(v._layouts, builds, "the same intent again changes nothing")
	v.free()


func test_history_strip_signals_only_when_the_card_changes() -> void:
	var strip := HistoryStrip.new()
	root().add_child(strip)
	strip._items = [["VAN_CS2_120", true], ["VAN_CS2_182", false]]
	var shown := []
	strip.show_card.connect(func(c, on): shown.append([c, on]))
	for y in [5.0, 8.0, 12.0, 60.0, 62.0]:
		var ev := InputEventMouseMotion.new()
		ev.position = Vector2(10, y)
		strip._gui_input(ev)
	eq(shown, [["VAN_CS2_120", true], ["VAN_CS2_182", true]], "one signal per card")
	strip.free()


func test_end_turn_turns_green_when_nothing_is_left_to_do() -> void:
	var v := _view({"hero": "HERO_08", "hand": ["VAN_CS2_120"], "mana": 2, "max_mana": 2})
	eq(v.end_turn_ready, false, "a card can still be played")
	var croc := v.g.players[0].hand[0]
	v.controller.submit({"type": "play", "player": 0, "entity": croc.id, "target": -1, "pos": 0, "choice": -1})
	eq(v.end_turn_ready, true, "no mana, no attacks, hero power too dear: end turn glows")
	v.free()


func test_used_hero_power_turns_face_down() -> void:
	var v := _view({"hero": "HERO_01"})
	var power := v.g.players[0].hero_power
	eq((v._views[power.id] as PowerView).face_down_used, false, "ready")
	v.controller.submit({"type": "hero_power", "player": 0, "target": -1})
	eq((v._views[power.id] as PowerView).face_down_used, true, "used: turned over")
	v.free()


func test_board_views_show_the_state_of_the_last_refresh() -> void:
	# The engine changes the state at once; the table shows it when the animation
	# reaches that moment (the hit), not before.
	var v := _view({"hero": "HERO_08", "board": ["VAN_CS2_182"]})
	var yeti := v.g.players[0].board[0]
	var hero := v.g.hero(0)
	yeti.damage = 2
	yeti.give_tag("DIVINE_SHIELD")
	hero.damage = 5
	eq((v._views[yeti.id] as MinionView).s.health(), 5, "minion: old health shown")
	eq((v._views[yeti.id] as MinionView).s.has("DIVINE_SHIELD"), false, "minion: no shield yet")
	eq((v._views[hero.id] as HeroView).s.health(), 30, "hero: old health shown")
	v.refresh()
	eq((v._views[yeti.id] as MinionView).s.health(), 3, "minion: new health after refresh")
	eq((v._views[yeti.id] as MinionView).s.has("DIVINE_SHIELD"), true, "minion: shield after refresh")
	eq((v._views[hero.id] as HeroView).s.health(), 25, "hero: new health after refresh")
	v.free()


func test_table_effects_follow_what_changed() -> void:
	var g := H.scene({"hero": "HERO_08", "board": ["VAN_CS2_182"]})
	var yeti := g.players[0].board[0]
	var before := yeti.copy()
	yeti.damage = 2
	eq(TableFx.kinds(before, yeti), ["hurt"], "damage")
	before = yeti.copy()
	yeti.damage = 0
	eq(TableFx.kinds(before, yeti), ["heal"], "healing")
	before = yeti.copy()
	yeti.add_enchant({"atk": 1, "hp": 1})
	yeti.give_tag("TAUNT")
	eq(TableFx.kinds(before, yeti), ["buff", "gain"], "buff and a keyword")
	before = yeti.copy()
	yeti.give_tag("FROZEN")
	eq(TableFx.kinds(before, yeti), ["freeze"], "frozen")
	before = yeti.copy()
	yeti.silence()
	eq(TableFx.kinds(before, yeti), ["silence"], "silence (losing the buff is not a debuff)")
	before = yeti.copy()
	yeti.add_enchant({"set_atk": 1})
	eq(TableFx.kinds(before, yeti), ["debuff"], "attack set lower")


func test_changed_numbers_pop() -> void:
	var v := _view({"hero": "HERO_08", "board": ["VAN_CS2_182"]})
	var yeti := v.g.players[0].board[0]
	var mv := v._views[yeti.id] as MinionView
	Anim.instant = false
	yeti.damage = 2
	mv.sync()
	check(mv._pops.has("hp") and not mv._pops.has("atk"), "health pops, attack stays")
	Anim.instant = true
	v.free()


func test_hovered_card_shows_the_mana_it_would_spend() -> void:
	var v := _view({"hero": "HERO_08", "mana": 5, "max_mana": 5, "hand": ["VAN_CS2_029", "VAN_CS2_032"]})  # Fireball 4, Flamestrike 7
	var hand := v.g.players[0].hand
	v._hover_hand = hand[0].id
	v.refresh()
	eq(v._mana[0].preview, 4, "Fireball: 4 crystals blink")
	v._hover_hand = hand[1].id
	v.refresh()
	eq(v._mana[0].preview, 0, "Flamestrike costs too much: nothing blinks")
	v._hover_hand = -1
	v.refresh()
	eq(v._mana[0].preview, 0, "no card under the mouse")
	v.free()
