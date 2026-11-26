class_name StudioCards
extends Control
## ClassicHS Studio's Cards tab: the project's cards in a list (search, class and type filters, new,
## duplicate, delete); the chosen card's form (its numbers, tribe, rarity, class, set, keywords, and its name
## and text in each of the 8 languages), its effect (building blocks of StudioEffects or raw Lua), its picture
## (uploaded and framed as the game frames it: classichs-art-framing/1) and its sounds; on the right the card
## as the game draws it (CardView) and, for a minion, on the board (MinionView), from the project's preview
## pack. Every change goes into the project in memory and `changed` tells the shell to save.

## The project changed (the shell saves it).
signal changed
## Play this card in a test match.
signal try_card(cid: String)

const TYPE_NAMES := {"MINION": "Minion", "SPELL": "Spell", "WEAPON": "Weapon", "CHAMPION": "Hero", "POWER": "Hero Power"}
const LANG_NAMES := {"en": "English", "ru": "Русский", "de": "Deutsch", "fr": "Français", "es": "Español",
	"pt_BR": "Português (Brasil)", "it": "Italiano", "pl": "Polski"}
## The fields of each type besides cost (form rows; the others go when the type changes) and their defaults.
const FIELDS := {"MINION": ["attack", "health", "race"], "SPELL": [], "WEAPON": ["attack", "durability"],
	"CHAMPION": ["health", "armor", "power"], "POWER": []}
const DEFAULTS := {"attack": 1, "health": 1, "durability": 2, "armor": 0}
const SLOT_NAMES := {"play": "When played", "attack": "Attack", "death": "Death", "trigger": "Trigger", "aim": "Aim",
	"missile": "Missile", "hit": "Hit", "reveal": "Reveal", "choose": "Choose", "music": "Music"}
## The card types an action's card chooser offers.
const CARD_KINDS := {"summon": ["MINION"], "transform": ["MINION"], "equip": ["WEAPON"]}
## The words a sentence of StudioEffects.describe starts with that the card text shows in bold.
static var _head_re := RegEx.create_from_string("^(Battlecry|Combo|Deathrattle|Secret):")
const PREVIEW_DELAY := 0.3

var project: StudioProject
## The chosen card's id ("" when the project has none).
var cid := ""
## The language of the name and text being edited and of the preview.
var lang := "en"
## The preview: the card as the game draws it, and the minion on the board (null for other types).
var card_view: CardView
var minion_view: MinionView
## The pack the preview draws from (a new one after each change).
var preview: Pack

var _filling := false  # the form is being filled from the card: its signals change nothing
var _list := ItemList.new()
var _search := LineEdit.new()
var _class_filter := OptionButton.new()
var _type_filter := OptionButton.new()
var _tabs := TabContainer.new()
var _form := GridContainer.new()
var _rows := {}  # field -> [label, control]
var _id_edit := LineEdit.new()
var _id_problem := Label.new()
var _keywords := HFlowContainer.new()
var _lang_pick := OptionButton.new()
var _name_edit := LineEdit.new()
var _text_edit := TextEdit.new()
var _marks := Marks.new()
var _insert := MenuButton.new()
var _blocks_box := VBoxContainer.new()
var _problems := Label.new()
var _raw := CheckButton.new()
var _lua := CodeEdit.new()
var _lua_box := VBoxContainer.new()
var _framer := Framer.new()
var _sliders := {}  # x, y, zoom -> HSlider
var _art_message := Label.new()
var _sounds := VBoxContainer.new()
var _player := AudioStreamPlayer.new()
var _stage := VBoxContainer.new()
var _timer := Timer.new()
var _web_callback: JavaScriptObject  # kept alive while the browser's file picker is open


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	row.add_child(_left())
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_tabs)
	for t in [[_card_tab(), "Card"], [_effect_tab(), "Effect"], [_art_tab(), "Picture"], [_sound_tab(), "Sounds"]]:
		_tabs.add_child(t[0])
		_tabs.set_tab_title(_tabs.get_tab_count() - 1, tr(t[1]))
	row.add_child(_right())
	_timer.one_shot = true
	_timer.wait_time = PREVIEW_DELAY
	_timer.timeout.connect(refresh_preview)
	add_child(_timer)
	add_child(_player)
	_fill_filters()
	refresh_list()
	select(_shown()[0] if not _shown().is_empty() else "")


func _exit_tree() -> void:
	if preview:
		CardDb.forget(preview)
		preview.close()


static func _btn(text: String, id: String) -> Button:
	var b := Palette.button(text, id)
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 16)
	return b


static func _scroll(inner: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(inner)
	return s


# --- the list ------------------------------------------------------------------------------------

func _left() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 240
	_search.name = "Search"
	_search.placeholder_text = tr("Search by name or id")
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): refresh_list())
	box.add_child(_search)
	for o: OptionButton in [_class_filter, _type_filter]:
		o.item_selected.connect(func(_i): refresh_list())
		box.add_child(o)
	_class_filter.name = "ClassFilter"
	_type_filter.name = "TypeFilter"
	_list.name = "CardList"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i): select(str(_list.get_item_metadata(i))))
	box.add_child(_list)
	var new_b := MenuButton.new()
	new_b.name = "NewCard"
	new_b.text = tr("New card")
	new_b.flat = false
	for t in StudioProject.TYPES:
		new_b.get_popup().add_item(tr(TYPE_NAMES[t]))
	new_b.get_popup().add_item(tr("Secret"))
	new_b.get_popup().index_pressed.connect(func(i): new_card(StudioProject.TYPES[i]) if i < StudioProject.TYPES.size() else new_secret())
	box.add_child(new_b)
	var row := HBoxContainer.new()
	var dup := _btn(tr("Duplicate"), "Duplicate")
	dup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dup.pressed.connect(duplicate_card)
	row.add_child(dup)
	var del := _btn(tr("Delete"), "Delete")
	del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del.pressed.connect(_ask_delete)
	row.add_child(del)
	box.add_child(row)
	return box


