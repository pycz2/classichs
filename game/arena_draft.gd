class_name ArenaDraft
extends RefCounted
## The Arena draft as in Hearthstone in 2014: three heroes of different classes to
## choose from, then 30 picks; each pick offers three different cards of one
## rarity (Basic and Common are one tier) from the hero's class and the neutral
## cards. Picks 1, 10, 20 and 30 are Rare or better; class cards are 1.5 times as
## likely as neutral ones; an Arena deck has no limit on copies.
## The odds are a ruling (docs/superpowers/specs/2026-10-12-arena-design.md).

const PICKS := 30
const SPECIAL := [0, 9, 19, 29]  # pick indexes that are Rare or better
const ODDS := {"common": 0.80, "rare": 0.14, "epic": 0.05, "legendary": 0.01}
const SPECIAL_ODDS := {"rare": 0.78, "epic": 0.18, "legendary": 0.04}
const CLASS_WEIGHT := 1.5
const CLASSES := ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"]

var rng := RandomNumberGenerator.new()
var heroes: Array[String] = []  # the three offered
var hero := ""
var cards: Array[String] = []
var offer: Array[String] = []  # the three cards of the current pick


func _init(seed := -1) -> void:
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	var classes := CLASSES.duplicate()
	for i in 3:
		heroes.append(Decks.hero(classes.pop_at(rng.randi_range(0, classes.size() - 1))))


func choose_hero(i: int) -> void:
	hero = heroes[i]
	_next()


## Takes card i of the offer; the other two are gone.
func pick(i: int) -> void:
	if done() or i < 0 or i >= offer.size():
		return
	cards.append(offer[i])
	_next()


func done() -> bool:
	return cards.size() >= PICKS


func deck() -> Deck:
	var d := Deck.new()
	d.name = TranslationServer.translate("Arena")
	d.hero = hero
	d.arena = true
	d.cards = cards.duplicate()
	return d


## How many cards cost 0, 1, … 6 and 7 or more.
func curve() -> Array:
	var out := [0, 0, 0, 0, 0, 0, 0, 0]
	for id in cards:
		out[mini(int(CardDb.card(id).get("cost", 0)), 7)] += 1
	return out


func _next() -> void:
	offer.clear()
	if not done():
		offer = roll_offer(roll_tier(cards.size() in SPECIAL))


## The rarity tier of a card: Basic counts as common.
static func tier(id: String) -> String:
	var r: String = CardDb.card(id).get("rarity", "FREE")
	return "common" if r == "FREE" or r == "COMMON" else r.to_lower()


func roll_tier(special: bool) -> String:
	var odds: Dictionary = SPECIAL_ODDS if special else ODDS
	var x := rng.randf()
	for t in odds:
		x -= odds[t]
		if x < 0.0:
			return t
	return odds.keys()[-1]


## The cards of a tier for a class with their weights: [[id, weight], …].
static func pool(card_class: String, t: String) -> Array:
	var out := []
	for id in CardDb.collectible():
		var c := CardDb.card(id)
		if c.type == "HERO" or tier(id) != t:
			continue
		if c.cardClass == card_class:
			out.append([id, CLASS_WEIGHT])
		elif c.cardClass == "NEUTRAL":
			out.append([id, 1.0])
	return out


## Three different cards of tier t for the hero, drawn by weight.
func roll_offer(t: String) -> Array[String]:
	var left := pool(Decks.card_class(hero), t)
	var out: Array[String] = []
	while out.size() < 3 and not left.is_empty():
		var total := 0.0
		for it in left:
			total += it[1]
		var x := rng.randf() * total
		var k := 0
		while k < left.size() - 1 and x >= left[k][1]:
			x -= left[k][1]
			k += 1
		out.append(left.pop_at(k)[0])
	return out
