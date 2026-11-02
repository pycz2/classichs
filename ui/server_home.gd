class_name ServerHome
extends Control
## A game server after the login: who the player is there (name#tag; friends and chat are the
## Social overlay's: the Friends button opens it), and the server's games (its packs and the
## player's own uploads): Download one (its progress), Play one the player has (its game menu),
## the art and music set for each, kept on the server for this account (server/README.md, "Game
## settings"; an older server: on this device); Upload a game of this device; Delete an own
## upload (pressed twice). A server without packs plays its built-in Classic rules: Classic is
## its game then.

signal back
## A game was chosen (main opens its menu, played through this server).
signal entered(p: Pack)
signal friends

var link: ServerLink
var _list: VBoxContainer
var _note: Label
var _delete_armed := ""


func _ready() -> void:
	name = "ServerHome"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sound.music("menu")
	link.packs_changed.connect(_build)
	link.pack_progress.connect(_on_progress)
	link.pack_downloaded.connect(func(_h, res):
		_build()
		say(tr("Downloaded: %s") % res.pack.title() if res.has("pack") else str(res.get("error", ""))))
	link.pack_uploaded.connect(func(res):
		_build()
		say(tr("Uploaded: %s") % ServerView.entry_title(res.pack) if res.has("pack") else str(res.get("error", ""))))
	link.message.connect(func(msg):
		if msg.get("t") in ["me", "game_settings"]:
			_build())
	_build()
	link.request_packs()


func say(text: String) -> void:
	if _note:
		_note.text = text


## The games the server offers: its packs and the player's uploads (Classic, the built-in rules,
## when it has none of its own).
func entries() -> Array:
	var out: Array = link.packs.server + link.packs.mine
	if link.packs.server.is_empty():
		for p: Pack in Packs.all():
			if p.id() == Packs.CLASSIC:
				out.push_front({"id": p.id(), "name": p.manifest.get("name", {}), "version": p.version(),
					"rules_hash": p.rules_hash(), "content_hash": Packs.content_hash(p), "size": p.size})
				break
	return out


func _build() -> void:
	var keep := _note.text if _note else ""
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self, "library_bg")
	var title := Palette.label(link.display_name(), 34, Palette.ATTACK)
	title.name = "Title"
	title.position = Vector2(40, 18)
	title.size = Vector2(560, 48)
	title.clip_text = true
	add_child(title)
	var me := Palette.label(ServerView.player_label(link.me), 22, Palette.TEXT)
	me.name = "PlayerName"
	me.position = Vector2(40, 66)
	me.size = Vector2(560, 30)
	me.clip_text = true
	add_child(me)
	var row := HBoxContainer.new()
	row.position = Vector2(640, 24)
	row.size = Vector2(600, 48)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	for spec in [["Friends", "Friends", func(): friends.emit()], ["Log out", "Logout", log_out], ["Back", "Back", func(): back.emit()]]:
		var b := Palette.button(tr(spec[0]), spec[1])
		b.custom_minimum_size = Vector2(150, 46)
		b.pressed.connect(spec[2])
		row.add_child(b)
	var head := Palette.label(tr("Games on this server"), 26, Palette.ATTACK)
	head.position = Vector2(40, 112)
	add_child(head)
	var panel := Panel.new()
	panel.position = Vector2(30, 152)
	panel.size = Vector2(1220, 486)
	panel.add_theme_stylebox_override("panel", Palette.frame())
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(46, 166)
	scroll.size = Vector2(1188, 458)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.name = "Games"
	_list.custom_minimum_size.x = 1176
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	var all := entries()
	if all.is_empty():
		var none := Palette.label(tr("No games on this server yet"), 18, Palette.MUTED)
		none.name = "NoGames"
		_list.add_child(none)
	for e in all:
		_list.add_child(_game_row(e))
	var up := Palette.button(tr("Upload a game"), "UploadPack")
	up.position = Vector2(150, 654)  # (the friends button has the corner)
	up.custom_minimum_size = Vector2(260, 50)
	up.disabled = not link.has_packs
	up.pressed.connect(show_upload)
	add_child(up)
	_note = Palette.label(keep, 17, Palette.MUTED)
	_note.name = "Note"
	_note.position = Vector2(430, 666)
	_note.size = Vector2(810, 30)
	_note.clip_text = true
	add_child(_note)


