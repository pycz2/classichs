class_name Deck
extends RefCounted
## A player's deck: name, hero and 30 card ids. The deck-building rules are the engine's.

const SIZE := 30
const NAME_MAX := 60

var name := ""
var hero := "HERO_08"
var cards: Array[String] = []
## An Arena deck: drafted, so any number of copies of a card.
var arena := false


func card_class() -> String:
	return Decks.card_class(hero)


func count(id: String) -> int:
	return cards.count(id)


## Why id can't be added ("" = it can): the engine's deck rules.
func can_add(id: String) -> String:
	if not CardDb.has(id):  # (the engine drops unknown ids from a deck it reads)
		return TranslationServer.translate("This card can't be put in a deck")
	var why := Rules.deck_error({"hero": hero, "cards": Array(cards) + [id], "arena": arena})
	return "" if why.begins_with("A deck needs exactly 30 cards") else Rules.tr_error(why)


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


## Why the deck can't be played ("" = it is complete and legal), from the engine.
func validate() -> String:
	return Rules.validate({"hero": hero, "cards": Array(cards), "arena": arena})


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
	var d := {"name": name, "hero": hero, "cards": cards.duplicate()}
	if arena:
		d["arena"] = true
	return d


## A deck from saved data; unknown fields are ignored. Card ids that no longer
## exist are dropped (they could never be played); a bad structure or an
## unknown hero gives null.
static func from_dict(d: Variant) -> Deck:
	if not d is Dictionary or not d.get("hero") is String or not d.get("cards") is Array:
		return null
	if not Decks.heroes().values().has(d.hero):
		return null
	var deck := Deck.new()
	deck.name = str(d.get("name", "")).left(NAME_MAX)
	deck.hero = d.hero
	deck.arena = d.get("arena", false) == true
	for id in d.cards:
		if not id is String:
			return null
		if CardDb.has(id):
			deck.cards.append(id)
	return deck
