class_name MatchView
extends Control
## The game table. Everything on it is rebuilt from the game state after each
## action; effects (floating numbers, ghosts of dead minions, shake) come from events.
## Input flow: pick a card / attacker / hero power → (Choose One) → (position) → (target).

signal leave
## Tutorial: the player asked for the next mission.
signal tutorial_next(n: int)

const ENEMY_HERO := Vector2(575, 40)
const OWN_HERO := Vector2(575, 466)
const ENEMY_BOARD_Y := 188.0
const OWN_BOARD_Y := 336.0
const HAND_Y := 604.0
const SLOT := 104.0
const TOOLTIP_POS := Vector2(1035, 160)

## Fixed button texts by node name, set again when the language changes.
const LABELS := {"HistoryButton": "History", "JsonButton": "Position → JSON", "EmoteButton": "Emote",
	"MuteButton": "Mute", "SettingsButton": "Settings", "TrackerButton": "Deck Tracker"}
const EMOTES := {"greetings": "Greetings!", "well_played": "Well played!", "thanks": "Thanks.",
	"wow": "Wow!", "oops": "Oops.", "threaten": "I will destroy you!"}

var debug_mode := false
## Names shown next to the heroes ("" = You/Opponent).
var player_names: Array = ["", ""]
## Online opponent's emotes are hidden.
var muted := false
var session: NetSession
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
var _history: HistoryPanel
var _tracker: DeckTrackerPanel
var _end_turn: Button
var _mana: Array[Label] = []
var _names: Array[Label] = []
var _hint: Label
var _hint_timer := 0.0
var _bubbles := {}
var _emote_panel: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sound.music("battle")
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var board := Panel.new()
	board.add_theme_stylebox_override("panel", Palette.box(Palette.BOARD, 24, Color("2a2118"), 4))
	board.position = Vector2(150, 176)
	board.size = Vector2(980, 294)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	var mid := ColorRect.new()
	mid.color = Color(0, 0, 0, 0.25)
	mid.position = Vector2(170, 322)
	mid.size = Vector2(940, 2)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mid)
	for c in [_layer, _fx]:
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(c)
	_end_turn = Palette.button(tr("End Turn"), "EndTurn")
	_end_turn.custom_minimum_size = Vector2(140, 52)
	_end_turn.position = Vector2(1128, 310)
	_end_turn.pressed.connect(_on_end_turn)
	add_child(_end_turn)
	for i in 2:
		var l := Palette.label("", 20, Palette.MANA.lightened(0.4))
		l.position = Vector2(1128, 560 if i == 0 else 120)
		_mana.append(l)
		add_child(l)
		var n := Palette.label("", 16)
		n.position = Vector2(12, 690 if i == 0 else 8)
		_names.append(n)
		add_child(n)
	var left := VBoxContainer.new()
	left.position = Vector2(12, 250)
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	var hist := Palette.button(tr("History"), "HistoryButton")
	hist.custom_minimum_size = Vector2(130, 40)
	hist.pressed.connect(func(): _history.visible = not _history.visible)
	left.add_child(hist)
	if debug_mode:
		var js := Palette.button(tr("Position → JSON"), "JsonButton")
		js.custom_minimum_size = Vector2(130, 40)
		js.pressed.connect(show_json)
		left.add_child(js)
	var tracker := Palette.button(tr("Deck Tracker"), "TrackerButton")
	tracker.custom_minimum_size = Vector2(130, 40)
	tracker.pressed.connect(func():
		_tracker.visible = not _tracker.visible
		Settings.data.tracker = _tracker.visible
		Settings.save()
		refresh())
	left.add_child(tracker)
	var emote := Palette.button(tr("Emote"), "EmoteButton")
	emote.custom_minimum_size = Vector2(130, 40)
	emote.pressed.connect(func(): _emote_panel.visible = not _emote_panel.visible)
	left.add_child(emote)
	var mute := Palette.button(tr("Mute"), "MuteButton")
	mute.custom_minimum_size = Vector2(130, 40)
	mute.toggle_mode = true
	mute.visible = false
	mute.toggled.connect(set_muted)
	left.add_child(mute)
	var settings := Palette.button(tr("Settings"), "SettingsButton")
	settings.custom_minimum_size = Vector2(130, 40)
	settings.pressed.connect(open_settings)
	left.add_child(settings)
	var concede := Palette.button(tr("Concede"), "Concede")
	concede.custom_minimum_size = Vector2(130, 40)
	concede.pressed.connect(_on_concede)
	left.add_child(concede)
	_emote_panel = VBoxContainer.new()
	_emote_panel.position = Vector2(150, 420)
	_emote_panel.visible = false
	for id in EMOTES:
		var b := Button.new()
		b.name = "Emote_" + id
		b.text = tr(EMOTES[id])
		b.custom_minimum_size = Vector2(200, 34)
		var e: String = id
		b.pressed.connect(func():
			_emote_panel.visible = false
			send_emote(e))
		_emote_panel.add_child(b)
	add_child(_emote_panel)
	_hint = Palette.label("", 20, Palette.SELECTED)
	_hint.position = Vector2(170, 306)
	_hint.size = Vector2(940, 30)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_tracker = DeckTrackerPanel.new()
	_tracker.visible = Settings.data.tracker
	add_child(_tracker)
	_history = HistoryPanel.new()
	_history.visible = false
	add_child(_history)
	if tutorial:
		emote.visible = false
		mute.visible = false


