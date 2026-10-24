extends TestCase
## Phones: a text field under the on-screen keyboard is lifted above it (the numbers of a OnePlus
## Open: a 2484x1116 window, the game 1280x720 scaled 1.55 with bars at the sides, a 632 px keyboard).

const XF := Transform2D(0.0, Vector2(1.55, 1.55), 0.0, Vector2(250, 0))
const WIN_H := 1116.0


func test_no_keyboard_no_lift() -> void:
	eq(KeyboardLift.lift_for(Rect2(300, 512, 400, 58), 0.0, WIN_H, XF), 0.0)


func test_a_field_above_the_keyboard_stays() -> void:
	eq(KeyboardLift.lift_for(Rect2(300, 120, 400, 58), 632.0, WIN_H, XF), 0.0, "the account name field")


func test_a_covered_field_rises_above_the_keyboard() -> void:
	# the keyboard's top in the game: (1116 - 632) / 1.55 = 312.26; the field ends at 570, and 12 under
	var lift := KeyboardLift.lift_for(Rect2(300, 512, 400, 58), 632.0, WIN_H, XF)
	check(absf(lift - (570.0 + KeyboardLift.MARGIN - 312.26)) < 0.1, "lifted by %s" % lift)


func test_never_above_the_top_of_the_screen() -> void:
	eq(KeyboardLift.lift_for(Rect2(300, 600, 400, 110), 1000.0, WIN_H, XF), 600.0, "the field's top stays on screen")


## A field in the friends overlay (a CanvasLayer) moves its layer; one in a screen moves the game.
func test_lifts_the_layer_of_the_field() -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	var layer := CanvasLayer.new()
	var in_layer := LineEdit.new()
	layer.add_child(in_layer)
	root.add_child(layer)
	var lift := KeyboardLift.new()
	root.add_child(lift)
	lift.apply(in_layer, 40.0)
	eq(layer.offset, Vector2(0, -40), "the overlay's layer")
	var plain := LineEdit.new()
	root.add_child(plain)
	lift.apply(plain, 25.0)
	eq([layer.offset, root.canvas_transform.origin], [Vector2.ZERO, Vector2(0, -25)], "the layer back, the game lifted")
	lift.apply(null, 0.0)
	eq(root.canvas_transform, Transform2D.IDENTITY, "all back when the keyboard is gone")
	for n in [lift, plain, layer]:
		n.free()
