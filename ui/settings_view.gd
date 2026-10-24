class_name SettingsView
extends Control
## Settings: language, volumes, speech, screen shake, fullscreen, player name.
## Every change is applied and saved at once. Works as a screen and as an overlay.

signal back
## The debug tools were asked for (the button shows only when this is connected:
## not in the settings opened over a match).
signal debug
## The language changed; the owner relabels its own texts.
signal language_changed
## The picture set changed; the owner redraws its cards.
signal art_changed

## Row labels (English keys); the translation tool reads these lists.
const SLIDERS := [["Music", "music"], ["Sounds", "sfx"]]
const TOGGLES := [["Screen shake", "Shake", "shake"], ["Fullscreen", "Fullscreen", "fullscreen"]]


func _ready() -> void:
	name = "SettingsView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Color(Palette.TABLE, 0.95)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var title := Palette.label(tr("Settings"), 40, Palette.ATTACK)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)

	var lang := OptionButton.new()
	lang.name = "Language"
	for code in Locale.LANGS:
		lang.add_item(Locale.LANGS[code])
		if code == Settings.language():
			lang.select(lang.item_count - 1)
	lang.item_selected.connect(func(i): set_language(Locale.LANGS.keys()[i]))
	_row(grid, tr("Language"), lang)

	for s in SLIDERS:
		var sl := HSlider.new()
		sl.name = s[0]
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = Settings.data[s[1]]
		sl.custom_minimum_size = Vector2(300, 32)
		var key: String = s[1]
		sl.value_changed.connect(func(v): _store(key, v))
		_row(grid, tr(s[0]), sl)

	var pack := Packs.active()
	var music := OptionButton.new()
	music.name = "MusicSet"
	var music_sets := pack.sets("music").map(func(x): return str(x.id))
	for x in pack.sets("music"):
		music.add_item(pack_set_name(pack, x))
	music.select(maxi(0, music_sets.find(Packs.choice(pack, "music"))) if not music_sets.is_empty() else -1)  # a pack may have no music
	music.item_selected.connect(func(i):
		Packs.set_choice(pack, "music", music_sets[i])
		Sound.restart_music())
	_row(grid, tr("Music set"), music)

	var art := OptionButton.new()
	art.name = "ArtSet"
	var sets := Art.sets()
	for name in sets:
		var own: Array = pack.sets("art").filter(func(x): return x.id == name)
		art.add_item(pack_set_name(pack, own[0]) if not own.is_empty() else {"original": tr("Original")}.get(name, name.capitalize()))
	art.select(maxi(0, sets.find(Packs.choice(pack, "art"))))
	art.item_selected.connect(func(i):
		Packs.set_choice(pack, "art", sets[i])
		art_changed.emit())
	_row(grid, tr("Card art"), art)

	var backs := HBoxContainer.new()
	backs.add_theme_constant_override("separation", 10)
	var back_pick := OptionButton.new()
	back_pick.name = "CardBack"
	back_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var preview := CardBacks.Preview.new()
	var back_names: Array = (["pack"] if CardBacks.pack_texture() else []) + CardBacks.NAMES
	for n in back_names:
		back_pick.add_item(pack.title() if n == "pack" else tr(CardBacks.LABELS[n]))
	back_pick.select(maxi(0, back_names.find(CardBacks.current())))
	preview.back = CardBacks.current()
	back_pick.item_selected.connect(func(i):
		if CardBacks.pack_texture():  # a pack with its own back: the choice is the pack's
			Packs.set_choice(pack, "back", back_names[i])
		else:
			_store("card_back", back_names[i])
		preview.back = back_names[i]
		preview.queue_redraw()
		art_changed.emit())
	backs.add_child(back_pick)
	backs.add_child(preview)
	_row(grid, tr("Card back"), backs)

	var speed := HSlider.new()
	speed.name = "AnimSpeed"
	speed.min_value = 1
	speed.max_value = 4
	speed.step = 1
	speed.tick_count = 4
	speed.ticks_on_borders = true
	speed.value = Settings.data.anim_speed
	speed.custom_minimum_size = Vector2(300, 32)
	speed.value_changed.connect(func(v): _store("anim_speed", int(v)))
	_row(grid, tr("Animation speed"), speed)

	for t in TOGGLES:
		var cb := CheckButton.new()
		cb.name = t[1]
		cb.button_pressed = Settings.data[t[2]]
		if t[2] == "fullscreen":  # Esc in the browser leaves fullscreen without us
			cb.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		var key: String = t[2]
		cb.toggled.connect(func(on):
			if key == "fullscreen":
				Settings.set_fullscreen(on)  # runs inside the click: the browser allows it
			_store(key, on))
		_row(grid, tr(t[0]), cb)

	var ed := LineEdit.new()
	ed.name = "Name"
	ed.text = Profile.load_name()
	ed.max_length = Profile.NAME_MAX
	ed.custom_minimum_size = Vector2(300, 36)
	ed.text_changed.connect(Profile.save_name)
	_row(grid, tr("Your name"), ed)

	var servers := Palette.button(_servers_line(), "Servers")
	servers.custom_minimum_size = Vector2(300, 36)
	servers.clip_text = true
	servers.pressed.connect(show_servers)
	_row(grid, tr("Game servers"), servers)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	if not debug.get_connections().is_empty():
		var d := Palette.button(tr("Debug tools"), "DebugTools")
		d.pressed.connect(func(): debug.emit())
		row.add_child(d)
	var b := Palette.button(tr("Back"), "Back")
	b.pressed.connect(func(): back.emit())
	row.add_child(b)


