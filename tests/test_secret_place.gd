extends TestCase
## Secrets sit on the top of their hero's portrait, on both sides of the table.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_secrets_sit_above_both_portraits() -> void:
	var g := H.scene({"hero": "HERO_08", "secrets": ["VAN_EX1_289"]}, {"hero": "HERO_05", "secrets": ["VAN_EX1_554"]})
	var v := MatchView.new()
	root().add_child(v)
	var m := Match.new()
	m.setup(g, [false, true])
	v.bind(m)
	for p in 2:
		var hero: Control = v._views[g.players[p].hero.id]
		var secret: Control = v._views[g.players[p].secrets[0].id]
		check(secret.position.y < hero.position.y + 20, "player %d: the secret is on the top of the portrait (secret y %d, hero y %d)" % [p, secret.position.y, hero.position.y])
	v.free()
