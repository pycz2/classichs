class_name KeywordTips
extends VBoxContainer
## Small parchment boxes beside a big card, one per keyword on it, explaining
## what the keyword does (the active pack's locales `mechanics`, in the interface language).

const WIDTH := 210.0

static var _data := {}  # client mechanic name -> {name: {lang: text}, text: {lang: tip}}


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
	for k in ["TAUNT", "CHARGE", "DIVINE_SHIELD", "STEALTH", "WINDFURY", "IMMUNE"]:
		if e.has(k) and not base.has(k) and kw.has(k):
			out.append(kw[k].name.get(lang, kw[k].name.en))
	if e.has("FROZEN"):
		out.append(tr.call("Frozen"))
	if e.silenced:
		out.append(tr.call("Silenced"))
	return out


static func make(card_id: String, e: GameView.Ent = null) -> KeywordTips:
	var tips := KeywordTips.new()
	tips.name = "KeywordTips"
	tips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tips.add_theme_constant_override("separation", 6)
	var lang := TranslationServer.get_locale()
	var kw := _keywords()
	var lines := changes(e)
	if not lines.is_empty():
		tips.add_child(_box("Changes", TranslationServer.translate("Changes"), "\n".join(lines), Color("dcefd2")))
	for m in keywords_of(card_id):
		if kw.has(m):
			tips.add_child(_box("Title" + m, kw[m].name.get(lang, kw[m].name.en), kw[m].text.get(lang, kw[m].text.en), Color("efe0bd")))
	return tips


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


## Places the boxes beside rect (right of it, or left when there is no room).
func beside(rect: Rect2) -> void:
	var x := rect.end.x + 8 if rect.end.x + 8 + WIDTH < 1280 else rect.position.x - WIDTH - 8
	position = Vector2(x, rect.position.y + 6)
