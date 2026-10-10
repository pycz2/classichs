class_name Decks
extends RefCounted
## Starter decks until the collection (subproject 3) exists.

const HEROES := {"WARRIOR": "HERO_01", "SHAMAN": "HERO_02", "ROGUE": "HERO_03", "PALADIN": "HERO_04",
	"HUNTER": "HERO_05", "DRUID": "HERO_06", "WARLOCK": "HERO_07", "MAGE": "HERO_08", "PRIEST": "HERO_09"}
## Neutral Basic cards that fill a class deck, in priority order.
const NEUTRAL_CORE := ["VAN_EX1_066", "VAN_CS2_172", "VAN_EX1_019", "VAN_CS2_182", "VAN_CS2_147",
	"VAN_CS2_179", "VAN_CS2_200", "VAN_CS2_120", "VAN_EX1_015", "VAN_CS2_189"]


static func hero(card_class: String) -> String:
	return HEROES[card_class]


static func card_class(hero_id: String) -> String:
	return HEROES.find_key(hero_id)


## Two copies of every Basic card of the class, then neutral core cards up to 30.
static func basic(card_class: String) -> Array:
	var deck: Array = []
	for id in CardDb.collectible():
		var c := CardDb.card(id)
		if c.cardClass == card_class and c.get("rarity", "") == "FREE":
			deck.append_array([id, id])
	for id in NEUTRAL_CORE:
		for i in 2:
			if deck.size() < 30:
				deck.append(id)
	return deck
