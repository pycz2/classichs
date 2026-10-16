class_name Decks
extends RefCounted
## The active pack's classes and champions (rules.json `classes`), and the ready decks
## a player starts with (Basic decks; a pack's own decks/*.json).

static var _heroes := {}  # class -> champion card id, in the pack's order


static func reset() -> void:
	_heroes = {}


## class -> champion card id of every playable class.
static func heroes() -> Dictionary:
	if _heroes.is_empty() and Packs.active():
		for c in Packs.active().rules().get("classes", []):
			if c is Dictionary and c.has("champion") and c.get("playable", true):
				_heroes[str(c.id)] = str(c.champion)
	return _heroes


## The playable classes in the pack's order.
static func classes() -> Array:
	return heroes().keys()


## The playable classes and the neutral one(s) (collection tabs).
static func classes_and_neutral() -> Array:
	var out := classes()
	for c in Packs.active().rules().get("classes", []) if Packs.active() else []:
		if c is Dictionary and c.get("neutral", false):
			out.append(str(c.id))
	return out


static func hero(card_class: String) -> String:
	return heroes().get(card_class, "")


static func card_class(hero_id: String) -> String:
	var c = heroes().find_key(hero_id)
	return c if c != null else ""


## Neutral cards that fill a class deck, in priority order (rules.json constructed.starter_core).
static func neutral_core() -> Array:
	return Packs.active().rules().get("modes", {}).get("constructed", {}).get("starter_core", [])


## Two copies of every Basic card of the class, then neutral core cards up to 30; a pack
## without Basic cards gives its own ready deck of that champion.
static func basic(card_class: String) -> Array:
	var deck: Array = []
	for id in CardDb.collectible():
		var c := CardDb.card(id)
		if c.cardClass == card_class and c.get("rarity", "") == "FREE":
			deck.append_array([id, id])
	for id in neutral_core():
		for i in 2:
			if deck.size() < 30:
				deck.append(id)
	if deck.size() < 30:
		for d in ready():
			if d.champion == hero(card_class):
				return d.cards.duplicate()
	return deck


## The pack's ready decks (decks/*.json, by file name): [{name, champion, cards, code?, key}].
static func ready() -> Array:
	var p := Packs.active()
	var out := []
	for f in p.files() if p else []:
		if f.begins_with("decks/") and f.ends_with(".json"):
			var d = p.json(f)
			if d is Dictionary and d.get("cards") is Array and d.has("champion"):
				var e: Dictionary = d.duplicate()
				e.key = f.get_file().get_basename()
				out.append(e)
	return out
