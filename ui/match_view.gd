class_name MatchView
extends Control
## The game table. Everything on it is rebuilt from the game state after each
## action; effects (floating numbers, ghosts of dead minions, shake) come from events.
## Input flow: pick a card / attacker / hero power -> (Choose One) -> (position) -> (target).

signal leave
signal arena_back  # an Arena game: back to the Arena's lobby
## Tutorial: the player asked for the next mission.
signal tutorial_next(n: int)  # go on to mission n (its intro first)
signal tutorial_retry(n: int)  # play mission n again

const ENEMY_HERO := Vector2(575, 40)
const OWN_HERO := Vector2(575, 466)
const ENEMY_BOARD_Y := 188.0
const OWN_BOARD_Y := 336.0
const TOOLTIP_POS := Vector2(1035, 160)

## Fixed button texts by node name, set again when the language changes.
const LABELS := {"HistoryButton": "History", "JsonButton": "Position -> JSON", "EmoteButton": "Emote",
	"MuteButton": "Mute", "SettingsButton": "Settings"}
const EMOTES := {"greetings": "Greetings!", "well_played": "Well played!", "thanks": "Thanks.",
	"wow": "Wow!", "oops": "Oops.", "threaten": "I will destroy you!"}

## Online turn timer (seconds), as in the original game: the rope burns in the last seconds.
const TURN_SECONDS := 75.0
const ROPE_SECONDS := 15.0
const MULLIGAN_SECONDS := 45.0

var debug_mode := false
## The turn timer runs only in online games against a person.
var timer_enabled := false
## Names shown next to the heroes ("" = You/Opponent).
var player_names: Array = ["", ""]
## Online opponent's emotes are hidden.
var muted := false
var session: NetSession
## Set for a game of the Arena: the result shows the Arena's score and leads back to it.
var arena: ArenaSession
## Set for a tutorial mission (hints, turn-end rules, reward screen).
var tutorial: Tutorial
var controller: Match
var g: Game:
	get:
		return controller.game

var _layer := Control.new()
var _fx := Control.new()
var _views := {}
var _sel := {}
var _overlay: Control
var _tooltip: CardView
var _tips: KeywordTips
var _history: HistoryPanel
var _tracker: DeckTrackerPanel
var _end_turn: Button
var _end_halo := _Halo.new()  # a green light behind End Turn when nothing is left to do
var _mana: Array[ManaBar] = []
var _piles: Array[DeckPile] = []
var _menu: PanelContainer
var _wheel: Control
var _enemy_menu: PanelContainer
var _hover_hand := -1
var _laid_out := false
var _gap := -1
## A press on a view that may become a drag: {id, at}.
var _press := {}
var _dragging := false
var _arrow := TargetArrow.new()
var _strip := HistoryStrip.new()
## Online: what the opponent points at.
var _opp_arrow := TargetArrow.new()
var _opp_hover := -1
var _opp_look := -1
var _last_intent := {}
var _intent_ms := 0
var _applied_intent := {}
## Full table layouts done (tests check that repeated intents cause none).
var _layouts := 0
## Nothing is left to do this turn: the End Turn button glows green.
var end_turn_ready := false
## Event batches waiting for their animation; while one plays the table is busy.
var _queue: Array = []
var _busy := false
## The local player's orders given while the table still animates: carried out
## one by one after the animations, in order (not in the tutorial).
var _pending_acts: Array = []
var _plan_cache: GameState  # the state after those orders (null = not made yet)
var _drag_home := []  # where a dragged hand card was: [id, position, scale, rotation]
var _final_refresh := false
const BURN_SHADER := preload("res://ui/burn.gdshader")
var _ending := false  # the losing hero's portrait is shattering (the result waits)
var _hold := {}  # id -> true: views an animation moves (the layout leaves them alone)
var _mull_wait := -1  # the player whose mulligan overlay waits for the new cards
## A card that changed its id in place (bounced, transformed): new id -> where it stood.
var _moved := {}
var _quiet := {}
var _names: Array[Label] = []
var _hint: Label
var _hint_timer := 0.0
var _bubbles := {}
var _rope := Fuse.new()
var _clock := Label.new()  # the match time and, in online games, the turn's time left
var _match_time := 0.0
var _turn_key := ""
var _bot_side := -1
var _time_left := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sound.music("battle")
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var board := TextureRect.new()  # the game board on a tavern table (generated)
	board.texture = load("res://ui/board_bg.jpg")
	board.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.offset_top = -12  # its middle line meets the line between the two rows of minions
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	_rope.name = "Rope"
	_rope.visible = false
	add_child(_rope)
	for c in [_layer, _fx]:
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(c)
	_end_turn = Palette.button(tr("End Turn"), "EndTurn")
	_end_turn.custom_minimum_size = Vector2(140, 52)
	_end_turn.position = Vector2(1132, 310)
	_end_turn.pressed.connect(_on_end_turn)
	_clock.name = "Clock"
	_clock.position = Vector2(1132, 366)
	_clock.size = Vector2(140, 44)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.add_theme_font_size_override("font_size", 15)
	_clock.add_theme_color_override("font_color", Color("f4ead5"))
	_clock.add_theme_color_override("font_outline_color", Color.BLACK)
	_clock.add_theme_constant_override("outline_size", 5)
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clock)
	_end_halo.position = _end_turn.position
	_end_halo.size = _end_turn.custom_minimum_size
	_end_halo.visible = false
	add_child(_end_halo)  # behind the button
	add_child(_end_turn)
	for i in 2:
		var bar := ManaBar.new()
		bar.name = "Mana%d" % i
		bar.position = Vector2(1000, 684) if i == 0 else Vector2(950, 10)
		_mana.append(bar)
		add_child(bar)
		var n := Palette.label("", 16)
		n.position = Vector2(12, 690 if i == 0 else 8)
		_names.append(n)
		add_child(n)
		var pile := DeckPile.new()
		pile.name = "Deck%d" % i
		pile.position = TableLayout.OWN_DECK if i == 0 else TableLayout.ENEMY_DECK
		_piles.append(pile)
		add_child(pile)
	_build_menu()
	_build_emote_wheel()
	add_child(_strip)
	_strip.open_history.connect(func(): _history.visible = not _history.visible)
	add_child(_arrow)
	_opp_arrow.tint = Color("e03131")
	add_child(_opp_arrow)
	_hint = Palette.label("", 20, Palette.SELECTED)
	_hint.position = Vector2(170, 306)
	_hint.size = Vector2(940, 30)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_tracker = DeckTrackerPanel.new()
	_tracker.z_index = 90
	_tracker.visible = Settings.data.tracker
	add_child(_tracker)
	_history = HistoryPanel.new()
	_history.z_index = 90
	_history.visible = false
	add_child(_history)


func bind(m: Match) -> void:
	controller = m
	m.busy = func() -> bool: return _busy
	add_child(m)
	m.changed.connect(_on_changed)
	m.finished.connect(func(_w): refresh())
	if player_names == ["", ""] and m.bots[0] != m.bots[1]:
		var me := m.viewer()
		player_names[me] = Profile.load_name()
		if m.bots[1 - me]:
			_bot_side = 1 - me  # named in _side_name, so the name follows the language
	m.start()
	refresh()


## An online match: the session (and its transport) now live under this view.
func bind_online(m: Match, s: NetSession) -> void:
	session = s
	timer_enabled = true
	for n in [s, s.transport]:
		if s.transport is ChannelTransport:
			break  # an Arena game: the Arena keeps its session
		if n.get_parent() and n.get_parent() != self:
			n.reparent(self)
		elif n.get_parent() == null:
			add_child(n)
	player_names[m.viewer()] = s.player_name
	player_names[m.remote] = s.remote_name
	s.emote_received.connect(func(p, id):
		if not muted:
			show_emote(p, id))
	s.failed.connect(_on_connection_lost)
	s.intent_received.connect(apply_intent)
	(find_child("MuteButton", true, false) as Button).visible = true
	bind(m)


func set_muted(on: bool) -> void:
	muted = on
	if on and controller and _bubbles.has(1 - viewer()) and is_instance_valid(_bubbles[1 - viewer()]):
		_bubbles[1 - viewer()].queue_free()


const EMOTE_COOLDOWN_MS := 1500
var _last_emote_ms := -100000


func send_emote(id: String) -> void:
	if not EMOTES.has(id) or controller == null:
		return
	if Time.get_ticks_msec() - _last_emote_ms < EMOTE_COOLDOWN_MS:
		return  # no emote spam
	_last_emote_ms = Time.get_ticks_msec()
	show_emote(viewer(), id)
	if session:
		session.send_emote(id)


## The hero says the emote in its own words (VoiceLines) when it has them.
func show_emote(p: int, id: String) -> void:
	var hero := g.players[p].hero.card_id
	var own := VoiceLines.text(hero, id)
	show_line(p, own if own != "" else tr(EMOTES[id]))


