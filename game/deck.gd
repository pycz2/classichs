class_name Deck
extends RefCounted
## A player's deck: name, hero and 30 card ids, with Hearthstone deck-building rules.

const SIZE := 30
const NAME_MAX := 60

var name := ""
var hero := "HERO_08"
var cards: Array[String] = []


func card_class() -> String:
	return Decks.card_class(hero)


func count(id: String) -> int:
	return cards.count(id)


static func max_copies(id: String) -> int:
	return 1 if CardDb.card(id).get("rarity", "") == "LEGENDARY" else 2


## Why id can't be added ("" = it can).
func can_add(id: String) -> String:
	if not CardDb.has(id) or not CardDb.collectible().has(id):
		return TranslationServer.translate("This card can't be put in a deck")
	var cls: String = CardDb.card(id).cardClass
	if cls != "NEUTRAL" and cls != card_class():
		return TranslationServer.translate("This card belongs to another class")
	if cards.size() >= SIZE:
		return TranslationServer.translate("The deck already has 30 cards")
	if count(id) >= max_copies(id):
		return TranslationServer.translate("No more copies of this card are allowed")
	return ""


func add(id: String) -> String:
	var why := can_add(id)
	if why == "":
		cards.append(id)
	return why


func remove(id: String) -> bool:
	var i := cards.find(id)
	if i < 0:
		return false
	cards.remove_at(i)
	return true


## Why the deck can't be played ("" = it is complete and legal).
func validate() -> String:
	if not Decks.HEROES.values().has(hero):
		return TranslationServer.translate("Unknown hero")
	var copy := Deck.new()
	copy.hero = hero
	for id in cards:
		var why := copy.add(id)
		if why != "":
			return why
	if cards.size() != SIZE:
		return TranslationServer.translate("A deck needs exactly 30 cards. Cards now: %d") % cards.size()
	return ""


## [card id, copies] sorted by cost, then name.
func sorted_counts() -> Array:
	var seen := {}
	for id in cards:
		seen[id] = seen.get(id, 0) + 1
	var out: Array = []
	for id in seen:
		out.append([id, seen[id]])
	out.sort_custom(func(a, b):
		var ca := int(CardDb.card(a[0]).get("cost", 0))
		var cb := int(CardDb.card(b[0]).get("cost", 0))
		return ca < cb or (ca == cb and CardText.name(a[0]) < CardText.name(b[0])))
	return out


func to_dict() -> Dictionary:
	return {"name": name, "hero": hero, "cards": cards.duplicate()}


## A deck from saved data; unknown fields are ignored. Card ids that no longer
## exist are dropped (they could never be played); a bad structure or an
## unknown hero gives null.
static func from_dict(d: Variant) -> Deck:
	if not d is Dictionary or not d.get("hero") is String or not d.get("cards") is Array:
		return null
	if not Decks.HEROES.values().has(d.hero):
		return null
	var deck := Deck.new()
	deck.name = str(d.get("name", "")).left(NAME_MAX)
	deck.hero = d.hero
	for id in d.cards:
		if not id is String:
			return null
		if CardDb.has(id):
			deck.cards.append(id)
	return deck
