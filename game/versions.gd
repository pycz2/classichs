class_name Versions
extends RefCounted
## The versions of a pack with versions (docs/packs/format.md §13) as the player sees them: their names and dates,
## the eras they belong to, and how the cards of two versions differ (the games library's "Compare versions").

## An era (a version's `era`: the pack folder its version is built from) -> the set it brought; the pack's locales
## name that set ("sets"), so the era is named as the game named the expansion.
const ERA_SETS := {"classic": "VANILLA", "naxx": "NAXX", "gvg": "GVG", "brm": "BRM", "tgt": "TGT", "loe": "LOE",
	"og": "OG", "kara": "KARA", "msg": "GANGS", "ungoro": "UNGORO", "icc": "ICECROWN", "loot": "LOOTAPALOOZA",
	"gil": "GILNEAS", "boom": "BOOMSDAY", "trl": "TROLL", "dal": "DALARAN"}
## What a card can differ in between versions, in the order a change lists them: [field, its name (an English key)].
## name and text are in the interface language; art: the picture a card points at.
const FIELDS := [["name", "Name"], ["cost", "Cost"], ["attack", "Attack"], ["health", "Health"],
	["durability", "Durability"], ["text", "Text"], ["keywords", "Keywords"], ["race", "Tribe"], ["rarity", "Rarity"],
	["class", "Class"], ["set", "Set"], ["art", "Picture"]]


## A version's manifest entry ({} when the pack has no such version).
static func entry(p: Pack, vid: String) -> Dictionary:
	for v in p.versions():
		if v is Dictionary and str(v.get("id", "")) == vid:
			return v
	return {}


## A version's name and date: "Leeroy Jenkins and Starving Buzzard nerfed, 2014-09-22". vid "": the version of a
## view, else the one the player chose. "" for a pack without versions.
static func label(p: Pack, vid := "") -> String:
	if vid == "":
		vid = p.version_id if p.version_id != "" else Packs.version(p)
	var v := entry(p, vid)
	if v.is_empty():
		return ""
	var date := str(v.get("date", ""))
	return p.text_of(v.get("name", vid)) + (", " + date if date != "" else "")


## The versions by era, oldest first: [{id, name, from, to (dates), versions: [manifest entries]}].
static func eras(p: Pack) -> Array:
	var out := []
	for v in p.versions():
		if not v is Dictionary:
			continue
		var e := str(v.get("era", ""))
		if out.is_empty() or out[-1].id != e:
			out.append({"id": e, "versions": []})
		out[-1].versions.append(v)
	var newest := p.version_view(p.default_version()) if p.default_version() != "" else null
	for e in out:
		e.from = str(e.versions[0].get("date", ""))
		e.to = str(e.versions[-1].get("date", ""))
		var key: String = ERA_SETS.get(e.id, "")
		e.name = newest.text(["sets", key]) if newest and key != "" else ""
		if e.name == "" and key != "":  # (a default version older than the era: the era's own version names it)
			var own := p.version_view(str(e.versions[-1].get("id", "")))
			e.name = own.text(["sets", key]) if own else ""
		if e.name == "":
			e.name = e.id.capitalize()
	return out


## How the cards of version b differ from version a's (two version views): {changed: [{id, fields, a, b}],
## added: [{id, b}], removed: [{id, a}]}; a and b: the card as in that version (its pack fields, with name and text
## in the language). Changed: a card both have that differs in FIELDS; added and removed: the collectible cards.
## Each list goes by cost, then name.
static func diff(a: Pack, b: Pack, lang := "") -> Dictionary:
	var ca := _cards(a, lang)
	var cb := _cards(b, lang)
	var out := {"changed": [], "added": [], "removed": []}
	for id in cb:
		var y: Dictionary = cb[id]
		var x: Dictionary = ca.get(id, {})
		if y.get("collectible", false) and not x.get("collectible", false):
			out.added.append({"id": id, "b": y})
		elif not x.is_empty():
			var fields := []
			for f in FIELDS:
				var u = x.get(f[0])
				var w = y.get(f[0])
				if typeof(u) != typeof(w) or u != w:
					fields.append(f[0])
			if not fields.is_empty():
				out.changed.append({"id": id, "fields": fields, "a": x, "b": y})
	for id in ca:
		if ca[id].get("collectible", false) and not cb.get(id, {}).get("collectible", false):
			out.removed.append({"id": id, "a": ca[id]})
	for k in out:
		out[k].sort_custom(func(m, n):
			var c: Dictionary = m.get("b", m.get("a"))
			var d: Dictionary = n.get("b", n.get("a"))
			return [int(c.get("cost", 0)), str(c.name), m.id] < [int(d.get("cost", 0)), str(d.name), n.id])
	return out


## A version's cards by id: the pack's fields, its keywords in order, name and text in the language.
static func _cards(p: Pack, lang: String) -> Dictionary:
	var l := p.lang_for(lang if lang != "" else TranslationServer.get_locale())
	var texts = p.locale(l).get("cards", {})
	var base = p.locale(p.default_locale()).get("cards", {}) if l != p.default_locale() else texts
	var out := {}
	for c in p.cards():
		if not c is Dictionary or not c.has("id"):
			continue
		var d: Dictionary = c.duplicate()
		var t: Dictionary = texts.get(c.id, base.get(c.id, {})) if texts is Dictionary else {}
		d.name = str(t.get("name", c.id))
		d.text = str(t.get("text", ""))
		if d.get("keywords") is Array:
			d.keywords = d.keywords.duplicate()
			d.keywords.sort()
		out[c.id] = d
	return out