func bind(m: Match) -> void:
	controller = m
	add_child(m)
	m.changed.connect(_on_changed)
	m.finished.connect(func(_w): refresh())
	if player_names == ["", ""] and m.bots[0] != m.bots[1]:
		var me := m.viewer()
		player_names[me] = Profile.load_name()
		player_names[1 - me] = tr("Bot") if m.bots[1 - me] else ""
		if tutorial:
			player_names[1 - me] = CardText.name(tutorial.mission.boss)
	m.start()
	refresh()


## An online match: the session (and its transport) now live under this view.
func bind_online(m: Match, s: NetSession) -> void:
	session = s
	for n in [s, s.transport]:
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
	var mute := find_child("MuteButton", true, false) as Button
	if mute:
		mute.visible = true
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


func show_emote(p: int, id: String) -> void:
	show_line(p, tr(EMOTES[id]))


## A speech bubble next to player p's hero (emotes, tutorial boss lines).
func show_line(p: int, text: String) -> void:
	if _bubbles.has(p) and is_instance_valid(_bubbles[p]):
		_bubbles[p].queue_free()
	var own := p == viewer()
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", Palette.box(Color("f4ead5"), 14, Color("2a2118"), 3))
	var l := Palette.label(text, 20, Color("2a2118"))
	var text_width := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	l.custom_minimum_size.x = minf(320.0, text_width + 8)  # set before wrapping, or the label collapses
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("outline_size", 0)
	bubble.add_child(l)
	bubble.position = (OWN_HERO + Vector2(-210, 20)) if own else (ENEMY_HERO + Vector2(-210, 40))
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bubble)
	_bubbles[p] = bubble
	Sound.speak(text)
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
	_centered_button(box, tr("Back to Menu"), "BackToMenuLost", _leave)


func _leave() -> void:
	if session:
		session.leave()
	leave.emit()


func _process(delta: float) -> void:
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_hint.text = ""
			_try_tutorial_hint()


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
	return g.legal_actions().filter(func(a): return a.player == viewer()) if my_action() else []


func show_hint(text: String, seconds := 2.0) -> void:
	_hint.text = text
	_hint_timer = seconds


# --- rendering ----------------------------------------------------------------

func open_settings() -> void:
	var s := SettingsView.new()
	s.back.connect(s.queue_free)
	s.language_changed.connect(relabel)
	add_child(s)


## Sets the fixed texts again in the current language.
func relabel() -> void:
	for n in LABELS:
		var b := find_child(n, true, false) as Button
		if b:
			b.text = tr(LABELS[n])
	for id in EMOTES:
		(_emote_panel.get_node("Emote_" + id) as Button).text = tr(EMOTES[id])
	refresh()


func refresh() -> void:
	for c in _layer.get_children():
		_layer.remove_child(c)
		c.queue_free()
	_views.clear()
	var me := viewer()
	var opp := g.opponent(me)
	_add_side(opp, false)
	_add_side(me, true)
	for i in 2:
		var p := g.players[[me, opp][i]]
		_mana[i].text = "%s %d/%d" % [tr("Mana"), p.mana, p.max_mana]
		if p.overload_locked > 0:
			_mana[i].text += " (-%d)" % p.overload_locked
		_names[i].text = "%s · %s %d · %s %d" % [_side_name(p.index), tr("Hand"), p.hand.size(), tr("Deck"), p.deck.size()]
	_end_turn.disabled = not (my_action() and g.phase == "PLAY" and g.pending.is_empty())
	_end_turn.text = tr("End Turn") if my_action() or g.game_over else tr("Enemy Turn")
	var concede := find_child("Concede", true, false) as Button
	if concede:
		concede.text = tr("Menu") if g.game_over else tr("Concede")
	_apply_glows()
	_history.update_from(g, me)
	if _tracker.visible:
		_tracker.update_from(g, me)
	_refresh_overlay()
	if tutorial:
		var line := tutorial.boss_line(g)
		if line != "":
			show_line(g.opponent(me), line)
		_try_tutorial_hint()


