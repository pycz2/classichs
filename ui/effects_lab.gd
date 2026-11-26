class_name EffectsLab
extends Control
## A tool to see every effect a card can show: any card of the active pack — a minion, a weapon, a spell, a
## hero card, a Hero Power, a Secret or a Quest — in play and as the card in hand with its pop-up boxes, with
## every keyword and tag of the pack (with a number: Spell Damage N), the states and every kind of enchantment
## (buffs, set stats, new base stats, a given Deathrattle, costs, the pack's named hook enchantments) switched on
## and off, in any language. The effects are put on real entities the way the engine does, so the views draw
## exactly what a game shows. (A developer tool: its own labels are not translated; the keywords are the pack's.)

signal back

## [key, label] of the effects that are no tag: states and kinds of enchantment.
const STATES := [
	["sleeping", "Played this turn (asleep)"], ["damaged", "Damaged (2)"],
	["buff", "+1/+1 (Shattered Sun Cleric)"], ["turn_buff", "+3 Attack this turn (Rockbiter)"],
	["set_attack", "Attack set to 1 (Humility)"], ["set_health", "Health set to 1"], ["base", "New base 5/5 (Crystal Core)"],
	["aura", "Aura +1/+1 (Stormwind Champion)"], ["deathrattle", "Given a Deathrattle (Harvest Golem)"],
	["silenced", "Silenced"], ["cheaper", "Costs (1) less"], ["dearer", "Costs (1) more"], ["cost_set", "Costs (0)"],
]
const GLOWS := [["none", Color.TRANSPARENT], ["playable", Palette.PLAYABLE], ["selected", Palette.SELECTED], ["target", Palette.TARGET]]
const LANG_NAMES := {"en": "English", "ru": "Русский", "de": "Deutsch", "fr": "Français", "es": "Español",
	"pt_BR": "Português (Brasil)", "it": "Italiano", "pl": "Polski"}

var ids: Array = []
var index := 0
var on := {}  # effect key -> true
var glow := Color.TRANSPARENT
## The number the switched-on tags get (1: a plain tag).
var tag_value := 1
var _was_lang := ""
var _stage := Control.new()
var _title := Label.new()
var _lang := OptionButton.new()
var _boxes := {}


## Every effect of the active pack: [key, label] — the states, then the pack's tags (its names), then its named
## hook enchantments ("ench:…").
static func effects() -> Array:
	var out := STATES.duplicate()
	for t in DebugTable.pack_tags():
		out.append([t, DebugTable.tag_label(t)])
	for h in Rules.enchantment_hooks():
		out.append([h, "Enchantment " + str(h).trim_prefix("ench:")])
	return out


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_was_lang = TranslationServer.get_locale()
	back.connect(func(): Locale.set_language(_was_lang))
	visibility_changed.connect(func():  # another debug tab opened: the game's language again
		if not is_visible_in_tree() and TranslationServer.get_locale() != _was_lang:
			set_language(_was_lang))
	var bg := TextureRect.new()
	bg.texture = Packs.picture("board") if Packs.picture("board") else Palette.shell_picture()
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
	search.custom_minimum_size = Vector2(200, 34)
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
	var n := Label.new()
	n.text = "tag ="
	bar.add_child(n)
	var value := SpinBox.new()
	value.name = "TagValue"
	value.min_value = -99
	value.max_value = 99
	value.value = 1
	value.value_changed.connect(func(v):
		tag_value = int(v)
		_build())
	bar.add_child(value)
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
	var scroll := ScrollContainer.new()  # the pack's tags make a long list
	scroll.position = Vector2(14, 76)
	scroll.size = Vector2(446, 580)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var list := GridContainer.new()
	list.columns = 2
	list.add_theme_constant_override("h_separation", 4)
	list.add_theme_constant_override("v_separation", 0)
	scroll.add_child(list)
	for ef in effects():
		var box := CheckBox.new()
		box.text = ef[1]
		box.name = "Effect_" + ef[0].replace(":", "_")
		box.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		box.custom_minimum_size.x = 214
		box.clip_text = true
		box.tooltip_text = ef[1]
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


## Where a card of each type is in play: [player field, view kind] (none: only in hand).
static func place(id: String) -> String:
	var c := CardDb.card(id)
	var mech: Array = c.get("mechanics", [])
	match str(c.get("type", "")):
		"MINION":
			return "board"
		"WEAPON":
			return "weapon"
		"HERO":
			return "hero"
		"HERO_POWER":
			return "power"
		"SPELL":
			return "quest" if mech.has("QUEST") else ("secret" if mech.has("SECRET") else "")
	return ""


