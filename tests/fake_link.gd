class_name FakeLink
extends ServerLink
## A ServerLink without a socket: "connected" at once, what it sends is kept in
## `sent`, and tests deliver the server's messages with dispatch().

var sent: Array = []
var up := true


func open(address: String) -> Error:
	url = address
	resuming = false
	token = ""
	return OK


func is_open() -> bool:
	return up


func send(msg: Dictionary) -> void:
	sent.append(msg)


## The messages of one type sent so far.
func of(t: String) -> Array:
	return sent.filter(func(m): return m.get("t") == t)


func close() -> void:
	super()
	up = false


## A game in the local engine standing in for the server's (id eng): Basic Mage
## against Basic Warrior.
static func engine_game(eng: String, seed := 5) -> void:
	Rules.request({"op": "new", "game": eng, "seed": seed, "first": 0, "decks": [
		{"hero": "HERO_08", "cards": Decks.basic("MAGE")}, {"hero": "HERO_01", "cards": Decks.basic("WARRIOR")}]})


## The server's `state` of game for seat, from the engine game eng (the player's view only).
static func state(game: String, eng: String, seat: int, events := []) -> Dictionary:
	var v: Dictionary = Rules.request({"op": "snapshot", "game": eng, "view": seat}).state
	return {"t": "state", "game": game, "view": v, "events": events, "result": {"over": v.game_over,
		"winner": v.winner, "turn": v.turn, "current": v.current, "phase": v.phase, "deadline": 75}}
