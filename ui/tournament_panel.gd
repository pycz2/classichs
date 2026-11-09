class_name TournamentPanel
extends CanvasLayer
## The player's tournament match over any screen (main shows it on the server's `t_match`, like a
## friendly invite): the opponent, the series score as pips, a countdown ring to the step's
## deadline, and the step: Accept, Ban one of the opponent's decks (their classes as big tiles),
## Pick the own deck for the next game, Wait, or the match's result. Hide folds it into a chip at
## the top that opens it again. The game itself comes as the usual `match` (main hides this then).

const STEP_MS := 60000.0  # a step's time (the ring's full turn)

var link: ServerLink
## The last `t_match`: {tournament, name, match, phase, deadline, opponent, score, mine, theirs}.
var cur := {}
## The step was answered here (its buttons wait for the server's next message).
var answered := false
var folded := false
var _root := Control.new()
var _ring: Ring
var _chip: Button
var _done_left := 0.0


func _ready() -> void:
	layer = 22
	name = "TournamentPanel"
	_root.name = "PanelRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = Fonts.theme()
	add_child(_root)
	visible = false


## A `t_match` from l.
func show_match(msg: Dictionary, l: ServerLink) -> void:
	var same := str(msg.get("match")) == str(cur.get("match")) and str(msg.get("phase")) == str(cur.get("phase"))
	cur = msg
	link = l
	if not same:
		answered = false
		if str(msg.get("phase", "")) in ["accept", "ban", "pick"]:
			folded = false  # a new step to answer: open
	if str(msg.get("phase", "")) == "accept":
		l.game_deck = null  # not the last casual deck: the pick sets it
	_done_left = 8.0 if str(msg.get("phase", "")) == "done" else 0.0
	visible = true
	_build()


## The game started (or the screen needs the panel gone).
func hide_panel() -> void:
	visible = false
	cur = {}


func phase() -> String:
	return str(cur.get("phase", ""))


func me() -> String:
	return str(link.me.get("user", "")) if link else ""


func left_ms() -> int:
	return int(cur.get("deadline", 0)) - TournamentsView.now_ms()


## Wins needed in the series (the tournament's best of, when its page was seen; else the decks).
func wins_needed() -> int:
	var t: Dictionary = TournamentsView.cache.get(TournamentBracket.key(cur.get("tournament")), {})
	if not t.is_empty():
		return (int(TournamentsView.opt(t, "best_of", 1)) + 1) / 2
	var s := TournamentBracket.score(cur)
	return maxi(maxi(s[0], s[1]) + 1, 1)


func _process(delta: float) -> void:
	if not visible:
		return
	if _ring:
		_ring.left = left_ms()
		_ring.queue_redraw()
	if _chip:
		_chip.text = "  " + tr("Tournament match") + "  ·  " + _step_title() + ("  ·  " + TournamentsView.left_text(left_ms()) if phase() in ["accept", "ban", "pick"] else "")
	if _done_left > 0.0:
		_done_left -= delta
		if _done_left <= 0.0:
			hide_panel()


func _step_title() -> String:
	match phase():
		"accept":
			return tr("Your match is ready")
		"ban":
			return tr("Ban a deck")
		"pick":
			return tr("Choose your deck")
		"wait":
			return tr("Waiting for %s") % str(cur.get("opponent", ""))
		"done":
			if str(cur.get("status", "done")) not in ["done", "bye"]:  # the tournament stopped (cancelled) mid-match
				return tr("The tournament was cancelled")
			var s := TournamentBracket.score(cur)
			return tr("You won the match!") if s[0] > s[1] else tr("The match is lost")
	return ""


