extends SceneTree
## The UI audit (expansions plan, step 13): screenshots of every client screen in each language and window
## size, and for each shot an automatic layout check (text wider than its box or cut, a control off the window
## or cut by its box, text over other text, a Latin-only string in Russian). The screens are in groups:
## res://tools/ui_audit/<group>.gd (extends RefCounted, `func run(a) -> void`, calls `await a.shot(name)`).
## Needs a window. Every user file goes to its own user dir (AUDIT_USER_DIR, as tests/run.gd's TEST_USER_DIR).
## Usage: AUDIT_USER_DIR=classichs-audit/<group> godot --path . --script res://tools/ui_audit.gd -- <job.json>
## Job: {group, out, langs: ["ru", "en"], sizes: [[1280, 720], [844, 390], ...], packs: [cardpack paths],
## main_pack?: pack id (default the last pack), only?: [shot names]}. A shot: <out>/<W>x<H>_<lang>_<name>.jpg,
## its check a line of <out>/checks.jsonl: {shot, lang, size, name, note, issues: [{kind, path, text, box}]}
## (box: [x, y, w, h] in the shot's pixels).

const MOUSE_AWAY := Vector2(640, 330)
var job: Dictionary
var m: Node  ## the client (ui/main.tscn) of now
var lang := "en"
var size := Vector2i(1280, 720)
var packs := {}  ## pack id -> Pack (installed by the job)
var main_pack: Pack
var failed := 0
var shots := 0
var group: Object
var _checks: FileAccess


func _init() -> void:
	var own := OS.get_environment("AUDIT_USER_DIR")
	if own != "":
		ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
		ProjectSettings.set_setting("application/config/custom_user_dir_name", own)
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())


func _initialize() -> void:
	if OS.get_environment("AUDIT_USER_DIR") == "":
		print("ERROR: set AUDIT_USER_DIR (the run's own user dir)")
		quit(2)
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
	job = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	_run()


func _run() -> void:
	for f in job.get("packs", []):
		var r := Packs.install_file(str(f))
		if not r.has("pack"):
			print("ERROR: the pack %s does not install: %s" % [f, r])
			failed += 1
			continue
		packs[r.pack.id()] = r.pack
		main_pack = r.pack
	if job.has("main_pack"):
		main_pack = packs.get(str(job.main_pack), main_pack)
	DirAccess.make_dir_recursive_absolute(str(job.out))
	_checks = FileAccess.open(str(job.out) + "/checks.jsonl", FileAccess.READ_WRITE if FileAccess.file_exists(str(job.out) + "/checks.jsonl") else FileAccess.WRITE)
	_checks.seek_end()
	var script: GDScript = load("res://tools/ui_audit/%s.gd" % job.group)
	if script == null or not script.can_instantiate():  # (a parse error: quit, not hang)
		print("ERROR: the group %s does not load" % job.group)
		quit(2)
		return
	group = script.new()
	for s in job.get("sizes", [[1280, 720]]):
		await set_size(Vector2i(int(s[0]), int(s[1])))
		for l in job.get("langs", ["ru", "en"]):
			lang = str(l)
			await group.run(self)
	if m:
		m.free()
	_checks.close()
	print("AUDIT DONE: %d shots, %d failed" % [shots, failed])
	quit(1 if failed else 0)


## The window at this size (pixels).
func set_size(s: Vector2i) -> void:
	size = s
	root.content_scale_factor = 1.0
	DisplayServer.window_set_size(s)
	root.size = s
	for i in 5:
		await process_frame


func want(name: String) -> bool:
	return not job.has("only") or job.only.has(name)


## A fresh client in the audit's language: its main menu (the pack: the job's main pack, or none set).
func open(pack: Pack = null, settings := {}) -> Node:
	if m:
		m.free()
		m = null
	Settings.load_settings()
	Settings.first_run = false
	Settings.data.language = lang
	Settings.data.tracker = false
	Settings.data.music = 0.0
	Settings.data.sfx = 0.0
	Settings.data.merge(settings, true)
	Settings.save()
	Packs.set_active(pack if pack else main_pack)
	m = load("res://ui/main.tscn").instantiate()
	root.add_child(m)
	await settle(1.0)
	return m


## A fresh client in the pack's game menu, with the pack's ready decks as the player's decks.
func open_game(pack: Pack = null, settings := {}) -> Node:
	await open(pack, settings)
	m.show_library()
	m.enter_game(pack if pack else main_pack)
	DeckStore.write(DeckStore.file(), Decks.templates().map(func(t): return t.deck.to_dict().merged({"name": t.name}, true)))
	await settle(0.8)
	return m


## Lets animations end (a match's too), then a short pause.
func settle(pause := 0.7) -> void:
	await create_timer(0.2).timeout
	var t0 := Time.get_ticks_msec()
	while m and is_instance_valid(m) and m.screen is MatchView and (m.screen as MatchView)._busy and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	await create_timer(pause).timeout


func wait(t: float) -> void:
	await create_timer(t).timeout


