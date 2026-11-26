class_name Studio
extends Control
## ClassicHS Studio: the card editor, a second application made from the game's project (studio/studio.tscn,
## the main scene of the "studio" feature tag's builds). The start screen lists the projects (StudioProject):
## open, delete, a new game, a copy of an installed game pack or a .cardpack. The editor: the tabs Game,
## Classes, Sets & rarities, Cards (StudioCards), Decks, Check & export; it saves a second after a change and
## on Save. "Try in a match" builds the pack, installs it and starts a local game against the bot (MatchView,
## as the game's start_match does); leaving it comes back to the editor.

## The projects' start screen and the editor's own interface languages are the game's (Settings).
const TITLE := "ClassicHS Studio"
## The editor's tabs: [node name, English title].
const TABS := [["Game", "Game"], ["Classes", "Classes"], ["Sets", "Sets & rarities"], ["Cards", "Cards"],
	["Decks", "Decks"], ["Check", "Check & export"]]
const CARDS_SCRIPT := "res://studio/studio_cards.gd"
## The content hash of the pack a test match installed, while the match lasts (in StudioProject.root).
const TRIAL_FILE := "trial_pack.txt"

var project: StudioProject
var screen: Control
var tabs: TabContainer
## The Cards tab (StudioCards; a placeholder until its file exists).
var cards_tab: Control
var check_tab: StudioCheck
var _title: Label
var _status: Label
var _save_timer: Timer
## The game active before a test match (it is again after), and the pack the match installed just for itself.
var _was: Pack
var _trial_pack: Pack
var _web_callback: JavaScriptObject  # kept alive while the browser's file picker is open


func _ready() -> void:
	name = "Studio"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if get_tree().current_scene == self:  # the build's main scene (tests add it themselves)
		Locale.load_all()
		Sprites.load_all()
		Settings.load_settings()
		Settings.apply()
		add_child(Sound.new())
		get_window().title = tr(TITLE)
	Packs.set_shell(true)  # the client's own look; a test match has its game's
	theme = Fonts.theme()
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 1.0
	_save_timer.timeout.connect(save)
	add_child(_save_timer)
	remove_left_trial()
	show_projects()


func _set_screen(s: Control) -> void:
	if screen:
		screen.get_parent().remove_child(screen)
		screen.queue_free()
	screen = s
	add_child(s)


# --- small pieces the tabs share -------------------------------------------------------------------

static func button(text: String, id: String, width := 160) -> Button:
	var b := Palette.button(text, id)
	b.custom_minimum_size = Vector2(width, 38)
	b.add_theme_font_size_override("font_size", 16)
	return b


static func field(text: String, id: String, changed: Callable, width := 260) -> LineEdit:
	var e := LineEdit.new()
	e.name = id
	e.text = text
	e.custom_minimum_size = Vector2(width, 34)
	e.text_changed.connect(changed)
	return e


