extends TestCase
## A phone (and a foldable's two screens): every screen shows whole at any size of the window, without a page that
## scrolls, and stays so through every change of size (fold, unfold, turn) with no screen change in between.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_every_screen_shows_whole_at_any_size() -> void:
	var was := TouchInput.phone
	var size0 := root().size
	TouchInput.phone = true
	var m: Node = load("res://ui/main.tscn").instantiate()
	root().add_child(m)
	# a 20:9 phone, a foldable's outer screen (22:10) and inner one (nearly square), 16:9, the outer again
	for size in [Vector2i(2400, 1080), Vector2i(2484, 1116), Vector2i(2440, 2268), Vector2i(1920, 1080), Vector2i(2484, 1116)]:
		root().size = size
		for show in ["show_menu", "show_library", "show_settings"]:
			m.call(show)
			for s in [size, Vector2i(2440, 2268), Vector2i(2484, 1116)]:  # (folded and unfolded on this screen)
				root().size = s
				eq(root().content_scale_size, Vector2i(1280, 720), "%s at %s: the whole game in view" % [show, s])
				check(m.screen.get_parent() == m and m.find_child("PhonePan", true, false) == null, "%s: no page that scrolls" % show)
				eq(m.screen.size, Vector2(1280, 720), "%s at %s: the screen is the game's size" % [show, s])
	m.free()
	root().size = size0
	TouchInput.phone = was
