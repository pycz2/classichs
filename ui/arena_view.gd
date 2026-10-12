class_name ArenaView
extends Control
## The online Arena between games: choose a hero out of three, draft 30 cards
## (three to choose from each time; the deck list on the right, the mana curve
## at the bottom left), then the lobby: ready, the score, concede, exit. The
## opponent's progress is in the upper right all the time.

signal play(game: NetSession, m: Match)
signal exit

const OFFER_SCALE := 1.75
const LIST_X := 968.0

var session: ArenaSession
var stage := ""  # "hero", "draft", "lobby" or "end" (the Arena is won, lost or broken)
var curve: _Curve
var _body := Control.new()  # what the stage shows; rebuilt on every change
var _title: Label
var _subtitle: Label
var _status: Label
var _opponent: Label
var _tips: Control
var _score: Label  # the lobby's parts that change without a rebuild
var _ready_button: Button
var _concede_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self, "library_bg")
	_title = Palette.label(tr("Arena"), 40, Palette.ATTACK)
	_title.position = Vector2(40, 18)
	add_child(_title)
	_subtitle = Palette.label("", 22)
	_subtitle.position = Vector2(42, 72)
	add_child(_subtitle)
	var panel := PanelContainer.new()
	panel.position = Vector2(LIST_X, 14)
	panel.custom_minimum_size = Vector2(292, 0)
	panel.add_theme_stylebox_override("panel", Palette.box(Color(0.08, 0.06, 0.04, 0.85), 10, Color("6b5320"), 2))
	add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	_opponent = Palette.label("", 18, Palette.ATTACK)
	_opponent.name = "OpponentName"
	col.add_child(_opponent)
	_status = Palette.label("", 16)
	_status.name = "OpponentStatus"
	col.add_child(_status)
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	session.changed.connect(_refresh)
	session.failed.connect(func(_r): _refresh())
	session.game_started.connect(func(g, m): play.emit(g, m))
	_rebuild()


func _stage() -> String:
	if session.over or session.failure != "":
		return "end"
	if session.draft.hero == "":
		return "hero"
	return "draft" if not session.draft.done() else "lobby"


func remote_text() -> String:
	var r := session.remote
	if session.remote_left:
		return tr("The opponent left")
	if not session.connected:
		return tr("Connecting…")
	if not r.hero:
		return tr("Choosing a hero")
	if r.cards < ArenaDraft.PICKS:
		return tr("Drafting: %d / 30 cards") % r.cards
	return tr("Ready to play") if r.ready else tr("Deck ready")


## The session changed (the opponent's progress, the score, the end): only what
## changed is redrawn, so the cards being chosen and an open question stay.
func _refresh() -> void:
	if not is_inside_tree():
		return
	_update_status()
	if _stage() != stage:
		_rebuild()
	elif stage == "lobby":
		_update_lobby()


func _update_status() -> void:
	var name_text := session.remote_name if session.remote_name != "" else tr("Opponent")
	_opponent.text = tr("Opponent: %s") % name_text
	_status.text = remote_text()


## Builds the whole stage again (a new stage, or this player's own pick).
func _rebuild() -> void:
	if not is_inside_tree():
		return
	stage = _stage()
	_update_status()
	_hide_tips()
	for c in _body.get_children():  # freed later: a pressed card may still be in its signal
		_body.remove_child(c)
		c.queue_free()
	match stage:
		"hero":
			_subtitle.text = tr("Choose your hero")
			_build_heroes()
		"draft":
			_subtitle.text = tr("Choose a card: pick %d of 30") % (session.draft.cards.size() + 1)
			_build_draft()
		"lobby":
			_subtitle.text = tr("Your Arena deck is ready")
			_build_lobby()
		"end":
			_subtitle.text = ""
			_build_end()


func _build_heroes() -> void:
	var row := HBoxContainer.new()
	row.position = Vector2((1280 - 3 * 322 - 2 * 16) / 2.0, 250)
	row.add_theme_constant_override("separation", 16)
	_body.add_child(row)
	for i in 3:
		var cls := Decks.card_class(session.draft.heroes[i])
		var t := TrainingSetup.HeroTile.new(cls)
		t.name = "Hero_" + cls
		t.toggle_mode = false
		t.pressed.connect(choose_hero.bind(i))
		row.add_child(t)
	_exit_button(Vector2(40, 642))


