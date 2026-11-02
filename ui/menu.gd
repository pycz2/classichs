class_name MainMenu
extends Control
## The client's main menu (pack null; no game styles it, Packs.shell): Play (a submenu:
## Direct, without a server, or Server, through one), Settings, Exit (not on the web).
## A game's menu (pack set: main made it the active pack, so the screen has its look, menu
## music, pictures and logo): Collection, Training, Code play (Direct) or Play (Server: the
## server's ranked, casual and Arena games), Tutorial (when the pack has one), Settings (with
## the debug tools of this game), Leave the game.

signal direct
signal server
signal settings
signal quit
signal collection
signal training
signal code_play
signal play
signal tutorial
signal leave

## Button labels (English keys); the translation tool reads this list.
const ITEMS := ["Play", "Direct", "Server", "Back", "Settings", "Exit", "Collection", "Training", "Code play",
	"Tutorial", "Leave the game", "Without a server: the games on this device, training, code play",
	"Through a server: an account, ranked games, the Arena, friends"]

## The game whose menu this is (null: the client's main menu).
var pack: Pack
## The game is played through a server (Play opens its lobby).
var through_server := false
var _box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sound.music("menu")
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var pic := TextureRect.new()  # the game's picture (Classic's quiet tavern) slowly drifting closer
	pic.texture = Packs.picture("menu") if Packs.picture("menu") else Palette.shell_picture()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.modulate = Color(0.78, 0.74, 0.7) if Packs.picture("menu") else Color.WHITE
	add_child(pic)
	var shade := ColorRect.new()
	shade.color = Palette.tc("menu.shade")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var fx := SceneFx.make(str(Palette.UI.menu.particles))
	if fx:
		add_child(fx)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var title := TitleLogo.new()
	title.name = "Title"
	if pack:
		title.text = pack.title()
	box.add_child(title)
	if not Anim.instant:
		pic.pivot_offset = Vector2(640, 360)
		var drift := pic.create_tween().set_loops()
		drift.tween_property(pic, "scale", Vector2(1.07, 1.07), 24.0).set_trans(Tween.TRANS_SINE)
		drift.tween_property(pic, "scale", Vector2.ONE, 24.0).set_trans(Tween.TRANS_SINE)
	_box = box
	show_main()
	var version := Button.new()
	version.name = "Version"
	version.text = "v" + str(ProjectSettings.get_setting("application/config/version"))
	version.flat = true
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.pressed.connect(func(): add_child(ChangelogView.new()))
	add_child(version)


## The first level: the client's Play, Settings, Exit; a game's items.
func show_main() -> void:
	if pack:
		_show_game()
		return
	var items := [["Play", show_play, true], ["Settings", settings, true]]
	if not OS.has_feature("web"):
		items.append(["Exit", quit, true])
	_fill(items)


## The client's Play: without a server or through one, and Back.
func show_play() -> void:
	_fill([["Direct", direct, true], ["Server", server, true], ["Back", show_main, true]])
	for spec in [["Direct", "Without a server: the games on this device, training, code play"],
			["Server", "Through a server: an account, ranked games, the Arena, friends"]]:
		var b := _box.find_child(spec[0], false, false) as Button
		b.tooltip_text = tr(spec[1])
		var l := Palette.label(tr(spec[1]), 15, Palette.MUTED)
		l.name = spec[0] + "Note"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(l)
		_box.move_child(l, b.get_index() + 1)


## A game's menu: what can be done in it (a pack this rules engine can't play: its games can't start).
func _show_game() -> void:
	var why := Rules.can_play(pack)
	var ok := why == ""
	var items := [["Play", play, ok]] if through_server else []
	items += [["Collection", collection, true], ["Training", training, ok]]
	if not through_server:  # WebRTC: the browser, or the webrtc-native plugin
		items.append(["Code play", code_play, ok and WebRtcTransport.available()])
	if pack.has_tutorial():
		items.append(["Tutorial", tutorial, ok])
	_fill(items + [["Settings", settings, true], ["Leave the game", leave, true]])
	var codes := _box.find_child("CodePlay", false, false) as Button
	if codes and ok and codes.disabled:
		codes.tooltip_text = tr("Direct play works only in the browser version of the game")
	if not ok:
		var note := Palette.label(tr(why), 18, Color("ffb070"))
		note.name = "CannotPlay"
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_box.add_child(note)


func _fill(items: Array) -> void:
	for c in _box.get_children():
		if c.name != "Title":
			_box.remove_child(c)
			c.queue_free()
	for it in items:
		var b := Palette.button(tr(it[0]), it[0].capitalize().replace(" ", ""))
		b.disabled = not it[2]
		if it[1] is Signal:
			var sig: Signal = it[1]
			b.pressed.connect(func(): sig.emit())
		else:
			b.pressed.connect(it[1])
		_box.add_child(b)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size = Vector2(300, 52)
		_animate_button(b, _box.get_child_count() - 2)
		if it[0] == "Leave the game":
			b.modulate = Color(1, 1, 1, 0.85)


## Buttons come in one after another and grow a little under the mouse.
func _animate_button(b: Button, i: int) -> void:
	if Anim.instant:
		return
	b.pivot_offset = Vector2(150, 26)
	b.modulate.a = 0.0
	b.scale = Vector2(0.85, 0.85)
	var tw := b.create_tween().set_parallel()
	tw.tween_property(b, "modulate:a", 1.0, Anim.d(0.3)).set_delay(Anim.d(0.08 * i))
	tw.tween_property(b, "scale", Vector2.ONE, Anim.d(0.35)).set_delay(Anim.d(0.08 * i)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	b.mouse_entered.connect(func(): b.create_tween().tween_property(b, "scale", Vector2(1.06, 1.06), 0.12))
	b.mouse_exited.connect(func(): b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.12))
