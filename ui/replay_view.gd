class_name ReplayView
extends Control
## Watching a replay (Replay): the table above (MatchView in its replay mode: nothing can be
## done there, both hands face up, the cards can be looked at) and a bar of controls below: the
## turn and who moves, a scrubber over every action with the turns marked, to the start, a turn
## back, an action back, play/pause, an action on, a turn on, to the end, the speed, and the
## result. Actions only, no time: playing steps one action after the table's animation of the last.
## Going forward animates; any other move builds the table again at once.
##
## Use: var v := ReplayView.new(); v.replay = r; v.back.connect(...); add it (the replay's pack
## must be the active one: main.show_replay does it).

signal back

const BAR_H := 124.0
const SPEEDS := [1.0, 2.0, 4.0]
const PAUSE := 0.9  # seconds between actions at 1x, after the table's animation
## The bar's buttons: [name, icon, what it does (English key)].
const CONTROLS := [["ToStart", "to_start", "To the start"], ["TurnBack", "turn_back", "A turn back"],
	["StepBack", "step_back", "An action back"], ["Play", "play", "Play"], ["StepForward", "step_fwd", "An action on"],
	["TurnForward", "turn_fwd", "A turn on"], ["ToEnd", "to_end", "To the end"]]

var replay: Replay
## Actions played on the table now (0 = the opening hands).
var at := 0
var playing := false
var view: MatchView
var _speed := 0
var _wait := 0.0
var _holder := Control.new()
var _scrub: Scrubber
var _turn_line: Label
var _sub_line: Label
var _result: Label
var _count: Label
var _buttons := {}
var _faces: Array = []  # the players' portraits beside the table, by seat


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("0d0a07")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var s := (720.0 - BAR_H) / 720.0
	_holder.name = "Table"
	_holder.size = Vector2(1280, 720)
	_holder.scale = Vector2(s, s)
	_holder.position = Vector2((1280.0 - 1280.0 * s) / 2.0, 0)
	_holder.clip_contents = true
	add_child(_holder)
	_build_sides(_holder.position.x)
	tree_exiting.connect(func(): Anim.boost = 1.0)
	_build_bar()
	_show_at(0)


## Beside the table: each player's portrait and name, the opponent's at the top, the winner's
## ring gold at the end.
func _build_sides(w: float) -> void:
	_faces = [null, null]
	for p in 2:
		var top := p != replay.me()
		var face := ReplaysView.Portrait.new()
		face.name = "Face%d" % p
		face.hero = replay.hero(p)
		face.size = Vector2(84, 84)
		face.position = Vector2((w - 84.0) / 2.0, 60.0 if top else 404.0)
		face.tooltip_text = CardText.name(replay.hero(p))
		add_child(face)
		_faces[p] = face
		var n := Palette.label(ReplaysView._name(replay.name(p)), 16)
		n.position = Vector2(4, face.position.y + 90)
		n.size = Vector2(w - 8, 24)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		n.clip_text = true
		add_child(n)
		var h := Palette.label(CardText.name(replay.hero(p)), 14, Palette.MUTED)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # (before the size: else it grows to one line)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.position = Vector2(4, face.position.y + 114)
		h.size = Vector2(w - 8, 40)
		add_child(h)


