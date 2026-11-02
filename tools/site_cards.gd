extends SceneTree
## The landing page's cards, drawn by the game itself (CardView) in each of its
## languages, plus the card back: <out>/cards/<lang>/<id>.webp, <out>/cards/back.webp.
## The cards are those in <out>/data.json (tools/site_data.py): Classic's and Neonfall's
## (`neon.cards`, drawn with Neonfall active). Each picture has PAD card pixels of room
## around the card for what sticks out (gems, crest, sword). Every user file goes to
## user://uitest_site_* (never the player's own).
## Needs a window (no --headless). Usage: godot --path . --script res://tools/site_cards.gd -- <out dir>

const K := 2.0
const PAD := 14.0

var out := ""
var jobs := []  # [lang, card id, pack id]; "" id = the back
var vp := SubViewport.new()
var _wait := 0


func _initialize() -> void:
	Settings.path = "user://uitest_site_settings.json"
	Profile.path = "user://uitest_site_profile.json"
	DeckStore.path = "user://uitest_site_decks.json"
	Progress.path = "user://uitest_site_progress.json"
	ServerLink.session_path = "user://uitest_site_session.json"
	Packs.user_dir = "user://uitest_site_packs"
	out = OS.get_cmdline_user_args()[0] + "/cards"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0] + "/data.json"))
	for lang in CardLayout.LANGS:
		DirAccess.make_dir_recursive_absolute("%s/%s" % [out, lang])
		for c in data.cards:
			jobs.append([lang, c.id, Packs.CLASSIC])
		for c in data.get("neon", {}).get("cards", []):
			jobs.append([lang, c.id, "neon"])
	jobs.append(["en", "", Packs.CLASSIC])
	vp.transparent_bg = true
	vp.size = Vector2i(((CardView.SIZE + Vector2(PAD, PAD) * 2.0) * K).ceil())
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	_show()


func _show() -> void:
	for c in vp.get_children():
		c.free()
	if Packs.active().id() != jobs[0][2]:
		for p: Pack in Packs.all():
			if p.id() == jobs[0][2]:
				Packs.set_active(p)
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
		for p in [Settings.path, Profile.path, DeckStore.path, Progress.path, ServerLink.session_path]:
			DirAccess.remove_absolute(p)
		for f in DirAccess.get_files_at(Packs.user_dir):  # the packs' index the switches wrote
			DirAccess.remove_absolute(Packs.user_dir + "/" + f)
		DirAccess.remove_absolute(Packs.user_dir)
		quit()
		return true
	_show()
	return false
