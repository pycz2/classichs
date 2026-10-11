extends SceneTree
## Cuts a flat green background out of a picture (chroma key with spill removal).
## Usage: godot --headless --path . --script res://tools/key_green.gd -- <in.png> <out.png> <width>


func _process(_d: float) -> bool:
	var args := OS.get_cmdline_user_args()
	var img := Image.load_from_file(args[0])
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var green := c.g - maxf(c.r, c.b)  # how much greener than the other channels
			c.a = clampf(1.0 - (green - 0.08) / 0.25, 0.0, 1.0)
			if green > 0.0:
				c.g = maxf(c.r, c.b)  # no green fringe on the edges
			img.set_pixel(x, y, c)
	img = img.get_region(img.get_used_rect())  # trim the empty margins: the bottom edge is the ornament's
	var w := int(args[2])
	img.resize(w, int(w * img.get_height() / float(img.get_width())), Image.INTERPOLATE_LANCZOS)
	img.save_png(args[1])
	print("saved ", args[1], " ", img.get_size())
	quit()
	return true
