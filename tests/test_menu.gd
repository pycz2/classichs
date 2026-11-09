extends TestCase
## The main menu's parallax: the picture far behind moves against the look, the title and buttons
## a little with it, and a moved picture never shows its edge.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_the_menu_layers_move_by_their_depth() -> void:
	var m := MainMenu.new()
	root().add_child(m)
	var pic: Control = m._layers[0][0]
	var front: Control = m._layers[1][0]
	var p0 := pic.position
	var f0 := front.position
	m.place(Vector2(1, 0))
	check(pic.position.x < p0.x and front.position.x > f0.x, "looking right: the picture goes left, the buttons right")
	check(absf(pic.position.x - p0.x) > absf(front.position.x - f0.x), "the far layer moves more")
	m.place(Vector2(-1, -1))
	check(pic.position.x <= 0.0 and pic.position.y <= 0.0 and pic.position.x + pic.size.x >= 1280.0 and pic.position.y + pic.size.y >= 720.0,
		"the picture still covers the screen at the far end: %s %s" % [pic.position, pic.size])
	m.place(Vector2.ZERO)
	eq([pic.position, front.position], [p0, f0], "back at rest")
	m.free()
