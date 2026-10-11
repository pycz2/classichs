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
	var m := Match.new()
	m.bot_delay = 0.0
	m.setup(H.scene({"hero": "HERO_08", "board": ["VAN_EX1_012"]}), [false, true])
	v.bind(m)
	v._on_hover(v._views[m.game.players[0].board[0].id], true)
	check(v.find_child("KeywordTips", true, false) != null, "tips next to the big card")
	v.free()
