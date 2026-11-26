class_name StudioSets
extends Control
## The Studio's Sets & rarities tab: the sets (a name per language; playable in constructed or not: rules
## modes.constructed.sets), the rarities (tier, colour, name) and the tribes (rules races), each added and
## removed (a set, rarity or tribe cards still use stays).

signal changed

const TIERS := ["common", "rare", "epic", "legendary"]

var project: StudioProject
var studio: Studio
var lang := "en"
var _why: Label


func _ready() -> void:
	refresh()


func refresh() -> void:
	Studio.clear(self)
	var v := Studio.page(self)
	_why = Palette.label("", 15, Palette.DANGER)
	_why.name = "Problem"
	v.add_child(Studio.row([Studio.languages(lang, func(l):
		lang = l
		refresh()), _why], 24))
	# sets
	v.add_child(Studio.heading(tr("Sets")))
	var playable: Array = project.rules.get_or_add("modes", {}).get_or_add("constructed", {"class_cards": "own_and_neutral"}).get_or_add("sets", [])
	for s: String in project.rules.sets:
		var r := Studio.row([_id(s), _term("sets", s),
			Studio.toggle(tr("Playable in constructed"), playable.has(s), "Playable", func(on):
				if on and not playable.has(s):
					playable.append(s)
				elif not on:
					playable.erase(s)
				changed.emit()),
			_remove(func(): return project.remove_set(s))])
		r.name = "Set_" + s
		v.add_child(r)
	var sid := Studio.field("", "NewSet", func(_t): pass, 200)
	var add_s := Studio.button(tr("Add a set"), "AddSet", 180)
	add_s.pressed.connect(func(): _did(add_set(sid.text.strip_edges())))
	v.add_child(Studio.row([tr("Id"), sid, add_s]))
	# rarities
	v.add_child(Studio.heading(tr("Rarities")))
	var colors: Dictionary = project.manifest.get_or_add("colors", {}).get_or_add("rarities", {})
	for rar: Dictionary in project.rules.rarities:
		var rid := str(rar.id)
		var tier := OptionButton.new()
		tier.name = "Tier"
		for t in TIERS:
			tier.add_item(tier_name(t))
		tier.select(TIERS.find(rar.get("tier", "common")))
		tier.item_selected.connect(func(i):
			rar.tier = TIERS[i]
			changed.emit())
		var r := Studio.row([_id(rid), _term("rarities", rid), tier,
			Studio.color_button(str(colors.get(rid, "e0e0e0")), "Color", func(hex):
				colors[rid] = hex
				changed.emit()),
			_remove(func(): return project.remove_rarity(rid))])
		r.name = "Rarity_" + rid
		v.add_child(r)
	var rid_f := Studio.field("", "NewRarity", func(_t): pass, 200)
	var new_tier := OptionButton.new()
	for t in TIERS:
		new_tier.add_item(tier_name(t))
	var add_r := Studio.button(tr("Add a rarity"), "AddRarity", 180)
	add_r.pressed.connect(func(): _did(project.add_rarity(rid_f.text.strip_edges().to_upper(), TIERS[new_tier.selected])))
	v.add_child(Studio.row([tr("Id"), rid_f, new_tier, add_r]))
	# tribes
	v.add_child(Studio.heading(tr("Tribes")))
	for race: String in project.rules.get("races", []):
		var r := Studio.row([_id(race), _term("races", race), _remove(func(): return remove_race(race))])
		r.name = "Tribe_" + race
		v.add_child(r)
	var tid := Studio.field("", "NewTribe", func(_t): pass, 200)
	var add_t := Studio.button(tr("Add a tribe"), "AddTribe", 180)
	add_t.pressed.connect(func(): _did(add_race(tid.text.strip_edges())))
	v.add_child(Studio.row([tr("Id"), tid, add_t]))


func tier_name(t: String) -> String:
	match t:
		"rare": return tr("Rare")
		"epic": return tr("Epic")
		"legendary": return tr("Legendary")
	return tr("Common")


func _id(id: String) -> Label:
	var l := Palette.label(id, 17, Palette.ATTACK)
	l.custom_minimum_size = Vector2(160, 0)
	return l


func _term(section: String, key: String) -> LineEdit:
	return Studio.field(project.locales.get(lang, {}).get(section, {}).get(key, ""), "Name", func(t):
		project.set_term(section, key, lang, t.strip_edges())
		changed.emit(), 220)


func _remove(f: Callable) -> Button:
	var b := Studio.button(tr("Remove"), "Remove", 110)
	b.pressed.connect(func(): _did(f.call()))
	return b


## After an add or a remove: "" refreshes the tab, else the reason shows.
func _did(why: String) -> void:
	if why != "":
		_why.text = tr(why)
		return
	changed.emit()
	refresh()


## Adds a set, playable in constructed; "" or why not.
func add_set(sid: String) -> String:
	return project.add_set(sid, true)


## Adds a tribe (an upper-case id); "" or why not.
func add_race(race: String) -> String:
	race = race.to_upper()
	if RegEx.create_from_string("^[A-Z0-9_]{1,64}$").search(race) == null:
		return "Use Latin letters, digits and underscores"
	var races: Array = project.rules.get_or_add("races", [])
	if races.has(race):
		return "A tribe with this id exists"
	races.append(race)
	project.set_term("races", race, "en", race.capitalize())
	return ""


## Removes a tribe no card is of; "" or why not.
func remove_race(race: String) -> String:
	if project.cards.any(func(c): return c.get("race") == race):
		return "Cards are of this tribe"
	project.rules.races.erase(race)
	for l in project.locales:
		project.locales[l].get("races", {}).erase(race)
	return ""
