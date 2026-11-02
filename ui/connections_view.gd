class_name ConnectionsView
extends Control
## Play through a server: the connections to game servers (Settings servers; none, one or
## many; the same address may be there twice with other logins). A row per connection: its name
## (to rename), the address, who is logged in, Open (log in or register there, then the server's
## home), Log out, Remove (pressed twice); a row to add one (name and address).

signal back
## A connection was opened (main logs in there or shows the server's home).
signal chosen(id: String)


func _ready() -> void:
	name = "ConnectionsView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sound.music("menu")
	_build()
	for l in get_tree().get_nodes_in_group(ServerLink.GROUP):  # who is logged in, as it changes
		l.message.connect(func(msg):
			if msg.get("t") in ["auth", "logged_out", "kicked"]:
				_build.call_deferred())
		l.closed.connect(func(_why): _build.call_deferred())


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self)
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", Palette.frame())
	p.position = Vector2(190, 50)
	p.size = Vector2(900, 620)
	add_child(p)
	var title := Palette.label(tr("Game servers"), 32, Palette.ATTACK)
	title.position = Vector2(0, 14)
	title.size.x = 900
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(24, 70)
	scroll.size = Vector2(852, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "ServerRows"
	list.custom_minimum_size.x = 840
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	if Settings.data.servers.is_empty():
		list.add_child(Palette.label(tr("No servers: add one below"), 18, Palette.MUTED))
	for i in Settings.data.servers.size():
		list.add_child(_server_row(i, Settings.data.servers[i]))
	var add := HBoxContainer.new()
	add.name = "AddServer"
	add.position = Vector2(24, 486)
	add.size = Vector2(852, 44)
	add.add_theme_constant_override("separation", 8)
	p.add_child(add)
	var name_ed := _edit("NewName", tr("Name"), 200)
	var url_ed := _edit("NewUrl", "wss://example.org:7377", 0)
	url_ed.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	url_ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.add_child(name_ed)
	add.add_child(url_ed)
	var go := Palette.button(tr("Add"), "AddServerButton")
	go.custom_minimum_size = Vector2(120, 40)
	go.pressed.connect(func(): add_server(name_ed.text, url_ed.text))
	url_ed.text_submitted.connect(func(_t): add_server(name_ed.text, url_ed.text))
	add.add_child(go)
	var note := Palette.label(tr("The password goes only to this server. Use a server you trust; a public server needs wss:// (TLS)."), 15, Color("a8967a"))
	note.name = "ServersNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # before the size: a label without wrapping is as wide as its text
	note.position = Vector2(24, 544)
	note.size = Vector2(660, 60)
	p.add_child(note)
	var done := Palette.button(tr("Back"), "Back")
	done.position = Vector2(716, 550)
	done.custom_minimum_size = Vector2(160, 50)
	done.pressed.connect(func(): back.emit())
	p.add_child(done)


func _edit(id: String, hint: String, width: float) -> LineEdit:
	var e := LineEdit.new()
	e.name = id
	e.placeholder_text = hint
	e.max_length = 200
	e.custom_minimum_size = Vector2(width, 40)
	return e


## The open connection (main's), or null.
func _link_of(id: String) -> ServerLink:
	if not is_inside_tree():
		return null
	for l in get_tree().get_nodes_in_group(ServerLink.GROUP):
		if l.id == id:
			return l
	return null


## A connection: its name (Enter or leaving the field renames it), the address, who is logged in.
func _server_row(i: int, e: Dictionary) -> Control:
	var id: String = e.id
	var row := PanelContainer.new()
	row.name = "Server%d" % i
	var st := Palette.box(Color(0, 0, 0, 0.28), 10, Color("6b5320", 0.7), 1)
	st.content_margin_left = 10
	st.content_margin_right = 8
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", st)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	row.add_child(hb)
	var name_ed := _edit("Name", tr("Name"), 170)
	name_ed.text = e.name
	name_ed.max_length = 40
	var rename := func(_t = ""): rename_server(id, name_ed.text)
	name_ed.text_submitted.connect(rename)
	name_ed.focus_exited.connect(rename)
	hb.add_child(name_ed)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	hb.add_child(words)
	var addr := Palette.label(e.url, 16, Palette.MUTED)
	addr.clip_text = true
	addr.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	addr.custom_minimum_size.x = 220
	words.add_child(addr)
	var who := Palette.label(_who(id), 16, Palette.TEXT)
	who.name = "Who"
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.custom_minimum_size.x = 220
	words.add_child(who)
	var open := Palette.button(tr("Open"), "Open")
	open.custom_minimum_size = Vector2(0, 40)
	open.pressed.connect(func(): chosen.emit(id))
	hb.add_child(open)
	var out := Palette.button(tr("Log out"), "Logout")
	out.custom_minimum_size = Vector2(0, 40)
	out.disabled = str(ServerLink.saved_for(id).get("token", "")) == ""
	out.pressed.connect(func():
		log_out_server(id)
		_build())
	hb.add_child(out)
	var rm := Palette.button(tr("Remove"), "Remove")
	rm.custom_minimum_size = Vector2(0, 40)
	rm.pressed.connect(func():
		if rm.has_meta("armed"):
			remove_server(id)
			_build()
			return
		rm.set_meta("armed", true)
		rm.text = tr("Remove? Press again"))
	hb.add_child(rm)
	return row


## Who is logged in: the account (when connected), "Logged in", "Logged in on another device"
## (kicked) or "Not logged in".
func _who(id: String) -> String:
	var l := _link_of(id)
	if l and l.logged_in():
		return tr("Logged in: %s") % ServerView.player_label(l.me)
	var s := ServerLink.saved_for(id)
	if str(s.get("token", "")) == "":
		return tr("Not logged in")
	return tr("You logged in on another device") if s.get("kicked", false) else tr("Logged in")


## Adds a connection (an address already in the list gets another one: another login there).
func add_server(name: String, url: String) -> bool:
	url = url.strip_edges()
	var ed := find_child("NewUrl", true, false) as LineEdit
	if not Settings.server_ok(url):
		if ed:
			ed.add_theme_color_override("font_color", Palette.OPPONENT)
		return false
	Settings.data.servers.append({"id": Settings.new_server_id(url), "url": url, "name": Settings.server_label(url, name)})
	Settings.save()
	_build()
	return true


func rename_server(id: String, name: String) -> void:
	for x in Settings.data.servers:
		if x.id == id and x.name != Settings.server_label(x.url, name):
			x.name = Settings.server_label(x.url, name)
			Settings.save()


func log_out_server(id: String) -> void:
	var l := _link_of(id)
	if l and l.is_open():
		l.log_out()
	else:
		ServerLink.remember_for(id, {"token": null, "kicked": null})


## Removes a connection: logged out there, its session forgotten (main closes it).
func remove_server(id: String) -> void:
	log_out_server(id)
	ServerLink.forget(id)
	Settings.data.servers = Settings.data.servers.filter(func(x): return x.id != id)
	Settings.save()
