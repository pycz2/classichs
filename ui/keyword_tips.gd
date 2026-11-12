class_name KeywordTips
extends VBoxContainer
## Small parchment boxes beside a big card, one per keyword on it, explaining
## what the keyword does (the active pack's locales `mechanics`, in the interface language),
## then small cards of what the card can bring into the game (CardDb.related).

const WIDTH := 210.0
## The related cards' size: two in a row fill WIDTH.
const RELATED_SCALE := 0.85

static var _data := {}  # client mechanic name -> {name: {lang: text}, text: {lang: tip}}
## The cards whose scripts put these hidden enchantments on (g.enchant {hooks}): the Changes box
## names them with their text. ponytail: the Classic pack's; another pack's show the hook's name.
const ENCH_SOURCES := {"ench:corruption": "VAN_CS2_063", "ench:shadow_madness": "VAN_EX1_334",
	"ench:power_overwhelming": "VAN_EX1_316", "ench:ancestral_spirit": "VAN_CS2_038", "ench:soul_of_the_forest": "VAN_EX1_158",
	"ench:blessing_of_wisdom": "VAN_EX1_363", "ench:nightmare": "VAN_DREAM_05", "ench:conceal": "VAN_EX1_128",
	"ench:headcrack": "VAN_EX1_137", "ench:commanding_shout": "VAN_NEW1_036", "ench:transcendence": "TU4f_006"}


## Keywords whose box shows only when the card's text names them in bold: patch 11.0 (The Witchwood) took the word
## Enrage off the cards' texts ("Has +3 Attack while damaged"), which keep the keyword for its damaged look. ponytail:
## only Enrage; the other hook keywords keep their boxes (Fatespinner's Choose One, which its text does not name).
const TEXT_ONLY := ["ENRAGED"]


static func reset() -> void:
	_data = {}


static func _keywords() -> Dictionary:
	var p := Packs.active()
	if _data.is_empty() and p:
		for lang in p.manifest.get("locales", []):
			var mech = p.locale(lang).get("mechanics", {})
			for name in mech if mech is Dictionary else {}:
				var e: Dictionary = _data.get_or_add(Packs.client_name(name), {"name": {}, "text": {}})
				if mech[name].has("name"):
					e.name[lang] = mech[name].name
				if mech[name].has("tip"):
					e.text[lang] = mech[name].tip
		for k in _data:  # the client falls back to English: the pack's default language is it
			for f in ["name", "text"]:
				if not _data[k][f].has("en"):
					_data[k][f].en = _data[k][f].get(p.default_locale(), "")
	return _data


## The card's keywords: its mechanics, and keywords written in bold in its text
## (the Classic data lists no mechanic for Enrage). POISONOUS marks "Destroy any
## minion damaged by this minion" (it has no keyword box).
static func keywords_of(card_id: String) -> Array:
	var c := CardDb.card(card_id)
	var out: Array = c.get("mechanics", []).duplicate()
	var en: String = c.get("text", {}).get("enUS", "") if c.get("text") is Dictionary else ""
	var kw := _keywords()
	for k in kw:
		if not out.has(k) and en.contains("<b>" + String(kw[k].name.en)):
			out.append(k)
	if en.contains("Destroy any minion damaged by this minion"):
		out.append("POISONOUS")
	return out


## What changed on a minion compared with its card: buffs (with the card that
## gave them), auras, set values, gained keywords, Silence.
static func changes(e: GameView.Ent) -> Array:
	var out := []
	if e == null:
		return out
	var tr := func(k: String) -> String: return TranslationServer.translate(k)
	var src := func(d: Dictionary) -> String: return (" — " + CardText.name(d.src)) if d.get("src", "") != "" else ""
	for ench in e.enchantments:
		var line := ""
		if ench.has("set_atk"):
			line = tr.call("Attack set to %d") % ench.set_atk
		if ench.has("set_hp"):
			line = (line + ", " if line != "" else "") + tr.call("Health set to %d") % ench.set_hp
		if line == "" and (int(ench.get("atk", 0)) != 0 or int(ench.get("hp", 0)) != 0):
			line = "%+d/%+d" % [int(ench.get("atk", 0)), int(ench.get("hp", 0))]
		if line == "" and ench.has("hooks"):  # a hidden effect: the card that cast it, and what it does
			var by: String = ENCH_SOURCES.get(ench.hooks, "")
			line = "%s: %s" % [CardText.name(by), CardText.text(by)] if CardDb.has(by) \
				else str(ench.hooks).trim_prefix("ench:").capitalize()
		if line != "":
			if ench.get("eot", false):
				line += " (%s)" % tr.call("this turn")
			out.append(line + src.call(ench))
	for card in e.aura.get("src", {}):
		var v: Array = e.aura.src[card]
		out.append("%+d/%+d — %s (%s)" % [v[0], v[1], CardText.name(card), tr.call("aura")])
	var base: Array = e.card().get("mechanics", [])
	var kw := _keywords()
	var lang := TranslationServer.get_locale()
	for k in ["TAUNT", "CHARGE", "DIVINE_SHIELD", "STEALTH", "WINDFURY", "IMMUNE", "LIFESTEAL", "POISONOUS", "RUSH", "ECHO"]:
		if e.has(k) and not base.has(k) and kw.has(k):
			out.append(kw[k].name.get(lang, kw[k].name.en))
	if e.has("FROZEN"):
		out.append(tr.call("Frozen"))
	if e.silenced:
		out.append(tr.call("Silenced"))
	return out