## Leaves the Arena (before the lobby too): the opponent wins it.
func _exit_button(at: Vector2) -> void:
	var b := Palette.button(tr("Exit to Menu"), "ExitArena")
	b.custom_minimum_size = Vector2(240, 48)
	b.position = at
	b.pressed.connect(func(): exit.emit())
	_body.add_child(b)


func choose_hero(i: int) -> void:
	session.draft.choose_hero(i)
	session.send_status()
	_rebuild()


func _build_draft() -> void:
	var w := CardView.SIZE.x * OFFER_SCALE
	var gap := 44.0
	var x0 := (LIST_X - (3 * w + 2 * gap)) / 2.0
	for i in session.draft.offer.size():
		var cv := CardView.make(session.draft.offer[i], OFFER_SCALE)
		cv.name = "Offer%d" % i
		cv.position = Vector2(x0 + i * (w + gap), 120)
		cv.clicked.connect(func(_v): pick(i))
		cv.hovered.connect(func(v, on): _on_hover(v, on))
		_body.add_child(cv)
		if not Anim.instant:  # the three cards come in one after another
			cv.modulate.a = 0.0
			cv.position.y += 30
			var tw := cv.create_tween().set_parallel()
			tw.tween_property(cv, "modulate:a", 1.0, Anim.d(0.25)).set_delay(Anim.d(0.08 * i))
			tw.tween_property(cv, "position:y", 120.0, Anim.d(0.3)).set_delay(Anim.d(0.08 * i)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var rarity := Palette.label(_rarity_text(), 18, Palette.TEXT)
	rarity.name = "Rarity"
	rarity.position = Vector2(x0, 440)
	_body.add_child(rarity)
	_build_deck_side()
	_exit_button(Vector2(470, 650))


func _rarity_text() -> String:
	if session.draft.offer.is_empty():
		return ""
	return {"common": tr("Common"), "rare": tr("Rare"), "epic": tr("Epic"), "legendary": tr("Legendary")}[ArenaDraft.tier(session.draft.offer[0])]


func pick(i: int) -> void:
	session.draft.pick(i)
	session.send_status()
	_rebuild()


## The deck list on the right, the card count and the mana curve at the bottom left.
func _build_deck_side() -> void:
	var head := Palette.label(CardText.name(session.draft.hero), 20, Palette.ATTACK)
	head.position = Vector2(LIST_X, 92)
	_body.add_child(head)
	var picks := Palette.label("%d / 30" % session.draft.cards.size(), 20)
	picks.name = "Picks"
	picks.position = Vector2(LIST_X + 210, 92)
	_body.add_child(picks)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(LIST_X, 124)
	scroll.size = Vector2(292, 586)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	for it in session.draft.deck().sorted_counts():
		var t := DeckTiles.DeckTile.new(it[0], it[1])
		t.custom_minimum_size.x = 280
		list.add_child(t)
	curve = _Curve.new()
	curve.name = "Curve"
	curve.counts = session.draft.curve()
	curve.position = Vector2(40, 520)
	curve.size = Vector2(380, 180)
	_body.add_child(curve)


func _build_lobby() -> void:
	var box := _lobby_box()
	_ready_button = _button(box, tr("Ready"), "Ready", func():
		session.set_ready()
		_update_lobby())
	_concede_button = _button(box, tr("Concede the Arena"), "ConcedeArena", _confirm_concede)
	_button(box, tr("Exit to Menu"), "ExitArena", func(): exit.emit())
	_update_lobby()


## Ready waits for the opponent, and nothing else can be done while a game starts.
func _update_lobby() -> void:
	_score.text = "%d : %d" % session.score
	var waiting := session.is_ready or session.game != null
	_ready_button.text = tr("Waiting for the opponent…") if waiting else tr("Ready")
	_ready_button.disabled = waiting
	_concede_button.disabled = session.game != null


## The end of the Arena: won, lost, or broken (and why), and the way out.
func _build_end() -> void:
	var box := _lobby_box()
	var res := Palette.label(_result_text(), 34, Palette.ATTACK)
	res.name = "ArenaResult"
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(res)
	if not session.over:
		var why := Palette.label(session.failure, 18)
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size.x = 440
		box.add_child(why)
	_button(box, tr("Exit to Menu"), "ExitArena", func(): exit.emit())


## The hero, the deck and the score; returns the column for the buttons.
func _lobby_box() -> VBoxContainer:
	if session.draft.hero != "":  # (the Arena may end while a hero is being chosen)
		_build_deck_side()
		var me := TrainingSetup.HeroTile.new(Decks.card_class(session.draft.hero))
		me.name = "MyHero"
		me.toggle_mode = false
		me.disabled = true
		me.custom_minimum_size = Vector2(380, 170)
		_body.add_child(me)
		me.position = Vector2(40, 150)
		me.size = me.custom_minimum_size  # in the tree: the class emblem follows the size
	return _score_box()


func _score_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.position = Vector2(470, 150)
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 14)
	_body.add_child(box)
	var you := Palette.label(tr("You") + "   —   " + (session.remote_name if session.remote_name != "" else tr("Opponent")), 20)
	you.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(you)
	_score = Palette.label("%d : %d" % session.score, 64, Palette.ATTACK)
	_score.name = "Score"
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_score)
	var rule := Palette.label(tr("First to %d wins takes the Arena") % ArenaSession.WINS, 16)
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(rule)
	return box


