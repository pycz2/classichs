class_name DebugTable
extends Control
## The debug tools, four tabs: Scene (build any position — heroes, mana, the
## cards in each zone, the JSON — and play it against the bot or hot-seat),
## Interaction test (a card's test from data/card_tests played in a real match),
## Card test (CardLab) and Effects test (EffectsLab).

signal start(game: Game, bots: Array)
## Play this card test (CardTests format) in a match.
signal run_test(test: Dictionary)
signal back

## Tab labels (English keys); the translation tool reads these lists.
const TABS := ["Scene", "Interaction test", "Card test", "Effects test"]
const SCENE := 0
const TESTS := 1
## Zones a clicked card can go to: [label, key].
const ZONES := [["Hand", "hand"], ["Board", "board"], ["Deck", "deck"], ["Secrets", "secrets"], ["Weapon", "weapon"]]
## A player's numbers: [label, key, max].
const STATS := [["Mana", "mana", 10], ["Max mana", "max_mana", 10], ["Damage", "damage", 29], ["Armor", "armor", 99]]
## The card list at this size leaves the right half to the players.
const LIST_SCALE := 0.7
## The right half of a page: the players, the JSON, a test's details.
const SIDE := Rect2(646, 0, 626, 620)

## The scene started last: the Scene tab opens with it again.
static var last_scene := ""
## The interaction test run last: [card id, index in its list].
static var last_test := ["", 0]

## The tab to open (set before the screen is shown).
var tab := SCENE
## The position being edited: the JSON's data.
var scene := {}
## Where a clicked card goes: [player, zone].
var target := [0, "hand"]
var editor := TextEdit.new()
var error: Label
var bot_mode: Button
var hot_seat: Button
## card id -> its tests (CardTests.load_all()).
var tests := {}
var test_card := ""
var test_list := ItemList.new()
var _pages: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _players := HBoxContainer.new()
var _json := VBoxContainer.new()
var _test_box := VBoxContainer.new()
var _steps: Label
var _first: Array[Button] = []  # "Player 1 moves" / "Player 2 moves"
var _test_error: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self)
	var bar := HBoxContainer.new()
	bar.position = Vector2(12, 8)
	bar.size = Vector2(1256, 40)
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	for i in TABS.size():
		var b := CollectionView.chip("Tab%d" % i, Vector2(0, 40))
		b.text = tr(TABS[i])
		b.pressed.connect(show_tab.bind(i))
		bar.add_child(b)
		_tab_buttons.append(b)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	var title := Palette.label(tr("Debug tools"), 22, Palette.ATTACK)
	bar.add_child(title)
	var bk := Palette.button(tr("Back"), "Back")
	bk.custom_minimum_size = Vector2(120, 40)
	bk.pressed.connect(func(): back.emit())
	bar.add_child(bk)
	for i in TABS.size():
		var page := Control.new()
		page.name = "Page%d" % i
		page.position = Vector2(0, 56)
		page.size = Vector2(1280, 664)
		page.visible = false
		add_child(page)
		_pages.append(page)
	_build_scene(_pages[SCENE])
	_build_tests(_pages[TESTS])
	show_tab(tab)


## Opens a tab; the labs are built the first time they are opened.
func show_tab(i: int) -> void:
	tab = i
	if i == 2 and _pages[2].get_child_count() == 0:
		_embed(CardLab.new(), _pages[2])
	if i == 3 and _pages[3].get_child_count() == 0:
		_embed(EffectsLab.new(), _pages[3])
	for j in _pages.size():
		_pages[j].visible = j == i
		_tab_buttons[j].set_pressed_no_signal(j == i)


func _embed(lab: Control, page: Control) -> void:
	page.add_child(lab)
	lab.find_child("Back", true, false).hide()  # the screen's own Back leaves


# --- Scene ---------------------------------------------------------------------