func _build() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_ring = null
	_chip = null
	if folded:
		_chip = Button.new()
		_chip.name = "PanelChip"
		_chip.position = Vector2(390, 6)
		_chip.size = Vector2(500, 50)
		_chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_chip.add_theme_font_size_override("font_size", 18)
		_chip.add_theme_stylebox_override("normal", Palette.frame(Color(0.12, 0.08, 0.04, 0.97), 24))
		_chip.add_theme_stylebox_override("hover", Palette.frame(Color(0.18, 0.12, 0.06, 0.97), 24))
		_chip.add_theme_stylebox_override("pressed", Palette.frame(Color(0.18, 0.12, 0.06, 0.97), 24))
		_chip.pressed.connect(func():
			folded = false
			_build())
		_root.add_child(_chip)
		return
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var p := Panel.new()
	p.name = "MatchPanel"
	p.position = Vector2(160, 40)
	p.size = Vector2(960, 640)
	p.add_theme_stylebox_override("panel", Palette.frame())
	_root.add_child(p)
	var title := Palette.label(str(cur.get("name", tr("Tournament"))), 20, Palette.MUTED)
	title.position = Vector2(30, 18)
	title.size = Vector2(700, 28)
	title.clip_text = true
	p.add_child(title)
	var step := Palette.label(_step_title(), 34, Palette.ATTACK)
	step.name = "Step"
	step.position = Vector2(30, 46)
	step.size = Vector2(740, 48)
	step.clip_text = true
	step.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	p.add_child(step)
	if phase() in ["accept", "ban", "pick"]:
		_ring = Ring.new()
		_ring.name = "Countdown"
		_ring.position = Vector2(840, 62)
		_ring.left = left_ms()
		p.add_child(_ring)
	var vs := Head.new()
	vs.name = "Versus"
	vs.position = Vector2(30, 104)
	vs.size = Vector2(900, 120)
	vs.me = me()
	vs.opponent = str(cur.get("opponent", ""))
	vs.score = TournamentBracket.score(cur)
	vs.need = wins_needed()
	p.add_child(vs)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.position = Vector2(30, 236)
	body.size = Vector2(900, 320)
	body.add_theme_constant_override("separation", 12)
	p.add_child(body)
	match phase():
		"accept":
			_note(body, tr("Accept before the time runs out, or this game is lost."))
			var a := Palette.button(tr("Accept"), "Accept")
			a.custom_minimum_size = Vector2(420, 84)
			a.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			a.add_theme_font_size_override("font_size", 30)
			a.disabled = answered
			a.pressed.connect(accept)
			body.add_child(a)
			if answered:
				_note(body, tr("Accepted: waiting for %s") % str(cur.get("opponent", "")))
			_small(body, tr("Your decks"), cur.get("mine", []))
			_small(body, tr("%s's decks") % str(cur.get("opponent", "")), cur.get("theirs", []))
		"ban":
			_note(body, tr("Ban one of %s's decks: it won't play in this match.") % str(cur.get("opponent", "")))
			_tiles(body, cur.get("theirs", []), "Theirs", true, ban)
			_small(body, tr("Your decks"), cur.get("mine", []))
		"pick":
			_note(body, tr("Choose the deck for the next game."))
			_tiles(body, cur.get("mine", []), "Mine", true, pick)
			_small(body, tr("%s's decks") % str(cur.get("opponent", "")), cur.get("theirs", []))
		"wait", "done":
			_small(body, tr("Your decks"), cur.get("mine", []))
			_small(body, tr("%s's decks") % str(cur.get("opponent", "")), cur.get("theirs", []))
	if answered and phase() in ["ban", "pick"]:
		_note(body, tr("Sent: waiting for %s") % str(cur.get("opponent", "")))
	var hide := Palette.button(tr("Hide") if phase() != "done" else tr("Close"), "Hide")
	hide.position = Vector2(700, 566)
	hide.custom_minimum_size = Vector2(230, 54)
	hide.pressed.connect(func():
		if phase() == "done":
			hide_panel()
		else:
			folded = true
			_build())
	p.add_child(hide)


func _note(parent: Control, text: String) -> void:
	var l := Palette.label(text, 19, Palette.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 900
	parent.add_child(l)


## Big tiles to tap: a deck each (its class; the own ones with their names); only usable ones.
func _tiles(parent: Control, list: Variant, id: String, own_names: bool, fn: Callable) -> void:
	var row := HFlowContainer.new()
	row.name = id
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 12)
	parent.add_child(row)
	var items: Array = list if list is Array else []
	for i in items.size():
		var d = items[i]
		if not d is Dictionary:
			continue
		var tile := TournamentsView.DeckChip.new()
		tile.name = "%s%d" % [id, i]
		tile.hero = str(d.get("hero", ""))
		tile.title = str(d.get("name", "")) if own_names and d.get("name") is String else CardText.name(tile.hero)
		tile.state = str(d.get("state", "ok"))
		tile.custom_minimum_size = Vector2(278, 118)
		tile.disabled = answered or tile.state != "ok"
		tile.pressed.connect(fn.bind(i))
		row.add_child(tile)


