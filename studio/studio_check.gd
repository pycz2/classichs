class_name StudioCheck
extends Control
## The Studio's Check & export tab: Check builds the pack, checks it, loads it into the rules engine and plays
## two bot games (StudioProject.build) and lists the findings as the pack tools do (errors red, warnings
## yellow, OK green, each with its file and line). Then: Export .cardpack, Install into the game, Upload to a
## server the game is logged in to, Try in a match.

signal changed

var project: StudioProject
var studio: Studio
## The last check (null before one).
var result: PackCheck
var _list: VBoxContainer
var _summary: Label
var _message: Label
var _servers: OptionButton
var _buttons := {}
## The server connection of an upload (a child while it runs).
var _link: ServerLink


func _ready() -> void:
	refresh()


func refresh() -> void:
	Studio.clear(self)
	var v := Studio.page(self)
	var check_b := Studio.button(tr("Check"), "Check", 160)
	check_b.pressed.connect(func(): run_later())
	var try_b := Studio.button(tr("Try in a match"), "TryGame", 200)
	try_b.pressed.connect(func(): studio.try_card(""))
	_summary = Palette.label("", 19)
	_summary.name = "Summary"
	v.add_child(Studio.row([check_b, try_b, _summary], 16))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	for b in [["Export .cardpack", "Export", export], ["Install into the game", "Install", install]]:
		_buttons[b[1]] = Studio.button(tr(b[0]), b[1], 230)
		_buttons[b[1]].pressed.connect(b[2])
		row.add_child(_buttons[b[1]])
	_servers = OptionButton.new()
	_servers.name = "Servers"
	for e in Settings.data.servers:
		_servers.add_item(str(e.get("name", e.url)) if str(e.get("name", "")) != "" else str(e.url))
	row.add_child(_servers)
	_buttons.Upload = Studio.button(tr("Upload to the server"), "Upload", 230)
	_buttons.Upload.pressed.connect(func(): upload(_servers.selected))
	row.add_child(_buttons.Upload)
	_message = Palette.label("", 16)
	_message.name = "Message"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_message)
	_list = VBoxContainer.new()
	_list.name = "Items"
	_list.add_theme_constant_override("separation", 6)
	v.add_child(_list)
	_show()


## Check, once "Checking…" is on the screen (bot games take a few seconds).
func run_later() -> void:
	_summary.text = tr("Checking…")
	_summary.add_theme_color_override("font_color", Palette.TEXT)
	for i in 2:
		await get_tree().process_frame
	run()


func run() -> PackCheck:
	show_result(project.build(true, 2))
	return result


func show_result(c: PackCheck) -> void:
	result = c
	if _list:
		_message.text = ""
		_show()


func _good() -> bool:
	return result != null and result.errors() == 0


func _show() -> void:
	Studio.clear(_list)
	for id in ["Export", "Install", "Upload"]:
		_buttons[id].disabled = not _good()
	_buttons.Upload.disabled = _buttons.Upload.disabled or _servers.item_count == 0
	if result == null:
		_summary.text = ""
		var hint := Palette.label(tr("Check builds the game pack, checks it, loads it into the rules engine and plays two games of bots with its decks."), 16, Palette.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(hint)
		return
	var e := result.errors()
	var w := result.count(PackCheck.WARNING)
	_summary.text = tr("%d errors, %d warnings") % [e, w]
	_summary.add_theme_color_override("font_color", PackTools.COLORS[PackCheck.ERROR if e else (PackCheck.WARNING if w else PackCheck.PASS)])
	var order := {PackCheck.ERROR: 0, PackCheck.WARNING: 1, PackCheck.PASS: 2}
	var sorted := result.items.duplicate()
	sorted.sort_custom(func(a, b): return order[a.level] < order[b.level])
	for i in sorted.size():
		var it: Dictionary = sorted[i]
		var c: Color = PackTools.COLORS[it.level]
		var tag := Palette.label(tr(PackTools.LEVELS[it.level]), 16, c)
		tag.custom_minimum_size = Vector2(110, 0)
		var at := Palette.label(it.file + (":%d" % it.line if it.line > 0 else ""), 16, Palette.MUTED)
		at.custom_minimum_size = Vector2(230, 0)
		var text := Palette.label(PackCheck.said(it), 16, c.lerp(Palette.TEXT, 0.45))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var r := Studio.row([tag, at, text], 12)
		r.name = "Item%d" % i
		_list.add_child(r)


func _say(text: String, good := true) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", PackTools.COLORS[PackCheck.PASS] if good else PackTools.COLORS[PackCheck.ERROR])


## Saves the .cardpack: the system's save dialog, a download on the web.
func export() -> void:
	if _good():
		studio.save_file(result.pack_bytes(), result.file_name(), func(f: String):
			_say(tr("Saved: %s") % f if f != "" else tr("Cannot write the game pack"), f != ""))


## Adds the pack to the game's library; the pack, or null (the reason is shown).
func install() -> Pack:
	if not _good():
		return null
	var r := Packs.install(result.pack_bytes(), "imported")
	if r.has("error"):
		_say(tr(str(r.error)) + (": " + str(r.detail) if r.has("detail") else ""), false)
		return null
	_say(tr("It is in the game's library: %s") % r.pack.title())
	return r.pack


## Uploads the pack to a server of the game's list (Settings servers) the game is logged in to: installs it,
## then sends it as the game's server home does (ServerLink.upload_pack). The link, or null.
func upload(i: int) -> ServerLink:
	if not _good() or i < 0 or i >= Settings.data.servers.size():
		return null
	var e: Dictionary = Settings.data.servers[i]
	var sid := str(e.get("id", e.url))
	var token := str(ServerLink.saved_for(sid).get("token", ServerLink.saved_for(str(e.url)).get("token", "")))
	if token == "":
		_say(tr("Log in to a server in the game first"), false)
		return null
	var p := install()
	if p == null:
		return null
	if _link:
		_link.queue_free()
	_link = ServerLink.new()
	_link.url = str(e.url)
	_link.id = sid
	_link.token = token
	studio.add_child(_link)  # (the tab rebuilds itself; the upload goes on)
	_link.pack_uploaded.connect(func(res: Dictionary):
		if res.has("error"):
			_say(str(res.error), false)
		else:
			_say(tr("Uploaded to %s") % _link.url))
	_say(tr("Uploading…"))
	_link.upload_pack(p)
	return _link
