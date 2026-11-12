extends TestCase
## Secrets sit on the top of their hero's portrait, on both sides of the table.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_secrets_sit_above_both_portraits() -> void:
	var m := H.scene({"hero": "HERO_08", "secrets": ["VAN_EX1_289"]}, {"hero": "HERO_05", "secrets": ["VAN_EX1_554"]}, 0, [false, true])
	var g := m.game
	var v := MatchView.new()
	root().add_child(v)
	v.bind(m)
	for p in 2:
		var hero: Control = v._views[g.players[p].hero.id]
		var secret: Control = v._views[g.players[p].secrets[0].id]
		check(secret.position.y < hero.position.y + 20, "player %d: the secret is on the top of the portrait (secret y %d, hero y %d)" % [p, secret.position.y, hero.position.y])
	v.free()


func test_a_sixth_secret_is_not_playable() -> void:
	var five := ["VAN_EX1_289", "VAN_EX1_294", "VAN_EX1_295", "VAN_EX1_594", "VAN_tt_010"]
	for n in [4, 5]:
		var m := H.scene({"hero": "HERO_08", "hand": ["VAN_EX1_287"], "secrets": five.slice(0, n)}, {"hero": "HERO_01"}, 0, [false, true])
		var g := m.game
		var v := MatchView.new()
		root().add_child(v)
		v.bind(m)
		v.click_entity(g.players[0].hand[0].id)
		var played: bool = not v._sel.is_empty() or g.players[0].secrets.size() > n
		eq(played, n == 4, "%d Secrets in play: a Counterspell from the hand is playable only below 5" % n)
		v.free()