## A small row of decks with their states.
func _small(parent: Control, title: String, list: Variant) -> void:
	var l := Palette.label(title, 17, Palette.MUTED)
	parent.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	for d in list if list is Array else []:
		if d is Dictionary:
			var tile := TournamentsView.DeckChip.new()
			tile.hero = str(d.get("hero", ""))
			tile.title = str(d.get("name", "")) if d.get("name") is String else CardText.name(tile.hero)
			tile.state = str(d.get("state", "ok"))
			tile.custom_minimum_size = Vector2(172, 60)
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(tile)


func accept() -> void:
	link.send({"t": "t_accept", "match": TournamentsView.wire_id(cur.get("match"))})
	answered = true
	_build()


func ban(i: int) -> void:
	link.send({"t": "t_ban", "match": TournamentsView.wire_id(cur.get("match")), "deck": i})
	answered = true
	_build()


func pick(i: int) -> void:
	link.send({"t": "t_pick", "match": TournamentsView.wire_id(cur.get("match")), "deck": i})
	answered = true
	link.game_deck = own_deck(i)
	_build()


## The own deck i as given to the tournament (with its cards: the game's deck tracker), from
## the tournament's page data when it was seen.
func own_deck(i: int) -> Deck:
	var t: Dictionary = TournamentsView.cache.get(TournamentBracket.key(cur.get("tournament")), {})
	for e in t.get("entrants", []) if t.get("entrants") is Array else []:
		if e is Dictionary and str(e.get("name", "")) == me() and e.get("decks") is Array and i < e.decks.size():
			return Deck.from_dict(e.decks[i])
	return null


## The two players and the series as pips (wins needed each).
class Head:
	extends Control
	var me := ""
	var opponent := ""
	var score := [0, 0]
	var need := 1

	func _draw() -> void:
		draw_style_box(Palette.box(Color(0, 0, 0, 0.3), 14), Rect2(Vector2.ZERO, size))
		var f := get_theme_font("font", "Label")
		for i in 2:
			var who := me if i == 0 else opponent
			var cx := 90.0 if i == 0 else size.x - 90.0
			TournamentBracket.avatar(self, Vector2(cx, 48), 34, who)
			var w := minf(f.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x, 200)
			DeckTiles.text(self, Vector2(cx - w / 2.0, 108), who, 20, Palette.SELECTED if i == 0 else Palette.TEXT, 200)
			var r := 12.0
			var step := 32.0
			var total := need * step - (step - 2 * r)
			var x0 := size.x / 2.0 + (-60.0 - total if i == 0 else 60.0) + r
			for k in need:
				var c := Vector2(x0 + k * step, 52)
				var on: bool = int(score[i]) > k
				draw_circle(c, r + 2, Color(0, 0, 0, 0.6))
				draw_circle(c, r, (Palette.SELECTED if i == 0 else Color("ff8a5a")) if on else Color(0.24, 0.19, 0.14))
		var sc := "%d : %d" % [int(score[0]), int(score[1])]
		var sw := f.get_string_size(sc, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
		DeckTiles.text(self, Vector2(size.x / 2.0 - sw / 2.0, 66), sc, 36, Palette.ATTACK)
		var vs := TournamentsView._tr("vs")
		var vw := f.get_string_size(vs, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		DeckTiles.text(self, Vector2(size.x / 2.0 - vw / 2.0, 100), vs, 16, Palette.MUTED)


## The step's time: a ring that empties, the seconds in it (red at the end).
class Ring:
	extends Control
	var left := 0

	func _ready() -> void:
		custom_minimum_size = Vector2(96, 96)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(0, 0)
		var r := 40.0
		var frac := clampf(left / TournamentPanel.STEP_MS, 0.0, 1.0)
		var col := Color("ff5a4a") if left < 10000 else Palette.SELECTED
		draw_circle(c, r + 6, Color(0, 0, 0, 0.55))
		draw_arc(c, r, 0, TAU, 48, Color(0.3, 0.24, 0.16), 8, true)
		if frac > 0.0:
			draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * frac, 48, col, 8, true)
		var f := get_theme_font("font", "Label")
		var s := str(int(ceil(maxf(0, left) / 1000.0)))
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		DeckTiles.text(self, Vector2(-w / 2.0, 11), s, 30, col)
