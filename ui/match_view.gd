class_name MatchView
extends Control
## The game table. Everything on it is rebuilt from the game state after each
## action; effects (floating numbers, ghosts of dead minions, shake) come from events.
## Input flow: pick a card / attacker / hero power → (Choose One) → (position) → (target).

signal leave

const ENEMY_HERO := Vector2(575, 40)
const OWN_HERO := Vector2(575, 466)
const ENEMY_BOARD_Y := 188.0
const OWN_BOARD_Y := 336.0
const HAND_Y := 604.0
const SLOT := 104.0
const TOOLTIP_POS := Vector2(1035, 160)

var debug_mode := false
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
var _end_turn: Button
var _mana: Array[Label] = []
var _names: Array[Label] = []
var _hint: Label
var _hint_timer := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	var concede := Palette.button(tr("Concede"), "Concede")
	concede.custom_minimum_size = Vector2(130, 40)
	concede.pressed.connect(_on_concede)
	left.add_child(concede)
	_hint = Palette.label("", 20, Palette.SELECTED)
	_hint.position = Vector2(170, 306)
	_hint.size = Vector2(940, 30)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_history = HistoryPanel.new()
	_history.visible = false
	add_child(_history)


func bind(m: Match) -> void:
	controller = m
	add_child(m)
	m.changed.connect(_on_changed)
	m.finished.connect(func(_w): refresh())
	m.start()
	refresh()


func _process(delta: float) -> void:
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			_hint.text = ""


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
	var concede := find_child("Concede", false, false) as Button
	if concede:
		concede.text = tr("Menu") if g.game_over else tr("Concede")
	_apply_glows()
	_history.update_from(g, me)
	_refresh_overlay()


func _side_name(p: int) -> String:
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
	if my_action():
		_sel = {}
		controller.submit({"type": "end_turn", "player": viewer()})


func _on_concede() -> void:
	if g.game_over:
		leave.emit()
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
	for ev in events:
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
			_centered_button(box, tr("Back to Menu"), "BackToMenu", func(): leave.emit())
		return
	if g.phase == "MULLIGAN" and my_action():
		if _overlay == null or _overlay.name != "Mulligan":
			_show_mulligan()
		return
	if not g.pending.is_empty() and my_action():
		if _overlay == null or _overlay.name != "Choice":
			_show_choice()
		return
	if _overlay and _overlay.name in ["Mulligan", "Choice", "GameOver"]:
		_close_overlay()


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
