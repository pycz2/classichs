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


## A Game in PLAY phase, turn of player 0, empty hands, 10/10 mana for both.
static func game(seed := 1) -> Game:
	var deck: Array = []
	for i in 20:
		deck.append(WISP)
	var g := Game.new({"hero": "HERO_08", "deck": deck}, {"hero": "HERO_01", "deck": deck}, seed, 0)
	g.apply({"type": "mulligan", "player": 0, "replace": []})
	g.apply({"type": "mulligan", "player": 1, "replace": []})
	for p in g.players:
		for e in p.hand:
			e.zone = "SETASIDE"
		p.hand.clear()
		p.max_mana = 10
		p.mana = 10
	g.event_log.clear()
	return g


static func play(g: Game, e: Entity, t: Entity = null, pos := -1, choice := -1) -> Dictionary:
	if pos < 0 and e.is_minion():
		pos = g.players[e.controller].board.size()
	return g.apply({"type": "play", "player": e.controller, "entity": e.id,
		"target": t.id if t else -1, "pos": pos, "choice": choice})


static func attack(g: Game, a: Entity, d: Entity) -> Dictionary:
	return g.apply({"type": "attack", "player": a.controller, "attacker": a.id, "defender": d.id})


static func power(g: Game, t: Entity = null) -> Dictionary:
	return g.apply({"type": "hero_power", "player": g.current, "target": t.id if t else -1})


static func end_turn(g: Game) -> Dictionary:
	return g.apply({"type": "end_turn", "player": g.current})
