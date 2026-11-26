class_name StudioGame
extends Control
## The Studio's Game tab: the pack's id, version, names and descriptions in the 8 languages, authors, licence;
## the rules' basics (rules.json limits, start, fatigue, the turn timer); the game's tile in the library
## (ui/tile, 750x300) and its menu background (ui/menu).

signal changed

## The pictures: kind -> [English title, size (the tile is cut to it; the menu fits into it)].
const PICTURES := {"tile": ["The game's tile in the library", Vector2i(750, 300)], "menu": ["The menu background", Vector2i(1920, 1080)],
	"board": ["The game board", Vector2i(1920, 1080)], "library": ["The collection's background", Vector2i(1920, 1080)]}
## The game's own music and event sounds: [folder, name, English title] (StudioProject.MUSIC, GAME_SOUNDS).
const AUDIO := [["music", "menu", "Menu music"], ["music", "battle_1", "Battle music 1"], ["music", "battle_2", "Battle music 2"],
	["music", "battle_3", "Battle music 3"], ["music", "mulligan", "Mulligan music"], ["music", "victory", "Victory music"],
	["music", "defeat", "Defeat music"], ["sounds", "play_card", "A card is played"], ["sounds", "attack", "An attack lands"],
	["sounds", "damage", "Damage"], ["sounds", "death", "A minion dies"], ["sounds", "hero_power", "Hero Power"],
	["sounds", "turn_start", "Your turn"], ["sounds", "heal", "Healing"], ["sounds", "spell", "A spell"],
	["sounds", "draw", "A card is drawn"], ["sounds", "summon", "A minion lands"], ["sounds", "victory", "Victory"],
	["sounds", "defeat", "Defeat"], ["sounds", "click", "A click"]]
## The rules' numbers: [English title, path in rules.json, min, max].
const NUMBERS := [["Hero health", "limits.champion_health", 1, 1000], ["Max mana", "limits.max_mana", 1, 100],
	["Hand size", "limits.hand", 1, 50], ["Board size", "limits.board", 1, 20], ["Deck size", "limits.deck_size", 1, 200],
	["Copies of a card", "limits.copies", 1, 99], ["Starting hand: first player", "start.hand.0", 0, 20],
	["Starting hand: second player", "start.hand.1", 0, 20], ["Turn timer, seconds", "timers.turn", 10, 600]]

var project: StudioProject
var studio: Studio
var lang := "en"


func _ready() -> void:
	refresh()


static func _value(d: Variant, path: String) -> Variant:
	for k in path.split("."):
		d = d[int(k)] if d is Array else (d.get(k) if d is Dictionary else null)
	return d


static func _put(d: Variant, path: String, v: Variant) -> void:
	var parts := path.split(".")
	for k in parts.slice(0, -1):
		d = d[int(k)] if d is Array else d.get_or_add(k, {})
	if d is Array:
		d[int(parts[-1])] = v
	else:
		d[parts[-1]] = v


func refresh() -> void:
	Studio.clear(self)
	var v := Studio.page(self)
	var m := project.manifest
	v.add_child(Studio.heading(tr("The game")))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	v.add_child(g)
	_line(g, tr("Id"), Palette.label(project.id, 18))
	_line(g, tr("Version"), Studio.field(str(m.get("version", "")), "Version", func(t):
		m.version = t.strip_edges()
		changed.emit()))
	_line(g, tr("Language"), Studio.languages(lang, func(l):
		lang = l
		refresh()))
	_line(g, tr("Name"), Studio.field(str(m.get("name", {}).get(lang, "")), "Name", func(t): _text("name", t), 420))
	var d := TextEdit.new()
	d.name = "Description"
	d.text = str(m.get("description", {}).get(lang, ""))
	d.custom_minimum_size = Vector2(620, 90)
	d.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	d.text_changed.connect(func(): _text("description", d.text))
	_line(g, tr("Description"), d)
	_line(g, tr("Authors"), Studio.field(", ".join(m.get("authors", [])), "Authors", func(t):
		m.authors = Array(t.split(",")).map(func(a): return a.strip_edges()).filter(func(a): return a != "")
		changed.emit(), 420))
	_line(g, tr("License"), Studio.field(str(m.get("license", "")), "License", func(t):
		m.license = t.strip_edges()
		changed.emit(), 420))
	_line(g, "", Studio.toggle(tr("Others may share the game"), bool(m.get("redistributable", true)), "Redistributable", func(on):
		m.redistributable = on
		changed.emit()))
	v.add_child(Studio.heading(tr("Rules")))
	var r := GridContainer.new()
	r.name = "Rules"
	r.columns = 4
	r.add_theme_constant_override("h_separation", 14)
	v.add_child(r)
	for n in NUMBERS:
		var path: String = n[1]
		var have = _value(project.rules, path)
		_line(r, tr(n[0]), Studio.number(int(have) if have != null else n[2], n[2], n[3], path.replace(".", "_"), func(x):
			_put(project.rules, path, x)
			changed.emit()))
	var legend := _legendary()
	if legend != "":
		var cbr: Dictionary = project.rules.limits.get_or_add("copies_by_rarity", {})
		_line(r, tr("Copies of a legendary"), Studio.number(int(cbr.get(legend, project.rules.limits.get("copies", 2))), 1, 99, "Legendary", func(x):
			cbr[legend] = x
			changed.emit()))
	_line(r, "", Studio.toggle(tr("Mulligan"), bool(project.rules.get("start", {}).get("mulligan", true)), "Mulligan", func(on):
		project.rules.get_or_add("start", {}).mulligan = on
		changed.emit()))
	_line(r, "", Studio.toggle(tr("Fatigue"), bool(project.rules.get("fatigue", {}).get("enabled", true)), "Fatigue", func(on):
		project.rules.get_or_add("fatigue", {"first": 1, "step": 1}).enabled = on
		changed.emit()))
	v.add_child(Studio.heading(tr("Pictures")))
	for kind in PICTURES:
		v.add_child(_picture_row(kind))
	v.add_child(Studio.heading(tr("Music and sounds")))
	v.add_child(Palette.label(tr("Without its own, the game plays the client's music and sounds."), 14, Palette.MUTED))
	for a in AUDIO:
		v.add_child(_audio_row(a[0], a[1], a[2]))


