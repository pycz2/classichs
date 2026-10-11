class_name CardLayout
extends RefCounted
## How each card's name and text sit on the card, per language, written out by
## hand in data/card_layout/<lang>.json: the text size, the name size and the
## text's lines (nothing is wrapped by code). problems() only checks a layout;
## the card lab (ui/card_lab.gd) is where layouts are changed.

const DIR := "res://data/card_layout"
const LANGS := ["en", "ru", "de", "fr", "es", "pt_BR", "it", "pl"]
## At card scale 1 (CardView.SIZE 120x170).
const NAME_BOX := Rect2(Vector2(10, 86), Vector2(100, 16))
const TEXT_BOX := Rect2(Vector2(14, 105), Vector2(92, 48))
## How much tighter than the font's own line height the text lines are (in sizes).
const LEADING_CUT := 0.25
## Gems the text must not run into (minions and weapons): centre and radius.
## (The attack gem's sword points out of the card, away from the text.)
const GEMS := [[Vector2(17, 154), 17.0], [Vector2(103, 154), 17.0]]

static var _data := {}  # lang -> card id -> {text, name, lines, valign?}


static func _lang(lang: String) -> Dictionary:
	if not _data.has(lang):
		var j := JSON.new()
		var path := "%s/%s.json" % [DIR, lang]
		_data[lang] = j.data if FileAccess.file_exists(path) and j.parse(FileAccess.get_file_as_string(path)) == OK and j.data is Dictionary else {}
	return _data[lang]


## The layout of a card in a language: text and name sizes, lines (rich lines:
## [b]bold[/b], [lb] for "["), valign ("top"; else centred), dy (a shift, px).
static func of(card_id: String, lang: String) -> Dictionary:
	var e: Dictionary = _lang(lang).get(card_id, {})
	return e if e.has("text") else {"text": 8, "name": 10}


static func store(card_id: String, lang: String, entry: Dictionary) -> void:
	_lang(lang)[card_id] = entry


## Writes one language's file (only where the game runs from its source folder).
static func save(lang: String) -> bool:
	var f := FileAccess.open("%s/%s.json" % [DIR, lang], FileAccess.WRITE)
	if f == null:
		return false
	var data := {}
	for id in _lang(lang):  # sizes and shifts as whole numbers ("11", not "11.0")
		var e: Dictionary = _lang(lang)[id].duplicate(true)
		for k in ["text", "name", "dy"]:
			if e.has(k):
				e[k] = int(e[k])
		data[id] = e
	f.store_string(JSON.stringify(data, "\t", true))
	return true


## Kept alive here: a TextParagraph holds only the fonts' RIDs.
static var _fonts := {}


static func _font(weight: int) -> Font:
	if not _fonts.has(weight):
		_fonts[weight] = Fonts.ui(weight)
	return _fonts[weight]


static func body_font() -> Font:
	return _font(500)


static func bold_font() -> Font:
	return _font(800)


static func name_font() -> Font:
	return _font(700)


## The card text as spans [[text, bold], ...], the layout's lines joined by "\n"
## (a card without lines yet: its own text, wrapped by paragraph()).
static func spans(card_id: String, lang: String) -> Array:
	var e := of(card_id, lang)
	var rich: String = "\n".join(e.lines) if e.has("lines") else CardText.rich(card_id, CardText.hs_locale(lang))
	var out := []
	var bold := false
	var i := 0
	while i < rich.length():
		var next := rich.find("[", i)
		if next < 0:
			next = rich.length()
		if next > i:
			out.append([rich.substr(i, next - i), bold])
		if next >= rich.length():
			break
		var close := rich.find("]", next)
		match rich.substr(next + 1, close - next - 1):
			"b": bold = true
			"/b": bold = false
			"lb": out.append(["[", bold])
		i = close + 1
	return out