## A speech bubble next to player p's hero (emotes, tutorial boss lines).
func show_line(p: int, text: String) -> void:
	if _bubbles.has(p) and is_instance_valid(_bubbles[p]):
		_bubbles[p].queue_free()
	var own := p == viewer()
	var bubble := _Bubble.new()
	var l := Palette.label(text, 20, Color("2a2118"))
	var text_width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	l.custom_minimum_size.x = minf(320.0, text_width + 8)  # set before wrapping, or the label collapses
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("outline_size", 0)
	bubble.add_child(l)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bubble)
	# its right edge (and tail) just left of the hero, whatever the text's length
	var w := bubble.get_combined_minimum_size().x
	bubble.position = (OWN_HERO if own else ENEMY_HERO) + Vector2(-w - 18, 20 if own else 40)
	_bubbles[p] = bubble
	if not Anim.instant and is_inside_tree():
		bubble.pivot_offset = Vector2(160, 30)
		bubble.scale = Vector2(0.3, 0.3)
		bubble.create_tween().tween_property(bubble, "scale", Vector2.ONE, Anim.d(0.22)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var hero: EntityView = _views.get(g.hero(p).id)
		if hero:  # the hero "talks"
			hero.pivot_offset = hero.size / 2.0
			var tw := hero.create_tween()
			for i in 3:
				tw.tween_property(hero, "scale", Vector2(1.05, 0.96), Anim.d(0.09))
				tw.tween_property(hero, "scale", Vector2.ONE, Anim.d(0.09))
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_interval(2.5 if tutorial == null else 4.5)
		tw.tween_property(bubble, "modulate:a", 0.0, 0.5)
		tw.tween_callback(bubble.queue_free)


## Text of the emote bubble currently shown for player p ("" = none).
func bubble_text(p: int) -> String:
	if not _bubbles.has(p) or not is_instance_valid(_bubbles[p]) or _bubbles[p].is_queued_for_deletion():
		return ""
	return (_bubbles[p].get_child(0) as Label).text


func _on_connection_lost(reason: String) -> void:
	if g.game_over:
		return
	var box := _open_overlay(tr("Out of sync") if session and session.failure_kind == "desync" else tr("Connection lost"))
	_overlay.name = "ConnectionLost"
	var why := Palette.label(reason, 20)
	why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(why)
	if arena:
		_centered_button(box, tr("Back to the Arena"), "BackToArena", _leave)
	else:
		_centered_button(box, tr("Back to Menu"), "BackToMenuLost", _leave)


func _leave() -> void:
	if arena:
		arena_back.emit()  # the Arena's connection stays: its lobby decides what next
		return
	if session:
		session.leave()
	leave.emit()


func _process(delta: float) -> void:
	tick(delta)
	if session:
		_send_intent()
	if not _dragging:
		_track_hand_hover()
		_aim_click_mode()
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_hint.text = ""
			_try_tutorial_hint()


# --- opponent intents (online) ----------------------------------------------------------

func _send_intent() -> void:
	var i := intent_at(get_local_mouse_position())
	var now := Time.get_ticks_msec()
	if i != _last_intent and now - _intent_ms > 100:
		_last_intent = i
		_intent_ms = now
		session.send_intent(i)


## What the local player points at with the mouse at m: an aim, a card of the
## hand, or anything on the table (minion, hero, hero power, weapon, Secret).
func intent_at(m: Vector2) -> Dictionary:
	if _dragging or _sel.get("stage", "") == "target":
		var over := _view_at(m)
		return {"k": "aim", "from": _sel.get("id", -1), "to": over.entity_id if over else -1,
			"x": snappedf(m.x, 8.0), "y": snappedf(m.y, 8.0)}
	if _hover_hand >= 0:
		return {"k": "hover", "i": g.players[viewer()].hand.find(g.ent(_hover_hand))}
	var over := _view_at(m)
	if over and over.get_meta("kind") != "hand":
		return {"k": "look", "id": over.entity_id}
	return {"k": "none"}


## Shows what the opponent points at: their arrow, and in red the card raised in
## their hand or whatever on the table they look at.
func apply_intent(i: Dictionary) -> void:
	if i == _applied_intent:
		return  # nothing new: a stuck or flooding peer costs nothing
	_applied_intent = i
	var hover := -1
	var look := -1
	_opp_arrow.visible = false
	match i.get("k"):
		"hover":
			hover = i.i
		"look":
			look = i.id
		"aim":
			if _views.has(i.from):
				var to: Vector2 = _center_of(i.to) if _views.has(i.to) else Vector2(i.x, 720.0 - i.y)
				_opp_arrow.aim(_center_of(i.from), to, _views.has(i.to))
	if hover != _opp_hover:
		_opp_hover = hover
		_opp_look = look
		refresh()  # the card is raised (refresh puts the glows on too)
	elif look != _opp_look:
		_opp_look = look
		_apply_glows()


# --- drag and drop ------------------------------------------------------------------

func _on_press(v: EntityView) -> void:
	if not my_action() or _overlay != null or (_busy and tutorial != null):
		return
	if _sel.get("stage", "") in ["target", "position"]:
		click_entity(v.entity_id)  # finishing a click-mode choice
		return
	_press = {"id": v.entity_id, "at": get_local_mouse_position()}


func _input(ev: InputEvent) -> void:
	if _press.is_empty() or controller == null:
		return
	if ev is InputEventMouseMotion:
		var m := get_local_mouse_position()
		if not _dragging and m.distance_to(_press.at) > 12.0:
			_start_drag()
		if _dragging:
			_drag_to(m)
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		var id: int = _press.id
		var was := _dragging
		_press = {}
		_dragging = false
		_arrow.visible = false
		if was:
			_drop_at(get_local_mouse_position(), id)
		else:
			click_entity(id)


func _start_drag() -> void:
	var id: int = _press.id
	var acts := _actions_for(id)
	if acts.is_empty():
		_press = {}
		click_entity(id)  # shows why it can't be played or attack
		return
	_dragging = true
	_sel = {"id": id, "actions": acts, "dragging": true}
	var dv: EntityView = _views.get(id)
	_drag_home = [id, dv.position, dv.scale.x, dv.rotation] if dv and dv.get_meta("kind") == "hand" else []
	_apply_glows()
	if not _targets(acts).is_empty():
		for t in _targets(acts):
			if _views.has(t):
				_views[t].set_glow(Palette.TARGET)


func _actions_for(id: int) -> Array:
	return _legal().filter(func(a):
		match a.type:
			"play": return a.entity == id
			"attack": return a.attacker == id
			"hero_power": return id == g.players[viewer()].hero_power.id
		return false)


func _view_at(m: Vector2) -> EntityView:
	for id in _views:
		var v: EntityView = _views[id]
		if v.get_meta("kind") != "hand" and Rect2(v.position, v.size * v.scale).has_point(m):
			return v
	return null


func _drag_to(m: Vector2) -> void:
	if _sel.is_empty() or not _dragging:
		_end_drag()
		return
	var id: int = _sel.id
	var v: EntityView = _views.get(id)
	var e := g.ent(id)
	var targets := _targets(_sel.actions)
	var over := _view_at(m)
	var hot := over != null and targets.has(over.entity_id)
	if e.zone == "HAND":
		var is_minion := e.is_minion()
		var aiming := not is_minion and not targets.is_empty() and m.y < TableLayout.HAND_Y - 40
		if v:
			v.z_index = 50
			v.rotation = 0.0
			v.scale = Vector2(0.9, 0.9)
			v.position = m - v.pivot_offset + Vector2(0, CardView.SIZE.y * 0.45)
			v.modulate.a = 0.25 if aiming else 1.0
		if aiming:
			_arrow.aim(OWN_HERO + HeroView.SIZE / 2.0, m, hot)
		else:
			_arrow.visible = false
		var gap := -1
		if is_minion and m.y > OWN_BOARD_Y - 40 and m.y < OWN_BOARD_Y + 150 and g.players[viewer()].board.size() < 7:
			gap = TableLayout.board_index(m.x, g.players[viewer()].board.size())
		if gap != _gap:
			_gap = gap
			refresh()
	else:
		var src: EntityView = _views.get(id)
		if src:
			_arrow.aim(src.position + src.size * src.scale / 2.0, m, hot)


func _drop_at(m: Vector2, id: int) -> void:
	var gap := _gap
	_gap = -1
	var e := g.ent(id)
	var v: EntityView = _views.get(id)
	if v:
		v.modulate.a = 1.0
	if _sel.is_empty():
		refresh()
		return
	var over := _view_at(m)
	var targets := _targets(_sel.actions)
	if e.zone == "HAND":
		if m.y > TableLayout.HAND_Y - 20:
			cancel()  # back into the hand
			return
		var positions := []
		for a in _sel.actions:
			if a.get("pos", -1) >= 0 and not positions.has(a.pos):
				positions.append(a.pos)
		if positions.size() > 1:
			var pos := gap if gap >= 0 else TableLayout.board_index(m.x, g.players[viewer()].board.size())
			_sel.actions = _sel.actions.filter(func(a): return a.pos == pos)
			_sel.pos = pos
		if not e.is_minion() and over and targets.has(over.entity_id):
			_sel.actions = _sel.actions.filter(func(a): return _target_of(a) == over.entity_id)
			_sel.target = over.entity_id
		_sel.erase("dragging")
		_advance()
	elif over and targets.has(over.entity_id):
		_sel.actions = _sel.actions.filter(func(a): return _target_of(a) == over.entity_id)
		_sel.target = over.entity_id
		_advance()
	elif targets.is_empty():
		_advance()  # an untargeted hero power dragged out
	else:
		cancel()


## In click mode the arrow follows the mouse from the chosen source; a minion
## waiting for its place opens a gap under the mouse.
func _aim_click_mode() -> void:
	if controller == null:
		return
	var stage: String = _sel.get("stage", "")
	var m := get_local_mouse_position()
	if stage == "target" and _placing() >= 0 and m.y > TableLayout.HAND_Y + 30:
		cancel()  # the arrow led back into the hand: the minion goes back, not played
		return
	if stage == "target" and _views.has(_sel.id):
		var src: EntityView = _views[_sel.id]
		var over := _view_at(m)
		_arrow.aim(src.position + src.size * src.scale / 2.0, m, over != null and _targets(_sel.actions).has(over.entity_id))
	elif _arrow.visible:
		_arrow.visible = false
	if stage == "position":
		var gap := TableLayout.board_index(m.x, g.players[viewer()].board.size())
		if gap != _gap:
			_gap = gap
			refresh()
	elif _gap >= 0 and not _dragging:
		_gap = -1
		refresh()


## End Turn: wood while moves are left, glowing green (and pulsing) when none are.
func _style_end_turn() -> void:
	_end_halo.visible = end_turn_ready
	var tint := Color(0.75, 1.35, 0.7) if end_turn_ready else Color.WHITE
	for st in [["normal", 1.0], ["hover", 1.15], ["pressed", 0.85]]:
		_end_turn.add_theme_stylebox_override(st[0], Fonts.plank(tint * st[1]))
	if _end_turn.has_meta("pulse"):
		(_end_turn.get_meta("pulse") as Tween).kill()
		_end_turn.remove_meta("pulse")
	_end_turn.modulate = Color.WHITE
	if end_turn_ready and not Anim.instant and is_inside_tree():
		var tw := _end_turn.create_tween().set_loops()
		tw.tween_property(_end_turn, "modulate", Color(1.25, 1.25, 1.25), 0.6)
		tw.tween_property(_end_turn, "modulate", Color.WHITE, 0.6)
		_end_turn.set_meta("pulse", tw)


## The hand card under the mouse rises (by slot, so a rising card never loses the hover).
func _track_hand_hover() -> void:
	if controller == null or _overlay != null or _menu.visible or find_child("SettingsView", false, false):
		return
	var hand := g.players[viewer()].hand
	var m := get_local_mouse_position()
	var id := -1
	if m.y > TableLayout.HAND_Y - (TableLayout.HOVER_LIFT if _hover_hand >= 0 else 10.0) and not hand.is_empty():
		var fan := TableLayout.hand(hand.size(), true)
		var best := INF
		for i in hand.size():
			var cx: float = fan[i].pos.x + CardView.SIZE.x * fan[i].scale / 2.0
			if absf(m.x - cx) < best and absf(m.x - cx) < CardView.SIZE.x * 0.7:
				best = absf(m.x - cx)
				id = hand[i].id
	if id != _hover_hand:
		_hover_hand = id
		refresh()
		var e := g.ent(id)
		if e:  # beside where the raised card ends up
			var i := hand.find(e)
			var f: Dictionary = TableLayout.hand(hand.size(), true, i)[i]
			_show_tips(e.card_id, Rect2(f.pos, CardView.SIZE * f.scale))
		elif _tooltip == null:
			_show_tips("", Rect2())


func _build_menu() -> void:
	var gear := Button.new()
	gear.name = "MenuButton"
	gear.custom_minimum_size = Vector2(40, 40)
	gear.position = Vector2(1236, 4)
	gear.tooltip_text = tr("Menu")
	gear.pressed.connect(func(): _menu.visible = not _menu.visible)
	Icons.attach(gear, "gear", 30)
	add_child(gear)
	var deck := Button.new()  # the deck tracker, left of the gear
	deck.name = "TrackerButton"
	deck.custom_minimum_size = Vector2(40, 40)
	deck.position = gear.position - Vector2(46, 0)
	deck.tooltip_text = tr("Deck Tracker")
	deck.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed"]:
		deck.add_theme_stylebox_override(st, Palette.box(Color(0.1, 0.07, 0.05, 0.9 if st == "normal" else 1.0), 20, Color("c9a74a") if st != "normal" else Color("6b5320"), 2))
	deck.pressed.connect(func():
		Settings.data.tracker = not Settings.data.tracker
		Settings.save()
		_tracker.slide(Settings.data.tracker)
		refresh())
	Icons.attach(deck, "cards", 28)
	add_child(deck)
	_menu = PanelContainer.new()
	_menu.name = "GameMenu"
	_menu.z_index = 100
	_menu.visible = false
	_menu.add_theme_stylebox_override("panel", Palette.box(Color(0.1, 0.07, 0.05, 0.95), 10, Color("c9a74a"), 2))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_menu.add_child(box)
	var items := [["History", "HistoryButton", func(): _history.visible = not _history.visible],
		["Settings", "SettingsButton", open_settings]]
	if debug_mode:
		items.append(["Position -> JSON", "JsonButton", show_json])
	items.append(["Concede", "Concede", _on_concede])
	for it in items:
		var b := Palette.button(tr(it[0]), it[1])
		b.custom_minimum_size = Vector2(220, 42)
		var fn: Callable = it[2]
		b.pressed.connect(func():
			_menu.visible = false
			fn.call())
		box.add_child(b)
	add_child(_menu)
	_menu.position = Vector2(1036, 50)


func _build_emote_wheel() -> void:
	_wheel = Control.new()
	_wheel.name = "EmoteWheel"
	_wheel.z_index = 100
	_wheel.visible = false
	_wheel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var spots := [Vector2(-190, -10), Vector2(-200, 40), Vector2(-190, 90), Vector2(130, -10), Vector2(140, 40), Vector2(130, 90)]
	var ids := EMOTES.keys()
	for i in ids.size():
		var b := Button.new()
		b.name = "Emote_" + ids[i]
		b.text = tr(EMOTES[ids[i]])
		b.custom_minimum_size = Vector2(190, 40)
		b.position = OWN_HERO + spots[i]
		b.add_theme_stylebox_override("normal", Palette.box(Color("f4ead5"), 20, Color("2a2118"), 3))
		b.add_theme_stylebox_override("hover", Palette.box(Color("fff8e8"), 20, Color("c9a74a"), 3))
		b.add_theme_color_override("font_color", Color("2a2118"))
		b.add_theme_color_override("font_hover_color", Color("2a2118"))
		var e: String = ids[i]
		b.pressed.connect(func():
			_wheel.visible = false
			send_emote(e))
		_wheel.add_child(b)
	add_child(_wheel)
	_enemy_menu = PanelContainer.new()
	_enemy_menu.name = "EnemyMenu"
	_enemy_menu.z_index = 100
	_enemy_menu.visible = false
	_enemy_menu.position = ENEMY_HERO + Vector2(140, 20)
	var mute := Palette.button(tr("Mute"), "MuteButton")
	mute.toggle_mode = true
	mute.visible = false
	mute.toggled.connect(func(on):
		_enemy_menu.visible = false
		set_muted(on))
	_enemy_menu.add_child(mute)
	add_child(_enemy_menu)


## Emotes may be sent (not in the tutorial, only by a human side).
func emotes_allowed() -> bool:
	return tutorial == null and controller != null and not controller.bots[viewer()]


## Right click: your hero opens the emotes, the online opponent's hero the mute option.
func _on_right_click(v: EntityView) -> void:
	var e := g.ent(v.entity_id)
	if e == null or not e.is_hero():
		cancel()
		return
	if e.controller == viewer():
		_wheel.visible = emotes_allowed() and not _wheel.visible
	elif session:
		_enemy_menu.visible = not _enemy_menu.visible


## Runs the online turn timer: the rope in the last seconds, then the local
## player's turn ends by itself (Match.timeout).
func tick(delta: float) -> void:
	_update_clock(delta)
	if not timer_enabled or controller == null or g.game_over:
		_rope.visible = false
		return
	_reset_timer()  # a new turn gets its full time even while the table is animating
	_time_left -= delta
	_rope.visible = _time_left <= ROPE_SECONDS
	_rope.left = _time_left / ROPE_SECONDS
	if _time_left > 0.0:
		return
	var me := viewer()
	if (g.phase == "MULLIGAN" and not g.players[me].mulliganed) or (g.phase != "MULLIGAN" and g.current == me):
		_end_drag()
		_sel = {}
		controller.timeout(me)


## Under End Turn: the time since the match began (counting up) and, when the turn
## has a time limit, the time left in this turn (counting down, full again each turn).
func _update_clock(delta: float) -> void:
	if controller == null:
		return
	if not g.game_over:
		_match_time += delta
	var t := tr("Game %s") % _mmss(_match_time)
	if timer_enabled and not g.game_over:
		t += "\n" + tr("Turn %s") % _mmss(maxf(0.0, _time_left))
	_clock.text = t
	_clock.add_theme_color_override("font_color", Color("ff8a5b") if timer_enabled and _time_left <= ROPE_SECONDS else Color("f4ead5"))


static func _mmss(seconds: float) -> String:
	var s := int(ceil(seconds))
	return "%d:%02d" % [s / 60, s % 60]


func _reset_timer() -> void:
	var key := "M" if g.phase == "MULLIGAN" else "%d:%d" % [g.turn, g.current]
	if key != _turn_key:
		_turn_key = key
		_time_left = MULLIGAN_SECONDS if g.phase == "MULLIGAN" else TURN_SECONDS


## Shows the next tutorial hint only when nothing else is on the banner (an
## unread hint or a "Choose a target" prompt), so hints never overwrite each other.
func _try_tutorial_hint() -> void:
	if tutorial == null or _hint_timer > 0.0 or not _sel.is_empty() or g.game_over:
		return
	var hint := tutorial.next_hint(g, viewer())
	if hint != "":
		show_hint(hint, 7.0)


# --- state helpers ----------------------------------------------------------

func viewer() -> int:
	return controller.viewer()


## True when the local human may act now.
func my_action() -> bool:
	return not g.game_over and not controller.bots[controller.actor()] and controller.actor() == viewer()


func _legal() -> Array:
	return _plan().legal_actions().filter(func(a): return a.player == viewer()) if my_action() else []


## The state the next order is checked against: the game after the orders still
## waiting in the queue.
func _plan() -> GameState:
	if _pending_acts.is_empty():
		return g
	if _plan_cache == null:
		_plan_cache = g.clone()
		for a in _pending_acts:
			_plan_cache.apply(a)
	return _plan_cache


## Carries out an order now, or queues it while the table animates.
func _act(a: Dictionary) -> void:
	if a.is_empty():
		return
	if (_busy or not _pending_acts.is_empty()) and tutorial == null:
		_pending_acts.append(a)
		_plan_cache = null
		_return_dragged()
		_apply_glows()
		return
	controller.submit(a)


## The orders waiting for the animations, in order; an order that is no longer
## possible (the turn ended, a target died) drops it and the rest.
func _release_orders() -> void:
	while not _pending_acts.is_empty() and not _busy:
		var a: Dictionary = _pending_acts.pop_front()
		_plan_cache = null
		var r := controller.submit(a)
		if not r.ok:
			_pending_acts.clear()
			show_hint(tr("The queued moves were cancelled: they are no longer possible"), 3.0)
	_apply_glows()


## A hand card dropped as a queued order goes back to its place until its turn comes.
## (While the table animates the layout waits, so the card is put back by hand.)
func _return_dragged() -> void:
	if _drag_home.size() == 4 and not _dragging:
		var v: EntityView = _views.get(_drag_home[0])
		if v:
			_glide(v, _drag_home[1], _drag_home[2], _drag_home[3])
		_drag_home = []


func show_hint(text: String, seconds := 2.0) -> void:
	_hint.text = text
	_hint_timer = seconds


# --- rendering ----------------------------------------------------------------

func open_settings() -> void:
	var s := SettingsView.new()
	s.z_index = 100
	s.back.connect(s.queue_free)
	s.language_changed.connect(relabel)
	s.art_changed.connect(func():  # card art or card back
		for v in _views.values():
			v.queue_redraw()
		for p in _piles:
			p.queue_redraw())
	add_child(s)


## Sets the fixed texts again in the current language.
func relabel() -> void:
	for n in LABELS:
		var b := find_child(n, true, false) as Button
		if b:
			b.text = tr(LABELS[n])
	for id in EMOTES:
		(_wheel.get_node("Emote_" + id) as Button).text = tr(EMOTES[id])
	_history.relabel()
	_tracker.relabel()
	if _overlay and _overlay.name != "ConnectionLost":
		_close_overlay()  # refresh() builds it again in the new language
	refresh()


func refresh() -> void:
	if _busy and not _final_refresh:
		_apply_glows()  # the layout changes when the running animation ends
		_return_dragged()
		return
	var me := viewer()
	var opp := g.opponent(me)
	var want := {}
	_layout_side(opp, false, want)
	_layout_side(me, true, want)
	_reconcile(want)
	_layouts += 1
	_laid_out = true
	for i in 2:
		var p := g.players[[me, opp][i]]
		_mana[i].set_values(p.mana, p.max_mana, p.overload_locked, p.overload_owed)
		_names[i].text = _side_name(p.index)
		_piles[i].count = p.deck.size()
		_piles[i].hand = p.hand.size()
	var hovered := g.ent(_hover_hand)  # the crystals a card would spend blink, when there is mana for it
	var price := g.cost(hovered) if hovered and hovered.zone == "HAND" else 0
	_mana[0].set_preview(price if price > 0 and price <= g.players[viewer()].mana and my_action() and g.phase == "PLAY" else 0)
	_end_turn.disabled = not (my_action() and g.phase == "PLAY" and g.pending.is_empty())
	var ready := not _end_turn.disabled and _legal().all(func(a): return a.type in ["end_turn", "concede"])
	if ready != end_turn_ready:
		end_turn_ready = ready
		_style_end_turn()
	_end_turn.text = tr("End Turn") if my_action() or g.game_over else tr("Enemy Turn")
	var concede := find_child("Concede", true, false) as Button
	if concede:
		concede.text = tr("Menu") if g.game_over else tr("Concede")
	_apply_glows()
	_history.update_from(g, me)
	_strip.update_from(g, me)
	_reset_timer()
	if _tracker.visible:
		_tracker.update_from(g, me)
	_refresh_overlay()
	if tutorial:
		var line := tutorial.boss_line(g)
		if line != "":
			show_line(g.opponent(me), line)
		_try_tutorial_hint()


func _side_name(p: int) -> String:
	if p == _bot_side and player_names[p] == "":
		return CardText.name(tutorial.mission.boss) if tutorial else tr("Bot")
	if player_names[p] == Profile.DEFAULT_NAME:
		return tr("Player")
	if player_names[p] != "":
		return player_names[p]
	if controller.bots[0] == controller.bots[1]:
		return tr("Player %d") % (p + 1)
	return tr("You") if p == viewer() else tr("Opponent")


func _slot_x(i: int, n: int) -> float:
	return TableLayout.board_x(i, n, _gap if n == g.players[viewer()].board.size() else -1)


## What should be on the table: id -> {kind, pos, scale, rot, z, own}.
func _layout_side(p: int, own: bool, want: Dictionary) -> void:
	var pl := g.players[p]
	var hero_pos := OWN_HERO if own else ENEMY_HERO
	want[pl.hero.id] = {"kind": "hero", "pos": hero_pos}
	if not pl.hero_power.has("LOCKED"):
		want[pl.hero_power.id] = {"kind": "power", "pos": hero_pos + Vector2(150, 30)}
	if pl.weapon:
		want[pl.weapon.id] = {"kind": "weapon", "pos": hero_pos + Vector2(-100, 30)}
	for i in pl.secrets.size():
		want[pl.secrets[i].id] = {"kind": "secret", "pos": hero_pos + Vector2(-10 + 40 * i, -6 if own else 120), "hide": not own}
	var board: Array = pl.board.duplicate()
	var placing := _placing() if own else -1
	if placing >= 0:  # a minion waiting for its Battlecry target already stands in its place
		board.insert(clampi(_placing_pos(), 0, board.size()), g.ent(placing))
	var n := board.size()
	var gap := _gap if own and placing < 0 else -1
	for i in n:
		want[board[i].id] = {"kind": "minion", "pos": Vector2(TableLayout.board_x(i, n, gap), OWN_BOARD_Y if own else ENEMY_BOARD_Y)}
	var hand: Array = pl.hand.filter(func(e): return e.id != placing)
	var hover := -1
	if own:
		for i in hand.size():
			if hand[i].id == _hover_hand:
				hover = i
	var fan := TableLayout.hand(hand.size(), own, hover)
	for i in hand.size():
		var f: Dictionary = fan[i]
		if not own and i == _opp_hover:  # the card the opponent is looking at
			f = f.duplicate()
			f.pos += Vector2(-6, 46)
			f.scale = 0.62
			f.z = 20
		want[hand[i].id] = {"kind": "hand", "pos": f.pos, "scale": f.scale, "rot": f.rot, "z": f.z, "own": own}


## The minion card waiting for its Battlecry target (it stands on the board), or -1.
func _placing() -> int:
	if _sel.get("stage", "") != "target":
		return -1
	var e := g.ent(_sel.get("id", -1))
	return e.id if e and e.zone == "HAND" and e.is_minion() and e.controller == viewer() else -1


func _placing_pos() -> int:
	return _sel.get("pos", _sel.actions[0].get("pos", 0) if not _sel.actions.is_empty() else 0)


func _make_view(e: Entity, spec: Dictionary) -> EntityView:
	var v: EntityView
	match spec.kind:
		"hero":
			v = HeroView.make(e, g)
		"power":
			v = PowerView.make(e, g, PowerView.Kind.POWER)
		"weapon":
			v = PowerView.make(e, g, PowerView.Kind.WEAPON)
		"secret":
			v = PowerView.make(e, g, PowerView.Kind.SECRET, spec.get("hide", false))
		"minion":
			v = MinionView.make(e, g)
		"hand":
			var cv := CardView.make(e.card_id)
			cv.face_up = spec.own
			cv.pivot_offset = Vector2(CardView.SIZE.x / 2.0, CardView.SIZE.y)
			v = cv
	v.set_meta("kind", spec.kind)
	v.clicked.connect(_on_press)
	v.right_clicked.connect(_on_right_click)
	v.hovered.connect(_on_hover)
	return v


## Brings the views in line with the wanted layout: new views come in from where
## they start (the deck, the card that was played), others glide to their new
## place, and views of things that left the table go away.
func _reconcile(want: Dictionary) -> void:
	var from := {}
	for id in _views.keys():
		var v: EntityView = _views[id]
		if want.has(id) and v.get_meta("kind") == want[id].kind:
			continue
		_views.erase(id)
		if want.has(id):  # the same card in a new form (a card in hand became a minion)
			from[id] = v.position + v.size * v.scale / 2.0
			_drop(v, false)
		else:
			if v.has_method("sync"):
				v.sync()  # a dying minion fades out with its last numbers
			_drop(v, not _quiet.has(id))
	for id in want:
		var spec: Dictionary = want[id]
		var e := g.ent(id)
		var v: EntityView = _views.get(id)
		if v == null:
			v = _make_view(e, spec)
			_views[id] = v
			_layer.add_child(v)
			var start: Vector2 = spec.pos
			var s0 := 1.0
			if not _laid_out:
				pass
			elif from.has(id) or _moved.has(id):  # a card that became a minion, a bounced or transformed one
				start = from.get(id, _moved.get(id)) - v.size / 2.0
				s0 = 0.9
			elif spec.kind == "hand":  # drawn from the deck
				start = (_piles[0] if spec.own else _piles[1]).top() - v.pivot_offset * (1.0 - 0.6)
				s0 = 0.6
			else:
				s0 = 0.3
				start = spec.pos + v.size * 0.35
			v.position = start
			v.scale = Vector2(s0, s0)
		if v is CardView:
			v.face_up = spec.own
			if spec.own:
				v.show_entity(e, g)
		elif v is MinionView or v is HeroView or v is PowerView:
			v.sync()
		if _hold.has(id):
			continue  # an attacker in mid-leap
		if not (_dragging and id == _press.get("id", -1)):
			v.z_index = spec.get("z", 0)
		var sc: float = spec.get("scale", 1.0)
		var pos: Vector2 = spec.pos
		if spec.kind == "hand":  # fan cards turn around their bottom centre
			pos = spec.pos + Vector2(CardView.SIZE.x * sc / 2.0, CardView.SIZE.y * sc) - v.pivot_offset
		if _dragging and id == _press.get("id", -1) and spec.kind == "hand":
			continue  # the dragged card follows the mouse
		_glide(v, pos, sc, spec.get("rot", 0.0))


func _glide(v: Control, pos: Vector2, s := 1.0, rot := 0.0, dur := 0.3) -> void:
	if v.has_meta("tw"):
		var old: Tween = v.get_meta("tw")
		if old and old.is_valid():
			old.kill()
	if Anim.instant or not is_inside_tree() or (v.position == pos and v.scale.x == s and v.rotation == rot):
		v.position = pos
		v.scale = Vector2(s, s)
		v.rotation = rot
		return
	var tw := v.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "position", pos, Anim.d(dur))
	tw.tween_property(v, "scale", Vector2(s, s), Anim.d(dur))
	tw.tween_property(v, "rotation", rot, Anim.d(dur))
	v.set_meta("tw", tw)


