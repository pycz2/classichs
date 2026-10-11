extends SceneTree
## The landing page's cards, drawn by the game itself (CardView) in each of its
## languages, plus the card back: <out>/cards/<lang>/<id>.webp, <out>/cards/back.webp.
## The cards are those in <out>/data.json (tools/site_data.py). Each picture has
## PAD card pixels of room around the card for what sticks out (gems, crest, sword).
## Needs a window (no --headless). Usage: godot --path . --script res://tools/site_cards.gd -- <out dir>

const K := 2.0
const PAD := 14.0

var out := ""
var jobs := []  # [lang, card id]; "" id = the back
var vp := SubViewport.new()
var _wait := 0


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0] + "/cards"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0] + "/data.json"))
	for lang in CardLayout.LANGS:
		DirAccess.make_dir_recursive_absolute("%s/%s" % [out, lang])
		for c in data.cards:
			jobs.append([lang, c.id])
	jobs.append(["en", ""])
	vp.transparent_bg = true
	vp.size = Vector2i(((CardView.SIZE + Vector2(PAD, PAD) * 2.0) * K).ceil())
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	_show()


func _show() -> void:
	for c in vp.get_children():
		c.free()
	var cv := CardView.make(jobs[0][1], K)
	cv.locale = jobs[0][0]
	cv.face_up = jobs[0][1] != ""
	cv.position = Vector2(PAD, PAD) * K
	vp.add_child(cv)


func _process(_d: float) -> bool:
	_wait += 1
	if _wait < 3:
		return false
	_wait = 0
	var j: Array = jobs.pop_front()
	var path := "%s/back.webp" % out if j[1] == "" else "%s/%s/%s.webp" % [out, j[0], j[1]]
	vp.get_texture().get_image().save_webp(path, true, 0.85)
	if jobs.is_empty():
		print("site cards in ", out)
		quit()
		return true
	_show()
	return false
