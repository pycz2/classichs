extends SceneTree
## Renders the boot splash (icons/splash.png) from the real menu look: the tavern
## background, darkened, and the gold title logo. Needs a window (no --headless).
## Usage: godot --path . --script res://tools/make_splash.gd

var _frames := 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_factor = 1.0
	var bg := ColorRect.new()
	bg.color = Color("1b140f")
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	var pic := TextureRect.new()
	pic.texture = load("res://ui/menu_bg.jpg")
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.size = Vector2(1280, 720)
	pic.modulate = Color(0.55, 0.5, 0.46)
	root.add_child(pic)
	var center := CenterContainer.new()  # layout, not pixels: the same on any screen scale
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var logo := TitleLogo.new()
	center.add_child(logo)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 5:
		var img := root.get_texture().get_image()
		img.save_png("res://icons/splash.png")
		print("splash saved ", img.get_size())
		quit()
	return false