## Removes a view; gone=true plays a fade (death, discard), false removes it at once.
func _drop(v: EntityView, gone: bool) -> void:
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Anim.instant or not gone or not is_inside_tree():
		_layer.remove_child(v)
		v.queue_free()
		return
	var tw := v.create_tween().set_parallel()
	tw.tween_property(v, "modulate:a", 0.0, Anim.d(0.45))
	tw.tween_property(v, "scale", v.scale * 0.6, Anim.d(0.45))
	tw.tween_property(v, "position", v.position + v.size * v.scale * 0.2, Anim.d(0.45))
	tw.chain().tween_callback(v.queue_free)


func _apply_glows() -> void:
	for v in _views.values():
		v.set_glow(Color.TRANSPARENT)
	_own_glows()
	# what the online opponent points at: a red mark, over this player's own glow
	var opp := 1 - viewer()
	var looked := _opp_look
	if _opp_hover >= 0 and _opp_hover < g.players[opp].hand.size():
		looked = g.players[opp].hand[_opp_hover].id
	for id in _views:
		_views[id].set_opp_mark(id == looked)
	for a in _pending_acts:  # what waits in the queue is marked as chosen
		var id: int = {"play": a.get("entity", -1), "attack": a.get("attacker", -1),
			"hero_power": g.players[viewer()].hero_power.id}.get(a.type, -1)
		if _views.has(id):
			_views[id].set_glow(Palette.SELECTED)


