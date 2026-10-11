extends SceneTree
## Builds the app icons (PWA, favicon) from the dragon crest: icons/icon_<size>.png.
## Usage: godot --headless --path . --script res://tools/make_icons.gd


func _process(_d: float) -> bool:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var r := 96.0
	var half := Vector2(n, n) / 2.0
	for y in n:
		for x in n:
			var q := (Vector2(x + 0.5, y + 0.5) - half).abs() - (half - Vector2(r, r))
			var edge := -(Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0.0) - r)
			if edge < -0.5:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var glow := 1.0 - (Vector2(x, y) - Vector2(256, 230)).length() / 360.0
			var c := Color("2a1a0e").lerp(Color("6b4428"), clampf(glow, 0.0, 1.0) * 0.6)
			if edge < 12.0:
				c = Color("d9b44a").lerp(Color("8a6d2a"), float(y) / n)
			elif edge < 16.0:
				c = Color("1b0f06")
			c.a = clampf(edge + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, c)
	var dragon := Image.load_from_file("res://ui/dragon_title.png")
	dragon.resize(430, int(430.0 * dragon.get_height() / dragon.get_width()), Image.INTERPOLATE_LANCZOS)
	img.blend_rect(dragon, Rect2i(Vector2i.ZERO, dragon.get_size()), Vector2i((n - dragon.get_width()) / 2, (n - dragon.get_height()) / 2 - 10))
	DirAccess.make_dir_recursive_absolute("res://icons")
	for s in [512, 180, 144]:
		var out := img.duplicate()
		out.resize(s, s, Image.INTERPOLATE_LANCZOS)
		out.save_png("res://icons/icon_%d.png" % s)
	print("icons done")
	quit()
	return true
