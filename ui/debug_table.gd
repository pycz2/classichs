class_name DebugTable
extends Control
## The debug tools, four tabs: Scene (build any position — heroes and hero cards, their Hero Powers, mana, the
## cards in each zone with any of the pack's keywords, tags, damage and buffs, the JSON — and play it against
## the bot or hot-seat), Interaction test (every card's scenarios — CardScenarios: generic ones from its
## mechanics and the hand-written ones — played in a real match, marked passed / failed / with a note, and the
## walk through the whole pack with a checklist per card, its marks exported as JSON), Card test (CardLab) and
## Effects test (EffectsLab).

## A game from the scene: the engine's `new` request ({scenario}) and who the bots are.
signal start(req: Dictionary, bots: Array)
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
## A scenario's marks: [mark, button label, colour].
const MARKS := [["passed", "Passed", Color("69db7c")], ["failed", "Failed", Color("ff6b6b")], ["note", "Note", Color("ffd43b")]]
## The card list at this size leaves the right half to the players.
const LIST_SCALE := 0.7
## The right half of a page: the players, the JSON, a test's details.
const SIDE := Rect2(646, 0, 626, 620)
## Where the marks go for an agent (and the clipboard).
const EXPORT_PATH := "user://card_marks_export.json"

## The scene started last: the Scene tab opens with it again.
static var last_scene := ""
## The scenario run last: [card id, index in its list].
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
## card id -> its hand-written tests (CardTests.load_all()).
var tests := {}
var test_card := ""
## The card's scenarios (CardScenarios.for_card) as listed.
var scenarios: Array = []
var test_list := ItemList.new()
## The cards of the pack in the walk's order.
var walk: Array = []
var _pages: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _players := HBoxContainer.new()
var _json := VBoxContainer.new()
var _test_box := VBoxContainer.new()
var _steps: Label
var _first: Array[Button] = []  # "Player 1 moves" / "Player 2 moves"
var _test_error: Label
var _note := LineEdit.new()
var _walk_info: Label
var _checks := GridContainer.new()
var _item_editor: PanelContainer
var _test_cards: CollectionView


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
	var hint := Palette.label(tr("Click a card to add it to the zone marked on the right; click a card there to change or remove it."), 15, Palette.SELECTED)
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
	error.text = Rules.scenario_error(scene)
	_show_players()
	return true


## The scene's players as objects, or null when the JSON does not have two.
func _player(p: int) -> Variant:
	var ps = scene.get("players")
	return ps[p] if ps is Array and ps.size() == 2 and ps[p] is Dictionary else null


## The visual editor changed the scene: the JSON follows.
func _changed() -> void:
	editor.text = JSON.stringify(Rules.ints(scene.duplicate(true)), "  ")
	error.text = Rules.scenario_error(scene)


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
	if zone == "secrets" and not (c.get("mechanics", []).has("SECRET") or c.get("mechanics", []).has("QUEST")):
		error.text = tr("Only Secrets and Quests go there")
		return
	if zone == "weapon" and c.get("type", "") != "WEAPON":
		error.text = tr("Only a weapon goes there")
		return
	var was_ok: bool = Rules.scenario_error(scene) == ""
	var before = pl.get(zone)
	if zone == "weapon":  # one slot: a new weapon replaces the old one
		pl.weapon = id
	else:
		var list: Array = pl.get(zone, [])
		list.append(id)
		pl[zone] = list
	var why: String = Rules.scenario_error(scene)
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
	_close_item()
	_changed()
	_show_players()


func _set_value(p: int, key: String, v: Variant) -> void:
	_player(p)[key] = v
	if key == "hero":  # the new hero's own power; a hero card's from its card
		_player(p).erase("hero_power")
		if not Decks.heroes().values().has(v) and CardDb.has(str(CardDb.card(v).get("power", ""))):
			_player(p).hero_power = str(CardDb.card(v).power)
	if key == "hero_power" and v == "":
		_player(p).erase("hero_power")
	_changed()