## This player's glows: the chosen card and its targets, or what can be played.
func _own_glows() -> void:
	var legal := _legal()
	if not _sel.is_empty():
		var sv: EntityView = _views.get(_sel.id)
		if sv:
			sv.set_glow(Palette.SELECTED)
		if _sel.get("stage", "") == "target":
			for id in _targets(_sel.actions):
				if _views.has(id):
					_views[id].set_glow(Palette.TARGET)
		return
	for a in legal:
		var id: int = {"play": a.get("entity", -1), "attack": a.get("attacker", -1),
			"hero_power": g.players[viewer()].hero_power.id}.get(a.type, -1)
		if _views.has(id):
			_views[id].set_glow(Palette.PLAYABLE)


# --- input --------------------------------------------------------------------

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if _sel.get("stage", "") == "position" and ev.position.y > OWN_BOARD_Y - 20 and ev.position.y < OWN_BOARD_Y + 140:
				click_board(_pos_from_x(ev.position.x))
			elif _views.has(_hover_hand) and ev.position.y > TableLayout.HAND_Y and _sel.is_empty():
				_on_press(_views[_hover_hand])  # below the raised card, where it was: still that card
			else:
				cancel()


func _pos_from_x(x: float) -> int:
	return TableLayout.board_index(x, g.players[viewer()].board.size())


func cancel() -> void:
	_end_drag()
	if not _sel.is_empty():
		_sel = {}
		refresh()


## Drops any drag in progress: the arrow hides and the card goes back to the hand.
func _end_drag() -> void:
	if _dragging and _views.has(_press.get("id", -1)):
		_views[_press.id].modulate.a = 1.0
	_press = {}
	_dragging = false
	_arrow.visible = false
	_gap = -1


func click_entity(id: int) -> void:
	if not my_action() or _overlay != null:
		return
	var board := g.players[viewer()].board
	var e := g.ent(id)
	if _sel.get("stage", "") == "position" and board.has(e):
		# A click on one of your minions picks the slot on that side of it.
		var i := board.find(e)
		var right: bool = get_global_mouse_position().x > _views[id].global_position.x + _views[id].size.x / 2.0
		click_board(i + 1 if right else i)
		return
	if _sel.is_empty():
		_select(id)
	elif _sel.get("stage", "") == "target" and _targets(_sel.actions).has(id):
		_sel.actions = _sel.actions.filter(func(a): return _target_of(a) == id)
		_sel.target = id
		_advance()
	elif id == _sel.id:
		cancel()
	else:
		cancel()
		_select(id)