func _result_text() -> String:
	if session.over:
		return tr("You won the Arena!") if session.winner == 0 else tr("You lost the Arena")
	return tr("The Arena ended")


func _button(box: Container, text: String, id: String, fn: Callable) -> Button:
	var c := CenterContainer.new()
	var b := Palette.button(text, id)
	b.custom_minimum_size = Vector2(320, 48)
	b.pressed.connect(fn)
	c.add_child(b)
	box.add_child(c)
	return b


func _confirm_concede() -> void:
	var dim := ColorRect.new()
	dim.name = "ConcedeDialog"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	dim.add_child(box)
	var q := Palette.label(tr("Concede the Arena? The opponent wins it."), 28, Palette.ATTACK)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(q)
	_button(box, tr("Concede"), "ConfirmConcedeArena", func():
		session.concede()
		_rebuild())
	_button(box, tr("Keep playing"), "KeepPlayingArena", func(): dim.queue_free())


func _on_hover(v: EntityView, on: bool) -> void:
	_hide_tips()
	if not on or not v is CardView:
		return
	_tips = KeywordTips.make((v as CardView).card_id)
	if _tips.get_child_count() == 0:
		_tips.free()
		_tips = null
		return
	add_child(_tips)
	_tips.beside(Rect2(v.global_position, v.size * v.scale))


func _hide_tips() -> void:
	if _tips and is_instance_valid(_tips):
		_tips.queue_free()
	_tips = null


## The mana curve: how many cards of each cost (0 … 6, 7+), as bars.
class _Curve:
	extends Control
	var counts: Array = [0, 0, 0, 0, 0, 0, 0, 0]

	func _draw() -> void:
		var top := maxi(4, counts.max())
		var bw := size.x / 8.0
		var base := size.y - 26
		var font := get_theme_default_font()
		draw_style_box(Palette.box(Color(0.08, 0.06, 0.04, 0.7), 10, Color("6b5320"), 2), Rect2(Vector2(-12, -34), size + Vector2(24, 40)))
		draw_string(font, Vector2(0, -12), tr("Mana curve"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.ATTACK)
		for i in 8:
			var h: float = (base - 20) * counts[i] / float(top)
			var r := Rect2(i * bw + 6, base - h, bw - 12, h)
			if counts[i] > 0:
				draw_rect(r, Color("3b82c4"))
				draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color("9fd0ff"))
				draw_string(font, Vector2(i * bw, r.position.y - 4), str(counts[i]), HORIZONTAL_ALIGNMENT_CENTER, bw, 15, Palette.TEXT)
			draw_string(font, Vector2(i * bw, size.y - 6), "7+" if i == 7 else str(i), HORIZONTAL_ALIGNMENT_CENTER, bw, 16, Color("9fd0ff"))
