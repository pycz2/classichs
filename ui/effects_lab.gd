class_name EffectsLab
extends Control
## A tool to see every effect a card can show on the table: any card (a minion on
## the board, a hero, a weapon, and the card itself as in hand with its pop-up
## boxes), with buffs, debuffs and states switched on and off, in any language.
## The effects are put on a real entity the way the engine does, so the views
## draw exactly what a game shows. (A developer tool: its labels are not translated.)

signal back

## [key, label]: a tag key (TAUNT...) is given as a tag; the others are below.
const EFFECTS := [
	["TAUNT", "Taunt"], ["DIVINE_SHIELD", "Divine Shield"], ["STEALTH", "Stealth"], ["WINDFURY", "Windfury"],
	["CHARGE", "Charge"], ["IMMUNE", "Immune"], ["ELUSIVE", "Elusive"], ["FROZEN", "Frozen"], ["SPELLPOWER", "Spell Damage +1"],
	["sleeping", "Played this turn (asleep)"], ["damaged", "Damaged (2)"],
	["buff", "+1/+1 (Shattered Sun Cleric)"], ["turn_buff", "+3 Attack this turn (Rockbiter)"],
	["set_attack", "Attack set to 1 (Humility)"], ["aura", "Aura +1/+1 (Stormwind Champion)"],
	["silenced", "Silenced"], ["cheaper", "Costs (1) less"], ["dearer", "Costs (1) more"],
]
const GLOWS := [["none", Color.TRANSPARENT], ["playable", Palette.PLAYABLE], ["selected", Palette.SELECTED], ["target", Palette.TARGET]]
const LANG_NAMES := {"en": "English", "ru": "Русский", "de": "Deutsch", "fr": "Français", "es": "Español",
	"pt_BR": "Português (Brasil)", "it": "Italiano", "pl": "Polski"}

