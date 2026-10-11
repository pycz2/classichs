extends SceneTree
## Sheets of card faces in one language, to look over their layouts: the lower
## part of each card (name, text, gems) with the boxes outlined, 24 to a sheet.
## Needs a window (no --headless).
## Usage: godot --path . --script res://tools/card_sheets.gd -- <lang> <out dir> [card ids...]

const K := 1.6
const COLS := 6
const ROWS := 4
const CELL := Vector2(208, 172)

var lang := "en"
var out := ""
var ids: Array = []
var sheet := 0
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	lang = args[0]
	out = args[1]
	ids = args.slice(2) if args.size() > 2 else CardDb.all_ids()
	if args.size() <= 2:
		ids.sort()
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(int(CELL.x * COLS), int(CELL.y * ROWS))
	root.content_scale_factor = 1.0
	_fill()


func _fill() -> void:
	for c in root.get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color("2b2118")
	bg.size = Vector2(root.size)
	root.add_child(bg)
	for i in COLS * ROWS:
		var n := sheet * COLS * ROWS + i
		if n >= ids.size():
			break
		var at := Vector2(i % COLS, i / COLS) * CELL
		var label := Label.new()
		label.text = ids[n]
		label.position = at + Vector2(6, 0)
		label.add_theme_font_size_override("font_size", 13)
		root.add_child(label)
		var clip := Control.new()  # only the card from its name banner down
		clip.clip_contents = true
		clip.position = at + Vector2(8, 20)
		clip.size = Vector2(CardView.SIZE.x * K, 90 * K)
		root.add_child(clip)
		var cv := CardView.make(ids[n], K)
		cv.locale = lang
		cv.show_boxes = true
		cv.position = Vector2(0, -80 * K)
		clip.add_child(cv)


func _process(_d: float) -> bool:
	_wait += 1
	if _wait < 4:
		return false
	_wait = 0
	root.get_texture().get_image().save_png("%s/%s_%02d.png" % [out, lang, sheet])
	sheet += 1
	if sheet * COLS * ROWS >= ids.size():
		quit()
		return true
	_fill()
	return false
