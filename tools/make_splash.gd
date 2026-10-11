extends SceneTree
## Renders the boot splash (icons/splash.png) from the real menu look: the tavern
## background, darkened, the gold title logo and the game's version. Needs a window (no --headless).
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
	var version := Label.new()  # the game's version under the title (tools/build_site.sh redraws the splash)
	version.text = "v" + str(ProjectSettings.get_setting("application/config/version"))
	version.add_theme_font_override("font", Fonts.ui(700))
	version.add_theme_font_size_override("font_size", 26)
	version.add_theme_color_override("font_color", Color("f2dca0"))
	version.add_theme_color_override("font_outline_color", Color("1b0f06"))
	version.add_theme_constant_override("outline_size", 6)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.position = Vector2(0, 470)
	version.size = Vector2(1280, 40)
	root.add_child(version)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 5:
		var img := root.get_texture().get_image()
		img.save_png("res://icons/splash.png")
		print("splash saved ", img.get_size())
		quit()
	return false
