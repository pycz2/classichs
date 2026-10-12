class_name Sprites
extends RefCounted
## Interface pictures made by tools/gen_ui_art.py (ui/sprites/<name>.png, big ones .jpg). They are
## all loaded at start (main.gd): a texture first loaded while drawing shows white
## in the web build. A missing picture gives null, and the code draws its own.

const DIR := "res://ui/sprites"
static var _tex := {}
static var _loaded := false


static func load_all() -> void:
	_loaded = true
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		if not (f.ends_with(".png.import") or f.ends_with(".jpg.import")):  # only imported pictures (a new one needs `godot --import`)
			continue
		var pic := f.trim_suffix(".import")  # .jpg: the big full-screen pictures
		var t = load(DIR + "/" + pic)
		if t is Texture2D:
			_tex[pic.get_basename()] = t


static func get_tex(name: String) -> Texture2D:
	if not _loaded:
		load_all()
	return _tex.get(name)


## Draws a sprite with its centre at c, as wide as w (keeping its shape); false if there is none.
static func draw(ci: CanvasItem, name: String, c: Vector2, w: float, rot := 0.0, col := Color.WHITE) -> bool:
	var t := get_tex(name)
	if t == null:
		return false
	var h := w * t.get_height() / float(t.get_width())
	if rot == 0.0:
		ci.draw_texture_rect(t, Rect2(c - Vector2(w, h) / 2.0, Vector2(w, h)), false, col)
	else:
		ci.draw_set_transform(c, rot)
		ci.draw_texture_rect(t, Rect2(-Vector2(w, h) / 2.0, Vector2(w, h)), false, col)
		ci.draw_set_transform(Vector2.ZERO)
	return true