static func _card_id(item: Variant) -> String:
	var id = item.get("card") if item is Dictionary else item
	return id if id is String and CardDb.has(id) else ""


## The heroes a scene may have: the classes' and every hero card of the pack.
static func hero_choices() -> Array:
	var out: Array = Decks.heroes().values()
	var cards := CardDb.all_ids().filter(func(id): return CardDb.card(id).get("type") == "HERO" and not out.has(id))
	cards.sort_custom(func(a, b): return CardText.name(a) < CardText.name(b))
	return out + cards


## Every Hero Power of the pack ("" first: the hero's own).
static func power_choices() -> Array:
	var out := CardDb.all_ids().filter(func(id): return CardDb.card(id).get("type") == "HERO_POWER")
	out.sort_custom(func(a, b): return CardText.name(a) < CardText.name(b))
	return [""] + out


## Both players' columns: hero, Hero Power, numbers, whose turn it is, and the cards in each zone.
func _show_players() -> void:
	var cur := int(scene.get("current", 0)) if scene.get("current", 0) is float or scene.get("current", 0) is int else 0
	_first.clear()
	var turn_group := ButtonGroup.new()
	for c in _players.get_children():
		_players.remove_child(c)
		c.queue_free()
	var group := ButtonGroup.new()
	var heroes := hero_choices()
	var powers := power_choices()
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
		var pp: int = p
		var mine: Array = heroes.duplicate()
		if not pl.get("hero") in mine and pl.get("hero") is String and CardDb.has(pl.hero):
			mine.append(pl.hero)
		head.add_child(_pick("Hero", mine, pl.get("hero"), func(i): _set_value(pp, "hero", mine[i])))
		var hp_row := HBoxContainer.new()
		col.add_child(hp_row)
		hp_row.add_child(Palette.label(tr("Hero Power"), 15))
		var hp = pl.get("hero_power", "")
		var hp_id: String = _card_id(hp) if hp is Dictionary else str(hp)
		hp_row.add_child(_pick("HeroPower", powers, hp_id, func(i): _set_value(pp, "hero_power", powers[i])))
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
				if items[i] is Dictionary and items[i].size() > 1:  # changed from the card: marked
					t.modulate = Palette.SELECTED
				var zone: String = z[1]
				var idx: int = i
				t.pressed.connect(func(): edit_item(pp, zone, idx))
				tiles.add_child(t)