## A shot of the window now and its layout check; note: what the shot shows (for the report).
func shot(name: String, note := "") -> void:
	if not want(name):
		return
	await process_frame
	var base := "%dx%d_%s_%s" % [size.x, size.y, lang, name]
	var file := "%s/%s.jpg" % [job.out, base]
	var img := root.get_texture().get_image()
	var at := Vector2i.ZERO  # the game's picture in the window (stretch "keep": black bars around it)
	if img.get_size() != size:
		var full := Image.create(size.x, size.y, false, img.get_format())
		full.fill(Color.BLACK)
		at = (size - img.get_size()) / 2
		full.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), at)
		img = full
	_at = Vector2(at)
	img.save_jpg(file, 0.9)
	shots += 1
	var issues := check_layout()
	_checks.store_line(JSON.stringify({"shot": base + ".jpg", "lang": lang, "size": "%dx%d" % [size.x, size.y],
		"name": name, "note": note, "w": img.get_width(), "h": img.get_height(), "issues": issues}))
	_checks.flush()
	print("saved %s (%d checks)" % [base, issues.size()])


func error(text: String) -> void:
	print("ERROR: ", text)
	failed += 1


# --- the automatic layout check ------------------------------------------------------------------

var _xf: Transform2D  # canvas -> shot pixels
var _view: Rect2  # the visible canvas
var _at := Vector2.ZERO  # where the game's picture is in the shot


func check_layout() -> Array:
	_xf = root.get_final_transform()
	_view = root.get_visible_rect()
	var items: Array = []  # [Control, rect, order key]
	_collect(root, items, 0)
	var out: Array = []
	var texts: Array = []
	for i in items.size():
		var c: Control = items[i][0]
		var r: Rect2 = items[i][1]
		if _covered(items, i) or _scrolled_away(c, r):
			continue
		var t := _text(c)
		if t != "":
			texts.append([c, _ink(c, r), t])
			_check_text(c, r, t, out)
			if lang == "ru" and _latin_only(t):
				out.append(_issue("latin", c, r, t))
		if (c is BaseButton or c is LineEdit or c is Range) and not _view.grow(1).encloses(r) and not _scrolled(c):
			out.append(_issue("off_window", c, r, t))
		var clip := _clipper(c)
		if clip and not (clip is ScrollContainer) and not clip.get_global_rect().grow(1).encloses(r) and (t != "" or c is BaseButton):
			out.append(_issue("clipped", c, r, t))
		var box := _box(c)
		if box and t != "" and not _rect(box).grow(2).encloses(_ink(c, r)):
			out.append(_issue("out_of_box", c, _ink(c, r), t))
	for a in texts.size():  # text over text (not one inside the other)
		for b in range(a + 1, texts.size()):
			var ca: Control = texts[a][0]
			var cb: Control = texts[b][0]
			if ca.is_ancestor_of(cb) or cb.is_ancestor_of(ca):
				continue
			var x: Rect2 = texts[a][1].intersection(texts[b][1])
			if x.get_area() > 40.0 and x.size.y > 4.0:
				var o := _issue("overlap", ca, texts[a][1].merge(texts[b][1]), texts[a][2] + "  |  " + texts[b][2])
				o.path2 = str(cb.get_path())
				out.append(o)
	return out


## Every visible control in drawing order (CanvasLayers by layer), with its rect on the canvas.
func _collect(n: Node, items: Array, layer: int) -> void:
	if n is CanvasLayer:
		if not n.visible:
			return
		layer = n.layer
	if n is CanvasItem and not n.visible:
		return
	if n is Window and n != root and not n.visible:
		return
	if n is Control and _alpha(n) > 0.15:
		var c: Control = n
		items.append([c, _rect(c), layer])
	for k in n.get_children():
		_collect(k, items, layer)
	if n == root:  # the drawing order: by layer, then the tree's (stable)
		var idx := {}
		for i in items.size():
			idx[items[i][0]] = i
		items.sort_custom(func(p, q): return p[2] < q[2] or (p[2] == q[2] and idx[p[0]] < idx[q[0]]))


func _rect(c: Control) -> Rect2:
	return c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c.size)


func _alpha(c: CanvasItem) -> float:
	var a := 1.0
	var n: Node = c
	while n is CanvasItem:
		a *= (n as CanvasItem).modulate.a
		n = n.get_parent()
	return a * c.self_modulate.a


## Hidden under an opaque panel drawn after it (a dialog over a screen).
func _covered(items: Array, i: int) -> bool:
	var r: Rect2 = items[i][1]
	var c: Control = items[i][0]
	for j in range(i + 1, items.size()):
		var o: Control = items[j][0]
		if o.is_ancestor_of(c) or not _opaque(o):
			continue
		if (items[j][1] as Rect2).grow(1).encloses(r):
			return true
	return false


func _opaque(o: Control) -> bool:
	if o is ColorRect:
		return (o as ColorRect).color.a * _alpha(o) >= 0.6
	if o is Panel or o is PanelContainer:
		var sb := o.get_theme_stylebox("panel")
		return sb is StyleBoxFlat and (sb as StyleBoxFlat).bg_color.a * _alpha(o) >= 0.6 and (sb as StyleBoxFlat).draw_center
	return false


