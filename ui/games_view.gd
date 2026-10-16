class_name GamesView
extends Control
## The "Games" screen: the game packs the player has (built-in, downloaded, imported,
## received from a player) as big tiles, the active one marked; the selected one's
## details with its art, sound and music sets, "Play this game", Delete (not for a
## built-in one) and Import a pack file. Below the tiles, per game server: the games
## that server offers (download, use).

signal back

const GRID := Rect2(Vector2(36, 84), Vector2(780, 620))
const PANEL := Rect2(Vector2(836, 84), Vector2(410, 620))
const TILE := Vector2(376, 212)
## Origin -> label (English keys; i18n_keys.gd reads this table).
const ORIGINS := {"builtin": "Built-in", "downloaded": "Downloaded", "imported": "Imported", "p2p": "Received from a player"}

## The game servers whose games are listed (main gives its links).
var links: Array = []
var selected: Pack
var message: Label
var _list := VBoxContainer.new()
var _panel := PanelContainer.new()
var _overlay: Control
var _web_callback: JavaScriptObject  # kept alive while the browser's file picker is open


func _ready() -> void:
	name = "GamesView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sound.music("menu")
	selected = Packs.active()
	_build()
	for l: ServerLink in links:
		l.packs_changed.connect(_build_list)
		l.pack_progress.connect(_on_progress)
		l.pack_downloaded.connect(_on_downloaded)
		if l.logged_in():
			l.request_packs()


func _on_progress(content_hash: String, done: int, total: int) -> void:
	var b := find_child("Get_" + content_hash.left(12), true, false) as Button
	if b and total > 0:
		b.text = "%d%%" % (100 * done / total)


func _on_downloaded(_content_hash: String, result: Dictionary) -> void:
	if result.has("error"):
		show_message(str(result.error))
	else:
		show_message(tr("Added: %s") % (result.pack as Pack).title(), true)
	_build_list()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self, "library_bg")
	var title := Palette.label(tr("Games"), 34, Palette.ATTACK)
	title.name = "Title"
	title.position = Vector2(GRID.position.x + 4, 18)
	add_child(title)
	var import := Palette.button(tr("Import a game file"), "ImportPack")
	import.custom_minimum_size = Vector2(250, 46)
	import.position = Vector2(GRID.end.x - 250, 20)
	import.pressed.connect(import_pack)
	add_child(import)
	var back_b := Palette.button(tr("Back"), "Back")
	back_b.custom_minimum_size = Vector2(150, 46)
	back_b.position = Vector2(PANEL.end.x - 150, 20)
	back_b.pressed.connect(func(): back.emit())
	add_child(back_b)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.position = GRID.position
	scroll.size = GRID.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 14)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_panel = PanelContainer.new()
	_panel.name = "Details"
	_panel.position = PANEL.position
	_panel.size = PANEL.size
	_panel.add_theme_stylebox_override("panel", Palette.frame())
	add_child(_panel)
	message = Palette.label("", 17, Palette.DANGER)
	message.name = "Message"
	message.position = Vector2(GRID.position.x + 4, GRID.end.y - 2)
	message.size = Vector2(GRID.size.x, 20)
	add_child(message)
	_build_list()
	_build_details()


## The tiles, then each server's games.
func _build_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var grid := GridContainer.new()
	grid.name = "Tiles"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	_list.add_child(grid)
	for p: Pack in Packs.all():
		var t := PackTile.new(p)
		t.selected = p == selected
		t.pressed.connect(func(): select(p))
		t.gui_input.connect(func(ev):  # a double click plays it
			if ev is InputEventMouseButton and ev.double_click:
				activate(p))
		grid.add_child(t)
	for l in links:
		_server_section(l)


## A server's games: what it offers (its own and the player's uploads), with Download / Use.
func _server_section(link: ServerLink) -> void:
	var entries: Array = link.packs.get("server", []) + link.packs.get("mine", [])
	var head := Palette.label(tr("On the server %s") % link.display_name(), 22, Palette.ATTACK)
	head.name = "Server_" + link.url.md5_text().left(8)
	_list.add_child(head)
	if not link.logged_in():
		_list.add_child(Palette.label(tr("Log in on this server to see its games."), 16))
		return
	if entries.is_empty():
		_list.add_child(Palette.label(tr("This server offers no games yet."), 16))
		return
	for e in entries:
		_list.add_child(_server_row(link, e))