func _build_bar() -> void:
	var bar := Panel.new()
	bar.name = "ReplayBar"
	var st := Palette.frame(Color(0.09, 0.06, 0.035, 0.98), 0)
	st.set_border_width(SIDE_LEFT, 0)
	st.set_border_width(SIDE_RIGHT, 0)
	st.set_border_width(SIDE_BOTTOM, 0)
	st.shadow_size = 10
	bar.add_theme_stylebox_override("panel", st)
	bar.position = Vector2(0, 720.0 - BAR_H)
	bar.size = Vector2(1280, BAR_H)
	add_child(bar)
	_scrub = Scrubber.new()
	_scrub.name = "Scrubber"
	_scrub.position = Vector2(24, 8)
	_scrub.size = Vector2(1232, 40)
	_scrub.total = replay.size()
	_scrub.ticks = replay.turn_starts()
	_scrub.seek.connect(func(k: int, done: bool):
		_pause()
		if done:
			_show_at(k)
		else:
			_scrub.value = k
			_update_labels(k))
	bar.add_child(_scrub)
	var leave := _icon_button("ReplayBack", "", tr("Back"), func(): back.emit())
	leave.text = tr("Back")
	leave.custom_minimum_size = Vector2(118, 60)
	leave.position = Vector2(20, 56)
	bar.add_child(leave)
	_turn_line = Palette.label("", 22, Palette.ATTACK)
	_turn_line.name = "TurnLine"
	_turn_line.position = Vector2(150, 54)
	_turn_line.size = Vector2(290, 30)
	_turn_line.clip_text = true
	bar.add_child(_turn_line)
	_sub_line = Palette.label("", 17, Palette.MUTED)
	_sub_line.position = Vector2(150, 86)
	_sub_line.size = Vector2(290, 24)
	_sub_line.clip_text = true
	bar.add_child(_sub_line)
	var row := HBoxContainer.new()
	row.name = "Transport"
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	var fns := [func(): _show_at(0), func(): _show_at(_turn_from(at, -1)), func(): _show_at(at - 1), toggle_play, step,
		func(): _show_at(_turn_from(at, 1)), func(): _show_at(replay.size())]
	for i in CONTROLS.size():
		var spec: Array = CONTROLS[i]
		var b := _icon_button(spec[0], spec[1], tr(spec[2]), fns[i])
		b.custom_minimum_size = Vector2(88 if spec[0] == "Play" else 70, 60)
		row.add_child(b)
	row.position = Vector2(450, 56)
	var speed := _icon_button("Speed", "", tr("Speed"), func():
		_speed = (_speed + 1) % SPEEDS.size()
		Anim.boost = SPEEDS[_speed]  # the table's animations too
		_buttons.Speed.text = "%d×" % SPEEDS[_speed])
	speed.text = "1×"
	speed.custom_minimum_size = Vector2(64, 60)
	speed.position = Vector2(1018, 56)
	bar.add_child(speed)
	var pill := PanelContainer.new()  # the result, at the end: a gold pill
	pill.name = "ResultPill"
	var ps := Palette.raw_box(Color("3a2a10"), 16, Color("f2c94c"), 2)
	ps.content_margin_left = 10
	ps.content_margin_right = 10
	pill.add_theme_stylebox_override("panel", ps)
	pill.position = Vector2(1092, 54)
	pill.custom_minimum_size = Vector2(172, 32)
	pill.size = pill.custom_minimum_size
	_result = Palette.label("", 17, Color("ffd75e"))
	_result.name = "Result"
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.clip_text = true
	pill.add_child(_result)
	bar.add_child(pill)
	_count = Palette.label("", 16, Palette.MUTED)
	_count.name = "Count"
	_count.position = Vector2(1090, 88)
	_count.size = Vector2(176, 24)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_count)


## A big button of the bar with an icon (and a long-press/hover name).
func _icon_button(id: String, icon: String, tip: String, fn: Callable) -> Button:
	var b := Button.new()
	b.name = id
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 20)
	var gold := Color("c9a74a")
	b.add_theme_stylebox_override("normal", Palette.box(Color(0.16, 0.11, 0.07, 1.0), 12, gold.darkened(0.35), 2))
	b.add_theme_stylebox_override("hover", Palette.box(Color(0.22, 0.15, 0.09, 1.0), 12, gold, 2))
	b.add_theme_stylebox_override("pressed", Palette.box(Color(0.3, 0.2, 0.1, 1.0), 12, Palette.SELECTED, 2))
	b.add_theme_stylebox_override("disabled", Palette.box(Color(0.1, 0.07, 0.05, 1.0), 12, gold.darkened(0.6), 2))
	b.pressed.connect(fn)
	b.pressed.connect(Sound.play.bind("click"))
	if icon != "":
		var v := Icons.attach(b, icon, 34)
		v.name = "Icon"
	_buttons[id] = b
	return b


## Builds the table at k actions (at once: a seek, a step back, a jump).
func _show_at(k: int) -> void:
	k = clampi(k, 0, replay.size())
	at = k
	if view:
		_holder.remove_child(view)
		view.queue_free()
	var m := Match.new()
	var why := m.setup(replay.setup_req(), [false, false])
	if why != "" or not m.fast_forward(replay.data.actions.slice(0, k)):
		push_warning("replay: the engine refused it (%s)" % why)
	view = MatchView.new()
	view.name = "ReplayTable"
	view.replay = true
	view.replay_side = replay.me()
	view.player_names = [replay.name(0), replay.name(1)]
	_holder.add_child(view)
	view.bind(m)
	_update_labels(k)


## One action on, animated (the end: nothing).
func step() -> void:
	if at >= replay.size():
		_pause()
		return
	var a: Dictionary = replay.data.actions[at]
	at += 1
	if not view.controller.submit(a).get("ok", false):
		push_warning("replay: action %d refused" % at)
	_update_labels(at)


func toggle_play() -> void:
	if playing:
		_pause()
		return
	if at >= replay.size():
		_show_at(0)  # played to the end: again from the start
	playing = true
	_wait = 0.0
	_set_play_icon()


func _pause() -> void:
	playing = false
	_set_play_icon()


