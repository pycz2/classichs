extends TestCase


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_tips_explain_a_cards_keywords_in_the_game_language() -> void:
	var tips := KeywordTips.make("VAN_EX1_012")  # Bloodmage Thalnos: Spell Damage, Deathrattle
	var titles := tips.find_children("Title*", "Label", true, false).map(func(l): return l.text)
	eq(titles, ["Deathrattle", "Spell Damage"], "one box per keyword")
	tips.free()
	Locale.set_language("ru")
	tips = KeywordTips.make("VAN_CS2_150")  # Stormpike Commando: Battlecry
	eq(tips.find_children("Title*", "Label", true, false).map(func(l): return l.text), ["Боевой клич"], "Russian")
	tips.free()
	Locale.set_language("en")
	eq(KeywordTips.make("VAN_CS2_182").get_child_count(), 0, "a vanilla minion has no boxes")


func test_hovering_a_board_minion_shows_its_tips() -> void:
	var v := MatchView.new()
	root().add_child(v)
	var m := H.scene({"hero": "HERO_08", "board": ["VAN_EX1_012"]}, {"hero": "HERO_01"}, 0, [false, true])
	v.bind(m)
	v._on_hover(v._views[m.game.players[0].board[0].id], true)
	check(v.find_child("KeywordTips", true, false) != null, "tips next to the big card")
	v.free()


func test_a_buffed_minion_lists_its_changes() -> void:
	# a Yeti beside a Raid Leader, then Blessing of Kings on the Yeti
	var m := H.scene({"hero": "HERO_04", "hand": ["VAN_CS2_092"], "board": ["VAN_CS2_182", "VAN_CS2_122"]},
		{"hero": "HERO_01", "board": ["VAN_CS2_182"]})
	var g := m.game
	var yeti: GameView.Ent = g.players[0].board[0]
	H.play(m, g.players[0].hand[0], yeti)
	var lines := KeywordTips.changes(yeti)
	check(lines.has("+4/+4 — Blessing of Kings"), "the buff and its card: %s" % [lines])
	check(lines.has("+1/+0 — Raid Leader (aura)"), "the aura: %s" % [lines])
	var tips := KeywordTips.make(yeti.card_id, yeti)
	check(tips.find_child("Changes", true, false) != null, "a box with the changes")
	tips.free()
	eq(KeywordTips.changes(g.players[1].board[0]), [], "an untouched minion has none")


## Corruption leaves no number changed: the minion gets a mark, its card view says what waits.
func test_a_hidden_effect_is_marked_and_listed() -> void:
	var m := H.scene({"hero": "HERO_07", "hand": ["VAN_CS2_063"]}, {"hero": "HERO_01", "board": ["VAN_CS2_182"]})
	var yeti: GameView.Ent = m.game.players[1].board[0]
	check(not MinionView.hidden_effects(yeti), "nothing on it yet")
	H.play(m, m.game.players[0].hand[0], yeti)
	yeti = m.game.players[1].board[0]
	check(MinionView.hidden_effects(yeti), "Corruption: a mark")
	var lines := KeywordTips.changes(yeti)
	check(lines.size() == 1 and lines[0].begins_with(CardText.name("VAN_CS2_063") + ": "), "the card that cast it and its text: %s" % [lines])
	yeti.silenced = true
	check(not MinionView.hidden_effects(yeti), "a silenced minion has none")


func test_collection_shows_keyword_tips() -> void:
	var c := CollectionView.new()
	root().add_child(c)
	var cv := CardView.make("VAN_EX1_012")  # Bloodmage Thalnos
	c._on_hover(cv, true)
	check(c.find_child("KeywordTips", true, false) != null, "tips beside the big card in the collection")
	cv.free()
	c.free()