func _fill_filters() -> void:
	_class_filter.clear()
	_class_filter.add_item(tr("All classes"))
	_class_filter.set_item_metadata(0, "")
	for c in project.rules.get("classes", []):
		_class_filter.add_item(project.term("classes", c.id, lang))
		_class_filter.set_item_metadata(_class_filter.item_count - 1, c.id)
	_type_filter.clear()
	_type_filter.add_item(tr("All types"))
	_type_filter.set_item_metadata(0, "")
	for t in StudioProject.TYPES:
		_type_filter.add_item(tr(TYPE_NAMES[t]))
		_type_filter.set_item_metadata(_type_filter.item_count - 1, t)


## A card's name in the language being edited, else English, else its id.
func card_name(id: String) -> String:
	return str(project.text(id, lang).get("name", project.text(id, "en").get("name", id)))


## The cards the search and the filters let through, by cost and name.
func _shown() -> Array:
	var q := _search.text.strip_edges().to_lower()
	var cls := str(_class_filter.get_selected_metadata()) if _class_filter.selected >= 0 else ""
	var type := str(_type_filter.get_selected_metadata()) if _type_filter.selected >= 0 else ""
	var out := project.cards.filter(func(c): return (cls == "" or c.get("class") == cls) and (type == "" or c.type == type) \
		and (q == "" or str(c.id).to_lower().contains(q) or card_name(c.id).to_lower().contains(q)))
	out.sort_custom(func(a, b): return [int(a.get("cost", 0)), card_name(a.id)] < [int(b.get("cost", 0)), card_name(b.id)])
	return out.map(func(c): return str(c.id))


func _item_text(id: String) -> String:
	var c := project.card(id)
	return "%d  %s  (%s)" % [int(c.get("cost", 0)), card_name(id), tr(TYPE_NAMES.get(c.get("type"), "Card"))]


func refresh_list() -> void:
	_list.clear()
	for id in _shown():
		_list.add_item(_item_text(id))
		_list.set_item_metadata(_list.item_count - 1, id)
		if id == cid:
			_list.select(_list.item_count - 1)


## Shows the project as it is now (another tab may have changed its classes, sets or cards).
func refresh() -> void:
	_fill_filters()
	refresh_list()
	select(cid if not project.card(cid).is_empty() else (_shown()[0] if not _shown().is_empty() else ""))


## Shows a card in the form and the preview.
func select(id: String) -> void:
	cid = id if not project.card(id).is_empty() else ""
	for i in _list.item_count:
		if _list.get_item_metadata(i) == cid:
			_list.select(i)
			_list.ensure_current_is_visible()
	_fill()
	refresh_preview()


func new_card(type: String) -> String:
	var cls := str(_class_filter.get_selected_metadata()) if _class_filter.selected > 0 else "NEUTRAL"
	if not project.rules.classes.any(func(c): return c.id == cls):
		cls = str(project.rules.classes[-1].id)
	var id := project.add_card(type, cls)
	_search.text = ""
	_touch()
	refresh_list()
	select(id)
	return id


## A new Secret: a spell whose block waits for the opponent's minion and deals 2 damage to it (its trigger, target
## and action can be changed on the Effect tab; the pack's Secret mechanic comes with it).
func new_secret() -> String:
	var id := new_card("SPELL")
	project.set_effect(id, {"blocks": [{"when": "secret_minion_played", "target": "event", "do": "damage", "n": 2}], "lua": ""})
	project.set_text(id, "en", "New secret", "")
	_touch()
	select(id)
	return id


## A copy of the chosen card with its texts, effect, picture and sounds.
func duplicate_card() -> String:
	if cid == "":
		return ""
	var c := project.card(cid)
	var id := project.add_card(c.type, c.get("class", "NEUTRAL"))
	var n := project.card(id)
	n.clear()
	n.merge(c.duplicate(true))
	n.id = id
	for l in StudioProject.LANGS:
		var t := project.text(cid, l)
		project.set_text(id, l, str(t.get("name", "")), str(t.get("text", "")))
	if project.effects.has(cid):
		project.effects[id] = project.effects[cid].duplicate(true)
	if project.art_path(cid) != "":
		project.set_art(id, Image.load_from_file(project.art_path(cid)))
		var f := project.framing(cid)
		project.set_framing(id, f.x, f.y, f.z)
	for slot in StudioProject.SOUND_SLOTS:
		var p := project.sound_path(cid, slot)
		if p != "":
			project.set_sound(id, slot, FileAccess.get_file_as_bytes(p), p.get_extension())
	_touch()
	refresh_list()
	select(id)
	return id


func _ask_delete() -> void:
	if cid == "":
		return
	var d := ConfirmationDialog.new()
	d.dialog_text = tr("Delete the card \"%s\" with its picture and sounds?") % card_name(cid)
	d.confirmed.connect(delete_card)
	d.visibility_changed.connect(func(): if not d.visible: d.queue_free())
	add_child(d)
	d.popup_centered()


func delete_card() -> void:
	if cid == "":
		return
	var i := _shown().find(cid)
	project.remove_card(cid)
	_touch()
	refresh_list()
	var left := _shown()
	select(left[clampi(i, 0, left.size() - 1)] if not left.is_empty() else "")


# --- the form ------------------------------------------------------------------------------------