## One game: its name, version and size; its art and music set; Download, Play, Delete.
func _game_row(e: Dictionary) -> Control:
	var h := str(e.get("content_hash", ""))
	var row := PanelContainer.new()
	row.name = "Game_" + str(e.get("id", "")).replace(".", "_")
	var st := Palette.box(Color(0, 0, 0, 0.28), 10, Color("6b5320", 0.7), 1)
	st.set_content_margin_all(10)
	row.add_theme_stylebox_override("panel", st)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	row.add_child(hb)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	hb.add_child(words)
	var name_l := Palette.label(ServerView.entry_title(e), 22, Palette.ATTACK)
	name_l.clip_text = true
	words.add_child(name_l)
	var mine := link.is_mine(e)
	var sub := "%s · %s" % [str(e.get("version", "")), Packs.size_text(int(e.get("size", 0)))]
	if mine:
		sub += " · " + (tr("uploaded by you") if e.get("enabled", true) else tr("uploaded by you, turned off"))
	words.add_child(Palette.label(sub, 15, Palette.MUTED))
	var have := ServerLink.local_pack(e)
	if have:
		for spec in [["art", "ArtSet", "Card art"], ["music", "MusicSet", "Music set"]]:
			var kind: String = spec[0]
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 0)
			col.add_child(Palette.label(tr(spec[2]), 13, Palette.MUTED))
			var pick := GamesView.set_picker(have, kind, choice(have, kind), func(v): set_choice(have, kind, v))
			pick.name = spec[1]
			pick.custom_minimum_size = Vector2(190, 36)
			col.add_child(pick)
			hb.add_child(col)
	if have:
		var play := Palette.button(tr("Play"), "Play")
		play.custom_minimum_size = Vector2(130, 44)
		play.pressed.connect(func(): entered.emit(have))
		hb.add_child(play)
	elif link.downloading.has(h):
		var prog := Palette.label(tr("Downloading…"), 17, Palette.SELECTED)
		prog.name = "Progress"
		prog.custom_minimum_size.x = 130
		hb.add_child(prog)
	else:
		var dl := Palette.button(tr("Download"), "Download")
		dl.custom_minimum_size = Vector2(130, 44)
		dl.pressed.connect(func():
			link.download_pack(e)
			_build())
		hb.add_child(dl)
	if mine:
		var del := Palette.button(tr("Delete"), "Delete")
		del.custom_minimum_size = Vector2(110, 44)
		del.pressed.connect(func():
			if _delete_armed == h:
				link.delete_pack(h)
				_delete_armed = ""
				say(tr("Deleting…"))
				return
			_delete_armed = h
			del.text = tr("Delete? Press again"))
		hb.add_child(del)
	return row


## The art or music set chosen for a game: kept on the server (an older one: on this device).
func choice(p: Pack, kind: String) -> String:
	var v := link.game_setting(p, kind) if link.has_settings else ""
	return v if v != "" else Packs.choice(p, kind)


func set_choice(p: Pack, kind: String, value: String) -> void:
	if link.has_settings:
		link.set_game_setting(p, kind, value)
	else:
		Packs.set_choice(p, kind, value)


func _on_progress(h: String, done: int, total: int) -> void:
	for e in entries():
		if str(e.get("content_hash", "")) == h:
			var row := _list.find_child("Game_" + str(e.get("id", "")).replace(".", "_"), false, false) if _list else null
			var l := row.find_child("Progress", true, false) as Label if row else null
			if l:
				l.text = tr("Downloading… %d%%") % (100 * done / total) if total > 0 else tr("Downloading…")


func log_out() -> void:
	link.log_out()
	back.emit()


## Upload a game: the packs of this device the server has not got (the same rules), one click each.
func show_upload() -> void:
	var dim := ColorRect.new()
	dim.name = "UploadPanel"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Palette.frame())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(Palette.label(tr("Upload a game"), 26, Palette.ATTACK))
	var mine := Packs.all().filter(func(p: Pack): return link.server_pack_for(p).is_empty())
	if mine.is_empty():
		box.add_child(Palette.label(tr("The server has every game of this device"), 18, Palette.MUTED))
	for p: Pack in mine:
		var b := Palette.button(p.title(), "Upload_" + p.id().replace(".", "_"))
		b.custom_minimum_size = Vector2(420, 46)
		b.pressed.connect(func():
			dim.queue_free()
			say(tr("Uploading %s…") % p.title())
			link.upload_pack(p))
		box.add_child(b)
	var close := Palette.button(tr("Cancel"), "Cancel")
	close.pressed.connect(dim.queue_free)
	box.add_child(close)