## The name of a pack's art, sound or music set in the interface language (an English name
## the pack does not translate goes through the game's own translations).
static func pack_set_name(pack: Pack, entry: Dictionary) -> String:
	var names = entry.get("name", {})
	var lang := TranslationServer.get_locale()
	if names is Dictionary and not names.has(lang) and names.has("en"):
		return TranslationServer.translate(names.en)
	var t := pack.text_of(names, lang)
	return t if t != "" else str(entry.get("id", "")).capitalize()


func _row(grid: GridContainer, text: String, control: Control) -> void:
	grid.add_child(Palette.label(text, 20))
	grid.add_child(control)


func _store(key: String, value: Variant) -> void:
	Settings.data[key] = value
	Settings.apply()
	Settings.save()


func set_language(code: String) -> void:
	_store("language", code)
	_build()
	language_changed.emit()


# --- game servers (D14) ------------------------------------------------------------

## "localhost", "localhost +2" or "none" (the Servers button).
func _servers_line() -> String:
	var list: Array = Settings.data.servers
	if list.is_empty():
		return tr("None")
	return list[0].name + (" +%d" % (list.size() - 1) if list.size() > 1 else "")


## The open connection to a server (main's), or null.
func _link_of(url: String) -> ServerLink:
	if not is_inside_tree():
		return null
	for l in get_tree().get_nodes_in_group(ServerLink.GROUP):
		if l.url == url:
			return l
	return null