func click_board(pos: int) -> void:
	if _sel.get("stage", "") != "position":
		return
	_sel.actions = _sel.actions.filter(func(a): return a.pos == pos)
	_sel.pos = pos
	_advance()


func _select(id: int) -> void:
	var acts := _legal().filter(func(a):
		match a.type:
			"play": return a.entity == id
			"attack": return a.attacker == id
			"hero_power": return id == g.players[viewer()].hero_power.id
		return false)
	if acts.is_empty():
		var e := g.ent(id)
		if e and e.zone == "HAND" and e.controller == viewer():
			show_hint(tr("Not enough mana") if g.cost(e) > g.players[viewer()].mana else tr("You can't play this card now"))
		elif e and e.controller == viewer() and (e.is_minion() or e.is_hero()):
			show_hint(tr("This character can't attack now"))
		return
	_sel = {"id": id, "actions": acts}
	_advance()


func _target_of(a: Dictionary) -> int:
	return a.defender if a.type == "attack" else a.target


func _targets(acts: Array) -> Array:
	var out := []
	for a in acts:
		var t := _target_of(a)
		if t >= 0 and not out.has(t):
			out.append(t)
	return out


func _advance() -> void:
	var acts: Array = _sel.actions
	if acts.is_empty():
		_sel = {}
		refresh()
		return
	var choices := []
	for a in acts:
		if a.get("choice", -1) >= 0 and not choices.has(a.choice):
			choices.append(a.choice)
	if choices.size() > 1 and not _sel.has("choice"):
		_show_choose_one(choices)
		return
	var positions := []
	for a in acts:
		if a.get("pos", -1) >= 0 and not positions.has(a.pos):
			positions.append(a.pos)
	if positions.size() > 1 and not _sel.has("pos"):
		_sel.stage = "position"
		show_hint(tr("Choose a place on the board"), 3.0)
		refresh()
		return
	if not _targets(acts).is_empty() and not _sel.has("target"):
		_sel.stage = "target"
		show_hint(tr("Choose a target"), 3.0)
		refresh()
		return
	var a: Dictionary = acts[0]
	_sel = {}
	_act(a)
	if _overlay == null:
		refresh()


func _on_end_turn() -> void:
	if _busy and tutorial != null:
		return
	if tutorial and my_action():
		var why := tutorial.end_turn_block(g, viewer())
		if why != "":
			show_hint(why, 3.0)
			return
	if my_action() and _legal().any(func(a): return a.type == "end_turn"):
		_sel = {}
		_act({"type": "end_turn", "player": viewer()})


func _on_concede() -> void:
	if g.game_over:
		_leave()
		return
	var box := _open_overlay(tr("Concede the match?"))
	_overlay.name = "ConcedeConfirm"
	var p := viewer() if not controller.bots[viewer()] else controller.actor()
	_centered_button(box, tr("Concede"), "ConfirmConcede", func():
		_close_overlay()
		controller.submit({"type": "concede", "player": p}))
	_centered_button(box, tr("Keep playing"), "KeepPlaying", _close_overlay)


## Keyword boxes beside a big card ("" hides them).
func _show_tips(card_id: String, rect: Rect2, e: Entity = null) -> void:
	if _tips:
		_tips.queue_free()
		_tips = null
	if card_id == "":
		return
	_tips = KeywordTips.make(card_id, e)
	if _tips.get_child_count() == 0:
		_tips.free()
		_tips = null
		return
	_tips.z_index = 95
	add_child(_tips)
	_tips.beside(rect)


func _on_hover(v: EntityView, on: bool) -> void:
	var e := g.ent(v.entity_id)
	if e and e.zone == "HAND" and e.controller == viewer():
		return  # the card itself rises in the hand; _track_hand_hover shows its keyword boxes
	if _tooltip:
		_tooltip.queue_free()
		_tooltip = null
	_show_tips("", Rect2())
	if not on or _dragging or _sel.get("stage", "") == "target":
		return  # no card pop-ups while aiming
	if e == null or (e.zone == "HAND" and e.controller != viewer()) or (e.zone == "SECRET" and e.controller != viewer()):
		return
	_tooltip = CardView.make(e.card_id, 1.8)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if e.zone != "SECRET":
		_tooltip.show_entity(e, g)
		_tooltip.silenced = e.silenced
	_tooltip.position = TOOLTIP_POS
	add_child(_tooltip)
	_show_tips(e.card_id, Rect2(_tooltip.position, _tooltip.size), e if e.zone == "PLAY" else null)


# --- events and effects ---------------------------------------------------------

func _on_changed(events: Array) -> void:
	if Anim.instant or not is_inside_tree():
		_effects_now(events)
		return
	_queue.append(events)
	if not _busy:
		_play_queue()


func _play_queue() -> void:
	_busy = true
	while not _queue.is_empty():
		await _animate(_queue.pop_front())
	_busy = false
	refresh()
	_release_orders()  # the next queued order starts its own animation


## Plays one batch: what happens before the change (cards shown, attacks,
## spells flying), then the change itself — the layout, numbers and sounds — at
## the moment of the hit (the attacker touches its target, the bolt arrives), or
## at the end when nothing hits.
func _animate(events: Array) -> void:
	var me := viewer()
	var hit := {"done": false}
	var your_turn := false
	var land := func() -> void:
		if hit.done:
			return
		hit.done = true
		_final_refresh = true
		_effects_now(events)
		_final_refresh = false
	for ev in events:
		match ev.type:
			"play":
				await _show_played(ev, land)
			"attack":
				await _lunge(ev.attacker, ev.defender, land)
			"hero_power":
				await _pulse(ev.entity, ev.get("target", -1), land)
			"secret_revealed":
				await _reveal(ev.card)
			"mulligan":
				if ev.player == _mull_wait and _overlay and _overlay.name == "Mulligan":
					await _mulligan_result(events, ev.player)
			"fatigue":
				await _fatigue(ev)
			"burn":
				await _burn(ev)
			"turn_start":
				your_turn = your_turn or (ev.get("player", -1) == me and ev.has("turn"))
	if not hit.done:
		await _travel(events)  # end of turn effects first, then the new turn
	land.call()
	if your_turn:
		_banner(tr("Your Turn"))
	await _wait(0.32)


## The mulligan comes back: new cards fly from the deck into the places of the
## replaced ones, the Coin appears for the second player, then the whole hand
## goes down to its place.
func _mulligan_result(events: Array, p: int) -> void:
	var slots: Dictionary = _overlay.get_meta("slots", {})
	var views: Array = _overlay.get_meta("views", [])
	var replaced: Array = _overlay.get_meta("replaced", [])
	var at := events.find_custom(func(e): return e.type == "mulligan" and e.player == p)
	var drawn := []
	for i in at:
		if events[i].type == "draw" and events[i].player == p:
			drawn.append(events[i].entity)
	var shown := []  # [entity id, view]
	for cv in views:
		if not replaced.has(cv.entity_id):
			shown.append([cv.entity_id, cv])
	for i in mini(drawn.size(), replaced.size()):
		var e := g.ent(drawn[i])
		var cv := CardView.make(e.card_id, 1.3)
		cv.show_entity(e, g)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(cv)
		cv.global_position = _piles[0].global_position
		cv.scale = Vector2(0.4, 0.4)
		var tw := cv.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(cv, "global_position", slots[replaced[i]], Anim.d(0.45)).set_delay(Anim.d(0.12 * i))
		tw.tween_property(cv, "scale", Vector2.ONE, Anim.d(0.45)).set_delay(Anim.d(0.12 * i))
		shown.append([drawn[i], cv])
	if not drawn.is_empty():
		await _wait(0.5 + 0.12 * drawn.size())
	var coin_ev: Dictionary = {}
	for ev in events:
		if ev.type == "add_to_hand" and ev.player == p and ev.card == Game.COIN:
			coin_ev = ev
	if not coin_ev.is_empty():  # the Coin turns up beside the hand, spinning in with a golden light
		var last: Vector2 = slots.values().reduce(func(a, b): return a if a.x > b.x else b, Vector2(400, 250))
		var cv := CardView.make(Game.COIN, 1.3)
		cv.show_entity(g.ent(coin_ev.entity), g)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.set_glow(Palette.SELECTED)
		_overlay.add_child(cv)
		cv.global_position = last + Vector2(CardView.SIZE.x * 1.3 + 16, 0)
		cv.pivot_offset = cv.size / 2.0
		cv.scale = Vector2(0.05, 1.0)
		var tw := cv.create_tween()
		tw.tween_property(cv, "scale", Vector2(-1.0, 1.0), Anim.d(0.2))
		tw.tween_property(cv, "scale", Vector2(1.0, 1.0), Anim.d(0.25)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Sound.play("draw")
		await _wait(0.9)
		shown.append([coin_ev.entity, cv])
	for pair in shown:  # the hand's views start where these cards are
		var cv: CardView = pair[1]
		_moved[pair[0]] = cv.global_position - global_position + cv.size * cv.scale / 2.0
		if _views.has(pair[0]):
			var old: EntityView = _views[pair[0]]
			_views.erase(pair[0])
			_layer.remove_child(old)
			old.queue_free()
	_mull_wait = -1
	_close_overlay()


## The game is over: each losing hero's portrait bursts into shards that fly
## apart and fall, then the result shows.
## The players whose heroes lost: both on a draw.
func losers() -> Array:
	return [0, 1] if g.winner < 0 else [1 - g.winner]


## The result from the local player's side: [kind, text]; kind is "victory",
## "defeat" or "draw" (the picture). Two people at one screen get the winner's number.
func result() -> Array:
	if g.winner < 0:
		return ["draw", tr("Draw")]
	if controller.remote < 0 and controller.bots[0] == controller.bots[1]:
		return ["victory", tr("Player %d wins") % (g.winner + 1)]
	return ["victory", tr("Victory!")] if g.winner == viewer() else ["defeat", tr("Defeat")]


func _shatter_losers() -> void:
	var losers := losers()
	_ending = true
	Sound.play("hit_big")
	if Match.shake_enabled:
		_shake(2.0)
	for p in losers:
		var hero := g.players[p].hero
		var v: EntityView = _views.get(hero.id)
		if v:
			var arch := Rect2(v.position + Vector2(10, 6), HeroView.SIZE - Vector2(20, 14))
			for sh in _Shard.cut(arch, Art.texture(hero.card_id)):
				_fx.add_child(sh)
			TableFx.spawn(_fx, "hurt", arch.get_center(), Color("ffb347"))
			v.modulate.a = 0.0
	await _wait(1.6)
	_ending = false
	if is_inside_tree():
		refresh()


## Fatigue: a dark card with a skull flies from the empty deck to the hero.
func _fatigue(ev: Dictionary) -> void:
	var own: bool = ev.player == viewer()
	var card := _Fatigue.new()
	card.amount = ev.amount
	card.text = tr("Fatigue")
	_fx.add_child(card)
	var pile: DeckPile = _piles[0] if own else _piles[1]
	card.position = pile.position
	card.pivot_offset = card.size / 2.0
	card.scale = Vector2(0.6, 0.6)
	var mid := Vector2(560, 250)
	var tw := card.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "position", mid, Anim.d(0.35))
	tw.parallel().tween_property(card, "scale", Vector2(1.3, 1.3), Anim.d(0.35))
	tw.tween_interval(Anim.d(0.55))
	tw.tween_property(card, "position", _center_of(g.players[ev.player].hero.id) - card.size / 2.0, Anim.d(0.25)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(card, "scale", Vector2(0.4, 0.4), Anim.d(0.25))
	tw.tween_callback(card.queue_free)
	await _wait(1.15)
	TableFx.spawn(_fx, "hurt", _center_of(g.players[ev.player].hero.id), Color("845ef7"))


## A card burnt because the hand was full: it shows, then goes up in flames.
func _burn(ev: Dictionary) -> void:
	var own: bool = ev.player == viewer()
	var cv := CardView.make(ev.card, 1.2)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(cv)
	var pile: DeckPile = _piles[0] if own else _piles[1]
	cv.position = pile.position
	cv.pivot_offset = cv.size / 2.0
	cv.scale = Vector2(0.5, 0.5)
	var tw := cv.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "position", Vector2(900, 210 if own else 120), Anim.d(0.35))
	tw.parallel().tween_property(cv, "scale", Vector2.ONE, Anim.d(0.35))
	await _wait(0.6)
	var burn := ShaderMaterial.new()  # the card burns away from its edges, with a glowing rim
	burn.shader = BURN_SHADER
	burn.set_shader_parameter("noise", MinionView._smoke())
	burn.set_shader_parameter("size", cv.size)
	burn.set_shader_parameter("progress", 0.0)
	cv.material = burn
	var fire := _Burn.new()  # a few flames licking up as it goes
	fire.size = cv.size
	fire.modulate.a = 0.55
	cv.add_child(fire)
	var out := cv.create_tween()
	out.tween_method(func(v: float): burn.set_shader_parameter("progress", v), 0.0, 1.0, Anim.d(1.1))
	out.parallel().tween_property(fire, "modulate:a", 0.0, Anim.d(1.1))
	out.tween_callback(cv.queue_free)
	show_hint(tr("Hand is full: %s burns") % CardText.name(ev.card), 1.6)
	await _wait(1.15)