func _side_name(p: int) -> String:
	if player_names[p] == Profile.DEFAULT_NAME:
		return tr("Player")
	if player_names[p] != "":
		return player_names[p]
	if controller.bots[0] == controller.bots[1]:
		return tr("Player %d") % (p + 1)
	return tr("You") if p == viewer() else tr("Opponent")


func _add_view(v: EntityView, pos: Vector2) -> void:
	v.position = pos
	v.clicked.connect(func(view): click_entity(view.entity_id))
	v.hovered.connect(_on_hover)
	_layer.add_child(v)
	_views[v.entity_id] = v


func _add_side(p: int, own: bool) -> void:
	var pl := g.players[p]
	var hero_pos := OWN_HERO if own else ENEMY_HERO
	_add_view(HeroView.make(pl.hero, g), hero_pos)
	if not pl.hero_power.has("LOCKED"):
		_add_view(PowerView.make(pl.hero_power, g, PowerView.Kind.POWER), hero_pos + Vector2(150, 30))
	if pl.weapon:
		_add_view(PowerView.make(pl.weapon, g, PowerView.Kind.WEAPON), hero_pos + Vector2(-100, 30))
	for i in pl.secrets.size():
		var hide := not own  # enemy Secrets stay hidden
		_add_view(PowerView.make(pl.secrets[i], g, PowerView.Kind.SECRET, hide), hero_pos + Vector2(-10 + 40 * i, -6 if own else 120))
	var n := pl.board.size()
	var y := OWN_BOARD_Y if own else ENEMY_BOARD_Y
	for i in n:
		_add_view(MinionView.make(pl.board[i], g), Vector2(_slot_x(i, n), y))
	var hand := pl.hand
	var k := 1.0 if own else 0.55
	var step := minf(112.0 * k, (620.0 if own else 520.0) / maxf(1, hand.size()))
	var start := 640.0 - (step * (hand.size() - 1) + CardView.SIZE.x * k) / 2.0
	for i in hand.size():
		var cv := CardView.make(hand[i].card_id, k)
		cv.face_up = own
		cv.show_entity(hand[i], g)
		_add_view(cv, Vector2(start + step * i, HAND_Y if own else -48.0))


func _slot_x(i: int, n: int) -> float:
	return 640.0 - n * SLOT / 2.0 + i * SLOT + (SLOT - MinionView.SIZE.x) / 2.0


func _apply_glows() -> void:
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
			else:
				cancel()


func _pos_from_x(x: float) -> int:
	var board := g.players[viewer()].board
	for i in board.size():
		if x < _slot_x(i, board.size()) + MinionView.SIZE.x / 2.0:
			return i
	return board.size()


func cancel() -> void:
	if not _sel.is_empty():
		_sel = {}
		refresh()


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
	controller.submit(a)
	if _overlay == null:
		refresh()


func _on_end_turn() -> void:
	if tutorial and my_action():
		var why := tutorial.end_turn_block(g, viewer())
		if why != "":
			show_hint(why, 3.0)
			return
	if my_action():
		_sel = {}
		controller.submit({"type": "end_turn", "player": viewer()})


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


func _on_hover(v: EntityView, on: bool) -> void:
	if _tooltip:
		_tooltip.queue_free()
		_tooltip = null
	if not on:
		return
	var e := g.ent(v.entity_id)
	if e == null or (e.zone == "HAND" and e.controller != viewer()) or (e.zone == "SECRET" and e.controller != viewer()):
		return
	_tooltip = CardView.make(e.card_id, 1.8)
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if e.zone != "SECRET":
		_tooltip.show_entity(e, g)
	_tooltip.position = TOOLTIP_POS
	add_child(_tooltip)


# --- events and effects ---------------------------------------------------------