## A drop-down of cards (by name; "" is the hero's own power) with one selected.
func _pick(id: String, cards: Array, selected: Variant, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.name = id
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.clip_text = true
	for c in cards:
		o.add_item(CardText.name(c) if c != "" else tr("The hero's own"))
	o.select(cards.find(selected if selected is String else ""))
	o.item_selected.connect(on_pick)
	return o


# --- One card of the scene: its keywords, tags, damage, buffs ------------------

## The scene's item as an object (a plain id becomes {"card": id}), so it can carry changes.
func item_spec(p: int, zone: String, i: int) -> Dictionary:
	var pl: Dictionary = _player(p)
	var it = pl.get("weapon") if zone == "weapon" else pl[zone][i]
	if not it is Dictionary:
		it = {"card": it}
		if zone == "weapon":
			pl.weapon = it
		else:
			pl[zone][i] = it
	return it


## A tag's number on an item: 0 without it, 1 for a plain tag.
static func tag_value(spec: Dictionary, tag: String) -> int:
	for t in spec.get("tags", []):
		if t is String and t == tag:
			return 1
		if t is Dictionary and t.has(tag):
			return int(t[tag])
	return 0


## Sets a tag's number on an item (0 takes it off; 1 is a plain tag).
static func set_tag(spec: Dictionary, tag: String, n: int) -> void:
	var tags: Array = spec.get("tags", []).filter(func(t): return not (t is String and t == tag) and not (t is Dictionary and t.has(tag)))
	if n == 1:
		tags.append(tag)
	elif n != 0:
		tags.append({tag: n})
	spec.tags = tags
	if tags.is_empty():
		spec.erase("tags")


## The tags a scene's card may get: every mechanic of the active pack (its names).
static func pack_tags() -> Array:
	var m = Packs.active().rules().get("mechanics", {}) if Packs.active() else {}
	var out: Array = m.keys() if m is Dictionary else []
	out.sort()
	return out


## A tag's name for the editor: the pack's word for it (in the player's language), and the tag.
static func tag_label(tag: String) -> String:
	var n := KeywordTips.name_of(Packs.client_name(tag))
	return tag if n == "" else "%s (%s)" % [n, tag]


func _close_item() -> void:
	if _item_editor:
		_item_editor.queue_free()
		_item_editor = null


## Opens the editor of one card of the scene: remove it, or give it any of the pack's tags (a number too:
## Spell Damage N), damage, +Attack/+Health, a Deathrattle of another card, Silence, asleep.
func edit_item(p: int, zone: String, i: int) -> void:
	_close_item()
	var spec := item_spec(p, zone, i)
	var panel := PanelContainer.new()
	panel.name = "ItemEditor"
	panel.position = Vector2(150, 40)
	panel.size = Vector2(980, 600)
	var st := Palette.box(Color(0.08, 0.05, 0.03, 0.97), 12, Color("c9a74a"), 2)
	st.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", st)
	_pages[SCENE].add_child(panel)
	_item_editor = panel
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	var zone_name: String = ZONES.filter(func(z): return z[1] == zone)[0][0]
	var name_l := Palette.label("%s — %s, %s" % [CardText.name(spec.card), tr("Player %d") % (p + 1), tr(zone_name)], 20, Palette.ATTACK)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	head.add_child(name_l)
	for b_spec in [[tr("Remove"), "RemoveItem", func(): remove_card(p, zone, i)], [tr("Close"), "CloseItem", _close_item]]:
		var b := Palette.button(b_spec[0], b_spec[1])
		b.custom_minimum_size = Vector2(130, 40)
		b.pressed.connect(b_spec[2])
		head.add_child(b)
	var changed := func():
		_changed()
		_show_players()
	var nums := HFlowContainer.new()
	nums.add_theme_constant_override("h_separation", 10)
	nums.add_theme_constant_override("v_separation", 6)
	box.add_child(nums)
	var buff: Dictionary = {}
	for e in spec.get("enchantments", []):
		if e is Dictionary and e.get("debug", false):
			buff = e
	for n_spec in [[tr("Damage"), "damage", 0, 99], [tr("Attack +"), "atk", -20, 99], [tr("Health +"), "hp", -20, 99]]:
		nums.add_child(Palette.label(n_spec[0], 15))
		var spin := SpinBox.new()
		spin.name = "Item_" + n_spec[1]
		spin.min_value = n_spec[2]
		spin.max_value = n_spec[3]
		var key: String = n_spec[1]
		spin.value = int(spec.get("damage", 0)) if key == "damage" else int(buff.get(key, 0))
		spin.value_changed.connect(func(v):
			if key == "damage":
				spec.damage = int(v)
			else:
				_set_buff(spec, key, int(v))
			changed.call())
		nums.add_child(spin)
	for f_spec in [[tr("Silenced"), "silenced"], [tr("Asleep"), "exhausted"]]:
		if f_spec[1] == "exhausted" and zone != "board":
			continue
		var check := CheckBox.new()
		check.name = "Item_" + f_spec[1]
		check.text = f_spec[0]
		var key: String = f_spec[1]
		check.button_pressed = bool(spec.get(key, false))
		check.toggled.connect(func(on):
			if on:
				spec[key] = true
			else:
				spec.erase(key)
			changed.call())
		nums.add_child(check)
	var dr_row := HBoxContainer.new()
	dr_row.add_theme_constant_override("separation", 8)
	box.add_child(dr_row)
	dr_row.add_child(Palette.label(tr("Given Deathrattle (card id or name)"), 15))
	var dr := LineEdit.new()
	dr.name = "Item_deathrattle"
	dr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for e in spec.get("enchantments", []):
		if e is Dictionary and e.has("deathrattle"):
			dr.text = str(e.deathrattle)
	dr.text_submitted.connect(func(t):
		dr.text = give_deathrattle(spec, t)
		changed.call())
	dr_row.add_child(dr)
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	box.add_child(tag_row)
	var tag_hint := Palette.label(tr("Tags of the pack: a click switches one on with this number (Spell Damage, a Quest's progress)"), 15, Palette.SELECTED)
	tag_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_row.add_child(tag_hint)
	var value := SpinBox.new()
	value.name = "TagValue"
	value.min_value = -99
	value.max_value = 99
	value.value = 1
	tag_row.add_child(value)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var chips := HFlowContainer.new()
	chips.name = "Tags"
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	scroll.add_child(chips)
	for tag in pack_tags():
		var chip := CollectionView.chip("Tag_" + tag, Vector2(0, 34))
		var n := tag_value(spec, tag)
		chip.text = tag_label(tag) + (" = %d" % n if n not in [0, 1] else "")
		chip.button_pressed = n != 0
		chip.toggled.connect(func(on):
			set_tag(spec, tag, int(value.value) if on else 0)
			var now := tag_value(spec, tag)
			chip.text = tag_label(tag) + (" = %d" % now if now not in [0, 1] else "")
			changed.call())
		chips.add_child(chip)


## The editor's +Attack/+Health: one enchantment of its own on the item.
static func _set_buff(spec: Dictionary, key: String, v: int) -> void:
	var list: Array = spec.get("enchantments", [])
	var buff: Dictionary = {}
	for e in list:
		if e is Dictionary and e.get("debug", false):
			buff = e
	if buff.is_empty():
		buff = {"debug": true}
		list.append(buff)
	buff[key] = v
	if int(buff.get("atk", 0)) == 0 and int(buff.get("hp", 0)) == 0:
		list.erase(buff)
	spec.enchantments = list
	if list.is_empty():
		spec.erase("enchantments")


## Gives the item another card's Deathrattle (by id or name; "" or an unknown card takes it off); the card id.
static func give_deathrattle(spec: Dictionary, what: String) -> String:
	var q := what.strip_edges()
	var id := q if CardDb.has(q) else ""
	if id == "" and q != "":
		for c in CardDb.all_ids():
			if Rules.hooks(c).get("deathrattle", false) and CardText.name(c).to_lower() == q.to_lower():
				id = c
				break
	var list: Array = spec.get("enchantments", []).filter(func(e): return not (e is Dictionary and e.has("deathrattle")))
	if id != "":
		list.append({"deathrattle": id})
	spec.enchantments = list
	if list.is_empty():
		spec.erase("enchantments")
	return id


func start_game() -> void:
	if not apply_json():
		return
	var why := Rules.scenario_error(scene)
	if why != "":
		error.text = why
		return
	last_scene = editor.text
	start.emit({"scenario": scene}, [false, true] if bot_mode.button_pressed else [false, false])


# --- Interaction test: the scenarios of a card, the walk, the marks --------------

func _build_tests(page: Control) -> void:
	tests = CardTests.load_all()
	walk = CardScenarios.walk_ids()
	var list := CollectionView.new()
	list.name = "TestCards"
	list.scale = Vector2(LIST_SCALE, LIST_SCALE)
	list.include_tokens = true
	list.only = tests
	list.picked.connect(pick_test_card)
	page.add_child(list)
	_test_cards = list
	var only := _radio("OnlyTested", tr("Only cards with hand-written tests") + " (%d)" % tests.size())
	only.button_pressed = true
	only.position = Vector2(12, 512)
	only.toggled.connect(func(on):
		list.only = tests if on else null
		list.set_tab(list.tab))
	page.add_child(only)
	var walk_row := HFlowContainer.new()
	walk_row.position = Vector2(12, 554)
	walk_row.size = Vector2(620, 100)
	walk_row.add_theme_constant_override("h_separation", 8)
	walk_row.add_theme_constant_override("v_separation", 6)
	page.add_child(walk_row)
	for spec in [[tr("Previous card"), "WalkPrev", func(): walk_to(-1)], [tr("Next card"), "WalkNext", func(): walk_to(1)],
			[tr("Next unmarked"), "WalkUnmarked", next_unmarked], [tr("Export marks"), "ExportMarks", export_marks]]:
		var b := Palette.button(spec[0], spec[1])
		b.custom_minimum_size = Vector2(0, 42)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(spec[2])
		walk_row.add_child(b)
	_walk_info = Palette.label("", 15, Palette.SELECTED)
	_walk_info.name = "WalkInfo"
	_walk_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_walk_info.custom_minimum_size = Vector2(600, 0)
	walk_row.add_child(_walk_info)
	_test_box.position = SIDE.position
	_test_box.size = SIDE.size + Vector2(0, 40)
	_test_box.add_theme_constant_override("separation", 6)
	page.add_child(_test_box)
	var card_row := HBoxContainer.new()
	card_row.name = "CardRow"
	card_row.add_theme_constant_override("separation", 12)
	_test_box.add_child(card_row)
	test_list.name = "TestList"
	test_list.custom_minimum_size = Vector2(0, 250)
	test_list.item_selected.connect(func(_i): _show_steps())
	test_list.item_activated.connect(func(_i): run_selected())
	_test_box.add_child(test_list)
	_steps = Palette.label("", 15)
	_steps.name = "Steps"
	_steps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_steps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_steps.clip_text = true
	_test_box.add_child(_steps)
	_test_error = Palette.label("", 15, Palette.TARGET)
	_test_error.name = "TestError"
	_test_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_test_box.add_child(_test_error)
	var marks := HBoxContainer.new()
	marks.add_theme_constant_override("separation", 6)
	_test_box.add_child(marks)
	_note.name = "Note"
	_note.placeholder_text = tr("A note")
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.custom_minimum_size.y = 42
	marks.add_child(_note)
	for m in MARKS:
		var b := Palette.button(tr(m[1]), "Mark_" + m[0])
		b.custom_minimum_size = Vector2(0, 42)
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_color", m[2])
		var mark: String = m[0]
		b.pressed.connect(func(): mark_selected(mark))
		marks.add_child(b)
	var run := Palette.button(tr("Run"), "Run")
	run.custom_minimum_size = Vector2(110, 42)
	run.pressed.connect(run_selected)
	marks.add_child(run)
	var first: String = last_test[0] if CardDb.has(last_test[0]) else (tests.keys()[0] if not tests.is_empty() else (walk[0] if not walk.is_empty() else ""))
	if first != "":
		list.set_tab(CardDb.card(first).get("cardClass", "NEUTRAL"))
		pick_test_card(first)
		if first == last_test[0] and int(last_test[1]) < test_list.item_count:
			test_list.select(int(last_test[1]))
			_show_steps()
	else:
		_steps.text = tr("No tests for this card")


## Shows a card: its picture, its place in the walk, its checklist and its scenarios.
func pick_test_card(id: String) -> void:
	test_card = id
	var row := _test_box.get_node("CardRow")
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	var cv := CardView.make(id, 0.9)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cv)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 4)
	row.add_child(side)
	var name_label := Palette.label(CardText.name(id), 22, Palette.ATTACK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(name_label)
	side.add_child(Palette.label("%s · %s" % [id, tr("Card %d of %d") % [walk.find(id) + 1, walk.size()]], 14))
	_checks = GridContainer.new()
	_checks.name = "Checklist"
	_checks.columns = 3
	_checks.add_theme_constant_override("h_separation", 6)
	_checks.add_theme_constant_override("v_separation", 6)
	side.add_child(_checks)
	var done: Dictionary = CardScenarios.card_marks(id).get("check", {})
	for item in CardScenarios.CHECKLIST:
		var b := CollectionView.chip("Check_" + item, Vector2(150, 36))
		b.toggle_mode = false
		_paint_check(b, item, str(done.get(item, "")))
		b.pressed.connect(func(): cycle_check(item))
		_checks.add_child(b)
	scenarios = CardScenarios.for_card(id, tests)
	_fill_list()
	_test_error.text = ""
	if test_list.item_count > 0:
		test_list.select(0)
		_show_steps()
	else:
		_steps.text = tr("No tests for this card")
	_show_walk()


## A checklist item: none, passed, failed, none again.
func cycle_check(item: String) -> void:
	var now := str(CardScenarios.card_marks(test_card).get("check", {}).get(item, ""))
	var next: String = {"": "passed", "passed": "failed", "failed": ""}.get(now, "")
	CardScenarios.set_check(test_card, item, next)
	var b := _checks.get_node_or_null("Check_" + item) as Button
	if b:
		_paint_check(b, item, next)
	_show_walk()


func _paint_check(b: Button, item: String, mark: String) -> void:
	b.text = tr(item) + ({"passed": " +", "failed": " -"}.get(mark, ""))
	var color: Color = MARKS.filter(func(m): return m[0] == mark).map(func(m): return m[2]).front() if mark != "" else Palette.TEXT
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", color)


## The scenario list with each one's mark in its colour.
func _fill_list() -> void:
	var sel := test_list.get_selected_items()
	test_list.clear()
	var marks: Dictionary = CardScenarios.card_marks(test_card).get("s", {})
	for t in scenarios:
		var text: String = t.title if t.get("generic", false) else "%s — %s" % [t.get("kind", "?"), t.get("title", "")]
		var i := test_list.add_item(text)
		var m: Dictionary = marks.get(t.key, {})
		if not m.is_empty():
			var color: Color = MARKS.filter(func(x): return x[0] == m.mark).map(func(x): return x[2]).front()
			test_list.set_item_custom_fg_color(i, color)
			test_list.set_item_text(i, "%s  [%s]" % [text, tr(MARKS.filter(func(x): return x[0] == m.mark)[0][1])])
	if not sel.is_empty() and sel[0] < test_list.item_count:
		test_list.select(sel[0])


func selected_test() -> Dictionary:
	var sel := test_list.get_selected_items()
	if sel.is_empty() or sel[0] >= scenarios.size():
		return {}
	return scenarios[sel[0]]


## What to do (the steps, or by hand) and what should happen; the mark's note.
func _show_steps() -> void:
	var t := selected_test()
	var lines: Array = [tr("What to do:")]
	var steps: Array = t.get("steps", [])
	for i in steps.size():
		lines.append("%d. %s" % [i + 1, describe(steps[i])])
	if steps.is_empty():
		lines.append(str(t.get("do", tr("Play the scene by hand."))))
	if str(t.get("expect", "")) != "":
		lines.append(tr("What should happen:"))
		lines.append(str(t.expect))
	_steps.text = "\n".join(lines)
	_note.text = str(CardScenarios.card_marks(test_card).get("s", {}).get(t.get("key", ""), {}).get("note", ""))


## Marks the selected scenario (the note field goes with it); the same mark again clears it.
func mark_selected(mark: String) -> void:
	var t := selected_test()
	if t.is_empty():
		return
	var was: Dictionary = CardScenarios.card_marks(test_card).get("s", {}).get(t.key, {})
	var same: bool = was.get("mark", "") == mark and was.get("note", "") == _note.text
	CardScenarios.set_mark(test_card, t.key, "" if same else mark, _note.text)
	_fill_list()
	_show_walk()


## Plays the selected scenario in a match (its scene must build).
func run_selected() -> void:
	var t := selected_test()
	if t.is_empty():
		_test_error.text = tr("No tests for this card")
		return
	var why := Rules.scenario_error(t.get("scene", {}) if t.get("scene") is Dictionary else {})
	if why != "":
		_test_error.text = why
		return
	last_test = [test_card, test_list.get_selected_items()[0]]
	run_test.emit(t)


## The next (1) or previous (-1) card of the walk.
func walk_to(step: int) -> void:
	if walk.is_empty():
		return
	var i := posmod(walk.find(test_card) + step, walk.size())
	pick_test_card(walk[i])
	_test_cards.set_tab(CardDb.card(walk[i]).get("cardClass", "NEUTRAL"))


## The next card of the walk without a mark (none left: says so).
func next_unmarked() -> void:
	var marks := CardScenarios.marks()
	var at := walk.find(test_card)
	for k in range(1, walk.size() + 1):
		var id: String = walk[(at + k) % walk.size()]
		if not marks.has(id):
			pick_test_card(id)
			return
	_walk_info.text = tr("Every card is marked")


func _show_walk() -> void:
	var marks := CardScenarios.marks()
	var failed := 0
	for id in marks:
		for k in marks[id].get("s", {}):
			failed += int(marks[id].s[k].get("mark") == "failed")
		for k in marks[id].get("check", {}):
			failed += int(marks[id].check[k] == "failed")
	_walk_info.text = tr("Marked: %d of %d cards, %d failed") % [marks.size(), walk.size(), failed]


## Writes the marks for an agent (user://card_marks_export.json) and copies them.
func export_marks() -> void:
	var text := CardScenarios.export()
	var f := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	DisplayServer.clipboard_set(text)
	_walk_info.text = tr("The marks are copied and saved to %s") % ProjectSettings.globalize_path(EXPORT_PATH)


## A step in a few words: "play P1 hand 1 -> P2 board 1".
static func describe(step: Variant) -> String:
	if not step is Dictionary:
		return str(step)
	var s := str(step.get("do", "?"))
	for k in ["card", "attacker", "target", "defender"]:
		if step.has(k):
			s += (" -> " if k in ["target", "defender"] else " ") + _ref(step[k])
	if step.get("any", false):
		s += " -> " + TranslationServer.translate("any target")
	if step.has("pos"):
		s += " @%d" % (int(step.pos) + 1)
	if step.has("choice"):
		s += " (choice %d)" % (int(step.choice) + 1)
	if step.has("option"):
		s += " %d" % (int(step.option) + 1)
	return s


static func _ref(r: Variant) -> String:
	return CardTests.ref_text(r)


## Plays a card test's steps one by one in a match through its controller, with
## all animations, a pause between steps; shows the step and stops at an illegal one.
## A scenario of the library shows what should happen and takes the mark passed / failed.
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
		size.x = 340
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
		if str(test.get("expect", "")) != "":
			var expect := Palette.label(str(test.expect), 14, Palette.SELECTED)
			expect.name = "RunExpect"
			expect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(expect)
		status = Palette.label("", 15)
		status.name = "RunStatus"
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(status)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 6)
		box.add_child(row)
		var buttons := [[tr("Again"), "RunAgain", func(): again.emit()], [tr("Back"), "RunBack", func(): view.leave.emit()]]
		if test.has("key") and test.has("card"):  # a library scenario: marked here
			for m in DebugTable.MARKS.slice(0, 2):
				var mark: String = m[0]
				buttons.append([tr(m[1]), "Run_" + mark, func():
					CardScenarios.set_mark(test.card, test.key, mark)
					status.text = tr("Marked: %s") % tr(m[1])])
		for spec in buttons:
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
			var a := CardTests.action(view.controller, step) if step is Dictionary else {"error": "not a step"}
			var r: Dictionary = a if a.has("error") else view.controller.submit(a)
			if a.has("error") or not r.ok:
				status.text += "\n" + str(r.get("error", "?"))
				status.add_theme_color_override("font_color", Palette.TARGET)
				return
		await _settle()
		var why := CardTests.check(view.controller.game, test.get("check", []))
		status.text = tr("Done") + " (%d)" % steps.size() + ("" if why == "" else "\n" + why)
		if why != "":
			status.add_theme_color_override("font_color", Palette.TARGET)

	## Waits for the table's animations, then a short pause.
	func _settle() -> void:
		while view._busy:
			_timer.start(0.1)
			await _timer.timeout
		if Anim.d(PAUSE) > 0.0:
			_timer.start(Anim.d(PAUSE))
			await _timer.timeout