## A mechanic's name (client name: "UNTOUCHABLE") in the player's language, from the active pack ("" if it has none).
static func name_of(m: String) -> String:
	var kw := _keywords()
	return str(kw[m].name.get(TranslationServer.get_locale(), kw[m].name.en)) if kw.has(m) else ""


static func make(card_id: String, e: GameView.Ent = null) -> KeywordTips:
	var tips := KeywordTips.new()
	tips.name = "KeywordTips"
	tips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tips.add_theme_constant_override("separation", 6)
	var lang := TranslationServer.get_locale()
	var kw := _keywords()
	var mark := Packs.set_mark(CardText.set_key(card_id))
	if mark and CardText.card_set(card_id) != "":  # the card's set (the packs after Classic)
		tips.add_child(_set_box(mark, CardText.card_set(card_id)))
	var classes: Array = CardDb.card(card_id).get("classes", [])
	if classes.size() > 1:  # a multi-class card: the classes it belongs to
		tips.add_child(_classes_box(classes))
	var lines := changes(e)
	if not lines.is_empty():
		tips.add_child(_box("Changes", TranslationServer.translate("Changes"), "\n".join(lines), Color("dcefd2")))
	var ms := keywords_of(card_id)
	if e and e.has("ECHO") and not ms.has("ECHO"):  # (a hand card under Glinda Crowskin's aura)
		ms.append("ECHO")
	var en: String = str(CardDb.card(card_id).get("text", {}).get("enUS", "")) if CardDb.card(card_id).get("text") is Dictionary else ""
	for m in ms:
		if TEXT_ONLY.has(m) and kw.has(m) and not en.contains("<b>" + String(kw[m].name.en)):
			continue
		if kw.has(m):
			tips.add_child(_box("Title" + m, kw[m].name.get(lang, kw[m].name.en), kw[m].text.get(lang, kw[m].text.en), Color("efe0bd")))
	var related := CardDb.related(card_id)
	if not related.is_empty():
		var grid := GridContainer.new()
		grid.name = "Related"
		grid.columns = 2
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_theme_constant_override("h_separation", int(WIDTH - 2 * CardView.SIZE.x * RELATED_SCALE))
		grid.add_theme_constant_override("v_separation", 6)
		for id: String in related:
			var cv := CardView.make(id, RELATED_SCALE)
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(cv)
		tips.add_child(grid)
	return tips


## A line with a multi-class card's classes, each name in its class's colour.
static func _classes_box(classes: Array) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "Classes"
	var st := Palette.box(Color("efe0bd"), 10, Color("8a6d3b"), 2)
	st.set_content_margin_all(6)
	box.add_theme_stylebox_override("panel", st)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for cls: String in classes:
		var name := CardText.term("classes", cls)
		var l := Palette.label(name if name != "" else cls.capitalize(), 14, Palette.of_class(cls).darkened(0.35))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
	return box


## A line with the card's set: its mark and its name.
static func _set_box(mark: Texture2D, title: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "SetMark"
	var st := Palette.box(Color("efe0bd"), 10, Color("8a6d3b"), 2)
	st.set_content_margin_all(6)
	box.add_theme_stylebox_override("panel", st)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var icon := TextureRect.new()
	icon.texture = mark
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color("5a3d17")
	row.add_child(icon)
	var label := Label.new()
	label.name = "SetName"
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - 46
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("2a1a08"))
	row.add_child(label)
	return box


static func _box(title_name: String, title_text: String, body: String, color: Color) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = title_name if title_name == "Changes" else "Box"
	var st := Palette.box(color, 10, Color("8a6d3b"), 2)
	st.set_content_margin_all(8)
	box.add_theme_stylebox_override("panel", st)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	box.add_child(col)
	var title := Label.new()
	title.name = title_name
	title.text = title_text
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("2a1a08"))
	col.add_child(title)
	var text := Label.new()
	text.text = body
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = WIDTH - 16
	text.add_theme_font_size_override("font_size", 13)
	text.add_theme_color_override("font_color", Color("3b2a14"))
	col.add_child(text)
	return box


## Places the boxes beside rect (right of it, or left when there is no room), on the screen.
func beside(rect: Rect2) -> void:
	var x := rect.end.x + 8 if rect.end.x + 8 + WIDTH < 1280 else rect.position.x - WIDTH - 8
	position = Vector2(x, maxf(8, minf(rect.position.y + 6, 712 - get_combined_minimum_size().y)))