static func number(value: int, lo: int, hi: int, id: String, changed: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.name = id
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.value_changed.connect(func(v): changed.call(int(v)))
	return s


static func toggle(text: String, on: bool, id: String, changed: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.name = id
	c.text = text
	c.button_pressed = on
	c.toggled.connect(changed)
	return c


static func color_button(hex: String, id: String, changed: Callable) -> ColorPickerButton:
	var c := ColorPickerButton.new()
	c.name = id
	c.color = Color(hex) if Color.html_is_valid(hex) else Color.GRAY
	c.edit_alpha = false
	c.custom_minimum_size = Vector2(60, 34)
	c.color_changed.connect(func(col: Color): changed.call(col.to_html(false)))
	return c


## A chooser of the pack's 8 languages (their own names); picked(lang).
static func languages(lang: String, picked: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.name = "Language"
	for code in StudioProject.LANGS:
		o.add_item(Locale.LANGS[code])
		o.set_item_metadata(o.item_count - 1, code)
	o.select(StudioProject.LANGS.find(lang))
	o.item_selected.connect(func(i): picked.call(o.get_item_metadata(i)))
	return o


static func heading(text: String) -> Label:
	return Palette.label(text, 22, Palette.ATTACK)


static func row(items: Array, sep := 10) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", sep)
	for it in items:
		r.add_child(Palette.label(it, 16) if it is String else it)
	return r


## A page of a tab: a scrolled column with a margin; the column.
static func page(tab: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	return v


static func clear(c: Node) -> void:
	for x in c.get_children():
		c.remove_child(x)
		x.queue_free()


## Removes a folder and everything in it.
static func remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + f)
	for d in DirAccess.get_directories_at(path):
		remove_dir(path + "/" + d)
	DirAccess.remove_absolute(path)


## Asks before doing something that can't be undone.
func confirm(text: String, yes: Callable) -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.name = "Confirm"
	d.dialog_text = text
	d.ok_button_text = tr("Delete")
	d.cancel_button_text = tr("Cancel")
	d.confirmed.connect(func():
		d.queue_free()
		yes.call())
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered()
	return d


## A file the person picks: the system's dialog, the browser's file picker on the web; done(bytes, file name).
func pick_file(exts: Array, done: Callable) -> void:
	if OS.has_feature("web"):
		_web_callback = JavaScriptBridge.create_callback(func(args: Array):
			done.call(Marshalls.base64_to_raw(str(args[1])), str(args[0])))
		JavaScriptBridge.get_interface("window").classichsStudioPicked = _web_callback
		JavaScriptBridge.eval("""(function () {
			var i = document.createElement('input');
			i.type = 'file'; i.accept = '%s'; i.style.display = 'none';
			document.body.appendChild(i);
			i.addEventListener('change', function () {
				var f = i.files[0];
				i.remove();
				if (!f) return;
				var r = new FileReader();
				r.onload = function () {
					var b = new Uint8Array(r.result), s = '';
					for (var k = 0; k < b.length; k += 32768) s += String.fromCharCode.apply(null, b.subarray(k, k + 32768));
					window.classichsStudioPicked(f.name, btoa(s));
				};
				r.readAsArrayBuffer(f);
			});
			i.click();
		})();""" % ",".join(exts.map(func(e): return "." + e)), true)
		return
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.filters = PackedStringArray([", ".join(exts.map(func(e): return "*." + e))])
	d.file_selected.connect(func(path: String):
		d.queue_free()
		done.call(FileAccess.get_file_as_bytes(path), path.get_file()))
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(900, 600))


## Saves bytes as a file: the system's save dialog, a download on the web; done(file name) after.
func save_file(bytes: PackedByteArray, file_name: String, done: Callable) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, file_name, "application/zip")
		done.call(file_name)
		return
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.current_file = file_name
	d.filters = PackedStringArray(["*.cardpack ; " + tr("Game packs")])
	d.file_selected.connect(func(path: String):
		d.queue_free()
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_buffer(bytes)
			f.close()
			done.call(path.get_file())
		else:
			done.call(""))
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(900, 600))


## An image from a file's bytes (png, jpg, webp); null when it isn't one.
static func image_of(bytes: PackedByteArray, file_name: String) -> Image:
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match file_name.get_extension().to_lower():
		"png": err = img.load_png_from_buffer(bytes)
		"jpg", "jpeg": err = img.load_jpg_from_buffer(bytes)
		"webp": err = img.load_webp_from_buffer(bytes)
	return img if err == OK and not img.is_empty() else null


# --- the projects ----------------------------------------------------------------------------------

func show_projects() -> Control:
	project = null
	_save_timer.stop()
	if get_tree().current_scene == self:
		get_window().title = tr(TITLE)
	var root := Control.new()
	root.name = "Projects"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := page(root)
	v.add_child(Palette.label(tr(TITLE), 34, Palette.ATTACK))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	v.add_child(cols)
	var left := VBoxContainer.new()
	left.name = "List"
	left.custom_minimum_size = Vector2(560, 0)
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	left.add_child(heading(tr("Your games")))
	var all := StudioProject.list()
	if all.is_empty():
		left.add_child(Palette.label(tr("No games yet: make a new one or copy a game pack."), 16, Palette.MUTED))
	for e in all:
		var name_l := Palette.label("%s  (%s)" % [e.name, e.id], 18)
		name_l.custom_minimum_size = Vector2(330, 0)
		name_l.clip_text = true
		var open_b := button(tr("Open"), "Open_" + e.id, 100)
		open_b.pressed.connect(func(): open_project(StudioProject.open(e.id)))
		var del_b := button(tr("Delete"), "Delete_" + e.id, 100)
		del_b.pressed.connect(func(): confirm(tr("Delete the game \"%s\" and all its files?") % e.name, func():
			remove_dir(e.dir)
			show_projects()))
		var r := row([name_l, open_b, del_b])
		r.name = "Project_" + e.id
		left.add_child(r)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	cols.add_child(right)
	# a new game
	right.add_child(heading(tr("New game")))
	var why := Palette.label("", 15, Palette.DANGER)
	why.name = "NewProblem"
	var nid := field("", "NewId", func(t): why.text = tr(StudioProject.id_problem(t)) if t != "" else "", 220)
	nid.placeholder_text = "my-game"
	var ntitle := field("", "NewName", func(_t): pass, 220)
	ntitle.placeholder_text = tr("Name in English")
	right.add_child(row([tr("Id"), nid]))
	right.add_child(row([tr("Name"), ntitle]))
	var make := button(tr("Create"), "Create")
	make.pressed.connect(func():
		var p := new_project(nid.text.strip_edges(), ntitle.text.strip_edges())
		if p == null:
			why.text = tr(StudioProject.id_problem(nid.text.strip_edges())))
	right.add_child(make)
	right.add_child(why)
	# a copy of a game pack
	right.add_child(heading(tr("Open a game pack as a copy")))
	var packs := OptionButton.new()
	packs.name = "Packs"
	for p: Pack in Packs.all():
		packs.add_item("%s %s" % [p.title(), p.version()])
	var cid := field("", "CopyId", func(_t): pass, 220)
	cid.placeholder_text = "my-copy"
	var cwhy := Palette.label("", 15, Palette.DANGER)
	cwhy.name = "CopyProblem"
	right.add_child(packs)
	right.add_child(row([tr("New id"), cid]))
	var copy := button(tr("Copy"), "Copy")
	copy.pressed.connect(func():
		if packs.selected >= 0:
			cwhy.text = copy_pack(Packs.all()[packs.selected], cid.text.strip_edges()))
	var file_b := button(tr("A .cardpack file…"), "CopyFile", 220)
	file_b.pressed.connect(func(): pick_file(["cardpack"], func(bytes: PackedByteArray, _n: String):
		cwhy.text = copy_file(bytes, cid.text.strip_edges())))
	right.add_child(row([copy, file_b]))
	right.add_child(cwhy)
	_set_screen(root)
	return root


