class_name ArenaView
extends Control
## The online Arena between games: the host chooses the rules (one deck for the
## whole Arena, or a new one every game, maybe with the right to keep the last
## one), then each player chooses a hero out of three, drafts 30 cards
## (three to choose from each time; the deck list on the right, the mana curve
## at the bottom left), then the lobby: ready, the score, concede, exit. The
## opponent's progress is in the upper right all the time.

signal play(game: NetSession, m: Match)
signal exit

const OFFER_SCALE := 1.75
const LIST_X := 968.0

var session: ArenaSession
## "rules", "hero", "draft", "lobby", "decide" (after a game: a new deck or the
## same) or "end" (the Arena is won, lost or broken)
var stage := ""
var curve: ManaCurve
var _body := Control.new()  # what the stage shows; rebuilt on every change
var _title: Label
var _subtitle: Label
var _status: Label
var _opponent: Label
var _tips: Control
var _score: Label  # the lobby's parts that change without a rebuild
var _ready_button: Button
var _concede_button: Button
var _rules_line: Label
var _rules_pick := "one"  # the host's choice before Start


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
	_rules_line = Palette.label("", 16, Palette.SELECTED)
	_rules_line.name = "RulesLine"
	_rules_line.position = Vector2(42, 104)
	add_child(_rules_line)
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
	if session.rules == "":
		return "rules"
	if session.deck_choice:
		return "decide"
	if session.draft.hero == "":
		return "hero"
	return "draft" if not session.draft.done() else "lobby"


func remote_text() -> String:
	var r := session.remote
	if session.remote_left:
		return tr("The opponent left")
	if not session.connected:
		return tr("Connecting…")
	if session.rules == "":
		return tr("Choosing the rules") if not session.host else tr("Waiting for your rules")
	if r.deciding:
		return tr("Deciding: a new deck or the same")
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
	_rules_line.text = rules_text()
	if session.games > 0:  # (a new draft between games: the score stays in sight)
		_rules_line.text += "   ·   " + tr("Score %d : %d") % session.score


func rules_text() -> String:
	match [session.rules, session.may_keep]:
		["one", _]:
			return tr("One deck for the whole Arena")
		["each", false]:
			return tr("A new deck for every game")
		["each", true]:
			return tr("A new deck for every game, or keep the last one")
	return ""


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
		"rules":
			_subtitle.text = tr("The Arena's rules")
			_build_rules()
		"decide":
			_subtitle.text = tr("A new deck for the next game, or the same?")
			_build_decide()
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


## The host picks the rules for both; the guest waits for them.
func _build_rules() -> void:
	if not session.host:
		var wait := Palette.label(tr("The host chooses the Arena's rules…"), 26)
		wait.position = Vector2(40, 260)
		_body.add_child(wait)
		_exit_button(Vector2(40, 642))
		return
	var row := HBoxContainer.new()
	row.position = Vector2(40, 160)
	row.add_theme_constant_override("separation", 30)
	_body.add_child(row)
	var group := ButtonGroup.new()
	var keep := CheckBox.new()
	for spec in [["one", "RulesOne", tr("One deck for the whole Arena"), tr("Draft once, then play every game of the Arena with that deck")],
			["each", "RulesEach", tr("A new deck for every game"), tr("Draft again before each game: less luck in one draft")]]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 10)
		row.add_child(col)
		var b := Palette.button(spec[2], spec[1])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = spec[0] == _rules_pick
		b.custom_minimum_size = Vector2(430, 150)
		b.add_theme_font_size_override("font_size", 26)
		var kind: String = spec[0]
		b.pressed.connect(func():
			_rules_pick = kind
			keep.disabled = kind != "each"
			if keep.disabled:
				keep.button_pressed = false)
		col.add_child(b)
		var why := Palette.label(spec[3], 18)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size.x = 430
		col.add_child(why)
	var mark := func():  # the chosen rule bright, the other dimmed
		for b in group.get_buttons():
			b.modulate = Color.WHITE if b.button_pressed else Color(0.6, 0.6, 0.6)
	group.pressed.connect(func(_b): mark.call())
	mark.call()
	keep.name = "MayKeep"
	keep.text = tr("Players may keep their deck instead of drafting again")
	keep.add_theme_font_size_override("font_size", 20)
	keep.disabled = _rules_pick != "each"
	keep.position = Vector2(500, 400)
	_body.add_child(keep)
	var go := Palette.button(tr("Start"), "StartArena")
	go.custom_minimum_size = Vector2(240, 52)
	go.position = Vector2(40, 560)
	go.pressed.connect(func():
		session.set_rules(_rules_pick, keep.button_pressed)
		_rebuild())
	_body.add_child(go)
	_exit_button(Vector2(40, 642))


## After a game when keeping is allowed: the deck just played, and the choice.
func _build_decide() -> void:
	var box := _lobby_box()
	var q := Palette.label(tr("Draft a new deck or keep this one?"), 22)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(q)
	_button(box, tr("Draft a new deck"), "NewDeck", func():
		session.new_deck()
		_rebuild())
	_button(box, tr("Keep my deck"), "KeepDeck", func():
		session.keep_deck()
		_rebuild())
	_button(box, tr("Exit to Menu"), "ExitArena", func(): exit.emit())


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
	curve = ManaCurve.new()
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
