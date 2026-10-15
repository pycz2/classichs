class_name ArenaDraft
extends RefCounted
## The Arena draft (three heroes, then 30 picks of three cards): the engine's
## `draft` op computes it from the seed and the picks (stateless), so both online
## players and the server get the same offers. This keeps the seed and the picks.

const PICKS := 30

var seed := 0
var heroes: Array[String] = []  # the three offered
var hero := ""
var cards: Array[String] = []
var offer: Array[String] = []  # the three cards of the current pick
var _hero := -1
var _picks: Array = []


func _init(p_seed := -1) -> void:
	seed = p_seed if p_seed >= 0 else randi()
	_ask()


func choose_hero(i: int) -> void:
	_hero = i
	_ask()


## Takes card i of the offer; the other two are gone.
func pick(i: int) -> void:
	if done() or i < 0 or i >= offer.size():
		return
	_picks.append(i)
	_ask()


func _ask() -> void:
	var req := {"op": "draft", "seed": seed}
	if _hero >= 0:
		req.merge({"hero": _hero, "picks": _picks})
	var r := Rules.request(req)
	heroes.assign(r.get("heroes", []))
	hero = str(r.get("hero", ""))
	cards.assign(r.get("cards", []))
	offer.assign(r.get("offer", []))


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


## The rarity tier of a card (Basic counts as common), as the draft screens show it.
static func tier(id: String) -> String:
	var r: String = CardDb.card(id).get("rarity", "FREE")
	return "common" if r == "FREE" or r == "COMMON" else r.to_lower()