func _set_play_icon() -> void:
	var b: Button = _buttons.get("Play")
	if b:
		(b.get_node("Icon") as IconView).kind = "pause" if playing else "play"
		b.tooltip_text = tr("Pause") if playing else tr("Play")


func _process(delta: float) -> void:
	if not playing or view == null:
		return
	if view._busy:  # the last action is still being shown
		_wait = 0.0
		return
	_wait += delta * SPEEDS[_speed]
	if _wait >= PAUSE:
		_wait = 0.0
		step()


## Where the turn of action k starts (dir -1: this turn's start, or the one before if k is there;
## +1: the next turn's start).
func _turn_from(k: int, dir: int) -> int:
	var starts: Array = replay.turn_starts()
	if dir > 0:
		for s in starts:
			if s[1] > k:
				return s[1]
		return replay.size()
	var out := 0
	for s in starts:
		if s[1] < k:
			out = s[1]
	return out


func _update_labels(k: int) -> void:
	_scrub.value = k
	var t: Array = replay.turns()
	var turn: int = t[k] if k < t.size() else 0
	var g := view.controller.game if view else null
	if turn == 0:
		_turn_line.text = tr("Mulligan")
	else:
		var who := g.current if g and k == at else _mover(k)
		_turn_line.text = tr("Turn %d — %s") % [turn, replay.name(who)]
	var mode := str(replay.data.get("mode", ""))
	_sub_line.text = "%s  vs  %s" % [ReplaysView._name(replay.name(replay.me())), ReplaysView._name(replay.name(1 - replay.me()))]
	if mode != "":
		_sub_line.text += "  ·  " + tr(ReplaysView.MODES.get(mode, mode))
	var w := replay.winner()
	for p in _faces.size():
		_faces[p].won = k >= replay.size() and w == p
		_faces[p].queue_redraw()
	_count.text = tr("Action %d of %d") % [k, replay.size()]
	_result.text = (tr("%s won") % replay.name(w) if w >= 0 else tr("Draw")) if k >= replay.size() else ""
	(_result.get_parent() as Control).visible = _result.text != ""
	for id in ["ToStart", "TurnBack", "StepBack"]:
		_buttons[id].disabled = k == 0
	for id in ["StepForward", "TurnForward", "ToEnd"]:
		_buttons[id].disabled = k >= replay.size()
	for id in _buttons:
		_buttons[id].modulate.a = 0.4 if _buttons[id].disabled else 1.0


## Who moves after k actions while scrubbing (the action's player; the table is not built yet).
func _mover(k: int) -> int:
	if k < replay.size():
		return int(replay.data.actions[k].get("player", 0))
	return int(replay.data.actions[k - 1].get("player", 0)) if k > 0 else 0



## The bar over every action: a gold fill to the place, a mark at each turn's start (its number
## where there is room), a knob. A tap or a drag seeks (done when the finger lets go).
class Scrubber:
	extends Control
	signal seek(k: int, done: bool)
	var total := 1
	var ticks: Array = []  # [[turn, k]]
	var value := 0:
		set(v):
			value = v
			queue_redraw()
	var _dragging := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _x(k: int) -> float:
		return 14.0 + (size.x - 28.0) * float(k) / maxf(1.0, total)

	func _k(x: float) -> int:
		return clampi(roundi((x - 14.0) / maxf(1.0, size.x - 28.0) * total), 0, total)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			_dragging = ev.pressed
			seek.emit(_k(ev.position.x), not ev.pressed)
			accept_event()
		elif ev is InputEventMouseMotion and _dragging:
			seek.emit(_k(ev.position.x), false)
			accept_event()

	func _draw() -> void:
		var y := 14.0
		var track := Rect2(14, y - 4, size.x - 28, 8)
		draw_style_box(Palette.box(Color(0.03, 0.02, 0.01), 4, Color("6b5320"), 1), track.grow(1))
		draw_style_box(Palette.box(Color("c9a74a"), 4), Rect2(track.position, Vector2(_x(value) - 14.0, 8)))
		var f := get_theme_font("font", "Label")
		var last_label := -1000.0
		for t in ticks:
			if t[0] == 0:
				continue
			var x := _x(t[1])
			var past: bool = t[1] <= value
			draw_line(Vector2(x, y - 9), Vector2(x, y + 9), Color("f2c94c") if past else Color("8a7240"), 2.0)
			if x - last_label >= 26.0:
				last_label = x
				var s := str(t[0])
				var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				draw_string(f, Vector2(x - w / 2.0, y + 26), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("d8c9a3") if past else Color("8a7a5a"))
		var kx := _x(value)
		draw_circle(Vector2(kx, y), 11.0, Color("1b140f"))
		draw_circle(Vector2(kx, y), 9.0, Color("f2c94c"))
		draw_circle(Vector2(kx, y), 4.0, Color("8a5a12"))