func _build_scene(page: Control) -> void:
	var list := CollectionView.new()
	list.name = "SceneCards"
	list.scale = Vector2(LIST_SCALE, LIST_SCALE)
	list.include_tokens = true  # tokens can be put in a scene too
	list.picked.connect(func(id): add_card(target[0], target[1], id))
	page.add_child(list)
	var col := VBoxContainer.new()
	col.position = Vector2(12, 512)
	col.size = Vector2(620, 150)
	col.add_theme_constant_override("separation", 6)
	page.add_child(col)
	var hint := Palette.label(tr("Click a card to add it to the zone marked on the right; click a card there to remove it."), 15, Palette.SELECTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)
	var modes := HFlowContainer.new()  # radio buttons: one is lit
	modes.add_theme_constant_override("h_separation", 8)
	modes.add_theme_constant_override("v_separation", 6)
	col.add_child(modes)
	var group := ButtonGroup.new()
	bot_mode = _radio("ModeBot", tr("Against the bot (you are player 1)"), group)
	hot_seat = _radio("ModeHotSeat", tr("Hot seat"), group)
	modes.add_child(bot_mode)
	modes.add_child(hot_seat)
	bot_mode.button_pressed = true

	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 10)
	buttons.add_theme_constant_override("v_separation", 6)
	col.add_child(buttons)
	var json_toggle := CollectionView.chip("JsonToggle", Vector2(0, 44))
	json_toggle.text = "JSON"
	json_toggle.toggled.connect(func(on):
		_json.visible = on
		_players.visible = not on)
	for spec in [[tr("Start"), "Start", start_game], [tr("Example"), "Example", load_example]]:
		var b := Palette.button(spec[0], spec[1])
		b.custom_minimum_size = Vector2(150, 44)
		b.pressed.connect(spec[2])
		buttons.add_child(b)
	buttons.add_child(json_toggle)
	_players.name = "Players"
	_players.position = SIDE.position
	_players.size = SIDE.size
	_players.add_theme_constant_override("separation", 12)
	page.add_child(_players)
	_json.name = "Json"
	_json.position = SIDE.position
	_json.size = SIDE.size
	_json.visible = false
	page.add_child(_json)
	editor.name = "Editor"
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.add_theme_font_size_override("font_size", 14)
	_json.add_child(editor)
	var apply := Palette.button(tr("Apply JSON"), "ApplyJson")
	apply.custom_minimum_size = Vector2(0, 44)
	apply.size_flags_horizontal = Control.SIZE_SHRINK_END
	apply.pressed.connect(apply_json)
	_json.add_child(apply)
	error = Palette.label("", 15, Palette.TARGET)
	error.name = "Error"
	error.position = SIDE.position + Vector2(0, SIDE.size.y + 4)
	error.size = Vector2(SIDE.size.x, 40)
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	page.add_child(error)
	if last_scene != "":
		editor.text = last_scene
		apply_json()
	else:
		load_example()


## A filter-style button that stays lit while on; with a group, one of the group is on.
static func _radio(id: String, text: String, group: ButtonGroup = null) -> Button:
	var b := CollectionView.chip(id, Vector2(0, 34))
	b.text = text
	b.button_group = group
	return b


func load_example() -> void:
	editor.text = FileAccess.get_file_as_string("res://data/debug_example.json")
	apply_json()


## Reads the JSON into the visual editor; false (and the reason shown) when it is broken.
func apply_json() -> bool:
	var j := JSON.new()
	if j.parse(editor.text) != OK or not j.data is Dictionary:
		error.text = tr("Invalid JSON")
		if j.get_error_line() > 0:
			error.text += " (%s %d: %s)" % [tr("line"), j.get_error_line(), j.get_error_message()]
		return false
	scene = j.data
	error.text = Scenario.build(scene).error
	_show_players()
	return true


## The scene's players as objects, or null when the JSON does not have two.
func _player(p: int) -> Variant:
	var ps = scene.get("players")
	return ps[p] if ps is Array and ps.size() == 2 and ps[p] is Dictionary else null


## The visual editor changed the scene: the JSON follows.
func _changed() -> void:
	editor.text = JSON.stringify(Scenario._ints(scene), "  ")
	error.text = Scenario.build(scene).error