## Before a change that nothing hit: the effects fly from their source (a spell,
## a Battlecry, a minion's trigger at the end or start of a turn) to each target.
func _travel(events: Array) -> void:
	var seen := {}
	await _missiles(events, seen)
	for ev in events:
		var src: int = ev.get("by_id", -1)
		var t := _event_target(ev)
		if src < 0 or t < 0 or t == src or not _views.has(t) or seen.has([src, t]):
			continue
		seen[[src, t]] = true
		var from := _center_of(src) if _views.has(src) else Vector2(640, 330)
		_shoot(from, _center_of(t), _fx_color(ev))
	if not seen.is_empty():
		await _wait(0.34)


## A card that hits random targets several times (Arcane Missiles, Avenging Wrath,
## Mad Bomber, Multi-Shot…): its hits fly one after another, each target's number
## dropping as it is hit. Deaths come after, with the rest of the change.
func _missiles(events: Array, seen: Dictionary) -> void:
	var count := {}
	for ev in events:
		if ev.type == "damage" and ev.has("by_id"):
			count[ev.by_id] = count.get(ev.by_id, 0) + 1
	for ev in events:
		var src: int = ev.get("by_id", -1)
		if ev.type != "damage" or count.get(src, 0) < 2 or not _views.has(ev.target):
			continue
		var text: Dictionary = CardDb.card(ev.by).get("text", {}) if CardDb.card(ev.by).get("text") is Dictionary else {}
		if not str(text.get("enUS", "")).to_lower().contains("random"):
			continue
		seen[[src, ev.target]] = true  # no second bolt for it in _travel
		var from := _center_of(src) if _views.has(src) else Vector2(640, 330)
		var to := _center_of(ev.target)
		_shoot(from, to, _fx_color(ev))
		await _wait(0.3)
		var v = _views.get(ev.target)
		if v is MinionView or v is HeroView:  # the number drops at once (the real state comes after)
			var hit: int = ev.amount
			if v is HeroView:
				var armor := int(v.s.tags.get("ARMOR", 0))
				v.s.tags.ARMOR = maxi(0, armor - hit)
				hit = maxi(0, hit - armor)
			v.s.damage += hit
			v.pop("hp")
			v.queue_redraw()
		TableFx.spawn(_fx, "hurt", to, _fx_color(ev))
		_float_text(ev.target, "-%d" % ev.amount, Palette.HEALTH, {})
		ev["shown"] = true  # its number already flew
		Sound.play("damage")
		await _wait(0.12)


## The entity an event happens to (-1 for none).
static func _event_target(ev: Dictionary) -> int:
	match ev.type:
		"damage", "heal", "buff", "freeze", "silence", "destroy", "take_control", "divine_shield_lost":
			return ev.get("target", -1)
		"transform":
			return ev.get("from", -1)
		"return_to_hand":
			return ev.get("entity", -1)
	return -1


## The colour of an effect: the element of the spell, else the kind of change.
func _fx_color(ev: Dictionary) -> Color:
	var by: String = ev.get("by", "")
	if by != "" and Art.design(by).kind == "spell":
		return _element_color(by)
	var kind: String = {"damage": "hurt", "heal": "heal", "buff": "buff", "freeze": "freeze", "silence": "silence",
		"destroy": "destroy", "transform": "smoke", "return_to_hand": "whoosh", "take_control": "control"}.get(ev.type, "hurt")
	return TableFx.COLORS[kind]


## A bolt that flies without being waited for.
func _shoot(a: Vector2, b: Vector2, col: Color) -> void:
	var orb := _Orb.new()
	orb.color = col
	orb.position = a
	orb.scale = Vector2(0.7, 0.7)
	_fx.add_child(orb)
	var tw := orb.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(orb, "position", b, Anim.d(0.32))
	tw.tween_callback(orb.burst)


## At the change: an effect on every minion and hero by what happened to it, and
## for the things that leave or arrive (deaths with a Deathrattle, transforms,
## summons, Battlecries, bounces).
func _impact_fx(events: Array, before: Dictionary, old: Dictionary) -> void:
	var col_of := {}
	for ev in events:
		var t := _event_target(ev)
		if t >= 0 and ev.has("by"):
			col_of[t] = _fx_color(ev)
	for id in before:
		var now := g.ent(id)
		if now == null or now.zone != "PLAY" or not _views.has(id):
			continue
		for k in TableFx.kinds(before[id], now):
			TableFx.spawn(_fx, k, _center_of(id), col_of.get(id, Color.TRANSPARENT) if k == "hurt" else Color.TRANSPARENT)
	var played := -1
	for ev in events:
		match ev.type:
			"play":
				played = ev.entity
			"death":
				var b: Entity = before.get(ev.entity)
				if old.has(ev.entity) and Cards.of(ev.card).has("deathrattle") and not (b and b.silenced):
					TableFx.spawn(_fx, "skull", old[ev.entity])
			"destroy":
				if old.has(ev.target):
					TableFx.spawn(_fx, "destroy", old[ev.target])
			"transform":
				if old.has(ev.from):
					TableFx.spawn(_fx, "smoke", old[ev.from])
			"return_to_hand":
				if old.has(ev.entity):
					TableFx.spawn(_fx, "whoosh", old[ev.entity])
			"take_control":
				if _views.has(ev.target):
					TableFx.spawn(_fx, "control", _center_of(ev.target))
			"summon":
				if ev.has("by") and _views.has(ev.entity):
					TableFx.spawn(_fx, "portal", _center_of(ev.entity))
	if played >= 0 and _views.has(played) and events.any(func(e): return e.get("by_id", -1) == played and e.type != "play"):
		TableFx.spawn(_fx, "battlecry", _center_of(played))
	var went_off := {}  # minions whose own trigger or poison acted: their mark pops, with a chime
	for ev in events:
		var src: int = ev.get("by_id", -1)
		if src < 0 or src == played or went_off.has(src) or not _views.get(src) is MinionView:
			continue
		var m := g.ent(src)
		if m and not m.silenced and (Cards.of(m.card_id).has("on") or KeywordTips.keywords_of(m.card_id).has("POISONOUS")):
			went_off[src] = true
			(_views[src] as MinionView).pop("mark")
	if not went_off.is_empty():
		Sound.play("trigger")


func _wait(t: float) -> void:
	if Anim.d(t) > 0.0 and is_inside_tree():
		await get_tree().create_timer(Anim.d(t)).timeout


func _center_of(id: int) -> Vector2:
	var v: EntityView = _views.get(id)
	return v.position + v.size * v.scale / 2.0 if v else Vector2(640, 330)


## A card is played: the opponent's card turns over in the middle of the table;
## your spells fly up and glow; a spell with a target sends its bolt.
func _show_played(ev: Dictionary, land: Callable) -> void:
	var e := g.ent(ev.entity)
	var v: EntityView = _views.get(ev.entity)
	if e == null or not v is CardView:
		return
	var own: bool = ev.get("player", -1) == viewer()
	var cv := v as CardView
	cv.z_index = 60
	if not own:
		if not ev.get("secret", false):
			cv.face_up = true
			cv.show_entity(e, g)
		_glide(cv, Vector2(560, 210) - cv.pivot_offset * 0.0, 1.2, 0.0, 0.35)
		await _wait(0.9)
	elif not e.is_minion():
		_glide(cv, Vector2(580, 200), 1.1, 0.0, 0.25)
		await _wait(0.35)
	if not e.is_minion() and ev.get("target", -1) >= 0:
		await _bolt(_center_of(ev.entity), _center_of(ev.target), _element_color(e.card_id))
		land.call()  # the spell touches its target
	if not e.is_minion() and not e.is_weapon():
		var tw := cv.create_tween().set_parallel()
		tw.tween_property(cv, "modulate:a", 0.0, Anim.d(0.25))
		tw.tween_property(cv, "scale", cv.scale * 1.3, Anim.d(0.25))
		await _wait(0.25)  # not tw.finished: the card's view may be gone by then


func _element_color(card_id: String) -> Color:
	var d := Art.design(card_id)
	if d.kind == "spell":
		return Color(Art.ELEMENT_COLORS[d.subject[0]][0])
	return Color("ffd43b")


## A glowing bolt flies from a to b.
func _bolt(a: Vector2, b: Vector2, col: Color) -> void:
	var orb := _Orb.new()
	orb.color = col
	orb.position = a
	_fx.add_child(orb)
	var tw := orb.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(orb, "position", b, Anim.d(0.32))
	await tw.finished
	orb.burst()