func _on_changed(events: Array) -> void:
	var old := {}
	for id in _views:
		old[id] = _views[id].position + _views[id].size / 2.0
	refresh()
	var big := false
	var heard := {}
	for ev in events:
		var sfx := Sound.sound_for(ev, g, viewer())
		if not heard.has(sfx):  # one copy of each sound per action
			heard[sfx] = true
			Sound.play(sfx)
		_speak_event(ev, heard)
		match ev.type:
			"damage":
				_float_text(ev.target, "-%d" % ev.amount, Palette.HEALTH, old)
				big = big or ev.amount >= 5
			"heal":
				_float_text(ev.target, "+%d" % ev.amount, Palette.BUFFED, old)
			"armor":
				_float_text(g.players[ev.player].hero.id, "+%d" % ev.amount, Palette.ARMOR, old)
			"divine_shield_lost":
				_float_text(ev.target, tr("Shield!"), Palette.ATTACK, old)
			"death":
				_ghost(ev.entity, old)
			"secret_revealed":
				show_hint(tr("Secret: %s") % CardText.name(ev.card), 2.5)
	if big and Match.shake_enabled:
		_shake()


## Legendary minions and new heroes say their name when they enter the board.
func _speak_event(ev: Dictionary, heard: Dictionary) -> void:
	var card := ""
	if ev.type in ["play", "summon"]:
		var e := g.ent(ev.entity)
		if e and e.is_minion() and CardDb.card(e.card_id).get("rarity") == "LEGENDARY":
			card = e.card_id
	elif ev.type == "hero_replaced":
		card = ev.card
	if card != "" and not heard.has(card):
		heard[card] = true
		Sound.speak(CardText.name(card))


func _float_text(id: int, text: String, color: Color, old: Dictionary) -> void:
	var at: Vector2
	if _views.has(id):
		at = _views[id].position + _views[id].size / 2.0
	elif old.has(id):
		at = old[id]
	else:
		return
	var l := Palette.label(text, 30, color)
	l.position = at - Vector2(20, 20)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 40, 0.9)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9)
	tw.tween_callback(l.queue_free)


func _ghost(id: int, old: Dictionary) -> void:
	if not old.has(id) or _views.has(id):
		return
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0.6)
	r.size = MinionView.SIZE * 0.8
	r.position = old[id] - r.size / 2.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(r)
	var tw := create_tween()
	tw.tween_property(r, "modulate:a", 0.0, 0.6)
	tw.tween_callback(r.queue_free)


func _shake() -> void:
	var tw := create_tween()
	for i in 6:
		tw.tween_property(_layer, "position", Vector2(randf_range(-8, 8), randf_range(-6, 6)), 0.04)
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
		if _overlay == null or _overlay.name != "GameOver":
			var text := tr("Draw")
			if g.winner >= 0:
				if controller.bots[0] == controller.bots[1]:
					text = tr("Player %d wins") % (g.winner + 1)
				else:
					text = tr("Victory!") if g.winner == viewer() else tr("Defeat")
			var box := _open_overlay(text)
			_overlay.name = "GameOver"
			if tutorial:
				_tutorial_result(box)
			else:
				_centered_button(box, tr("Back to Menu"), "BackToMenu", _leave)
		return
	if g.phase == "MULLIGAN" and my_action():
		if _overlay == null or _overlay.name != "Mulligan":
			_show_mulligan()
		return
	if not g.pending.is_empty() and my_action():
		if _overlay == null or _overlay.name != "Choice":
			_show_choice()
		return
	if _overlay and _overlay.name == "ConnectionLost":
		return
	if _overlay and _overlay.name in ["Mulligan", "Choice", "GameOver"]:
		_close_overlay()


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
			_centered_button(box, tr("Next Mission"), "NextMission", func(): tutorial_next.emit(n + 1))
	else:
		_centered_button(box, tr("Try Again"), "TryAgain", func(): tutorial_next.emit(n))
	_centered_button(box, tr("Back"), "BackToMenu", _leave)


func _show_mulligan() -> void:
	var p := controller.actor()
	var box := _open_overlay(tr("Choose cards to replace"))
	_overlay.name = "Mulligan"
	var row := _card_row(box)
	var marked := {}
	for e in g.players[p].hand:
		var cv := CardView.make(e.card_id, 1.3)
		cv.show_entity(e, g)
		cv.clicked.connect(func(v):
			v.marked = not v.marked
			marked[v.entity_id] = v.marked
			v.queue_redraw())
		row.add_child(cv)
	_centered_button(box, tr("Confirm"), "Confirm", func():
		var ids: Array = []
		for id in marked:
			if marked[id]:
				ids.append(id)
		ids.sort()
		_close_overlay()
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
