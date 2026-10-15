class_name H
extends RefCounted
## Test helpers. Games run in the rules engine (Rules, rust/engine) through a
## Match; its GameView (m.game) is what the table draws. The rules themselves are
## tested in Rust (rust/engine/tests: parity with the old GDScript engine).

const WISP := "VAN_CS2_231"

static var _made: Array[Match] = []


## A local match from a scenario (the Debug Table format): PLAY phase, mana 10/10
## for a player that gives none. Nobody is a bot; a bot moves at once (bot_delay 0).
static func scene(p0: Dictionary, p1: Dictionary = {"hero": "HERO_01"}, current := 0, bots := [false, false]) -> Match:
	for p in [p0, p1]:
		if not p.has("mana"):
			p["mana"] = 10
			p["max_mana"] = 10
	var m := Match.new()
	m.bot_delay = 0.0
	var why := m.setup({"scenario": {"current": current, "players": [p0, p1]}}, bots)
	assert(why == "", why)
	_made.append(m)
	return m


## A match in PLAY phase, turn of player 0, empty hands, 10/10 mana, 20 Wisps in each deck.
static func game(hand0: Array = [], hand1: Array = []) -> Match:
	var deck: Array = []
	for i in 20:
		deck.append(WISP)
	return scene({"hero": "HERO_08", "deck": deck, "hand": hand0}, {"hero": "HERO_01", "deck": deck.duplicate(), "hand": hand1})


## A local match from two decks (lists of 30 card ids; Basic decks by class name).
static func decks(d0: Variant = "MAGE", d1: Variant = "WARRIOR", seed := 1, first := 0, bots := [false, false]) -> Match:
	var pair := []
	for d in [d0, d1]:
		pair.append({"hero": Decks.hero(d), "cards": Decks.basic(d)} if d is String else d)
	var m := Match.new()
	m.bot_delay = 0.0
	var why := m.setup({"decks": pair, "seed": seed, "first": first, "check": false}, bots)
	assert(why == "", why)
	_made.append(m)
	return m


static func play(m: Match, e: GameView.Ent, t: GameView.Ent = null, pos := -1, choice := -1) -> Dictionary:
	if pos < 0 and e.is_minion():
		pos = m.game.players[e.controller].board.size()
	return m.submit({"type": "play", "player": e.controller, "entity": e.id,
		"target": t.id if t else -1, "pos": pos, "choice": choice})


static func attack(m: Match, a: GameView.Ent, d: GameView.Ent) -> Dictionary:
	return m.submit({"type": "attack", "player": a.controller, "attacker": a.id, "defender": d.id})


static func power(m: Match, t: GameView.Ent = null) -> Dictionary:
	return m.submit({"type": "hero_power", "player": m.game.current, "target": t.id if t else -1})


static func end_turn(m: Match) -> Dictionary:
	return m.submit({"type": "end_turn", "player": m.game.current})


static func types(events: Array) -> Array:
	return events.map(func(ev: Dictionary) -> String: return ev.type)


## Frees the matches the helpers made that nothing else took (a MatchView frees its own).
static func cleanup() -> void:
	for m in _made:
		if is_instance_valid(m) and m.get_parent() == null:
			m.free()
	_made.clear()