func _server_row(link: ServerLink, e: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.name = "ServerPack_" + str(e.get("id", ""))
	var st := Palette.box(Color(0.1, 0.07, 0.04, 0.9), 10, Color("6b5320"), 2)
	st.set_content_margin_all(10)
	row.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var l := Palette.label("%s  %s  ·  %s" % [ServerView.entry_title(e), str(e.get("version", "")), Packs.size_text(int(e.get("size", 0)))], 18)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	h.add_child(l)
	var have := ServerLink.local_pack(e)
	var b := Palette.button(tr("Use") if have else tr("Download"), "Get_" + str(e.get("content_hash", "")).left(12))
	b.custom_minimum_size = Vector2(150, 40)
	b.disabled = have != null and have == Packs.active()
	if have and have == Packs.active():
		b.text = tr("Active")
	b.pressed.connect(func():
		if have:
			activate(have)
		else:
			b.disabled = true
			b.text = tr("Downloading…")
			link.download_pack(e))
	h.add_child(b)
	return row


func select(p: Pack) -> void:
	selected = p
	for t in find_children("*", "PackTile", true, false):
		t.selected = t.pack == p
		t.queue_redraw()
	_build_details()


## Makes a pack the active one: the whole game shows and plays it from now on.
func activate(p: Pack) -> void:
	selected = p
	Packs.set_active(p)
	_build()


func show_message(text: String, good := false) -> void:
	message.text = text
	message.add_theme_color_override("font_color", Palette.OK if good else Palette.DANGER)


func _build_details() -> void:
	for c in _panel.get_children():
		_panel.remove_child(c)
		c.queue_free()
	var p := selected
	if p == null:
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var title := Palette.label(p.title(), 28, Palette.ATTACK)
	title.name = "PackName"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var desc := Palette.label(p.description(), 15)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(PANEL.size.x - 30, 0)
	box.add_child(desc)
	var origin := tr(ORIGINS.get(p.origin, "Imported"))
	if p.origin == "downloaded" and p.server != "":
		origin += " (%s)" % p.server.trim_prefix("wss://").trim_prefix("ws://")
	var cards := p.cards().filter(func(c): return c is Dictionary and c.get("collectible", false) and c.get("type") != "CHAMPION").size()
	var info := Palette.label("%s %s  ·  %s  ·  %s\n%s" % [tr("Version"), p.version(), Packs.size_text(p.size), origin,
		tr("%d cards, %d languages") % [cards, p.manifest.get("locales", []).size()]], 15, Color("d8c8a0"))
	info.name = "Info"
	box.add_child(info)
	var why := Rules.can_play(p)
	if why != "":
		var note := Palette.label(tr(why) + "\n" + tr("You can look at its cards and decks."), 15, Color("ffb070"))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(PANEL.size.x - 30, 0)
		box.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for row in [["Card art", "art", "ArtSet"], ["Sounds", "sound", "SoundSet"], ["Music set", "music", "MusicSet"]]:
		var kind: String = row[1]
		var sets := p.sets(kind).filter(func(x): return not x.get("local", false) or p.builtin())
		if p == Packs.active() and kind == "art":  # the player's own picture folders too
			for f in Art.sets():
				if not sets.any(func(x): return x.id == f):
					sets.append({"id": f, "name": {"en": {"original": "Original"}.get(f, f.capitalize())}})
		var pick := OptionButton.new()
		pick.name = row[2]
		pick.custom_minimum_size = Vector2(220, 36)
		for x in sets:
			pick.add_item(SettingsView.pack_set_name(p, x))
		pick.select(maxi(0, sets.map(func(x): return str(x.id)).find(Packs.choice(p, kind))) if not sets.is_empty() else -1)  # a pack may have no music
		pick.disabled = sets.size() < 2
		pick.item_selected.connect(func(i): Packs.set_choice(p, kind, str(sets[i].id)))
		grid.add_child(Palette.label(tr(row[0]), 17))
		grid.add_child(pick)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var play := Palette.button(tr("Active") if p == Packs.active() else tr("Play this game"), "Activate")
	play.disabled = p == Packs.active()
	play.pressed.connect(activate.bind(p))
	box.add_child(play)
	if not p.builtin():
		var del := Palette.button(tr("Delete"), "DeletePack")
		del.pressed.connect(_confirm_delete.bind(p))
		box.add_child(del)


func _confirm_delete(p: Pack) -> void:
	var box := _popup(tr("Delete \"%s\"?") % p.title())
	box.add_child(Palette.label(tr("The game file is removed from this device; you can get it again."), 17))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var yes := Palette.button(tr("Delete"), "ConfirmDelete")
	yes.pressed.connect(func():
		_close()
		delete_pack(p))
	row.add_child(yes)
	var no := Palette.button(tr("Cancel"), "Cancel")
	no.pressed.connect(_close)
	row.add_child(no)


func delete_pack(p: Pack) -> void:
	var title := p.title()
	Packs.remove(p)
	selected = Packs.active()
	_build()
	show_message(tr("Deleted: %s") % title, true)


func _popup(title: String) -> VBoxContainer:
	_close()
	_overlay = Control.new()
	_overlay.name = "Popup"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Palette.frame())
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(Palette.label(title, 26, Palette.ATTACK))
	add_child(_overlay)
	return box


