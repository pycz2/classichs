class_name DeckCode
extends RefCounted
## Hearthstone deck codes ("deckstrings"): base64 of varints
## [0, 1, format, 1, hero, n1, singles…, n2, doubles…, n3, (card, count)…].

const FORMAT_WILD := 1
const FORMAT_STANDARD := 2
const FORMAT_CLASSIC := 3
static var _b64 := RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$")


static func _t(s: String) -> String:
	return TranslationServer.translate(s)


static func _varint(out: PackedByteArray, v: int) -> void:
	while true:
		var b := v & 0x7f
		v >>= 7
		if v == 0:
			out.append(b)
			return
		out.append(b | 0x80)


## Raw deckstring from parts (sorted ascending, as the game writes them).
static func pack(format: int, heroes: Array, singles: Array, doubles: Array) -> String:
	var out := PackedByteArray()
	for v in [0, 1, format, heroes.size()]:
		_varint(out, v)
	var parts := [heroes.duplicate(), singles.duplicate(), doubles.duplicate()]
	for i in 3:
		parts[i].sort()
		if i > 0:
			_varint(out, parts[i].size())
		for v in parts[i]:
			_varint(out, v)
	_varint(out, 0)
	return Marshalls.raw_to_base64(out)


static func encode(deck: Deck) -> String:
	var singles := []
	var doubles := []
	for pair in deck.sorted_counts():
		var dbf: int = CardDb.card(pair[0]).dbfId
		(doubles if pair[1] == 2 else singles).append(dbf)
	return pack(FORMAT_CLASSIC, [CardDb.card(deck.hero).dbfId], singles, doubles)


## Parses the binary layout only: {"format", "heroes", "singles", "doubles", "error"}.
static func parse(code: String) -> Dictionary:
	var bad := {"error": _t("This is not a deck code")}
	code = code.strip_edges()
	if code.length() < 8 or code.length() % 4 != 0 or _b64.search(code) == null:
		return bad
	var raw := Marshalls.base64_to_raw(code)
	var pos := [0]
	var read := func() -> int:
		var v := 0
		var shift := 0
		while pos[0] < raw.size() and shift < 63:
			var b := raw[pos[0]]
			pos[0] += 1
			v |= (b & 0x7f) << shift
			shift += 7
			if b & 0x80 == 0:
				return v
		return -1
	if read.call() != 0 or read.call() != 1:
		return bad
	var format: int = read.call()
	var lists := []
	for i in 3:
		var n: int = read.call()
		if n < 0 or n > 60:
			return bad
		var items := []
		for j in n:
			var v: int = read.call()
			if v < 0:
				return bad
			items.append(v)
		lists.append(items)
	var extra: int = read.call()
	if extra < 0:
		return bad
	if extra != 0:
		return {"error": _t("Decks with more than 2 copies of a card are not supported")}
	return {"format": format, "heroes": lists[0], "singles": lists[1], "doubles": lists[2], "error": ""}


static func _hero_from_cards(dbfs: Array) -> String:
	for dbf in dbfs:
		var id := CardDb.by_dbf(dbf)
		if id != "" and CardDb.card(id).cardClass != "NEUTRAL" and Decks.heroes().has(CardDb.card(id).cardClass):
			return Decks.hero(CardDb.card(id).cardClass)
	return ""


## A deck from a code or from text copied out of the Hearthstone client
## ("### Name" header and "#" comment lines). {"deck": Deck or null, "error"}.
static func decode(text: String) -> Dictionary:
	var name := ""
	var p := {"error": _t("This is not a deck code")}
	for line in text.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("###"):
			name = l.substr(3).strip_edges().left(Deck.NAME_MAX)
		elif l != "" and not l.begins_with("#") and p.error != "":
			var q := parse(l)  # deck sites put a title line before the code
			if q.error == "" or p.error == _t("This is not a deck code"):
				p = q
	if p.error != "":
		return {"deck": null, "error": p.error}
	if not p.format in [FORMAT_WILD, FORMAT_STANDARD, FORMAT_CLASSIC]:
		return {"deck": null, "error": _t("Unknown deck format")}
	if p.heroes.size() != 1:
		return {"deck": null, "error": _t("A deck needs exactly one hero")}
	var hero := CardDb.by_dbf(p.heroes[0])
	if not Decks.heroes().values().has(hero):
		hero = _hero_from_cards(p.singles + p.doubles)  # a hero skin (Magni, Medivh…)
		if hero == "":
			return {"deck": null, "error": _t("Unknown hero in the deck code")}
	var deck := Deck.new()
	deck.name = name if name != "" else _t("Imported deck")
	deck.hero = hero
	for pair in [[p.singles, 1], [p.doubles, 2]]:
		for dbf in pair[0]:
			var id := CardDb.by_dbf(dbf)
			if id == "" or not CardDb.collectible().has(id):
				return {"deck": null, "error": _t("The deck has a card that is not in the Classic set (dbfId %d)") % dbf}
			for i in pair[1]:
				deck.cards.append(id)
	var why := deck.validate()
	if why != "":
		return {"deck": null, "error": why}
	return {"deck": deck, "error": ""}
