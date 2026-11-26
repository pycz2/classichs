class_name ReportsView
extends Control
## The player's problem reports on a server (GET /reports): the list (open or closed, the last news, a dot
## on the unread ones), a report's thread (the player's messages and the admins' answers, oldest first) and a
## reply with text and, if the player keeps it, the screenshot taken when the report window opened.

var link: ServerLink
var screen := PackedByteArray()  # the screenshot a reply may take (empty: none or removed)
var _box: VBoxContainer  # the list or the thread
var _status: Label
var _back: Button
var _thread := 0  # the report shown (0: the list)


func _init(l: ServerLink = null, png := PackedByteArray()) -> void:
	link = l
	screen = png


## The open/closed word of a report.
static func state_text(state: String) -> String:
	return TranslationServer.translate("Closed") if state == "closed" else TranslationServer.translate("Open")


func _ready() -> void:
	name = "ReportsView"
	z_index = 200
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	var style := Palette.box(Palette.TABLE, 12)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 160
	panel.offset_right = -160
	panel.offset_top = 40
	panel.offset_bottom = -40
	add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	outer.add_child(Palette.label(tr("My reports"), 26, Palette.ATTACK))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	_box = VBoxContainer.new()
	_box.name = "Items"
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_box)
	_status = Palette.label("", 17)
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	outer.add_child(buttons)
	_back = Palette.button(tr("Back"), "Back")
	_back.pressed.connect(show_list)
	buttons.add_child(_back)
	var close := Palette.button(tr("Close"), "Close")
	close.pressed.connect(queue_free)
	buttons.add_child(close)
	show_list()


func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()


func _text(text: String, size := 17, color := Palette.TEXT) -> Label:
	var l := Palette.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(l)
	return l


# --- the list ------------------------------------------------------------------------------

func show_list() -> void:
	_thread = 0
	_back.visible = false
	_clear()
	_status.text = tr("Loading…")
	link.request_reports(_on_list)


func _on_list(d: Dictionary) -> void:
	if _thread != 0:
		return  # (a thread opened meanwhile)
	_status.text = str(d.get("error", ""))
	var list: Array = d.get("list") if d.get("list") is Array else []
	if list.is_empty() and not d.has("error"):
		_text(tr("You have not sent any reports yet"), 18, Palette.MUTED)
	for r in list:
		if not r is Dictionary:
			continue
		var b := Button.new()
		b.name = "Report_%d" % int(r.get("id", 0))
		var first := str(r.get("text", "")).replace("\n", " ")
		b.text = "%s%s\n%s · %s" % ["● " if r.get("unread", false) else "", first.left(70) + ("…" if first.length() > 70 else ""),
			state_text(str(r.get("state", ""))), ReplaysView._date(int(r.get("last_at", 0)))]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(show_thread.bind(int(r.get("id", 0))))
		_box.add_child(b)


# --- a thread ------------------------------------------------------------------------------

func show_thread(id: int) -> void:
	_thread = id
	_back.visible = true
	_clear()
	_status.text = tr("Loading…")
	link.request_report(id, _on_thread)


func _on_thread(d: Dictionary) -> void:
	if int(d.get("id", _thread)) != _thread:
		return
	_status.text = str(d.get("error", ""))
	if d.has("error"):
		return
	_text(tr("Report %d: %s") % [_thread, state_text(str(d.get("state", "")))], 20, Palette.ATTACK).name = "State"
	for m in d.get("messages", []) if d.get("messages") is Array else []:
		if not m is Dictionary:
			continue
		var who := tr("You") if m.get("from") == "you" else (str(m.get("name", "")) if str(m.get("name", "")) != "" else tr("Admin"))
		var head := "%s · %s" % [who, ReplaysView._date(int(m.get("at", 0)))]
		if m.get("screen", false):
			head += " · " + tr("with a screenshot")
		_text(head, 15, Palette.ATTACK if m.get("from") != "you" else Palette.MUTED)
		_text(str(m.get("text", ""))).name = "Message_%d" % int(m.get("id", 0))
	var reply := TextEdit.new()
	reply.name = "ReplyText"
	reply.placeholder_text = tr("Your answer")
	reply.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	reply.custom_minimum_size = Vector2(0, 100)
	_box.add_child(reply)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_box.add_child(row)
	if not screen.is_empty():
		var shot := HBoxContainer.new()
		shot.name = "ReplyScreenshot"
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(128, 72)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var img := Image.new()
		if img.load_png_from_buffer(screen) == OK:
			pic.texture = ImageTexture.create_from_image(img)
		shot.add_child(pic)
		var remove := Button.new()
		remove.name = "RemoveScreenshot"
		remove.text = tr("Remove")
		remove.pressed.connect(func():
			screen = PackedByteArray()
			shot.queue_free())
		shot.add_child(remove)
		row.add_child(shot)
	var send := Palette.button(tr("Send"), "SendReply")
	send.pressed.connect(func():
		if reply.text.strip_edges() == "":
			return
		send.disabled = true
		_status.text = tr("Sending…")
		link.reply_report(_thread, reply.text.strip_edges().left(ReportView.MAX_TEXT), screen, _on_reply))
	row.add_child(send)


func _on_reply(d: Dictionary) -> void:
	if d.has("error"):
		_status.text = str(d.error)
		var send := _box.find_child("SendReply", true, false) as Button
		if send:
			send.disabled = false
		return
	screen = PackedByteArray()  # (sent once)
	show_thread(_thread)