func _close() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


## Import a .cardpack: the system's file dialog natively, the browser's file picker on the web.
func import_pack() -> void:
	if OS.has_feature("web"):
		_import_web()
		return
	var d := FileDialog.new()
	d.name = "ImportDialog"
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.filters = PackedStringArray(["*.cardpack ; " + tr("Game packs")])
	d.file_selected.connect(func(path: String):
		import_bytes(FileAccess.get_file_as_bytes(path), path.get_file())
		d.queue_free())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(900, 600))


## The browser: a hidden <input type=file> (id classichs-pack-input) reads the file and hands
## it over as base64.
func _import_web() -> void:
	_web_callback = JavaScriptBridge.create_callback(func(args: Array):
		import_bytes(Marshalls.base64_to_raw(str(args[1])), str(args[0])))
	JavaScriptBridge.get_interface("window").classichsPackPicked = _web_callback
	JavaScriptBridge.eval("""(function () {
		var i = document.getElementById('classichs-pack-input');
		if (!i) {
			i = document.createElement('input');
			i.type = 'file'; i.accept = '.cardpack'; i.id = 'classichs-pack-input'; i.style.display = 'none';
			document.body.appendChild(i);
			i.addEventListener('change', function () {
				var f = i.files[0];
				if (!f) return;
				var r = new FileReader();
				r.onload = function () {
					var b = new Uint8Array(r.result), s = '';
					for (var k = 0; k < b.length; k += 32768) s += String.fromCharCode.apply(null, b.subarray(k, k + 32768));
					i.value = '';
					window.classichsPackPicked(f.name, btoa(s));
				};
				r.readAsArrayBuffer(f);
			});
		}
		i.click();
	})();""", true)


## Installs a pack file's bytes and selects it (not active until the player says so).
func import_bytes(bytes: PackedByteArray, file_name := "") -> void:
	var r := Packs.install(bytes, "imported")
	if r.has("error"):
		show_message(tr(str(r.error)) + (": " + str(r.detail) if r.has("detail") else "") + (" (%s)" % file_name if file_name != "" else ""))
		return
	selected = r.pack
	_build()
	show_message(tr("Added: %s") % selected.title(), true)