func _card_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "CardForm"
	box.add_theme_constant_override("separation", 8)
	_form.columns = 2
	_form.add_theme_constant_override("h_separation", 12)
	box.add_child(_form)
	_id_edit.name = "Id"
	_id_edit.text_submitted.connect(func(t): rename(t))
	_id_edit.focus_exited.connect(func(): if _id_edit.text != cid: rename(_id_edit.text))
	_row("id", tr("Id"), _id_edit)
	_id_problem.add_theme_color_override("font_color", Palette.DANGER)
	_row("id_problem", "", _id_problem)
	var type := OptionButton.new()
	type.name = "Type"
	for t in StudioProject.TYPES:
		type.add_item(tr(TYPE_NAMES[t]))
	type.item_selected.connect(func(i): if not _filling: set_type(StudioProject.TYPES[i]))
	_row("type", tr("Type"), type)
	for f in [["cost", "Cost"], ["attack", "Attack"], ["health", "Health"], ["durability", "Durability"], ["armor", "Armor"]]:
		var s := SpinBox.new()
		s.name = f[0].capitalize()
		s.max_value = 99
		s.value_changed.connect(func(v): if not _filling: set_field(f[0], int(v)))
		_row(f[0], tr(f[1]), s)
	for f in [["power", "Hero Power"], ["race", "Tribe"], ["rarity", "Rarity"], ["class", "Class"], ["set", "Set"]]:
		var o := OptionButton.new()
		o.name = f[0].capitalize()
		o.item_selected.connect(func(i): if not _filling: set_field(f[0], o.get_item_metadata(i)))
		_row(f[0], tr(f[1]), o)
	var multi := HFlowContainer.new()
	multi.name = "Classes"
	_row("classes", tr("Or several classes"), multi)
	var coll := CheckBox.new()
	coll.name = "Collectible"
	coll.text = tr("Can go into decks")
	coll.toggled.connect(func(on): if not _filling: set_field("collectible", true if on else null))
	_row("collectible", tr("Collectible"), coll)
	box.add_child(Palette.label(tr("Keywords"), 18, Palette.ATTACK))
	_keywords.name = "Keywords"
	box.add_child(_keywords)
	var lang_row := HBoxContainer.new()
	lang_row.add_child(Palette.label(tr("Language"), 16))
	_lang_pick.name = "Language"
	for l in StudioProject.LANGS:
		_lang_pick.add_item(LANG_NAMES[l])
	_lang_pick.item_selected.connect(func(i): set_lang(StudioProject.LANGS[i]))
	lang_row.add_child(_lang_pick)
	box.add_child(lang_row)
	var texts := GridContainer.new()
	texts.columns = 2
	box.add_child(texts)
	texts.add_child(Palette.label(tr("Name"), 16))
	_name_edit.name = "CardName"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(_t): if not _filling: set_texts(_name_edit.text, _text_edit.text))
	texts.add_child(_name_edit)
	texts.add_child(Palette.label(tr("Text"), 16))
	_text_edit.name = "CardText"
	_text_edit.custom_minimum_size = Vector2(0, 90)
	_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text_edit.syntax_highlighter = _marks
	_text_edit.text_changed.connect(func(): if not _filling: set_texts(_name_edit.text, _text_edit.text))
	texts.add_child(_text_edit)
	var tools := HBoxContainer.new()
	_insert.name = "InsertKeyword"
	_insert.text = tr("Insert a keyword")
	_insert.flat = false
	_insert.get_popup().index_pressed.connect(func(i): insert_keyword(_insert.get_popup().get_item_text(i)))
	tools.add_child(_insert)
	var from := _btn(tr("English text from the effect"), "TextFromEffect")
	from.pressed.connect(english_from_effect)
	tools.add_child(from)
	box.add_child(tools)
	var hint := Palette.label(tr("<b>Taunt</b>: bold; $3: damage that Spell Damage raises; #2: healing."), 14, Palette.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	return _scroll(box)


func _row(key: String, title: String, control: Control) -> void:
	var l := Palette.label(title, 16)
	_form.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_child(control)
	_rows[key] = [l, control]


func _control(key: String) -> Control:
	return _rows[key][1]


## Fills the form, the effect, the picture and the sounds from the chosen card.
func _fill() -> void:
	_filling = true
	_tabs.visible = cid != ""
	if cid == "":
		_filling = false
		return
	var c := project.card(cid)
	var type: String = c.type
	_id_edit.text = cid
	_id_problem.text = ""
	(_control("type") as OptionButton).select(StudioProject.TYPES.find(type))
	for f in ["cost", "attack", "health", "durability", "armor"]:
		(_control(f) as SpinBox).value = int(c.get(f, 0))
	_options(_control("power"), project.cards.filter(func(x): return x.type == "POWER").map(func(x): return [x.id, card_name(x.id)]), c.get("power"))
	_options(_control("race"), [[null, tr("None")]] + project.rules.get("races", []).map(func(r): return [r, project.term("races", r, lang)]), c.get("race"))
	_options(_control("rarity"), [[null, tr("None")]] + project.rules.get("rarities", []).map(func(r): return [r.id, project.term("rarities", r.id, lang)]), c.get("rarity"))
	_options(_control("class"), project.rules.get("classes", []).map(func(r): return [r.id, project.term("classes", r.id, lang)]), c.get("class"))
	_options(_control("set"), project.rules.get("sets", []).map(func(s): return [s, project.term("sets", s, lang)]), c.get("set"))
	(_control("collectible") as CheckBox).button_pressed = bool(c.get("collectible", false))
	var multi := _control("classes")
	for b in multi.get_children():
		multi.remove_child(b)
		b.queue_free()
	for r in project.rules.get("classes", []):
		if not r.get("neutral", false) and r.get("playable", true):
			var b := CheckBox.new()
			b.name = r.id
			b.text = project.term("classes", r.id, lang)
			b.button_pressed = c.get("classes", []).has(r.id)
			b.toggled.connect(func(on): if not _filling: set_class_of_several(r.id, on))
			multi.add_child(b)
	_rows.classes[0].visible = type != "CHAMPION" and multi.get_child_count() > 1
	multi.visible = _rows.classes[0].visible
	for f in ["attack", "health", "durability", "armor", "power", "race"]:
		_rows[f][0].visible = FIELDS[type].has(f)
		_rows[f][1].visible = FIELDS[type].has(f)
	_show_id_problem("")
	for k in _keywords.get_children():
		_keywords.remove_child(k)  # (now: a new box takes its name)
		k.queue_free()
	_insert.get_popup().clear()
	var names := []
	for k: Dictionary in project.keyword_choices(lang):
		var b := CheckBox.new()
		b.name = k.id
		b.text = k.name
		b.tooltip_text = k.tip
		b.button_pressed = c.get("keywords", []).has(k.id)
		b.toggled.connect(func(on): if not _filling: set_keyword(k.id, on))
		_keywords.add_child(b)
		_insert.get_popup().add_item(k.name)
		names.append(k.name)
	_marks.set_words(names)
	_lang_pick.select(StudioProject.LANGS.find(lang))
	var t := project.text(cid, lang)
	_name_edit.text = str(t.get("name", ""))
	_name_edit.placeholder_text = str(project.text(cid, "en").get("name", ""))
	_text_edit.text = str(t.get("text", ""))
	_text_edit.placeholder_text = str(project.text(cid, "en").get("text", ""))
	_fill_effect()
	_fill_art()
	_fill_sounds()
	_filling = false


## Fills an option button with [value, label] pairs and selects the current value (added when missing).
func _options(o: OptionButton, items: Array, current: Variant) -> void:
	o.clear()
	if not items.any(func(it): return it[0] == current):
		items.append([current, str(current) if current != null else tr("None")])
	for it in items:
		o.add_item(str(it[1]))
		o.set_item_metadata(o.item_count - 1, it[0])
		if it[0] == current:
			o.select(o.item_count - 1)


## Something changed: the shell saves, the preview redraws soon, the list shows the new name and cost.
func _touch() -> void:
	changed.emit()
	_timer.start()
	for i in _list.item_count:
		if _list.get_item_metadata(i) == cid:
			_list.set_item_text(i, _item_text(cid))


## Sets a field of the card (null removes it).
func set_field(key: String, value: Variant) -> void:
	var c := project.card(cid)
	if c.is_empty():
		return
	if value == null:
		c.erase(key)
	else:
		c[key] = value
	if key == "class" and c.has("classes") and not project.rules.classes.any(func(r): return r.id == value and r.get("neutral", false)):
		c.erase("classes")  # one class chosen: no longer of several
		for b in _control("classes").get_children():
			b.set_pressed_no_signal(false)
	_touch()


## Makes the card one of several classes too, or not (docs/packs/cards.md `classes`: two or more, the card's
## own class then a neutral one; one left: the card is of that class).
func set_class_of_several(cls: String, on: bool) -> void:
	var c := project.card(cid)
	if c.is_empty():
		return
	var list: Array = c.get("classes", [] if project.rules.classes.any(func(r): return r.id == c.class and r.get("neutral", false)) else [c.class])
	list = list.filter(func(x): return x != cls)
	if on:
		list.append(cls)
	if list.size() >= 2:
		c.classes = list
		for r in project.rules.classes:
			if r.get("neutral", false):
				c["class"] = r.id
				break
	else:
		c.erase("classes")
		if list.size() == 1:
			c["class"] = list[0]
	_touch()
	_filling = true
	_options(_control("class"), project.rules.get("classes", []).map(func(r): return [r.id, project.term("classes", r.id, lang)]), c.get("class"))
	_filling = false


## Changes the card's type: the fields the new type has no use for go, the ones it needs come with defaults.
func set_type(type: String) -> void:
	var c := project.card(cid)
	if c.is_empty() or c.type == type:
		return
	c.type = type
	for f in ["attack", "health", "durability", "armor", "power", "race"]:
		if not FIELDS[type].has(f):
			c.erase(f)
		elif not c.has(f) and DEFAULTS.has(f):
			c[f] = DEFAULTS[f]
	if type == "CHAMPION":
		c.health = int(project.rules.get("limits", {}).get("champion_health", 30))
		c.power = str(project.rules.get("default_power", ""))
	_touch()
	_fill()


func set_keyword(k: String, on: bool) -> void:
	var c := project.card(cid)
	var kw: Array = c.get("keywords", [])
	if on and not kw.has(k):
		kw.append(k)
	elif not on:
		kw.erase(k)
	if kw.is_empty():
		c.erase("keywords")
	else:
		c.keywords = kw
	_touch()


## Renames the card everywhere. "" or why not (shown under the id).
func rename(new: String) -> String:
	new = new.strip_edges()
	if cid == "" or new == cid:
		return ""
	var why := project.rename_card(cid, new)
	_show_id_problem(tr(why))
	if why != "":
		return why
	cid = new
	_touch()
	refresh_list()
	_fill_sounds()
	return ""


func _show_id_problem(why: String) -> void:
	_id_problem.text = why
	for n: Control in _rows["id_problem"]:
		n.visible = why != ""  # (both cells, or the grid's columns shift)


## The language of the name, the text, the terms and the preview.
func set_lang(l: String) -> void:
	lang = l
	_fill()
	refresh_list()
	refresh_preview()


func set_texts(name: String, body: String) -> void:
	if cid == "":
		return
	project.set_text(cid, lang, name, body)
	_touch()


func insert_keyword(name: String) -> void:
	_text_edit.insert_text_at_caret("<b>%s</b>" % name)


## The English text made from the effect's blocks (StudioEffects.describe), keyword heads in bold.
func english_from_effect() -> void:
	var e: Dictionary = project.effects.get(cid, {})
	if str(e.get("lua", "")).strip_edges() != "":
		return
	var said := []
	for b in e.get("blocks", []):
		var shown: Dictionary = b.duplicate()
		if str(b.get("card", "")) != "":
			shown.card = str(project.text(b.card, "en").get("name", b.card))  # its name, not its id
		var s := StudioEffects.describe(shown, project.card(cid).type)
		if s != "":
			said.append(_head_re.sub(s, "<b>$1:</b>"))
	lang = "en"
	project.set_text(cid, "en", str(project.text(cid, "en").get("name", "")), " ".join(said))
	_touch()
	_fill()
	refresh_preview()


# --- the effect ----------------------------------------------------------------------------------

func _effect_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Effect"
	box.add_theme_constant_override("separation", 8)
	_raw.name = "RawLua"
	_raw.text = tr("Raw Lua")
	_raw.toggled.connect(func(on): if not _filling: set_raw_lua(on))
	box.add_child(_raw)
	_blocks_box.name = "Blocks"
	_blocks_box.add_theme_constant_override("separation", 10)
	box.add_child(_blocks_box)
	_problems.name = "Problems"
	_problems.add_theme_color_override("font_color", Palette.DANGER)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_problems)
	_lua_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hint := Palette.label(tr("The body of the card's hook table: battlecry, deathrattle, on, aura… See docs/packs/api.md for the g.* functions."), 14, Palette.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lua_box.add_child(hint)
	_lua.name = "Lua"
	_lua.custom_minimum_size = Vector2(0, 320)
	_lua.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lua.gutters_draw_line_numbers = true
	_lua.indent_use_spaces = true
	_lua.indent_size = 2
	_lua.text_changed.connect(func(): if not _filling: set_lua(_lua.text))
	_lua_box.add_child(_lua)
	box.add_child(_lua_box)
	return _scroll(box)


## The chosen card's effect ({blocks, lua}; a copy to change).
func effect() -> Dictionary:
	var e: Dictionary = project.effects.get(cid, {})
	return {"blocks": e.get("blocks", []).duplicate(true), "lua": str(e.get("lua", ""))}


func _set_effect(e: Dictionary) -> void:
	var c := project.card(cid)
	var kw = c.get("keywords", []).duplicate()
	project.set_effect(cid, e)
	_problems.text = "\n".join(StudioEffects.problems(e, c.type).map(func(p): return tr(p)))
	_touch()
	if c.get("keywords", []) != kw:  # Battlecry, Deathrattle… came or went
		_filling = true
		for b: CheckBox in _keywords.get_children():
			b.button_pressed = c.get("keywords", []).has(str(b.name))
		_filling = false


func _fill_effect() -> void:
	var e := effect()
	var raw: bool = e.lua.strip_edges() != ""
	_raw.button_pressed = raw
	_blocks_box.visible = not raw
	_lua_box.visible = raw
	_lua.text = e.lua
	_problems.text = "\n".join(StudioEffects.problems(e, project.card(cid).type).map(func(p): return tr(p)))
	for ch in _blocks_box.get_children():
		_blocks_box.remove_child(ch)
		ch.queue_free()
	for i in e.blocks.size():
		_blocks_box.add_child(_block_row(i, e.blocks[i]))
	var add := _btn(tr("Add a block"), "AddBlock")
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(add_block)
	_blocks_box.add_child(add)


func _block_row(i: int, b: Dictionary) -> Control:
	var type: String = project.card(cid).type
	var box := VBoxContainer.new()
	box.name = "Block%d" % i
	var line := HFlowContainer.new()
	box.add_child(line)
	var pick := func(key: String, list: Array, current: Variant, label := "label") -> OptionButton:
		var o := OptionButton.new()
		o.name = key.capitalize()
		var items := list.filter(func(it): return not it.has("types") or it.types.has(type)).map(func(it): return [it.id, tr(it[label])])
		_options(o, items, current)
		o.item_selected.connect(func(j): set_block(i, key, o.get_item_metadata(j)))
		line.add_child(o)
		return o
	pick.call("when", StudioEffects.TRIGGERS, b.get("when"))
	pick.call("target", StudioEffects.TARGETS, b.get("target"))
	pick.call("do", StudioEffects.ACTIONS, b.get("do"))
	var a := _action(b.get("do"))
	for f in ["n", "m"]:
		if a.get("fields", []).has(f):
			line.add_child(Palette.label(f.to_upper(), 16))
			var s := SpinBox.new()
			s.name = f.to_upper()
			s.max_value = StudioEffects.MAX_N
			s.value = int(b.get(f, 1))
			s.value_changed.connect(func(v): set_block(i, f, int(v), false))
			line.add_child(s)
	if a.get("fields", []).has("card"):
		var kinds: Array = CARD_KINDS.get(a.id, ["MINION", "SPELL", "WEAPON"])
		var cards := project.cards.filter(func(c): return kinds.has(c.type)).map(func(c): return {"id": c.id, "label": "%s (%s)" % [card_name(c.id), c.id]})
		pick.call("card", cards, b.get("card"))
	if a.get("fields", []).has("keyword"):
		pick.call("keyword", StudioEffects.KEYWORDS, b.get("keyword"))
	var del := _btn("✕", "Remove")
	del.tooltip_text = tr("Remove the block")
	del.pressed.connect(remove_block.bind(i))
	line.add_child(del)
	var said := Palette.label(StudioEffects.describe(b, type), 14, Palette.MUTED)
	said.name = "Says"
	said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(said)
	return box


static func _action(id: Variant) -> Dictionary:
	for a: Dictionary in StudioEffects.ACTIONS:
		if a.id == id:
			return a
	return {}


func add_block() -> void:
	var e := effect()
	e.blocks.append({"when": "play", "target": "chosen_any", "do": "damage", "n": 1})
	_set_effect(e)
	_fill_effect()


func remove_block(i: int) -> void:
	var e := effect()
	e.blocks.remove_at(i)
	_set_effect(e)
	_fill_effect()


## Sets a field of a block; a new action gets the fields it needs (a card, a keyword) and loses the others.
## rebuild: redraw the rows (not while a number is being typed).
func set_block(i: int, key: String, value: Variant, rebuild := true) -> void:
	var e := effect()
	var b: Dictionary = e.blocks[i]
	b[key] = value
	if key == "do":
		var fields: Array = _action(value).get("fields", [])
		for f in ["n", "m", "card", "keyword"]:
			if not fields.has(f):
				b.erase(f)
		if fields.has("card") and not b.has("card"):
			var kinds: Array = CARD_KINDS.get(value, ["MINION", "SPELL", "WEAPON"])
			var fit := project.cards.filter(func(c): return kinds.has(c.type))
			b.card = fit[0].id if not fit.is_empty() else ""
		if fields.has("keyword") and not b.has("keyword"):
			b.keyword = StudioEffects.KEYWORDS[0].id
	_set_effect(e)
	if rebuild:
		_fill_effect()
	else:
		var row := _blocks_box.get_child(i)
		(row.get_node("Says") as Label).text = StudioEffects.describe(b, project.card(cid).type)


## Raw Lua on: it starts from the Lua the blocks make (or an empty play hook), the blocks are kept for when
## it goes off again. Off: the blocks' Lua again.
func set_raw_lua(on: bool) -> void:
	var e := effect()
	if on:
		var type: String = project.card(cid).type
		var lines := Array(StudioEffects.card_lua(cid, type, {"blocks": e.blocks, "lua": ""}).split("\n"))
		e.lua = "\n".join(lines.slice(1, lines.size() - 2).map(func(l): return l.trim_prefix("  ")))
		if e.lua.strip_edges() == "":
			e.lua = "%s = function(g, me, t)\nend," % StudioEffects.PLAY_HOOK.get(type, "battlecry")
	else:
		e.lua = ""
	_set_effect(e)
	_filling = true
	_fill_effect()
	_filling = false


func set_lua(text: String) -> void:
	var e := effect()
	e.lua = text
	_set_effect(e)


# --- the picture ---------------------------------------------------------------------------------

func _art_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Picture"
	box.add_theme_constant_override("separation", 8)
	var buttons := HBoxContainer.new()
	var up := _btn(tr("Upload picture"), "UploadPicture")
	up.pressed.connect(func(): _pick_file(["png", "jpg", "jpeg", "webp"], tr("Pictures"), load_art))
	buttons.add_child(up)
	var rm := _btn(tr("Remove picture"), "RemovePicture")
	rm.pressed.connect(remove_art)
	buttons.add_child(rm)
	var reset := _btn(tr("Reset"), "ResetFraming")
	reset.pressed.connect(func(): set_frame(0, 0, 1))
	buttons.add_child(reset)
	box.add_child(buttons)
	_art_message.add_theme_color_override("font_color", Palette.DANGER)
	box.add_child(_art_message)
	_framer.name = "Framer"
	_framer.custom_minimum_size = Vector2(0, 300)
	_framer.moved.connect(func(f: Vector3): set_frame(f.x, f.y, f.z))
	box.add_child(_framer)
	box.add_child(Palette.label(tr("Drag the picture to move it, the mouse wheel zooms."), 14, Palette.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	for s in [["x", "Left / right", -1.0, 1.0], ["y", "Up / down", -1.0, 1.0], ["zoom", "Zoom", 0.5, 3.0]]:
		grid.add_child(Palette.label(tr(s[1]), 16))
		var sl := HSlider.new()
		sl.name = s[0].capitalize()
		sl.min_value = s[2]
		sl.max_value = s[3]
		sl.step = 0.001
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.value_changed.connect(func(_v): if not _filling: set_frame(_sliders.x.value, _sliders.y.value, _sliders.zoom.value))
		grid.add_child(sl)
		_sliders[s[0]] = sl
	box.add_child(grid)
	return _scroll(box)


func _fill_art() -> void:
	var type: String = project.card(cid).type
	_framer.shape = {"MINION": "oval", "WEAPON": "circle", "POWER": "circle"}.get(type, "arch")
	_framer.window = {"oval": Vector2(76, 84), "circle": Vector2(70, 70), "arch": Vector2(92, 76)}[_framer.shape]
	var path := project.art_path(cid)
	var img := Image.load_from_file(path) if path != "" else null
	_framer.texture = ImageTexture.create_from_image(img) if img else null
	_art_message.text = "" if img else tr("No picture: the game draws one.")
	_show_frame(project.framing(cid))


func _show_frame(f: Vector3) -> void:
	var was := _filling
	_filling = true
	_framer.frame = f
	_framer.queue_redraw()
	_sliders.x.value = f.x
	_sliders.y.value = f.y
	_sliders.zoom.value = f.z
	_filling = was


## A picture for the card (made at most 512 px and saved into the pack); its framing starts centred.
func load_art(img: Image) -> String:
	var why := project.set_art(cid, img)
	if why != "":
		_art_message.text = tr(why)
		return why
	project.set_framing(cid, 0, 0, 1)
	_touch()
	_fill_art()
	return ""


func remove_art() -> void:
	project.remove_art(cid)
	_touch()
	_fill_art()


## Where the picture sits in its window (x, y: -1…1 of the side, zoom 0.5…3), as the game's framing.json.
func set_frame(x: float, y: float, zoom: float) -> void:
	if cid == "":
		return
	project.set_framing(cid, x, y, zoom)
	_show_frame(project.framing(cid))
	_touch()


## The system's file dialog, the browser's file picker on the web; done gets the file's bytes and extension
## turned into what it takes (an Image for pictures, the bytes for sounds).
func _pick_file(exts: Array, what: String, done: Callable) -> void:
	var take := func(file_name: String, bytes: PackedByteArray) -> void:
		var ext := file_name.get_extension().to_lower()
		if done == load_art:
			load_art(_image(bytes, ext))
		else:
			done.call(bytes, ext)
	if OS.has_feature("web"):
		_web_callback = JavaScriptBridge.create_callback(func(args: Array):
			take.call(str(args[0]), Marshalls.base64_to_raw(str(args[1]))))
		JavaScriptBridge.get_interface("window").classichsStudioPicked = _web_callback
		JavaScriptBridge.eval("""(function () {
			var i = document.createElement('input');
			i.type = 'file'; i.accept = '%s'; i.style.display = 'none';
			document.body.appendChild(i);
			i.addEventListener('change', function () {
				var f = i.files[0];
				i.remove();
				if (!f) return;
				var r = new FileReader();
				r.onload = function () {
					var b = new Uint8Array(r.result), s = '';
					for (var k = 0; k < b.length; k += 32768) s += String.fromCharCode.apply(null, b.subarray(k, k + 32768));
					window.classichsStudioPicked(f.name, btoa(s));
				};
				r.readAsArrayBuffer(f);
			});
			i.click();
		})();""" % ",".join(exts.map(func(e): return "." + e)), true)
		return
	var d := FileDialog.new()
	d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	d.access = FileDialog.ACCESS_FILESYSTEM
	d.use_native_dialog = true
	d.filters = PackedStringArray([", ".join(exts.map(func(e): return "*." + e)) + " ; " + what])
	d.file_selected.connect(func(path: String):
		d.queue_free()
		take.call(path.get_file(), FileAccess.get_file_as_bytes(path)))
	d.canceled.connect(d.queue_free)
	add_child(d)
	d.popup_centered(Vector2i(900, 600))


static func _image(bytes: PackedByteArray, ext: String) -> Image:
	var img := Image.new()
	var err: int = {"png": img.load_png_from_buffer, "webp": img.load_webp_from_buffer}.get(ext, img.load_jpg_from_buffer).call(bytes)
	return img if err == OK else null


# --- the sounds ----------------------------------------------------------------------------------

func _sound_tab() -> Control:
	_sounds.name = "Sounds"
	_sounds.add_theme_constant_override("separation", 6)
	return _scroll(_sounds)


func _fill_sounds() -> void:
	for ch in _sounds.get_children():
		_sounds.remove_child(ch)
		ch.queue_free()
	_sounds.add_child(Palette.label(tr("The card's own sounds (.opus, .ogg, .wav or .mp3); without one the game plays its usual sound."), 14, Palette.MUTED))
	for slot: String in StudioProject.SOUND_SLOTS:
		var row := HBoxContainer.new()
		row.name = slot
		var l := Palette.label(tr(SLOT_NAMES[slot]), 16)
		l.custom_minimum_size.x = 110
		row.add_child(l)
		var path := project.sound_path(cid, slot)
		var f := Palette.label(path.get_file() if path != "" else tr("none"), 15, Palette.TEXT if path != "" else Palette.MUTED)
		f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		f.clip_text = true
		row.add_child(f)
		var up := _btn(tr("Load"), "Load")
		up.pressed.connect(func(): _pick_file(StudioProject.AUDIO_EXT, tr("Sounds"), func(bytes, ext): load_sound(slot, bytes, ext)))
		row.add_child(up)
		var play := _btn(tr("Play"), "Play")
		play.disabled = path == ""
		play.pressed.connect(play_sound.bind(slot))
		row.add_child(play)
		var rm := _btn(tr("Remove"), "Remove")
		rm.disabled = path == ""
		rm.pressed.connect(remove_sound.bind(slot))
		row.add_child(rm)
		_sounds.add_child(row)
	var hero: bool = project.card(cid).get("type") == "CHAMPION"
	if not hero and not project.card(cid).get("type") in ["MINION", "WEAPON"]:
		return
	_sounds.add_child(Palette.label(tr("Lines (%s)") % LANG_NAMES[lang], 18, Palette.ATTACK))
	for kind: String in StudioProject.HERO_LINES if hero else StudioProject.CARD_LINES:
		var row := HBoxContainer.new()
		row.name = "line_" + kind
		var l := Palette.label(tr(LINE_NAMES[kind]), 16)
		l.custom_minimum_size.x = 110
		row.add_child(l)
		var e := LineEdit.new()
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		e.text = project.voice_line(cid, lang, kind)
		e.placeholder_text = project.voice_line(cid, "en", kind)
		e.text_changed.connect(func(t): set_line(kind, t))
		row.add_child(e)
		_sounds.add_child(row)


## The words a hero, a minion or a weapon says at a moment (locales' `voice`), in the chosen language.
const LINE_NAMES := {"start": "Game start", "greetings": "Greetings", "well_played": "Well played", "thanks": "Thanks",
	"wow": "Wow", "oops": "Oops", "threaten": "Threaten", "play": "Played", "attack": "Attacks", "death": "Dies",
	"trigger": "Its effect"}


func set_line(kind: String, line: String) -> void:
	project.set_voice_line(cid, lang, kind, line)
	_touch()


func load_sound(slot: String, bytes: PackedByteArray, ext: String) -> String:
	var why := project.set_sound(cid, slot, bytes, ext)
	if why == "":
		_touch()
	_fill_sounds()
	if why != "":
		_sounds.get_child(0).text = tr(why)
	return why


func remove_sound(slot: String) -> void:
	project.remove_sound(cid, slot)
	_touch()
	_fill_sounds()


func play_sound(slot: String) -> void:
	var path := project.sound_path(cid, slot)
	var bytes := FileAccess.get_file_as_bytes(path)
	match path.get_extension():
		"opus":
			_player.stream = Opus.stream(bytes)
		"ogg":
			_player.stream = AudioStreamOggVorbis.load_from_buffer(bytes)
		"wav":
			_player.stream = AudioStreamWAV.load_from_buffer(bytes)
		"mp3":
			var s := AudioStreamMP3.new()
			s.data = bytes
			_player.stream = s
	_player.play()


# --- the preview ---------------------------------------------------------------------------------

func _right() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 260
	_stage.name = "Preview"
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_child(_stage)
	var go := _btn(tr("Try in a match"), "TryCard")
	go.pressed.connect(func(): if cid != "": try_card.emit(cid))
	box.add_child(go)
	return box


## Builds the preview pack of the project as it is now and draws the card from it.
func refresh_preview() -> void:
	_timer.stop()
	for ch in _stage.get_children():
		_stage.remove_child(ch)
		ch.queue_free()
	card_view = null
	minion_view = null
	if preview:  # (its views are gone: they drew from it)
		CardDb.forget(preview)
		preview.close()
		preview = null
	if cid == "":
		return
	preview = project.preview_pack([cid])
	if preview == null:
		return
	card_view = CardView.make(cid, 2.0)
	card_view.name = "Card"
	card_view.pack = preview
	card_view.locale = lang
	card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_stage.add_child(card_view)
	var c := project.card(cid)
	if c.type == "MINION":
		var e := GameView.Ent.new()
		var tags := {}
		for k in c.get("keywords", []):
			var engine := str(project.rules.get("mechanics", {}).get(k, {}).get("engine", k))
			tags[Packs.ENGINE_TO_CLIENT.get(engine, engine)] = true
		CardDb.begin(preview)
		e.set_from(1, {"card": cid, "zone": "PLAY", "atk": int(c.get("attack", 0)), "max_health": int(c.get("health", 0)), "tags": tags})
		CardDb.end()
		var g := GameView.new()
		g.current = 1
		var v := BoardMinion.new()  # (as MinionView.make, from the preview pack)
		v.pack = preview
		v.e = e
		v.g = g
		v.entity_id = e.id
		v.custom_minimum_size = MinionView.SIZE
		v.size = MinionView.SIZE
		v.sync()
		minion_view = v
		minion_view.name = "Minion"
		minion_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var holder := CenterContainer.new()
		holder.custom_minimum_size = MinionView.SIZE * 1.5 + Vector2(0, 16)
		var scaler := Control.new()
		scaler.custom_minimum_size = MinionView.SIZE * 1.5
		minion_view.scale = Vector2(1.5, 1.5)
		scaler.add_child(minion_view)
		holder.add_child(scaler)
		_stage.add_child(holder)


## A minion on the board drawn from the preview pack.
class BoardMinion extends MinionView:
	var pack: Pack

	func _draw() -> void:
		if pack == null or s == null:
			return
		CardDb.begin(pack)
		super()
		CardDb.end()


## The card text's marks: bold, $N and #N numbers, and the language's keyword names (orange when not bold).
class Marks extends SyntaxHighlighter:
	var _re: RegEx

	func set_words(words: Array) -> void:
		var names := words.filter(func(w): return str(w) != "").map(func(w): return "\\Q%s\\E" % w)
		names.sort_custom(func(a, b): return a.length() > b.length())
		var parts := ["(<b>.*?</b>)", "([$#]\\d+)"]
		if not names.is_empty():
			parts.append("(?<!\\w)(%s)(?!\\w)" % "|".join(names))
		_re = RegEx.create_from_string("(*UCP)(?i)" + "|".join(parts))
		clear_highlighting_cache()

	func _get_line_syntax_highlighting(line: int) -> Dictionary:
		var out := {}
		if _re == null:
			return out
		var base := get_text_edit().get_theme_color("font_color")
		for m in _re.search_all(get_text_edit().get_line(line)):
			var color := Color("ffc83d") if m.get_string(1) != "" else Color("6fc3ff") if m.get_string(2) != "" else Color("ff9f43")
			out[m.get_start()] = {"color": color}
			out[m.get_end()] = {"color": base}
		return out


## The card's picture in its window as the game frames it (Art.square): drag to move, the wheel zooms; the
## part outside the window shows dimmed.
class Framer extends Control:
	signal moved(f: Vector3)
	var texture: Texture2D
	var shape := "oval"
	var window := Vector2(76, 84)
	var frame := Vector3(0, 0, 1)

	func _rect() -> Rect2:
		var k := minf(size.x * 0.6 / window.x, size.y * 0.8 / window.y)
		return Rect2(size / 2.0 - window * k / 2.0, window * k)

	func _square(r: Rect2) -> Rect2:
		var side := maxf(r.size.x, r.size.y)
		var sz := Vector2(side, side) * frame.z
		return Rect2(r.get_center() + Vector2(frame.x, frame.y) * side - sz / 2.0, sz)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
		var r := _rect()
		var pts := Art.outline(shape, r)
		if texture == null:
			draw_colored_polygon(pts, Color(1, 1, 1, 0.12))
		else:
			var sq := _square(r)
			draw_texture_rect(texture, sq, false, Color(1, 1, 1, 0.3))
			var uvs := PackedVector2Array()
			for p in pts:
				uvs.append((p - sq.position) / sq.size)
			draw_colored_polygon(pts, Color.WHITE, uvs, texture)
		Frames.ring(self, pts, Frames.GOLD, 3)

	func _gui_input(ev: InputEvent) -> void:
		var side := maxf(_rect().size.x, _rect().size.y)
		if ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
			moved.emit(frame + Vector3(ev.relative.x / side, ev.relative.y / side, 0))
		elif ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			moved.emit(Vector3(frame.x, frame.y, frame.z * (1.05 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.05)))
		else:
			return
		accept_event()
