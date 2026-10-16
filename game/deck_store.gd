class_name DeckStore
extends RefCounted
## Saved decks in user:// (IndexedDB in the browser), one file per game pack (the Classic
## pack's is decks.json, another pack's decks.<pack id>.json). A broken file is kept aside
## as *.bad.json instead of being lost.

const DEFAULT_PATH := "user://decks.json"
const VERSION := 1

## Well-known decks of the Classic era, ready to play (name, deck code).
const CLASSIC := [
	["Control Warrior", "AAEDAQcIraEEr6EE3KEExKIExqIE1qIE2aIExKoEC5eWBJiWBP+WBLCXBLGhBMShBNChBLmiBL6iBMCiBMOiBAAA"],
	["Midrange Shaman", "AAEDAaa0BgK1oQSHogQO7ZUE7pUEr5YE55YE+ZYEsqEEy6EE06EEhKIEiaIEjqIEk6IE1KIEkKMEAAA="],
	["Midrange Druid", "AAEDAZICCK2hBK+hBLWhBL6hBNuhBI+jBJajBNGjBAvZlQTblQSwlgSzlgTdlgTpoQTxoQTUogS8owS9owTFqgQAAA=="],
	["Control Priest", "AAEDAa0GBr6WBICXBLehBNKhBJiiBKeiBAzLlQTNlQTQlQS3lwT6oASAoQSTogSpogSXowSrowStowTEowQAAA=="],
	["Miracle Rogue", "AAEDAaIHBvigBPugBIahBLWhBNyhBKWjBAz8lQT9lQTclgTqlgT7lgTBoQTUoQTdoQTfoQTkoQTnoQTooQQAAA=="],
	["Midrange Paladin", "AAEDAZ8FAraiBLeiBA6MlgSOlgSQlgSBoQSuoQS6oQS9oQS+oQTLoQTgoQSwogS1ogTDowTFowQAAA=="],
	["Handlock", "AAEDAf0GCvuVBK6XBIKhBK+hBNahBNyhBJqiBJyiBKWiBNyiBAr3lQTrlgTtlgT6oATAoQTCoQTJoQTToQTaoQSqowQAAA=="],
	["Freeze Mage", "AAEDAf0ECOWVBOeVBK+hBLWhBMahBJGiBNeiBNmiBAvhlQTilQTklQTmlQTUlgTzoAT0oASVogSXogSYowTFowQAAA=="],
	["Midrange Hunter", "AAEDAR8EhZYEnZYEwJYE3KEEDcqWBNGWBPiWBLGXBLyhBL2hBMyiBM2iBM+iBKKjBKOjBKijBMOjBAAA"],
	["Zoolock", "AAEDAf0GBK6hBMOhBNyhBMWjBA33lQT7lQTVlgTtlgSBoQSyoQS9oQTToQTuoQSdogSjogTUogTDowQAAA=="],
]

static var path := DEFAULT_PATH
## Set by load_all when the file was damaged (a copy is kept); shown to the player.
static var last_load_error := ""


## The decks file of the active pack.
static func file() -> String:
	var p := Packs.active()
	return path if p == null or p.id() == Packs.CLASSIC else "%s.%s.json" % [path.get_basename(), p.id()]


## The ready decks a first run starts with: the classic decks, and a Basic deck
## only for a class that has no classic deck.
static func starter() -> Array[Deck]:
	var out := classic()
	var covered := out.map(func(d: Deck): return d.card_class())
	for cls in Decks.classes():
		if not covered.has(cls) and Decks.basic(cls).size() == Deck.SIZE:
			out.append(_basic(cls))
	return out


static func _basic(cls: String) -> Deck:
	var d := Deck.new()
	d.hero = Decks.hero(cls)
	d.name = TranslationServer.translate("Basic deck: %s") % CardText.name(d.hero)
	d.cards.assign(Decks.basic(cls))
	return d


## The pack's ready decks (Classic: the well-known decks of the era, from their codes).
static func classic() -> Array[Deck]:
	var out: Array[Deck] = []
	if Packs.active() and Packs.active().id() != Packs.CLASSIC:
		for r in Decks.ready():
			var d := Deck.from_dict({"name": CardText.term("decks", r.key), "hero": r.champion, "cards": r.cards})
			if d:
				if d.name == "":
					d.name = str(r.name)
				out.append(d)
		return out
	for spec in CLASSIC:
		var d: Deck = DeckCode.decode(spec[1]).deck
		if d:
			d.name = spec[0]
			out.append(d)
	return out


static func load_all() -> Array[Deck]:
	var out: Array[Deck] = []
	var at := file()
	if not FileAccess.file_exists(at):
		return starter()
	var text := FileAccess.get_file_as_string(at)
	var j := JSON.new()
	var ok := j.parse(text) == OK and j.data is Dictionary and j.data.get("decks") is Array
	last_load_error = ""
	if ok:
		for d in j.data.decks:
			var deck := Deck.from_dict(d)
			if deck == null:
				ok = false
			else:
				if deck.cards.size() != d.cards.size():
					ok = false  # some cards no longer exist
				out.append(deck)
	if ok and int(j.data.get("classic", 0)) < 1:  # saved before the classic decks came: they are added once
		out.append_array(classic())
	if ok and int(j.data.get("basic", 0)) < 1:  # saved when every class got a Basic deck: the unchanged
		var covered := classic().map(func(d: Deck): return d.card_class())  # ones of classes with a classic deck go, once
		out = out.filter(func(d: Deck): return not (covered.has(d.card_class()) \
			and d.sorted_counts() == _basic(d.card_class()).sorted_counts()))
	if not ok:
		var backup := _free_backup_path(at)
		var bad := FileAccess.open(backup, FileAccess.WRITE)
		if bad:
			bad.store_string(text)
		last_load_error = TranslationServer.translate("The saved decks file was damaged; a copy was kept as %s") % backup.get_file()
	return out


## decks.bad.json, then decks.bad1.json, … — never overwrite an earlier copy.
static func _free_backup_path(at: String) -> String:
	var base := at.get_basename() + ".bad"
	var p := base + ".json"
	var n := 1
	while FileAccess.file_exists(p):
		p = "%s%d.json" % [base, n]
		n += 1
	return p


static func save_all(decks: Array) -> bool:
	var data := {"version": VERSION, "classic": 1, "basic": 1, "decks": decks.map(func(d: Deck): return d.to_dict())}
	var at := file()
	var tmp := at + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return DirAccess.rename_absolute(tmp, at) == OK