## A pack as a big tile: its menu picture (or its champions), its logo (or its name in
## the title font), name, version, size, where it came from; the active one is marked.
class PackTile:
	extends Button
	var pack: Pack
	var selected := false
	var _bg: Texture2D
	var _logo: Texture2D
	var _champions: Array = []  # textures

	func _init(p: Pack) -> void:
		pack = p
		name = "Pack_" + p.id().replace(".", "_") + ("" if p.builtin() else "_" + Packs.content_hash(p).left(8))
		custom_minimum_size = GamesView.TILE
		focus_mode = Control.FOCUS_NONE
		flat = true
		var f := p.find("ui", "menu", Pack.IMAGE_EXT)
		_bg = p.texture(f) if f != "" else null
		var logo = p.manifest.get("logo")
		_logo = p.texture(logo) if logo is String else null
		if _logo:
			var head := Rect2(Vector2(15, 19), Vector2(GamesView.TILE.x - 30, 96))
			var h := _logo.get_width() * head.size.y / head.size.x
			var crop := AtlasTexture.new()
			crop.atlas = _logo
			crop.region = Rect2(0, (_logo.get_height() - h) / 2.0, _logo.get_width(), h)
			var l := TextureRect.new()
			l.texture = crop
			l.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			l.position = head.position
			l.size = head.size
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var add := CanvasItemMaterial.new()
			add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			l.material = add
			add_child(l)
		if _bg == null:
			var art := p.default_set("art")
			for c in p.rules().get("classes", []):
				if c is Dictionary and c.has("champion") and _champions.size() < 3:
					var a := p.find("art/" + art, str(c.champion), Pack.IMAGE_EXT)
					if a != "":
						_champions.append(p.texture(a))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var inner := r.grow(-5)
		draw_style_box(Palette.box(Color("1b140f"), 14), r)
		if _bg:
			_cover(_bg, inner)
		elif not _champions.is_empty():
			var w := inner.size.x / _champions.size()
			for i in _champions.size():
				var cell := Rect2(inner.position + Vector2(w * i, 0), Vector2(w, inner.size.y))
				_cover(_champions[i], cell, 0.3)
		var shade := Color(0, 0, 0, 0.0)
		var dark := Color(0.05, 0.03, 0.02, 0.9)
		draw_polygon(PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]),
			PackedColorArray([shade, shade, dark, dark]))
		var head := Rect2(inner.position + Vector2(10, 14), Vector2(inner.size.x - 20, 96))
		if not _logo:  # (a logo is a child added onto the picture: light on black)
			var f := Fonts.title(pack)  # each game's tile in its own title font
			var t := pack.title()
			var fs := 40
			while fs > 20 and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > head.size.x:
				fs -= 2
			var at := Vector2(head.get_center().x - f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x / 2.0, head.get_center().y + fs * 0.35)
			draw_string_outline(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color("1b0f06"))
			draw_string_outline(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color("8a6d2a"))
			draw_string(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("f2c94c"))
		var font := get_theme_font("font", "Label")
		DeckTiles.text(self, Vector2(18, size.y - 40), pack.title(), 24, Color("f4ead5"), size.x - 36)
		var origin := TranslationServer.translate(GamesView.ORIGINS.get(pack.origin, "Imported"))
		DeckTiles.text(self, Vector2(18, size.y - 15), "%s  ·  %s  ·  %s" % [pack.version(), Packs.size_text(pack.size), origin], 15, Color("d8c8a0"), size.x - 36)
		var active := pack == Packs.active()
		if active:  # a green-gold ribbon in the top left corner
			var label := TranslationServer.translate("Active")
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 24
			var ribbon := Palette.box(Color("2f6b2a"), 8, Color("c9e88a"), 2) if Palette.CLASSIC else Palette.box(Palette.OK.darkened(0.7), 4, Palette.OK, 1)
			draw_style_box(ribbon, Rect2(Vector2(12, 10), Vector2(w, 26)))
			draw_string(font, Vector2(24, 29), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("f4ffe0"))
		var edge := (Palette.SELECTED if Palette.CLASSIC else Palette.ATTACK) if selected else (Color("c9a74a") if is_hovered() else Color("6b5320"))
		var st := Palette.box(Color.TRANSPARENT, 14, edge, 4 if selected else 3)
		st.draw_center = false
		draw_style_box(st, r)
		if active:
			var glow := Palette.box(Color.TRANSPARENT, 16, Color(0.75, 1, 0.5, 0.35), 3)
			glow.draw_center = false
			draw_style_box(glow, r.grow(3))

	## The picture covers rect (cropped to its shape; focus: where its middle is, 0 top … 1 bottom).
	func _cover(tex: Texture2D, rect: Rect2, focus := 0.5) -> void:
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var k := maxf(rect.size.x / tw, rect.size.y / th)
		var src := Vector2(rect.size.x / k, rect.size.y / k)
		var y := clampf(th * focus - src.y / 2.0, 0.0, th - src.y)
		draw_texture_rect_region(tex, rect, Rect2(Vector2((tw - src.x) / 2.0, y), src))
