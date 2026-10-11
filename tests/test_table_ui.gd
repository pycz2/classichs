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