func _line(g: GridContainer, title: String, c: Control) -> void:
	g.add_child(Palette.label(title, 16))
	g.add_child(c)


## A name or description in the chosen language (empty: none there; English stays).
func _text(key: String, t: String) -> void:
	var d: Dictionary = project.manifest.get_or_add(key, {})
	if t.strip_edges() == "" and lang != "en":
		d.erase(lang)
	else:
		d[lang] = t
	changed.emit()


## The rarity whose copies are "a legendary's": LEGENDARY, else the first of the legendary tier.
func _legendary() -> String:
	var all: Array = project.rules.get("rarities", []).filter(func(x): return x.get("tier") == "legendary").map(func(x): return str(x.id))
	return "LEGENDARY" if all.has("LEGENDARY") else (all[0] if not all.is_empty() else "")


func _picture_row(kind: String) -> Control:
	var tex := TextureRect.new()
	tex.name = "Picture_" + kind
	tex.custom_minimum_size = Vector2(250, 100) if kind == "tile" else Vector2(178, 100)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var path := picture_path(kind)
	if path != "":
		var img := Image.load_from_file(path)
		if img:
			tex.texture = ImageTexture.create_from_image(img)
	var why := Palette.label("", 15, Palette.DANGER)
	var pick := Studio.button(tr("Choose a picture"), "Choose_" + kind, 200)
	pick.pressed.connect(func(): studio.pick_file(StudioProject.IMAGE_EXT, func(bytes: PackedByteArray, f: String):
		why.text = tr(set_picture(kind, Studio.image_of(bytes, f)))
		if why.text == "":
			refresh()))
	var rm := Studio.button(tr("Remove"), "Remove_" + kind, 120)
	rm.disabled = path == ""
	rm.pressed.connect(func():
		remove_picture(kind)
		refresh())
	var col := VBoxContainer.new()
	col.add_child(Palette.label(tr(PICTURES[kind][0]), 16))
	col.add_child(Studio.row([pick, rm]))
	col.add_child(why)
	return Studio.row([tex, col], 16)


func _audio_row(folder: String, file: String, title: String) -> Control:
	var l := Palette.label(tr(title), 16)
	l.custom_minimum_size.x = 220
	var path := project.audio_path(folder, file)
	var f := Palette.label(path.get_file() if path != "" else tr("none"), 15, Palette.TEXT if path != "" else Palette.MUTED)
	f.custom_minimum_size.x = 200
	var why := Palette.label("", 15, Palette.DANGER)
	var pick := Studio.button(tr("Load"), "Load_%s_%s" % [folder, file], 120)
	pick.pressed.connect(func(): studio.pick_file(StudioProject.AUDIO_EXT, func(bytes: PackedByteArray, name: String):
		why.text = tr(set_audio(folder, file, bytes, name.get_extension()))
		if why.text == "":
			refresh()))
	var rm := Studio.button(tr("Remove"), "Remove_%s_%s" % [folder, file], 120)
	rm.disabled = path == ""
	rm.pressed.connect(func():
		project.remove_audio(folder, file)
		changed.emit()
		refresh())
	return Studio.row([l, f, pick, rm, why])


## The game's music or an event sound from a file. "" or why not.
func set_audio(folder: String, file: String, bytes: PackedByteArray, ext: String) -> String:
	var why := project.set_audio(folder, file, bytes, ext)
	if why == "":
		changed.emit()
	return why


## The file of a picture of the game (ui/tile, ui/menu); "" when there is none.
func picture_path(kind: String) -> String:
	for ext in StudioProject.IMAGE_EXT:
		var f := "%s/ui/%s.%s" % [project.pack_dir(), kind, ext]
		if FileAccess.file_exists(f):
			return f
	return ""


## Puts a picture into pack/ui/: the tile cut to 750x300 (the middle of it), the menu made at most 1920x1080;
## PNG, WebP when that is too big. "" or why not.
func set_picture(kind: String, img: Image) -> String:
	if img == null or img.is_empty():
		return "Not a picture"
	img = img.duplicate()
	var want: Vector2i = PICTURES[kind][1]
	if kind == "tile":
		var k := maxf(float(want.x) / img.get_width(), float(want.y) / img.get_height())
		img.resize(maxi(want.x, roundi(img.get_width() * k)), maxi(want.y, roundi(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		img = img.get_region(Rect2i((img.get_size() - want) / 2, want))
	elif img.get_width() > want.x or img.get_height() > want.y:
		var k := minf(float(want.x) / img.get_width(), float(want.y) / img.get_height())
		img.resize(roundi(img.get_width() * k), roundi(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	remove_picture(kind)
	DirAccess.make_dir_recursive_absolute(project.pack_dir() + "/ui")
	var bytes := img.save_png_to_buffer()
	var ext := "png"
	if bytes.size() > PackCheck.LIMITS.image:
		bytes = img.save_webp_to_buffer(true, 0.85)
		ext = "webp"
	var f := FileAccess.open("%s/ui/%s.%s" % [project.pack_dir(), kind, ext], FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	changed.emit()
	return ""


func remove_picture(kind: String) -> void:
	while picture_path(kind) != "":
		DirAccess.remove_absolute(picture_path(kind))
	changed.emit()