## A new game from the start screen; opened. Null when the id can't be used.
func new_project(pid: String, title: String) -> StudioProject:
	var p := StudioProject.create(pid, title)
	if p:
		open_project(p)
	return p


## A copy of an installed pack as a new project, opened. "" or why not.
func copy_pack(p: Pack, pid: String) -> String:
	var why := StudioProject.id_problem(pid)
	if why != "":
		return tr(why)
	var sp := StudioProject.from_pack(p, pid)
	if sp == null:
		return tr("Cannot copy this game pack")
	open_project(sp)
	return ""


## The same for a .cardpack file's bytes.
func copy_file(bytes: PackedByteArray, pid: String) -> String:
	var why := StudioProject.id_problem(pid)
	if why != "":
		return tr(why)
	var tmp := "user://studio_import.cardpack"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var p := Pack.open(tmp, "studio")
	if p == null:
		return tr("This is not a game pack")
	why = copy_pack(p, pid)
	p.close()
	DirAccess.remove_absolute(tmp)
	return why


# --- the editor ------------------------------------------------------------------------------------

func open_project(p: StudioProject, tab := 0) -> Control:
	if p == null:
		return null
	project = p
	var root := VBoxContainer.new()
	root.name = "Editor"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	var back_b := button(tr("Back"), "Back", 120)
	back_b.pressed.connect(func():
		save()
		show_projects())
	_title = Palette.label("", 24, Palette.ATTACK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_status = Palette.label("", 16, Palette.MUTED)
	_status.name = "Status"
	var save_b := button(tr("Save"), "Save", 120)
	save_b.pressed.connect(save)
	var top := row([back_b, _title, _status, save_b], 14)
	var m := MarginContainer.new()
	for side in ["left", "right", "top"]:
		m.add_theme_constant_override("margin_" + side, 10)
	m.add_child(top)
	root.add_child(m)
	tabs = TabContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	var made := [StudioGame.new(), StudioClasses.new(), StudioSets.new(), _cards(), StudioDecks.new(), StudioCheck.new()]
	check_tab = made[5]
	for i in made.size():
		var t: Control = made[i]
		t.name = TABS[i][0]
		if "studio" in t:
			t.set("studio", self)
		if "project" in t:
			t.set("project", p)
		if t.has_signal("changed"):
			t.connect("changed", _changed)
		tabs.add_child(t)
		tabs.set_tab_title(i, tr(TABS[i][1]))
	tabs.current_tab = tab
	tabs.tab_changed.connect(func(i): _refresh(tabs.get_child(i)))
	_set_screen(root)
	_show_title()
	return root


## The Cards tab: StudioCards when its file is there.
func _cards() -> Control:
	if ResourceLoader.exists(CARDS_SCRIPT):
		var c: Control = load(CARDS_SCRIPT).new()
		if c.has_signal("try_card"):
			c.connect("try_card", try_card)
		cards_tab = c
		return c
	cards_tab = Control.new()
	return cards_tab


## A tab shown again: it shows the project as it is now (another tab may have changed it).
func _refresh(t: Node) -> void:
	if not t.is_node_ready():  # (the container tells its tab while the editor enters the tree)
		return
	if t.has_method("refresh"):
		t.refresh()
	elif t.has_method("refresh_list"):  # (the Cards tab)
		t.refresh_list()


func tab(id: String) -> Control:
	return tabs.get_node(id) if tabs else null


## The Cards tab at a card.
func edit_card(cid: String) -> void:
	tabs.current_tab = tabs.get_node("Cards").get_index()
	if cards_tab.has_method("select"):
		cards_tab.select(cid)


func _changed() -> void:
	_show_title()
	_status.text = ""
	_save_timer.start()


func _show_title() -> void:
	var t := str(project.manifest.get("name", {}).get("en", project.id))
	_title.text = t
	if get_tree() and get_tree().current_scene == self:
		get_window().title = "%s — %s" % [t, tr(TITLE)]


func save() -> void:
	_save_timer.stop()
	if project:
		project.save()
		if is_instance_valid(_status):
			_status.text = tr("Saved")


# --- a test match ----------------------------------------------------------------------------------

## Builds the pack, installs it and plays a local game against the bot with a card in hand (twice; "" = none:
## the whole game). Leaving it comes back here. The view, or null (why: on the Check tab and the status line).
func try_card(cid := "") -> MatchView:
	save()
	if not Rules.ready():
		_status.text = tr("The game cannot start: its rules engine is missing.") + " " + Rules.missing()
		return null
	var c := project.build(true, 0)
	if StudioProject.blocking(c) > 0 or c.rules_hash == "":
		tabs.current_tab = check_tab.get_index()
		check_tab.show_result(c)
		_status.text = tr("The game has errors: see Check & export")
		return null
	var before := Packs.all().duplicate()
	var r := Packs.install(c.pack_bytes(), "imported")
	if r.has("error"):
		_status.text = tr(str(r.error))
		return null
	var p: Pack = r.pack
	_trial_pack = null if before.has(p) else p
	if _trial_pack:  # (remembered: a page closed during the match leaves it; the next start removes it)
		DirAccess.make_dir_recursive_absolute(StudioProject.root)
		var f := FileAccess.open(StudioProject.root + "/" + TRIAL_FILE, FileAccess.WRITE)
		f.store_string(Packs.content_hash(_trial_pack))
		f.close()
	_was = Packs.active()
	Packs.enter(p)
	var m := Match.new()
	var why := m.setup({"scenario": scenario(cid)}, [false, true])
	if why != "":
		m.free()
		_after_match()
		open_project(project, tabs.current_tab if tabs else 0)
		_status.text = tr("Cannot start the game: %s") % why
		return null
	var v := MatchView.new()
	v.leave.connect(func():
		_after_match()
		open_project(project, 3 if cid != "" else 5)
		if cid != "":
			edit_card(cid))
	_set_screen(v)
	v.bind(m)
	return v


## Back from a test match: the game active before it is again, the pack made for it goes.
func _after_match() -> void:
	if _was:
		Packs.set_active(_was)
	_was = null
	if _trial_pack:
		Packs.remove(_trial_pack)
	_trial_pack = null
	DirAccess.remove_absolute(StudioProject.root + "/" + TRIAL_FILE)


## A test match's pack left in the game's library (the studio was closed during the match) goes.
static func remove_left_trial() -> void:
	var path := StudioProject.root + "/" + TRIAL_FILE
	if not FileAccess.file_exists(path):
		return
	var p := Packs.find(FileAccess.get_file_as_string(path).strip_edges())
	if p and not p.builtin():
		Packs.remove(p)
	DirAccess.remove_absolute(path)
	Packs.set_shell(true)


## The test match's scene: the person with 10 mana, the card in hand twice and the first class's hero (a hero
## card: that hero; a Hero Power: the hero that has it); the bot the second class's hero (or the same) with a
## few of the pack's minions; both decks the pack's collectible cards.
func scenario(cid: String) -> Dictionary:
	var heroes: Array = project.rules.classes.filter(func(c): return not c.get("neutral", false) and c.has("champion")) \
		.map(func(c): return str(c.champion))
	var mine: String = heroes[0] if not heroes.is_empty() else ""
	var foe: String = heroes[1] if heroes.size() > 1 else mine
	var c := project.card(cid)
	var hand := []
	match str(c.get("type", "")):
		"CHAMPION":
			mine = cid
		"POWER":
			for h: Dictionary in project.cards:
				if h.type == "CHAMPION" and h.get("power") == cid:
					mine = h.id
		"":
			pass
		_:
			hand = [cid, cid]
	var pool: Array = project.cards.filter(func(x): return x.get("collectible", false) and x.type in ["MINION", "SPELL", "WEAPON"])
	var deck := []
	while not pool.is_empty() and deck.size() < 10:
		deck.append_array(pool.map(func(x): return x.id))
	deck.resize(mini(deck.size(), 10))
	var board: Array = pool.filter(func(x): return x.type == "MINION").map(func(x): return x.id).slice(0, 3)
	return {"players": [
		{"hero": mine, "mana": 10, "max_mana": 10, "hand": hand, "deck": deck},
		{"hero": foe, "mana": 10, "max_mana": 10, "board": board, "deck": deck}]}