## Adds a card to a player's zone (refused when the scene would break).
func add_card(p: int, zone: String, id: String) -> void:
	var pl = _player(p)
	if pl == null:
		error.text = tr("The scenario needs \"players\": a list of two objects")
		return
	if zone != "weapon" and not pl.get(zone, []) is Array:
		error.text = tr("players[%d].%s must be a list") % [p, zone]
		return
	var c := CardDb.card(id)
	if zone == "secrets" and not c.get("mechanics", []).has("SECRET"):
		error.text = tr("Only Secrets go there")
		return
	if zone == "weapon" and c.get("type", "") != "WEAPON":
		error.text = tr("Only a weapon goes there")
		return
	var was_ok: bool = Scenario.build(scene).error == ""
	var before = pl.get(zone)
	if zone == "weapon":  # one slot: a new weapon replaces the old one
		pl.weapon = id
	else:
		var list: Array = pl.get(zone, [])
		list.append(id)
		pl[zone] = list
	var why: String = Scenario.build(scene).error
	if was_ok and why != "":
		if before == null:
			pl.erase(zone)
		else:
			pl[zone] = before if zone == "weapon" else (pl[zone] as Array).slice(0, -1)
		error.text = why
		return
	_changed()
	_show_players()


func remove_card(p: int, zone: String, i: int) -> void:
	if zone == "weapon":
		_player(p).erase("weapon")
	else:
		(_player(p)[zone] as Array).remove_at(i)
	_changed()
	_show_players()


func _set_value(p: int, key: String, v: Variant) -> void:
	_player(p)[key] = v
	if key == "hero":
		_player(p).erase("hero_power")  # the new hero's own
	_changed()


static func _card_id(item: Variant) -> String:
	var id = item.get("card") if item is Dictionary else item
	return id if id is String and CardDb.has(id) else ""


## Both players' columns: hero, numbers, whose turn it is, and the cards in each zone.
func _show_players() -> void:
	var cur := int(scene.get("current", 0)) if scene.get("current", 0) is float or scene.get("current", 0) is int else 0
	_first.clear()
	var turn_group := ButtonGroup.new()
	for c in _players.get_children():
		_players.remove_child(c)
		c.queue_free()
	var group := ButtonGroup.new()
	for p in 2:
		var pl = _player(p)
		if pl == null:
			continue
		var col := VBoxContainer.new()
		col.name = "Player%d" % p
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		_players.add_child(col)
		var head := HBoxContainer.new()
		col.add_child(head)
		head.add_child(Palette.label(tr("Player %d") % (p + 1), 20, Palette.ATTACK))
		var hero := OptionButton.new()
		hero.name = "Hero"
		hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hero.clip_text = true
		var heroes: Array = CollectionView.CLASSES.slice(0, 9).map(func(c): return Decks.hero(c))
		if not pl.get("hero") in heroes and pl.get("hero") is String and CardDb.has(pl.hero):
			heroes.append(pl.hero)
		for h in heroes:
			hero.add_item(CardText.name(h))
		hero.select(heroes.find(pl.get("hero")))
		var pp: int = p
		hero.item_selected.connect(func(i): _set_value(pp, "hero", heroes[i]))
		head.add_child(hero)
		var moves := _radio("First%d" % p, tr("Player %d moves") % (p + 1), turn_group)  # whose turn the scene starts on
		moves.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		moves.button_pressed = p == cur
		moves.pressed.connect(func():
			scene["current"] = pp
			_changed())
		col.add_child(moves)
		_first.append(moves)
		var nums := GridContainer.new()
		nums.columns = 4
		nums.add_theme_constant_override("h_separation", 6)
		col.add_child(nums)
		for s in STATS:
			var l := Palette.label(tr(s[0]), 15)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nums.add_child(l)
			var spin := SpinBox.new()
			spin.name = "Stat_" + s[1]
			spin.max_value = s[2]
			spin.get_line_edit().add_theme_constant_override("minimum_character_width", 2)
			spin.value = int(pl.get(s[1], 0)) if pl.get(s[1], 0) is float or pl.get(s[1], 0) is int else 0
			var key: String = s[1]
			spin.value_changed.connect(func(v): _set_value(pp, key, int(v)))
			nums.add_child(spin)
		for z in ZONES:
			var items = pl.get(z[1], [])
			if z[1] == "weapon":
				items = [items] if items != null and _card_id(items) != "" else []
			if not items is Array:
				items = []
			var radio := _radio("Zone_" + z[1], "%s (%d)" % [tr(z[0]), items.size()], group)
			radio.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			radio.button_pressed = target == [p, z[1]]
			var where := [p, z[1]]
			radio.pressed.connect(func(): target = where)
			col.add_child(radio)
			var scroll := ScrollContainer.new()
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			if z[1] in ["secrets", "weapon"]:  # small zones: as tall as their few rows
				scroll.custom_minimum_size.y = 31 * maxi(1, items.size())
			else:
				scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			col.add_child(scroll)
			var tiles := VBoxContainer.new()
			tiles.name = "Tiles_" + z[1]
			tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tiles.add_theme_constant_override("separation", 1)
			scroll.add_child(tiles)
			for i in items.size():
				var id := _card_id(items[i])
				if id == "":
					continue
				var t := DeckTiles.DeckTile.new(id, 1)
				t.custom_minimum_size = Vector2(0, 30)
				var zone: String = z[1]
				var idx: int = i
				t.pressed.connect(func(): remove_card(pp, zone, idx))
				tiles.add_child(t)