## The servers overlay: a row per server (its name to rename, the address, who is logged
## in, Log out, Remove pressed twice) and a row to add one (name and address).
func show_servers() -> void:
	var old := find_child("ServerList", false, false)
	if old:
		remove_child(old)
		old.queue_free()
	var dim := ColorRect.new()
	dim.name = "ServerList"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", Palette.frame())
	p.position = Vector2(190, 70)
	p.size = Vector2(900, 580)
	dim.add_child(p)
	var title := Palette.label(tr("Game servers"), 32, Palette.ATTACK)
	title.position = Vector2(0, 14)
	title.size.x = 900
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(24, 70)
	scroll.size = Vector2(852, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "ServerRows"
	list.custom_minimum_size.x = 840
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	if Settings.data.servers.is_empty():
		list.add_child(Palette.label(tr("No servers: add one below"), 18, Color("c9b48a")))
	for i in Settings.data.servers.size():
		list.add_child(_server_row(i, Settings.data.servers[i]))
	var add := HBoxContainer.new()
	add.name = "AddServer"
	add.position = Vector2(24, 450)
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
	note.position = Vector2(24, 500)
	note.size = Vector2(660, 60)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(note)
	var done := Palette.button(tr("Close"), "CloseServers")
	done.position = Vector2(716, 508)
	done.custom_minimum_size = Vector2(160, 50)
	done.pressed.connect(func():
		dim.queue_free()
		_build())
	p.add_child(done)


func _edit(id: String, hint: String, width: float) -> LineEdit:
	var e := LineEdit.new()
	e.name = id
	e.placeholder_text = hint
	e.max_length = 200
	e.custom_minimum_size = Vector2(width, 40)
	return e


## A server: its name (Enter or leaving the field renames it), the address, who is logged in.
func _server_row(i: int, e: Dictionary) -> Control:
	var url: String = e.url
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
	var name_ed := _edit("Name", tr("Name"), 180)
	name_ed.text = e.name
	name_ed.max_length = 40
	var rename := func(_t = ""): rename_server(url, name_ed.text)
	name_ed.text_submitted.connect(rename)
	name_ed.focus_exited.connect(rename)
	hb.add_child(name_ed)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	hb.add_child(words)
	var addr := Palette.label(url, 16, Color("c9b48a"))
	addr.clip_text = true
	addr.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	addr.custom_minimum_size.x = 300
	words.add_child(addr)
	var who := Palette.label(_who(url), 16, Palette.TEXT)
	who.name = "Who"
	words.add_child(who)
	var out := Palette.button(tr("Log out"), "Logout")
	out.custom_minimum_size = Vector2(0, 40)
	out.disabled = str(ServerLink.saved_for(url).get("token", "")) == ""
	out.pressed.connect(func():
		log_out_server(url)
		show_servers())
	hb.add_child(out)
	var rm := Palette.button(tr("Remove"), "Remove")
	rm.custom_minimum_size = Vector2(0, 40)
	rm.pressed.connect(func():
		if rm.has_meta("armed"):
			remove_server(url)
			show_servers()
			return
		rm.set_meta("armed", true)
		rm.text = tr("Remove? Press again"))
	hb.add_child(rm)
	return row


## Who is logged in on a server: the account (when connected), "Logged in", "Logged in on
## another device" (kicked) or "Not logged in".
func _who(url: String) -> String:
	var l := _link_of(url)
	if l and l.logged_in():
		return tr("Logged in: %s") % ServerView.player_label(l.me)
	var s := ServerLink.saved_for(url)
	if str(s.get("token", "")) == "":
		return tr("Not logged in")
	return tr("You logged in on another device") if s.get("kicked", false) else tr("Logged in")


func add_server(name: String, url: String) -> bool:
	url = url.strip_edges()
	var ed := find_child("NewUrl", true, false) as LineEdit
	if not Settings.server_ok(url) or Settings.data.servers.any(func(x): return x.url == url):
		if ed:
			ed.add_theme_color_override("font_color", Palette.OPPONENT)
		return false
	Settings.data.servers.append({"url": url, "name": Settings.server_label(url, name)})
	Settings.save()
	show_servers()
	return true


func rename_server(url: String, name: String) -> void:
	for x in Settings.data.servers:
		if x.url == url and x.name != Settings.server_label(url, name):
			x.name = Settings.server_label(url, name)
			Settings.save()


func log_out_server(url: String) -> void:
	var l := _link_of(url)
	if l and l.is_open():
		l.log_out()
	else:
		ServerLink.remember_for(url, {"token": null, "kicked": null})


## Removes a server: logged out there, its session forgotten (main closes its connection).
func remove_server(url: String) -> void:
	log_out_server(url)
	ServerLink.forget(url)
	Settings.data.servers = Settings.data.servers.filter(func(x): return x.url != url)
	Settings.save()