var ids: Array = []
var index := 0
var on := {}  # effect key -> true
var glow := Color.TRANSPARENT
var _was_lang := ""
var _stage := Control.new()
var _title := Label.new()
var _lang := OptionButton.new()
var _boxes := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_was_lang = TranslationServer.get_locale()
	back.connect(func(): Locale.set_language(_was_lang))
	visibility_changed.connect(func():  # another debug tab opened: the game's language again
		if not is_visible_in_tree() and TranslationServer.get_locale() != _was_lang:
			set_language(_was_lang))
	var bg := TextureRect.new()
	bg.texture = load("res://ui/board_bg.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	ids = CardDb.all_ids()
	ids.sort()
	var bar := HBoxContainer.new()
	bar.position = Vector2(10, 6)
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	var search := LineEdit.new()
	search.placeholder_text = "card id or name"
	search.custom_minimum_size = Vector2(220, 34)
	search.text_submitted.connect(find)
	bar.add_child(search)
	for spec in [["<", func(): show_card(ids[posmod(index - 1, ids.size())])], [">", func(): show_card(ids[(index + 1) % ids.size()])]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(34, 34)
		b.pressed.connect(spec[1])
		bar.add_child(b)
	for code in CardLayout.LANGS:
		_lang.add_item(LANG_NAMES[code])
	_lang.select(maxi(0, CardLayout.LANGS.find(_was_lang)))
	_lang.item_selected.connect(func(i): set_language(CardLayout.LANGS[i]))
	bar.add_child(_lang)
	var glow_pick := OptionButton.new()
	glow_pick.name = "GlowPick"
	for gl in GLOWS:
		glow_pick.add_item("glow: " + gl[0])
	glow_pick.item_selected.connect(func(i):
		glow = GLOWS[i][1]
		_build())
	bar.add_child(glow_pick)
	var all := Button.new()
	all.text = "All off"
	all.pressed.connect(func():
		on.clear()
		for k in _boxes:
			_boxes[k].set_pressed_no_signal(false)
		_build())
	bar.add_child(all)
	var bk := Button.new()
	bk.text = "Back"
	bk.name = "Back"
	bk.pressed.connect(func(): back.emit())
	bar.add_child(bk)
	_title.position = Vector2(14, 46)
	add_child(_title)
	var list := GridContainer.new()
	list.columns = 2
	list.position = Vector2(14, 76)
	list.add_theme_constant_override("h_separation", 4)
	list.add_theme_constant_override("v_separation", 0)
	add_child(list)
	for ef in EFFECTS:
		var box := CheckBox.new()
		box.text = ef[1]
		box.name = "Effect_" + ef[0]
		box.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		box.custom_minimum_size.x = 214
		box.add_theme_font_size_override("font_size", 14)
		var key: String = ef[0]
		box.toggled.connect(func(v): set_effect(key, v))
		list.add_child(box)
		_boxes[key] = box
	add_child(_stage)
	if ids.size() > 0 and _stage.get_child_count() == 0:
		show_card(ids[index])


func _exit_tree() -> void:
	Locale.set_language(_was_lang)


func find(q: String) -> void:
	q = q.strip_edges().to_lower()
	for id in ids:
		if id.to_lower() == q or CardText.name(id, "enUS").to_lower().contains(q) or CardText.name(id).to_lower().contains(q):
			show_card(id)
			return


func show_card(id: String) -> void:
	index = maxi(0, ids.find(id))
	_build()


func set_effect(key: String, value: bool) -> void:
	if value:
		on[key] = true
	else:
		on.erase(key)
	if _boxes.has(key):
		_boxes[key].set_pressed_no_signal(value)
	_build()


func set_language(code: String) -> void:
	Locale.set_language(code)
	_lang.select(CardLayout.LANGS.find(code))
	_build()


## A fresh game with the card in play (or in hand), with the effects on it.
func _build() -> void:
	if ids.is_empty():
		return
	var id: String = ids[index]
	var c := CardDb.card(id)
	var type: String = c.get("type", "SPELL")
	var p0 := {"hero": id if type == "HERO" else "HERO_08", "mana": 10, "max_mana": 10}
	if type == "MINION":
		p0.board = [id]
	elif type == "WEAPON":
		p0.weapon = id
	p0.hand = [id] if type != "HERO" else []
	var r := Scenario.build({"current": 0, "players": [p0, {"hero": "HERO_01"}]})
	if r.error != "":
		_title.text = "%s: %s" % [id, r.error]
		return
	var g: GameState = r.game
	var pl = g.players[0]
	var e: Entity = pl.board[0] if type == "MINION" else (pl.hero if type == "HERO" else (pl.weapon if type == "WEAPON" else pl.hand[0]))
	_effects(e, g)
	_title.text = "%s — %s  (%d / %d)" % [id, CardText.name(id), index + 1, ids.size()]
	for ch in _stage.get_children():
		_stage.remove_child(ch)
		ch.queue_free()
	var board: EntityView = null
	match type:
		"MINION":
			board = MinionView.make(e, g)
			board.name = "Minion"
		"HERO":
			board = HeroView.make(e, g)
			board.name = "Hero"
		"WEAPON":
			board = PowerView.make(e, g, PowerView.Kind.WEAPON)
			board.name = "Weapon"
	if board:
		board.mouse_filter = Control.MOUSE_FILTER_IGNORE
		board.set_glow(glow)
		board.scale = Vector2(2, 2)
		board.position = Vector2(470, 110)
		_stage.add_child(board)
		# the same at the table's size
		var small: EntityView = MinionView.make(e, g) if type == "MINION" else (HeroView.make(e, g) if type == "HERO" else PowerView.make(e, g, PowerView.Kind.WEAPON))
		small.mouse_filter = Control.MOUSE_FILTER_IGNORE
		small.set_glow(glow)
		small.position = Vector2(518, 480)
		_stage.add_child(small)
	var hand: Entity = pl.hand[0] if not pl.hand.is_empty() else e  # in hand only the cost changes
	var cv := CardView.make(id, 1.6)
	cv.name = "Card"
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.show_entity(hand, g)
	var base := int(c.get("cost", 0))
	cv.cost = maxi(0, base - (1 if on.has("cheaper") else 0) + (1 if on.has("dearer") else 0))
	cv.set_glow(glow)
	cv.position = Vector2(760, 110)
	_stage.add_child(cv)
	var tips := KeywordTips.make(id, e)
	tips.position = Vector2(960, 110)
	tips.custom_minimum_size.x = 300
	_stage.add_child(tips)


## The effects on the entity in the engine's order: tags, enchantments, Silence,
## damage, auras.
func _effects(e: Entity, g: GameState) -> void:
	for ef in EFFECTS:
		var k: String = ef[0]
		if on.has(k) and k == k.to_upper():
			if k == "SPELLPOWER":
				e.tags.SPELLPOWER = 1
			else:
				e.give_tag(k)
	if on.has("sleeping"):
		e.give_tag("EXHAUSTED")
	if on.has("buff"):
		e.add_enchant({"atk": 1, "hp": 1, "src": "VAN_EX1_019"})
	if on.has("turn_buff"):
		e.add_enchant({"atk": 3, "eot": true, "src": "VAN_CS2_045"})
	if on.has("set_attack"):
		e.add_enchant({"set_atk": 1, "src": "VAN_EX1_360"})
	if on.has("silenced"):
		e.silence()
	if on.has("damaged"):
		e.damage = mini(2, maxi(0, e.max_health() - 1))
	g.update_auras()  # the card's own auras, as in a game (Enrage)
	if on.has("aura"):
		if not e.aura.has("src"):  # a card in hand: update_auras() does not reset it
			e.aura["src"] = {}
		g.source_card = "VAN_CS2_222"
		g.aura_add(e, 1, 1)
		g.source_card = ""
