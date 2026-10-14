extends TestCase
## The server's referee: new games, checked actions with state hashes, decks, the
## Arena draft — the same engine and hashes as the clients.


func _decks() -> Array:
	return [{"hero": "HERO_08", "cards": Decks.basic("MAGE")}, {"hero": "HERO_01", "cards": Decks.basic("WARRIOR")}]


## JSON round trip, like the socket: numbers come as floats.
func _ask(r: Referee, req: Dictionary) -> Dictionary:
	return r.handle(JSON.parse_string(JSON.stringify(req)))


func test_a_game_matches_a_client_game() -> void:
	var r := Referee.new()
	var rep := _ask(r, {"op": "new", "game": "g1", "seed": 77, "decks": _decks()})
	check(rep.ok, "new: " + str(rep))
	var client := Game.new({"hero": "HERO_08", "deck": Decks.basic("MAGE")}, {"hero": "HERO_01", "deck": Decks.basic("WARRIOR")}, 77)
	eq(rep.hash, client.state_hash(), "the same start as a client's")
	for a in [{"type": "mulligan", "player": 0, "replace": []}, {"type": "mulligan", "player": 1, "replace": []}]:
		client.apply(a)
		rep = _ask(r, {"op": "act", "game": "g1", "action": a})
		eq(rep.hash, client.state_hash(), "same after " + a.type)
	var end := {"type": "end_turn", "player": client.current}
	client.apply(end)
	rep = _ask(r, {"op": "act", "game": "g1", "action": end})
	eq(rep.hash, client.state_hash(), "same after the turn")
	var wrong := _ask(r, {"op": "act", "game": "g1", "action": {"type": "end_turn", "player": 1 - client.current}})
	check(not wrong.ok, "an action of the wrong player is refused")
	rep = _ask(r, {"op": "act", "game": "g1", "action": {"type": "concede", "player": 0}})
	check(rep.over and rep.winner == 1, "a concede ends it")
	eq(_ask(r, {"op": "drop", "game": "g1"}).ok, true, "dropped")
	check(not _ask(r, {"op": "act", "game": "g1", "action": end}).ok, "gone")


func test_bad_requests_are_refused() -> void:
	var r := Referee.new()
	for req in [{}, {"op": "fly"}, {"op": "new", "game": "x"}, {"op": "new", "game": "x", "seed": 1, "decks": [{"hero": "HERO_08", "cards": []}, {}]}]:
		check(not _ask(r, req).ok, "refused: " + str(req))
	check(not r.handle("not json").ok, "not an object")


func test_deck_validation() -> void:
	var r := Referee.new()
	check(_ask(r, {"op": "validate", "deck": _decks()[0]}).ok, "a Basic deck is fine")
	var three := Decks.basic("MAGE").slice(0, 27)
	three.append_array(["VAN_CS2_029", "VAN_CS2_029", "VAN_CS2_029"])
	check(not _ask(r, {"op": "validate", "deck": {"hero": "HERO_08", "cards": three}}).ok, "three copies only in the Arena")
	check(_ask(r, {"op": "validate", "deck": {"hero": "HERO_08", "cards": three, "arena": true}}).ok, "an Arena deck may")


func test_draft_is_the_same_as_the_client_draft() -> void:
	var r := Referee.new()
	var rep := _ask(r, {"op": "draft", "seed": 9, "hero": -1})
	var d := ArenaDraft.new(9)
	eq(rep.heroes, d.heroes, "the same heroes")
	rep = _ask(r, {"op": "draft", "seed": 9, "hero": 1, "picks": [0, 2, 1]})
	d.choose_hero(1)
	for p in [0, 2, 1]:
		d.pick(p)
	eq([rep.hero, rep.cards, rep.offer, rep.done], [d.hero, d.cards, d.offer, false], "the same picks and offer")