func start_game() -> void:
	if not apply_json():
		return
	var r := Scenario.build(scene)
	if r.error != "":
		error.text = r.error
		return
	last_scene = editor.text
	start.emit(r.game, [false, true] if bot_mode.button_pressed else [false, false])


# --- Interaction test ----------------------------------------------------------

func _build_tests(page: Control) -> void:
	tests = CardTests.load_all()
	var list := CollectionView.new()
	list.name = "TestCards"
	list.scale = Vector2(LIST_SCALE, LIST_SCALE)
	list.only = tests
	list.picked.connect(pick_test_card)
	page.add_child(list)
	var only := _radio("OnlyTested", tr("Only cards with tests") + " (%d)" % tests.size())
	only.button_pressed = true
	only.position = Vector2(12, 516)
	only.toggled.connect(func(on):
		list.only = tests if on else null
		list.set_tab(list.tab))
	page.add_child(only)
	_test_box.position = SIDE.position
	_test_box.size = SIDE.size + Vector2(0, 40)
	_test_box.add_theme_constant_override("separation", 8)
	page.add_child(_test_box)
	var card_row := HBoxContainer.new()
	card_row.name = "CardRow"
	card_row.add_theme_constant_override("separation", 12)
	_test_box.add_child(card_row)
	test_list.name = "TestList"
	test_list.custom_minimum_size = Vector2(0, 150)
	test_list.item_selected.connect(func(_i): _show_steps())
	test_list.item_activated.connect(func(_i): run_selected())
	_test_box.add_child(test_list)
	_steps = Palette.label("", 15)
	_steps.name = "Steps"
	_steps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_steps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_test_box.add_child(_steps)
	_test_error = Palette.label("", 15, Palette.TARGET)
	_test_error.name = "TestError"
	_test_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_test_box.add_child(_test_error)
	var run := Palette.button(tr("Run"), "Run")
	run.custom_minimum_size = Vector2(160, 44)
	run.size_flags_horizontal = Control.SIZE_SHRINK_END
	run.pressed.connect(run_selected)
	_test_box.add_child(run)
	var first: String = last_test[0] if tests.has(last_test[0]) else (tests.keys()[0] if not tests.is_empty() else "")
	if first != "":
		list.set_tab(CardDb.card(first).get("cardClass", "NEUTRAL"))
		pick_test_card(first)
		if first == last_test[0] and int(last_test[1]) < test_list.item_count:
			test_list.select(int(last_test[1]))
			_show_steps()
	else:
		_steps.text = tr("No tests for this card")


