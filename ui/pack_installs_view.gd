class_name PackInstallsView
extends CanvasLayer
## A small box over every screen while game packs install or upload (PackInstall.jobs): per pack its
## name, the stage it is in and a bar of that stage; when one ends, how it ended for a few seconds.
## main owns it, like the FPS counter; it never takes a click or a touch.

const RESULT_SECONDS := 5.0

var box := VBoxContainer.new()
var _rows := {}  # PackInstall -> {row, title, text, bar, left}


func _ready() -> void:
	name = "PackInstalls"
	layer = 98  # under the FPS counter
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_left = 12
	box.offset_bottom = -12
	add_child(box)
	visible = false


func _process(delta: float) -> void:
	for j: PackInstall in PackInstall.jobs:
		if not _rows.has(j):
			_rows[j] = _row(j)
	for j: PackInstall in _rows.keys():
		var r: Dictionary = _rows[j]
		r.title.text = j.title
		if j.stage != "done":
			r.text.text = j.text()
			r.bar.indeterminate = j.total <= 0
			r.bar.max_value = maxi(j.total, 1)
			r.bar.value = j.done
			continue
		if r.left == RESULT_SECONDS:
			r.text.text = result_text(j)
			r.text.add_theme_color_override("font_color", Palette.ATTACK if j.result.has("error") else Palette.SELECTED)
			r.bar.visible = false
		r.left -= delta
		if r.left <= 0.0:
			r.row.queue_free()
			_rows.erase(j)
	visible = not _rows.is_empty()


## How a job ended, in the interface's language.
static func result_text(j: PackInstall) -> String:
	var r := j.result
	if r.has("error"):
		return TranslationServer.translate(str(r.error)) + (": " + str(r.detail) if str(r.get("detail", "")) != "" else "")
	if j.upload:
		return TranslationServer.translate("Uploaded: %s") % ServerView.entry_title(r.pack)
	return TranslationServer.translate("Added: %s") % (r.pack.title() if r.get("pack") is Pack else j.title)


func _row(j: PackInstall) -> Dictionary:
	var row := PanelContainer.new()
	row.name = "Install"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := Palette.frame(Color(0.11, 0.075, 0.045, 0.92), 10)
	style.set_content_margin_all(8)
	row.add_theme_stylebox_override("panel", style)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	row.add_child(v)
	var title := Palette.label(j.title, 14)
	var text := Palette.label(j.text(), 13, Palette.MUTED)
	text.name = "Stage"
	text.custom_minimum_size.x = 280
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(280, 8)
	bar.show_percentage = false
	for c in [title, text, bar]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(c)
	box.add_child(row)
	return {"row": row, "title": title, "text": text, "bar": bar, "left": RESULT_SECONDS}
