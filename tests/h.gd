class_name H
extends RefCounted
## Test helpers.

const WISP := "VAN_CS2_231"

static var _defined: Array[String] = []


## A bare GameState with Jaina (player 0) and Garrosh (player 1) in play.
static func state(seed := 1) -> GameState:
	var g := GameState.new(seed)
	g.setup_players("HERO_08", "HERO_01")
	g.event_log.clear()
	return g


static func hand(g: GameState, p: int, id: String) -> Entity:
	var e := g.new_entity(id, p)
	e.zone = "HAND"
	g.players[p].hand.append(e)
	return e


## A minion on the board that can attack now.
static func board(g: GameState, p: int, id: String) -> Entity:
	var e := g.new_entity(id, p)
	g.place_on_board(e, -1)
	g.update_auras()
	return e


static func card(id: String, c: Dictionary, hooks := {}) -> void:
	var full := {"set": "TEST", "cardClass": "NEUTRAL", "rarity": "COMMON", "cost": 0,
		"name": {"enUS": id}, "text": {}, "mechanics": []}
	full.merge(c, true)
	CardDb.define(id, full)
	Cards.add(id, hooks)
	_defined.append(id)


## Removes test cards. Their hook lambdas must not outlive the test script.
static func cleanup() -> void:
	for id in _defined:
		Cards.remove(id)
		CardDb.undefine(id)
	_defined.clear()


static func types(events: Array) -> Array:
	return events.map(func(ev: Dictionary) -> String: return ev.type)
