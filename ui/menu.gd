class_name MainMenu
extends Control
## The client's main menu (pack null; no game styles it, Packs.shell): Play (a submenu:
## Direct, without a server, or Server, through one), Settings, Exit (not on the web).
## A game's menu (pack set: main made it the active pack, so the screen has its look, menu
## music, pictures and logo): Collection, Training, Code play (Direct) or Play (Server: the
## server's ranked, casual and Arena games), Tutorial (when the pack has one), Settings (with
## the debug tools of this game), Leave the game. Through a server also Tournaments.

signal direct
signal server
signal settings
signal quit
signal collection
signal training
signal code_play
signal play
signal tournaments
signal tutorial
signal leave

## Button labels (English keys); the translation tool reads this list.
const ITEMS := ["Play", "Direct", "Server", "Back", "Settings", "Exit", "Collection", "Training", "Code play",
	"Tutorial", "Tournaments", "Leave the game", "Without a server: the games on this device, training, code play",
	"Through a server: an account, ranked games, the Arena, friends"]

## The game whose menu this is (null: the client's main menu).
var pack: Pack
## The game is played through a server (Play opens its lobby).
var through_server := false
var _box: VBoxContainer
## Parallax: [node, its place at rest, depth in pixels]; a positive depth moves against the look
## (far away), a negative one with it (near). The look comes from the mouse, the phone's tilt or
## the last touch, eased, with a slow sway of its own.
var _layers: Array = []
var _look := Vector2.ZERO
var _rest_tilt := Vector3.INF  # the phone's gravity when the menu opened (its tilt is measured from it)
var _t := 0.0
const PIC_MARGIN := 40.0  # the picture is this much bigger on every side, so a move shows no edge


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
	pic.offset_left = -PIC_MARGIN
	pic.offset_top = -PIC_MARGIN
	pic.offset_right = PIC_MARGIN
	pic.offset_bottom = PIC_MARGIN
	pic.modulate = Color(0.78, 0.74, 0.7) if Packs.picture("menu") else Color.WHITE
	add_child(pic)
	var shade := ColorRect.new()
	shade.color = Palette.tc("menu.shade")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var fx := SceneFx.make(str(Palette.UI.menu.particles))
	if fx:
		add_child(fx)
	var motes := _motes()
	add_child(motes)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_layers = [[pic, pic.position, 30.0], [center, center.position, -8.0], [motes, motes.position, -22.0]]
	if fx:
		_layers.append([fx, fx.position, 14.0])
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var title := TitleLogo.new()
	title.name = "Title"
	if pack:
		title.text = pack.title()
	box.add_child(title)
	if not Anim.instant:
		pic.pivot_offset = Vector2(640, 360) + Vector2(PIC_MARGIN, PIC_MARGIN)
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


func _process(delta: float) -> void:
	if Anim.instant:
		return
	_t += delta
	var sway := Vector2(sin(_t * 0.23), cos(_t * 0.17)) * 0.2
	_look = _look.lerp((_aim() + sway).limit_length(1.0), minf(1.0, delta * 2.5))
	place(_look)


## Dust in the light, close to the eye: the nearest parallax layer (it moves most, with the look).
func _motes() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Motes"
	p.amount = 36
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.position = Vector2(640, 360)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(700, 400)
	p.direction = Vector2(0.3, -1)
	p.spread = 40.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 12.0
	p.scale_amount_min = 2.5
	p.scale_amount_max = 6.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 0.92, 0.75, 0.0))
	fade.set_color(1, Color(1, 0.92, 0.75, 0.0))
	fade.add_point(0.3, Color(1, 0.92, 0.75, 0.35))
	fade.add_point(0.7, Color(1, 0.92, 0.75, 0.3))
	p.color_ramp = fade
	p.emitting = not Anim.instant
	return p


## Where the player looks, -1..1 on each axis: the phone's tilt when it has a sensor, else the
## mouse (on a touchscreen: the last touch).
func _aim() -> Vector2:
	var g := Input.get_gravity()
	if g.length() > 1.0:
		if _rest_tilt == Vector3.INF:
			_rest_tilt = g
		var d := g - _rest_tilt
		return Vector2(clampf(-d.x / 3.0, -1.0, 1.0), clampf(d.y / 3.0, -1.0, 1.0))
	var m := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(m):
		return Vector2.ZERO
	return (m / size - Vector2(0.5, 0.5)) * 2.0


## Moves the layers for a look (-1..1): the far ones the other way, the near ones a little with it.
func place(look: Vector2) -> void:
	for l in _layers:
		if is_instance_valid(l[0]):
			l[0].position = l[1] - look * float(l[2])


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
	var items := [["Play", play, ok], ["Tournaments", tournaments, ok]] if through_server else []
	items += [["Collection", collection, true], ["Training", training, ok]]
	if not through_server:  # WebRTC: the browser, or the webrtc-native plugin
		items.append(["Code play", code_play, ok and WebRtcTransport.available()])
	if pack.has_tutorial():
		items.append(["Tutorial", tutorial, ok])
	_fill(items + [["Settings", settings, true], ["Leave the game", leave, true]])
	var codes := _box.find_child("CodePlay", false, false) as Button
	if codes and ok and codes.disabled:
		codes.tooltip_text = tr("Code play needs WebRTC, which this build does not have")
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