## The attacker leaps at its target and back; the hit lands when it touches.
func _lunge(attacker: int, defender: int, land: Callable) -> void:
	var v: EntityView = _views.get(attacker)
	if v == null:
		return
	var home := v.position
	var target := _center_of(defender) - v.size * v.scale / 2.0
	v.z_index = 40
	var tw := v.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(v, "position", home.lerp(target, 0.82), Anim.d(0.22))
	await tw.finished
	Sound.play("attack")
	if Match.shake_enabled:
		_shake()
	_hold[attacker] = true  # the layout leaves it to the leap back
	land.call()
	if _views.get(attacker) != v:  # killed by the hit: it fades out where it is
		_hold.erase(attacker)
		return
	var back := v.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	back.tween_property(v, "position", home, Anim.d(0.24))
	await back.finished
	_hold.erase(attacker)
	v.z_index = 0


## The hero power button flashes; a targeted power sends its bolt.
func _pulse(id: int, target: int, land: Callable) -> void:
	var v: EntityView = _views.get(id)
	if v == null:
		return
	v.pivot_offset = v.size / 2.0
	var tw := v.create_tween()
	tw.tween_property(v, "scale", Vector2(1.3, 1.3), Anim.d(0.14))
	tw.tween_property(v, "scale", Vector2.ONE, Anim.d(0.14))
	await tw.finished
	if target >= 0:
		await _bolt(_center_of(id), _center_of(target), _element_color(g.ent(id).card_id))
		land.call()


## A revealed Secret shows big in the middle for a moment.
func _reveal(card_id: String) -> void:
	var cv := CardView.make(card_id, 1.4)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.position = Vector2(640, 330) - cv.size / 2.0
	cv.pivot_offset = cv.size / 2.0
	cv.scale = Vector2(0.2, 0.2)
	_fx.add_child(cv)
	var tw := cv.create_tween()
	tw.tween_property(cv, "scale", Vector2.ONE, Anim.d(0.2)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(Anim.d(0.8))
	tw.tween_property(cv, "modulate:a", 0.0, Anim.d(0.25))
	tw.tween_callback(cv.queue_free)
	await _wait(0.9)


func _banner(text: String) -> void:
	var l := Palette.label(text, 54, Palette.ATTACK)
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(1280, 80)
	l.position = Vector2(0, 290)
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2(0.4, 0.4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, Anim.d(0.25)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(Anim.d(0.7))
	tw.tween_property(l, "modulate:a", 0.0, Anim.d(0.3))
	tw.tween_callback(l.queue_free)


## A shard of a shattered hero portrait: a triangle of the picture that flies off,
## spins, falls and fades.
class _Shard:
	extends Node2D
	var pts := PackedVector2Array()
	var uv := PackedVector2Array()
	var tex: Texture2D
	var vel := Vector2.ZERO
	var spin := 0.0
	var life := 1.5
	var _t := 0.0

	## Cuts rect into jagged triangles (a grid with shaken corners), each a shard.
	static func cut(rect: Rect2, tex: Texture2D) -> Array:
		var out := []
		var cols := 6
		var rows := 7
		var grid := []
		for y in rows + 1:
			var row := []
			for x in cols + 1:
				var p := Vector2(float(x) / cols, float(y) / rows)
				if x > 0 and x < cols and y > 0 and y < rows:
					p += Vector2(randf_range(-0.4, 0.4) / cols, randf_range(-0.4, 0.4) / rows)
				row.append(p)
			grid.append(row)
		var c := rect.get_center()
		for y in rows:
			for x in cols:
				var a: Vector2 = grid[y][x]
				var b: Vector2 = grid[y][x + 1]
				var d: Vector2 = grid[y + 1][x]
				var e: Vector2 = grid[y + 1][x + 1]
				for tri in [[a, b, e], [a, e, d]]:
					var sh := _Shard.new()
					var mid: Vector2 = (tri[0] + tri[1] + tri[2]) / 3.0
					sh.position = rect.position + mid * rect.size
					for q in tri:
						sh.pts.append((q - mid) * rect.size)
						sh.uv.append(q)
					sh.tex = tex
					var away := (sh.position - c).normalized()
					sh.vel = away * randf_range(140, 420) + Vector2(0, randf_range(-260, -60))
					sh.spin = randf_range(-9, 9)
					sh.life = randf_range(1.0, 1.5)
					sh.z_index = 80
					out.append(sh)
		return out

	func _process(delta: float) -> void:
		_t += delta
		vel.y += 900 * delta
		position += vel * delta
		rotation += spin * delta
		modulate.a = clampf(1.0 - _t / life, 0.0, 1.0)
		if _t >= life:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		if tex:
			draw_colored_polygon(pts, Color.WHITE, uv, tex)
		else:
			draw_colored_polygon(pts, Color("8a6d3b"))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 0.8, 0.4, 0.6), 1.0)


## The fatigue card: dark, with a skull and the damage it deals.
class _Fatigue:
	extends Control
	var amount := 1
	var text := "Fatigue"

	func _init() -> void:
		size = Vector2(100, 140)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(Palette.box(Color("1a1325"), 10, Color("6741d9"), 3), r)
		draw_style_box(Palette.box(Color("2b1d3f"), 8, Color("4c2f8a"), 1), r.grow(-7))
		var pic := Sprites.get_tex("fatigue")
		var c := Vector2(size.x / 2.0, 52)
		if pic:  # the generated picture in an arch, like a card's art
			var art := Rect2(Vector2(12, 12), Vector2(size.x - 24, 76))
			var arch := Art.outline("arch", art)
			var uv := PackedVector2Array()
			for p in arch:
				uv.append((p - art.position) / art.size)
			draw_colored_polygon(arch, Color.WHITE, uv, pic)
			Frames.ring(self, arch, Color("6741d9"), 2)
		else:  # a skull
			draw_circle(c, 22, Color("e9ecef"))
			draw_circle(c + Vector2(-8, -3), 6, Color("1a1325"))
			draw_circle(c + Vector2(8, -3), 6, Color("1a1325"))
			draw_rect(Rect2(c + Vector2(-10, 14), Vector2(20, 10)), Color("e9ecef"))
			for i in 3:
				draw_line(c + Vector2(-6 + i * 6, 15), c + Vector2(-6 + i * 6, 24), Color("1a1325"), 2)
		var f := Fonts.ui(700)
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(f, Vector2((size.x - tw) / 2.0, 100), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e5dbff"))
		Frames.attack(self, Vector2(size.x / 2.0, 122), amount, 13)


## Flames licking up a burning card.
class _Burn:
	extends Control
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		_t += d
		queue_redraw()

	func _draw() -> void:
		for i in 14:
			var x := fmod(i * 37.0, size.x)
			var h := 30.0 + 40.0 * fmod(_t * 2.0 + i * 0.37, 1.0)
			var y := size.y - fmod(_t * 160.0 + i * 23.0, size.y + 20.0)
			draw_colored_polygon(PackedVector2Array([Vector2(x - 9, y + h * 0.3), Vector2(x, y - h * 0.5), Vector2(x + 9, y + h * 0.3)]), Color(1, 0.5 + 0.3 * sin(i), 0.1, 0.8))


## A speech bubble: a round-cornered cloud with a shadow and a tail pointing at
## the hero on its right.
class _Bubble:
	extends PanelContainer

	func _init() -> void:
		var st := Palette.box(Color("fbf3df"), 22, Color("2a2118"), 3)
		st.set_content_margin_all(14)
		st.content_margin_left = 18
		st.content_margin_right = 18
		st.shadow_color = Color(0, 0, 0, 0.35)
		st.shadow_size = 6
		st.shadow_offset = Vector2(2, 4)
		add_theme_stylebox_override("panel", st)

	func _draw() -> void:  # the tail, drawn over the panel's right edge
		var y := size.y * 0.62
		var tail := PackedVector2Array([Vector2(size.x - 3, y - 12), Vector2(size.x + 26, y + 16), Vector2(size.x - 3, y + 8)])
		draw_colored_polygon(tail, Color("fbf3df"))
		draw_polyline(PackedVector2Array([tail[0], tail[1], tail[2]]), Color("2a2118"), 3.0, true)


## A soft glow behind a button (EntityView.soft_glow around its rect).
class _Halo:
	extends Control
	var color := Palette.PLAYABLE

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		EntityView.soft_glow(self, Callable(), color, Rect2(Vector2.ZERO, size), 10)


class _Orb:
	extends Control
	var color := Color.WHITE
	var _boom := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func burst() -> void:
		var tw := create_tween()
		tw.tween_property(self, "_boom", 1.0, Anim.d(0.25))
		tw.parallel().tween_property(self, "modulate:a", 0.0, Anim.d(0.25))
		tw.tween_callback(queue_free)

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var r := 14.0 + _boom * 50.0
		draw_circle(Vector2.ZERO, r * 1.6, Color(color, 0.25))
		draw_circle(Vector2.ZERO, r, color)
		draw_circle(Vector2.ZERO, r * 0.45, Color(1, 1, 1, 0.9))


func _effects_now(events: Array) -> void:
	if is_inside_tree() and not Anim.instant and events.any(func(e): return e.type == "game_over"):
		_ending = true  # the result waits for the losing hero to shatter
	var old := {}
	var before := {}  # what the minion and hero views showed before the change
	for id in _views:
		old[id] = _views[id].position + _views[id].size / 2.0
		if _views[id] is MinionView or _views[id] is HeroView:
			before[id] = _views[id].s
	for ev in events:  # a card made by a card on the table (Antonidas, Ysera) comes from it, not from the deck
		if ev.type == "add_to_hand" and _views.has(ev.get("by_id", -1)) and not _views.has(ev.entity) and not _moved.has(ev.entity):
			_moved[ev.entity] = _center_of(ev.by_id)
	for ev in events:  # the new card takes the old one's place instead of dying and arriving
		var pair: Array = {"return_to_hand": [ev.get("entity", -1), ev.get("new", -1)], "transform": [ev.get("from", -1), ev.get("to", -1)]}.get(ev.type, [])
		if not pair.is_empty() and _views.has(pair[0]):
			_moved[pair[1]] = _center_of(pair[0])
			_quiet[pair[0]] = true
	refresh()
	_moved.clear()
	_quiet.clear()
	if is_inside_tree() and not Anim.instant:
		_impact_fx(events, before, old)
		if events.any(func(e): return e.type == "game_over"):
			_shatter_losers()
	var big := false
	var hero_hit := 0  # 1: a hero took damage, 2: more than 5
	var heard := {}
	for ev in events:
		var sfx := Sound.sound_for(ev, g, viewer())
		if not heard.has(sfx):  # one copy of each sound per action
			heard[sfx] = true
			Sound.play(sfx)
		match ev.type:
			"damage":
				if ev.get("shown", false):
					continue  # shown missile by missile already
				var on_hero := g.ent(ev.target) != null and g.ent(ev.target).is_hero()
				var heavy: bool = on_hero and ev.amount > 5
				# a hero's damage shows bigger; a blow of more than 5 hits harder
				_float_text(ev.target, "-%d" % ev.amount, Palette.HEALTH, old, 58 if heavy else (44 if on_hero else 30))
				if on_hero:
					hero_hit = maxi(hero_hit, 2 if heavy else 1)
				big = big or ev.amount >= 5
			"heal":
				_float_text(ev.target, "+%d" % ev.amount, Palette.BUFFED, old)
			"armor":
				_float_text(g.players[ev.player].hero.id, "+%d" % ev.amount, Palette.ARMOR, old)
			"divine_shield_lost":
				_float_text(ev.target, tr("Shield!"), Palette.ATTACK, old)
			"secret_revealed":
				show_hint(tr("Secret: %s") % CardText.name(ev.card), 2.5)
	if hero_hit == 2:
		Sound.play("hit_big")
	if Match.shake_enabled and (big or hero_hit > 0):
		_shake(2.0 if hero_hit == 2 else 1.0)


func _float_text(id: int, text: String, color: Color, old: Dictionary, font_size := 30) -> void:
	var at: Vector2
	if _views.has(id):
		at = _views[id].position + _views[id].size / 2.0
	elif old.has(id):
		at = old[id]
	else:
		return
	if not Anim.instant:
		var splash := _Orb.new()
		splash.color = Color(color, 0.85)
		splash.position = at
		_fx.add_child(splash)
		splash.burst()
	var l := Palette.label(text, font_size, color)
	l.add_theme_constant_override("outline_size", maxi(8, font_size / 4))
	l.position = at - Vector2(font_size * 0.66, font_size * 0.66)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 40, 0.9)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9)
	tw.tween_callback(l.queue_free)