## Shows a card and the list of its tests.
func pick_test_card(id: String) -> void:
	test_card = id
	var row := _test_box.get_node("CardRow")
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	var cv := CardView.make(id, 1.0)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cv)
	var name_label := Palette.label(CardText.name(id), 24, Palette.ATTACK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	test_list.clear()
	for t in tests.get(id, []):
		test_list.add_item("%s — %s" % [t.get("kind", "?"), t.get("title", "")])
	_test_error.text = ""
	if test_list.item_count > 0:
		test_list.select(0)
		_show_steps()
	else:
		_steps.text = tr("No tests for this card")


func selected_test() -> Dictionary:
	var sel := test_list.get_selected_items()
	if sel.is_empty() or not tests.has(test_card):
		return {}
	return tests[test_card][sel[0]]


func _show_steps() -> void:
	var t := selected_test()
	var lines: Array = []
	var steps: Array = t.get("steps", [])
	for i in steps.size():
		lines.append("%d. %s" % [i + 1, describe(steps[i])])
	_steps.text = "\n".join(lines)


## Plays the selected test in a match (its scene must build).
func run_selected() -> void:
	var t := selected_test()
	if t.is_empty():
		_test_error.text = tr("No tests for this card")
		return
	var r := Scenario.build(t.get("scene", {}) if t.get("scene") is Dictionary else {})
	if r.error != "":
		_test_error.text = r.error
		return
	last_test = [test_card, test_list.get_selected_items()[0]]
	run_test.emit(t)


## A step in a few words: "play P1 hand 1 -> P2 board 1".
static func describe(step: Variant) -> String:
	if not step is Dictionary:
		return str(step)
	var s := str(step.get("do", "?"))
	for k in ["card", "attacker", "target", "defender"]:
		if step.has(k):
			s += (" -> " if k in ["target", "defender"] else " ") + _ref(step[k])
	if step.has("choice"):
		s += " (choice %d)" % (int(step.choice) + 1)
	if step.has("option"):
		s += " %d" % (int(step.option) + 1)
	return s


static func _ref(r: Variant) -> String:
	if not r is Dictionary:
		return str(r)
	var s := "P%d %s" % [int(r.get("side", 0)) + 1, r.get("zone", "?")]
	if r.has("index"):
		s += " %d" % (int(r.index) + 1)
	return s


## Plays a card test's steps one by one in a match through its controller, with
## all animations, a pause between steps; shows the step and stops at an illegal one.
class Run:
	extends PanelContainer

	signal again

	const PAUSE := 1.0

	var test: Dictionary
	var view: MatchView
	var status: Label
	var _timer := Timer.new()

	func _init(t: Dictionary, v: MatchView) -> void:
		test = t
		view = v
		name = "TestRun"

	func _ready() -> void:
		position = Vector2(84, 50)
		custom_minimum_size = Vector2(340, 0)
		z_index = 80
		var st := Palette.box(Color(0.08, 0.05, 0.03, 0.88), 10, Color("c9a74a"), 2)
		st.set_content_margin_all(10)
		add_theme_stylebox_override("panel", st)
		_timer.one_shot = true
		add_child(_timer)  # freed with the panel: a step left waiting never comes back
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		add_child(box)
		var title := Palette.label(str(test.get("title", "")), 16, Palette.ATTACK)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(title)
		status = Palette.label("", 15)
		status.name = "RunStatus"
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(status)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		for spec in [[tr("Again"), "RunAgain", func(): again.emit()], [tr("Back"), "RunBack", func(): view.leave.emit()]]:
			var b := Palette.button(spec[0], spec[1])
			b.custom_minimum_size = Vector2(0, 38)
			b.add_theme_font_size_override("font_size", 17)
			b.pressed.connect(spec[2])
			row.add_child(b)

	## Plays every step (at once with Anim.instant).
	func play() -> void:
		var steps: Array = test.get("steps", [])
		for i in steps.size():
			await _settle()
			var step = steps[i]
			status.text = tr("Step %d of %d") % [i + 1, steps.size()] + ": " + DebugTable.describe(step)
			var a := CardTests.action(view.g, step) if step is Dictionary else {"error": "not a step"}
			var r: Dictionary = a if a.has("error") else view.controller.submit(a)
			if a.has("error") or not r.ok:
				status.text += "\n" + str(r.get("error", "?"))
				status.add_theme_color_override("font_color", Palette.TARGET)
				return
		await _settle()
		status.text = tr("Done") + " (%d)" % steps.size()

	## Waits for the table's animations, then a short pause.
	func _settle() -> void:
		while view._busy:
			_timer.start(0.1)
			await _timer.timeout
		if Anim.d(PAUSE) > 0.0:
			_timer.start(Anim.d(PAUSE))
			await _timer.timeout