func _text(c: Control) -> String:
	if c is Label:
		return (c as Label).text.strip_edges()
	if c is Button:
		return (c as Button).text.strip_edges()
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text().strip_edges()
	if c is LineEdit:
		var e := c as LineEdit
		return (e.text if e.text != "" else e.placeholder_text).strip_edges()
	return ""


## Where the text itself is drawn (a label's line, aligned in its box), on the canvas.
func _ink(c: Control, r: Rect2) -> Rect2:
	if not (c is Label) or (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
		return r
	var l := c as Label
	var w := _width(l, l.text) * r.size.x / maxf(1.0, l.size.x)  # (the rect may be scaled)
	if w >= r.size.x:
		match l.horizontal_alignment:
			HORIZONTAL_ALIGNMENT_CENTER:
				return Rect2(r.position.x - (w - r.size.x) / 2.0, r.position.y, w, r.size.y)
			HORIZONTAL_ALIGNMENT_RIGHT:
				return Rect2(r.end.x - w, r.position.y, w, r.size.y)
			_:
				return Rect2(r.position.x, r.position.y, w, r.size.y)
	match l.horizontal_alignment:
		HORIZONTAL_ALIGNMENT_CENTER:
			return Rect2(r.position.x + (r.size.x - w) / 2.0, r.position.y, w, r.size.y)
		HORIZONTAL_ALIGNMENT_RIGHT:
			return Rect2(r.end.x - w, r.position.y, w, r.size.y)
	return Rect2(r.position.x, r.position.y, w, r.size.y)


func _width(c: Control, text: String) -> float:
	var font := c.get_theme_font("font")
	var fs := c.get_theme_font_size("font_size")
	var w := 0.0
	for line in text.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return w


func _check_text(c: Control, r: Rect2, t: String, out: Array) -> void:
	if c is Label:
		var l := c as Label
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
			var sb := l.get_theme_stylebox("normal")
			var need := _width(l, l.text) + (sb.get_minimum_size().x if sb else 0.0)
			if need > l.size.x + 2.0:
				var trimmed := l.clip_text or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING
				out.append(_issue("cut" if trimmed else "overflow", c, r, t, "needs %d px, has %d" % [need, l.size.x]))
		elif l.get_line_count() > l.get_visible_line_count() and l.visible_characters < 0:
			out.append(_issue("cut", c, r, t, "%d of %d lines shown" % [l.get_visible_line_count(), l.get_line_count()]))
	elif c is Button:
		var b := c as Button
		var sb := b.get_theme_stylebox("normal")
		var need := _width(b, b.text) + (sb.get_minimum_size().x if sb else 0.0)
		if b.icon:
			need += b.icon.get_width() + b.get_theme_constant("h_separation")
		if c is OptionButton or c is MenuButton:
			need += 16.0
		if need > b.size.x + 2.0 and (b.clip_text or b.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING or b.autowrap_mode == TextServer.AUTOWRAP_OFF):
			out.append(_issue("cut" if b.clip_text or b.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING else "overflow", c, r, t,
				"needs %d px, has %d" % [need, b.size.x]))
	elif c is RichTextLabel:
		var rt := c as RichTextLabel
		if not rt.scroll_active and not rt.fit_content and rt.get_content_height() > rt.size.y + 2:
			out.append(_issue("cut", c, r, t, "content %d px high, box %d" % [rt.get_content_height(), rt.size.y]))


## The nearest ancestor that clips its children.
func _clipper(c: Control) -> Control:
	var n := c.get_parent()
	while n is Control:
		if (n as Control).clip_contents:
			return n
		n = n.get_parent()
	return null


## Inside a scrolling list (off the window there is fine: it scrolls into view).
func _scrolled(c: Control) -> bool:
	var n := c.get_parent()
	while n is Control:
		if n is ScrollContainer:
			return true
		n = n.get_parent()
	return false


## Not wholly in its scrolling list's view (scrolled out, or half under its edge: not drawn there).
func _scrolled_away(c: Control, r: Rect2) -> bool:
	var n := c.get_parent()
	while n is Control:
		if n is ScrollContainer:
			return not _rect(n).grow(1).encloses(r)
		n = n.get_parent()
	return false


## The nearest panel the control is drawn in (its visible box).
func _box(c: Control) -> Control:
	var n := c.get_parent()
	while n is Control:
		if (n is PanelContainer or n is Panel) and _opaque(n):
			return n
		n = n.get_parent()
	return null


func _latin_only(t: String) -> bool:
	var re := RegEx.create_from_string("[A-Za-z]{3,}")
	var cyr := RegEx.create_from_string("[А-Яа-яЁё]")
	return re.search(t) != null and cyr.search(t) == null


func _issue(kind: String, c: Control, r: Rect2, t: String, why := "") -> Dictionary:
	var p := _xf * r
	p.position += _at - _xf.origin  # (the final transform's origin is the bars' offset in the window)
	return {"kind": kind, "path": str(c.get_path()).replace("/root/", ""), "class": c.get_class(), "text": t.left(160),
		"why": why, "box": [roundi(p.position.x), roundi(p.position.y), roundi(p.size.x), roundi(p.size.y)]}