## The table shakes; strength 2 is a heavy blow (wider and longer).
func _shake(strength := 1.0) -> void:
	var tw := create_tween()
	for i in int(6 * strength):
		tw.tween_property(_layer, "position", Vector2(randf_range(-8, 8), randf_range(-6, 6)) * strength, 0.04)
	tw.tween_property(_layer, "position", Vector2.ZERO, 0.05)


# --- overlays -------------------------------------------------------------------

func _close_overlay() -> void:
	if _overlay:
		remove_child(_overlay)
		_overlay.queue_free()
		_overlay = null


func _open_overlay(title: String) -> VBoxContainer:
	_close_overlay()
	_overlay = Control.new()
	_overlay.z_index = 100  # above the hand cards
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(box)
	var t := Palette.label(title, 34, Palette.ATTACK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	add_child(_overlay)
	return box


func _card_row(box: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	return row


func _centered_button(box: VBoxContainer, text: String, name: String, fn: Callable) -> Button:
	var c := CenterContainer.new()
	var b := Palette.button(text, name)
	b.pressed.connect(fn)
	c.add_child(b)
	box.add_child(c)
	return b


func _refresh_overlay() -> void:
	if _overlay and _overlay.name == "ConnectionLost":
		return
	if g.game_over:
		if _ending:
			return  # the losing hero is still shattering; the result comes after
		if _overlay == null or _overlay.name != "GameOver":
			var res := result()
			var box := _open_overlay(res[1])
			_overlay.name = "GameOver"
			_result_look(box, res[0])
			if tutorial:
				_tutorial_result(box)
			elif arena:
				_arena_result(box)
			else:
				_centered_button(box, tr("Back to Menu"), "BackToMenu", _leave)
		return
	if g.phase == "MULLIGAN" and my_action():
		if _overlay == null or _overlay.name != "Mulligan" or _mull_wait >= 0:  # (hot-seat: the next player's)
			_mull_wait = -1
			_show_mulligan()
		return
	if _mull_wait >= 0 and _overlay and _overlay.name == "Mulligan":
		return  # chosen: waiting for the opponent, then the new cards come in
	if not g.pending.is_empty() and my_action():
		if _overlay == null or _overlay.name != "Choice":
			_show_choice()
		return
	if _overlay and _overlay.name == "ConnectionLost":
		return
	if _overlay and _overlay.name in ["Mulligan", "Choice", "GameOver"]:
		_close_overlay()


## The result screen: the picture of the result dimmed behind a big title that
## grows in (ui/sprites/result_<kind>.png, made by tools/gen_ui_art.py).
func _result_look(box: VBoxContainer, kind: String) -> void:
	var art := TextureRect.new()
	art.name = "ResultArt"
	art.set_meta("kind", kind)
	art.texture = Sprites.get_tex("result_" + kind)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.modulate.a = 0.7
	_overlay.add_child(art)
	_overlay.move_child(art, 1)  # over the dimming, under the title and buttons
	var title := box.get_child(0) as Label
	title.name = "ResultTitle"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_color", {"victory": Color("ffd75e"), "defeat": Color("c9d4e6"), "draw": Color("f0e2c0")}[kind])
	if Anim.instant:
		return
	art.modulate.a = 0.0
	create_tween().tween_property(art, "modulate:a", 0.7, Anim.d(0.8))
	title.pivot_offset = Vector2(640, 40)
	title.scale = Vector2(0.5, 0.5)
	create_tween().tween_property(title, "scale", Vector2.ONE, Anim.d(0.5)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The Arena's score under the result (it may change a moment later: the game
## is counted right after it ends) and the way back to its lobby.
func _arena_result(box: VBoxContainer) -> void:
	var line := Palette.label("", 30, Palette.TEXT)
	line.name = "ArenaScore"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(line)
	var show := func():
		if not is_instance_valid(line):
			return
		line.text = tr("Arena: you %d : %d opponent") % arena.score
		if arena.over:
			line.text += "\n" + (tr("You won the Arena!") if arena.winner == 0 else tr("You lost the Arena"))
	show.call()
	arena.changed.connect(show)
	line.tree_exiting.connect(func(): if arena.changed.is_connected(show): arena.changed.disconnect(show))
	_centered_button(box, tr("Back to the Arena"), "BackToArena", _leave)


func _tutorial_result(box: VBoxContainer) -> void:
	var n := tutorial.number
	if g.winner == viewer():
		Progress.complete(n)
		var row := _card_row(box)
		row.add_child(CardView.make(tutorial.mission.reward, 1.4))
		var line := Palette.label(tr(tutorial.mission.reward_line), 24)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(line)
		if n < Missions.count():
			_centered_button(box, tr("Next Mission"), "NextMission", func(): tutorial_next.emit(n + 1))  # main shows its intro first
	else:
		_centered_button(box, tr("Try Again"), "TryAgain", func(): tutorial_retry.emit(n))
	_centered_button(box, tr("Back"), "BackToMenu", _leave)


func _show_mulligan() -> void:
	var p := controller.actor()
	var box := _open_overlay(tr("Choose cards to replace"))
	_overlay.name = "Mulligan"
	var row := _card_row(box)
	var marked := {}
	var views := []
	var hand := g.players[p].hand
	for i in hand.size():
		var cv := CardView.make(hand[i].card_id, 1.3)
		cv.show_entity(hand[i], g)
		cv.pivot_offset = cv.size / 2.0
		cv.clicked.connect(func(v):
			v.marked = not v.marked
			marked[v.entity_id] = v.marked
			v.queue_redraw())
		row.add_child(cv)
		views.append(cv)
		if not Anim.instant:  # the cards come out one after another
			cv.scale = Vector2(0.2, 0.2)
			cv.modulate.a = 0.0
			var tw := cv.create_tween().set_parallel()
			tw.tween_property(cv, "scale", Vector2.ONE, Anim.d(0.35)).set_delay(Anim.d(0.12 * i)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(cv, "modulate:a", 1.0, Anim.d(0.2)).set_delay(Anim.d(0.12 * i))
	_centered_button(box, tr("Confirm"), "Confirm", func():
		var ids: Array = []
		for id in marked:
			if marked[id]:
				ids.append(id)
		ids.sort()
		if Anim.instant or not is_inside_tree():
			_close_overlay()
			controller.submit({"type": "mulligan", "player": p, "replace": ids})
			return
		var confirm := _overlay.find_child("Confirm", true, false) as Button
		confirm.disabled = true
		confirm.modulate.a = 0.0
		var slots := {}  # where each card stands, for the new ones to land in
		for cv in views:
			slots[cv.entity_id] = cv.global_position
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.set_meta("slots", slots)
		_overlay.set_meta("views", views)
		_overlay.set_meta("replaced", ids)
		if not ids.is_empty():  # replaced cards fly back into the deck
			for cv in views:
				if marked.get(cv.entity_id, false):
					var tw: Tween = cv.create_tween().set_parallel()
					tw.tween_property(cv, "scale", Vector2(0.3, 0.3), Anim.d(0.35))
					tw.tween_property(cv, "modulate:a", 0.0, Anim.d(0.35))
					tw.tween_property(cv, "global_position", _piles[0].global_position, Anim.d(0.35))
			await _wait(0.4)
		if _overlay == null or _overlay.name != "Mulligan" or g.players[p].mulliganed:
			return  # the timer or a lost connection got there first
		_mull_wait = p  # the overlay stays: the new cards come into it
		controller.submit({"type": "mulligan", "player": p, "replace": ids}))


func _show_choice() -> void:
	var box := _open_overlay(tr("Choose a card"))
	_overlay.name = "Choice"
	var row := _card_row(box)
	for a in g.legal_actions().filter(func(x): return x.type == "choose"):
		var e := g.ent(a.option)
		var cv := CardView.make(e.card_id, 1.3)
		cv.entity_id = e.id
		var act: Dictionary = a
		cv.clicked.connect(func(_v):
			_close_overlay()
			controller.submit(act))
		row.add_child(cv)


func _show_choose_one(choices: Array) -> void:
	var box := _open_overlay(tr("Choose One"))
	_overlay.name = "ChooseOne"
	var row := _card_row(box)
	var card := g.ent(_sel.id)
	var opts: Array = Cards.of(card.card_id).choose_one
	for c in choices:
		var cv := CardView.make(opts[c], 1.3)
		var choice: int = c
		cv.clicked.connect(func(_v):
			_close_overlay()
			_sel.choice = choice
			_sel.actions = _sel.actions.filter(func(a): return a.choice == choice)
			_advance())
		row.add_child(cv)
	_centered_button(box, tr("Cancel"), "CancelChoice", func():
		_close_overlay()
		cancel())


## Debug: the current position as JSON (also copied to the clipboard).
func show_json() -> void:
	var text := JSON.stringify(Scenario.dump(g), "  ")
	DisplayServer.clipboard_set(text)
	var box := _open_overlay(tr("Position (copied to clipboard)"))
	_overlay.name = "Json"
	var ed := TextEdit.new()
	ed.text = text
	ed.custom_minimum_size = Vector2(900, 480)
	var c := CenterContainer.new()
	c.add_child(ed)
	box.add_child(c)
	_centered_button(box, tr("Close"), "CloseJson", _close_overlay)
