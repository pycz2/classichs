extends TestCase


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_every_class_icon_draws_inside_its_rect() -> void:
	var rect := Rect2(5, 5, 40, 40)
	var seen := {}
	for cls in Icons.CLASSES:
		var shapes := Icons.shapes(cls, rect)
		check(shapes.size() >= 4, cls)
		seen[str(shapes)] = true
		for s in shapes:
			for p in Art.points(s):
				check(rect.grow(1).has_point(p), "%s outside" % cls)
	eq(seen.size(), Icons.CLASSES.size(), "every class looks different")


func test_class_buttons_show_icons() -> void:
	var c := CollectionView.new()
	root().add_child(c)
	for cls in Decks.classes():
		var tab := c.find_child("Tab" + cls, true, false) as Button
		check(tab.find_children("*", "IconView", false, false).size() == 1, "tab icon " + cls)
		check(tab.tooltip_text != "", "tab tooltip " + cls)
	c.free()
	var t := TrainingSetup.new()
	root().add_child(t)
	check((t.find_child("bot_MAGE", true, false) as Button).find_children("*", "IconView", false, false).size() == 1, "opponent icon")
	t.free()
