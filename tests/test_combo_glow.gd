extends TestCase
## A Combo card in the hand glows yellow instead of green once a card was played
## this turn (its Combo is on), as in the original.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_combo_card_glows_yellow_when_its_combo_is_on() -> void:
	# Rogue: SI:7 Agent (Combo) and Backstab
	var g := H.scene({"hero": "HERO_03", "hand": ["VAN_EX1_134", "VAN_CS2_072"]}, {"hero": "HERO_01", "board": ["VAN_CS2_182"]})
	var v := MatchView.new()
	root().add_child(v)
	var m := Match.new()
	m.bot_delay = 0.0
	m.setup(g, [false, true])
	v.bind(m)
	var agent: EntityView = v._views[g.players[0].hand[0].id]
	var stab: EntityView = v._views[g.players[0].hand[1].id]
	eq(agent.glow, Palette.PLAYABLE, "no card played yet: green")
	eq(stab.glow, Palette.PLAYABLE, "an ordinary card: green")
	m.submit({"type": "play", "player": 0, "entity": stab.entity_id, "target": g.players[1].board[0].id, "pos": -1, "choice": -1})
	v.refresh()
	eq(v._views[g.players[0].hand[0].id].glow, Palette.COMBO, "after a card: the Combo is on, yellow")
	v.free()