## A fresh game with the card in play (where its type goes) and in hand, with the effects on both.
func _build() -> void:
	if ids.is_empty():
		return
	var id: String = ids[index]
	var c := CardDb.card(id)
	var where := place(id)
	var spec := _spec(id)
	var heroes: Array = Decks.heroes().values()
	var own: String = Decks.heroes().get(str(c.get("cardClass", "")), heroes[0] if not heroes.is_empty() else "HERO_08")
	var p0 := {"hero": own, "mana": 10, "max_mana": 10, "hand": [spec] if where != "power" else []}
	match where:
		"board":
			p0.board = [spec]
		"weapon":
			p0.weapon = spec
		"hero":  # the hero card as the hero, with its power
			p0.hero = id
			p0.hero_state = spec
			if CardDb.has(str(c.get("power", ""))):
				p0.hero_power = c.power
		"power":
			p0.hero_power = spec
		"secret", "quest":
			p0.secrets = [spec]
	var gid := Rules.new_id("lab")
	var foe: String = heroes.filter(func(h): return h != own).front() if heroes.size() > 1 else own
	var r := Rules.request({"op": "new", "game": gid, "scenario": {"current": 0, "players": [p0, {"hero": foe}]}})
	if not r.ok:
		_title.text = "%s: %s" % [id, r.error]
		return
	var g := GameView.new()
	g.update(Rules.request({"op": "snapshot", "game": gid}).state)
	Rules.request({"op": "drop", "game": gid})
	var pl = g.players[0]
	var hand: GameView.Ent = pl.hand[0] if not pl.hand.is_empty() else null
	var e: GameView.Ent = {"board": pl.board[0] if not pl.board.is_empty() else null, "weapon": pl.weapon, "hero": pl.hero,
		"power": pl.hero_power, "secret": pl.secrets[0] if not pl.secrets.is_empty() else null,
		"quest": pl.secrets[0] if not pl.secrets.is_empty() else null}.get(where, hand)
	if on.has("aura") and e:  # a Stormwind Champion's aura, drawn on the entity only
		e.aura.atk = int(e.aura.get("atk", 0)) + 1
		e.aura.hp = int(e.aura.get("hp", 0)) + 1
		e.aura.get_or_add("src", {})["VAN_CS2_222"] = [1, 1]
		e._atk += 1
		e._max_health += 1
	_title.text = "%s — %s  (%d / %d)" % [id, CardText.name(id), index + 1, ids.size()]
	for ch in _stage.get_children():
		_stage.remove_child(ch)
		ch.queue_free()
	if e and where != "":
		for big in [true, false]:  # twice the size, and as on the table
			var v := _view(where, e, g)
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.set_glow(glow)
			if big:
				v.name = {"board": "Minion", "hero": "Hero", "weapon": "Weapon", "power": "Power", "secret": "Secret", "quest": "Quest"}[where]
				v.scale = Vector2(2, 2)
				v.position = Vector2(470, 110)
			else:
				v.position = Vector2(518, 480)
			_stage.add_child(v)
	var cv := CardView.make(id, 1.6)
	cv.name = "Card"
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hand:
		cv.show_entity(hand, g)  # its cost, stats and keywords as the engine has them in hand
	cv.set_glow(glow)
	cv.position = Vector2(760, 110)
	_stage.add_child(cv)
	var tips := KeywordTips.make(id, e if e else hand)
	tips.position = Vector2(960, 110)
	tips.custom_minimum_size.x = 300
	_stage.add_child(tips)


static func _view(where: String, e: GameView.Ent, g: GameView) -> EntityView:
	match where:
		"board":
			return MinionView.make(e, g)
		"hero":
			return HeroView.make(e, g)
		"weapon":
			return PowerView.make(e, g, PowerView.Kind.WEAPON)
		"secret":
			return PowerView.make(e, g, PowerView.Kind.SECRET)
		"quest":
			return PowerView.make(e, g, PowerView.Kind.QUEST)
	return PowerView.make(e, g, PowerView.Kind.POWER)


## The entity with the effects switched on, as a scenario item (the engine builds
## it: Silence first, so the keywords and buffs Silence would remove are left out).
func _spec(id: String) -> Dictionary:
	var silenced := on.has("silenced")
	var spec := {"card": id, "tags": [], "enchantments": [], "silenced": silenced}
	var tags := DebugTable.pack_tags()
	for k in on:
		if tags.has(k) and not silenced:
			spec.tags.append(k if tag_value == 1 else {k: tag_value})
		if str(k).begins_with("ench:") and not silenced:
			spec.enchantments.append({"hooks": k})
	if on.has("sleeping"):
		spec.tags.append(Packs.pack_name("EXHAUSTED"))
	var ench := {"buff": {"atk": 1, "hp": 1, "src": "VAN_EX1_019"}, "turn_buff": {"atk": 3, "eot": true, "src": "VAN_CS2_045"},
		"set_attack": {"set_atk": 1, "src": "VAN_EX1_360"}, "set_health": {"set_hp": 1}, "deathrattle": {"deathrattle": "VAN_EX1_556"},
		"cheaper": {"cost": -1}, "dearer": {"cost": 1}}
	for k in ench:
		if on.has(k) and not silenced and (not ench[k].has("src") or CardDb.has(ench[k].src)) and (k != "deathrattle" or CardDb.has("VAN_EX1_556")):
			spec.enchantments.append(ench[k])
	if on.has("base"):  # (Silence leaves it)
		spec.enchantments.append({"set_atk": 5, "set_hp": 5, "base": true})
	if on.has("cost_set"):
		spec.enchantments.append({"cost_set": 0})
	if on.has("damaged"):
		var hp := int(CardDb.card(id).get("health", 30)) + (1 if on.has("buff") and not silenced else 0)
		spec.damage = mini(2, maxi(0, hp - 1))
	return spec