static func paragraph(card_id: String, lang: String, k := 1.0) -> TextParagraph:
	var size := int(int(of(card_id, lang).text) * k)
	var p := TextParagraph.new()
	p.alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.line_spacing = -LEADING_CUT * size  # the font's own lines are 1.5 sizes apart
	p.break_flags = TextServer.BREAK_MANDATORY
	if not of(card_id, lang).has("lines"):
		p.width = TEXT_BOX.size.x * k
		p.break_flags |= TextServer.BREAK_WORD_BOUND
	for s in spans(card_id, lang):
		p.add_string(s[0], bold_font() if s[1] else body_font(), size)
	return p


## From the top of the first line to the bottom of the last.
static func height(p: TextParagraph) -> float:
	var h := 0.0
	for i in p.get_line_count():
		h += p.get_line_size(i).y + (p.line_spacing if i > 0 else 0.0)
	return h


## Where each line lies on the card (scale 1): the text is centred in its box,
## or at its top (valign "top"), then moved down by dy (up if negative).
static func line_rects(card_id: String, lang: String, p: TextParagraph, k := 1.0) -> Array:
	var out := []
	var h := height(p) / k
	var e := of(card_id, lang)
	var top: bool = e.get("valign", "") == "top"
	var y := TEXT_BOX.position.y + (0.0 if top else maxf(0.0, (TEXT_BOX.size.y - h) / 2.0)) + float(e.get("dy", 0))
	for i in p.get_line_count():
		var sz := p.get_line_size(i) / k
		var w := p.get_line_width(i) / k
		out.append(Rect2(Vector2(TEXT_BOX.get_center().x - w / 2.0, y), Vector2(w, sz.y)))
		y += sz.y + p.line_spacing / k
	return out


## Where the letters of each line are (scale 1): from the top of the capitals
## to the bottom of the descenders, without the empty space of the line.
static func ink_rects(card_id: String, lang: String, p: TextParagraph, k := 1.0) -> Array:
	var size := float(int(of(card_id, lang).text))
	var out := []
	var rects := line_rects(card_id, lang, p, k)
	for i in rects.size():
		var r: Rect2 = rects[i]
		var base := r.position.y + p.get_line_ascent(i) / k
		out.append(Rect2(Vector2(r.position.x, base - 0.72 * size), Vector2(r.size.x, 0.94 * size)))
	return out


static func _hits_gem(r: Rect2) -> bool:
	for g in GEMS:
		var c: Vector2 = g[0]
		var near := Vector2(clampf(c.x, r.position.x, r.end.x), clampf(c.y, r.position.y, r.end.y))
		if near.distance_to(c) < g[1]:
			return true
	return false


## What is wrong with a card's layout ([] = all fine): "no layout", "name too
## long", "text differs" (the lines do not say what the card says), "text too
## tall", "text too high", "text too low" (moved out of the box), "line too
## wide", "hits a gem" (the letters run into a gem).
static func problems(card_id: String, lang: String) -> Array:
	var out := []
	var e := of(card_id, lang)
	if not _lang(lang).has(card_id):
		out.append("no layout")
	var name := CardText.name(card_id, CardText.hs_locale(lang))
	if name_font().get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(e.name)).x > NAME_BOX.size.x:
		out.append("name too long")
	var want := _plain(CardText.rich(card_id, CardText.hs_locale(lang)))
	if want == "":
		return out
	if _plain("\n".join(e.get("lines", []))) != want:
		out.append("text differs")
	var p := paragraph(card_id, lang)
	if height(p) > TEXT_BOX.size.y:
		out.append("text too tall")
	var rects := line_rects(card_id, lang, p)
	if rects[0].position.y < TEXT_BOX.position.y - 0.5:
		out.append("text too high")
	if rects[-1].end.y > TEXT_BOX.end.y + 0.5:
		out.append("text too low")
	if rects.any(func(r): return r.size.x > TEXT_BOX.size.x + 0.5):
		out.append("line too wide")
	if CardDb.card(card_id).get("type") in ["MINION", "WEAPON"] and ink_rects(card_id, lang, p).any(_hits_gem):
		out.append("hits a gem")
	return out


## The text without tags and spacing: what a layout's lines must still say.
static func _plain(rich: String) -> String:
	for t in ["[b]", "[/b]", "[i]", "[/i]", "\n", " ", " "]:
		rich = rich.replace(t, "")
	return rich.replace("[lb]", "[")
