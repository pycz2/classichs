extends TestCase


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_cards_a_card_can_bring_come_from_its_script() -> void:
	eq(CardDb.related("VAN_EX1_506"), ["VAN_EX1_506a"], "Murloc Tidehunter: Murloc Scout")
	eq(CardDb.related("VAN_EX1_116"), ["EX1_116t"], "Leeroy Jenkins: Whelps")
	eq(CardDb.related("VAN_NEW1_031"), ["VAN_NEW1_032", "VAN_NEW1_033", "VAN_NEW1_034"], "Animal Companion: its three beasts")
	eq(CardDb.related("VAN_HERO_02bp"), ["VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009"], "Totemic Call: the totems, through a helper")
	eq(CardDb.related("HERO_08"), ["VAN_HERO_08bp"], "a hero: its power")
	eq(CardDb.related("VAN_CS2_182"), [], "Chillwind Yeti: nothing")
	eq(CardDb.related("VAN_PRO_001c").size(), CardDb.RELATED_MAX, "at most RELATED_MAX")


func test_hover_shows_the_related_cards() -> void:
	var c := CollectionView.new()
	root().add_child(c)
	var cv := CardView.make("VAN_NEW1_031")  # Animal Companion
	c._on_hover(cv, true)
	var grid := c.find_child("Related", true, false)
	check(grid != null, "related cards beside the big card")
	if grid:
		eq(grid.get_children().map(func(v): return v.card_id), ["VAN_NEW1_032", "VAN_NEW1_033", "VAN_NEW1_034"], "the three beasts")
	cv.free()
	c.free()
	var v := MatchView.new()
	root().add_child(v)
	var m := H.scene({"hero": "HERO_08", "board": ["VAN_EX1_116"]}, {"hero": "HERO_01"}, 0, [false, true])
	v.bind(m)
	v._on_hover(v._views[m.game.players[0].board[0].id], true)
	var tips := v.find_child("KeywordTips", true, false) as Control
	check(tips != null and tips.find_child("Related", true, false) != null, "and in a match")
	if tips:
		check(tips.get_global_rect().end.y <= 720, "on the screen")
	v.free()
