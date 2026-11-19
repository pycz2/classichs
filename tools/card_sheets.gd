extends SceneTree
## Sheets of card faces in one language, to look over their layouts: the lower
## part of each card (name, text, gems) with the boxes outlined, 24 to a sheet.
## Needs a window (no --headless).
## Usage: godot --path . --script res://tools/card_sheets.gd -- <lang> <out dir> [--pack <file>] [--longest N] [card ids...]
## --pack: that .cardpack's cards; --longest: its N longest texts, each listed with the layout it gets and its
## problems at the hand's and the big view's scale (CardLayout.problems). Its own user dir
## (classichs-tools/card_sheets) keeps the player's files untouched.

const K := 1.6
const COLS := 6
const ROWS := 4
const CELL := Vector2(208, 172)

var lang := "en"
var out := ""
var ids: Array = []
var sheet := 0
var _wait := 0


func _init() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "classichs-tools/card_sheets")
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	lang = args[0]
	out = args[1]
	var longest := 0
	var i := 2
	while i < args.size():
		match args[i]:
			"--pack":
				Packs.set_active(Pack.open(args[i + 1], "imported"))
				i += 1
			"--longest":
				longest = int(args[i + 1])
				i += 1
			_:
				ids.append(args[i])
		i += 1
	if ids.is_empty():
		ids = CardDb.all_ids()
		ids.sort()
	if longest > 0:
		var loc := CardText.hs_locale(lang)
		ids.sort_custom(func(a, b): return CardText.text(a, loc).length() > CardText.text(b, loc).length())
		ids = ids.slice(0, longest)
		for id in ids:
			print("%s %d %s %s %s" % [id, CardText.text(id, loc).length(), CardLayout.of(id, lang),
				CardLayout.problems(id, lang, 1.0), CardLayout.problems(id, lang, 1.9)])
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
