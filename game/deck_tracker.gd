class_name DeckTracker
extends RefCounted
## Deck tracker data: the starting deck, the cards left with the chance to draw
## each one next, and what the opponent played (public information only).


static func _counts(ids: Array) -> Array:
	var d := Deck.new()
	d.cards.assign(ids)
	return d.sorted_counts()


static func _deck_ids(g: Game, p: int) -> Array:
	return g.players[p].deck.map(func(e): return e.card_id)


## [{card, total, left}] for the starting deck (cards put into the deck later count too).
static func deck_view(g: Game, p: int) -> Array:
	var left := {}
	for r in _counts(_deck_ids(g, p)):
		left[r[0]] = r[1]
	var start: Array = g.start_decks[p] if not g.start_decks[p].is_empty() else _deck_ids(g, p)
	var out := []
	var seen := {}
	for r in _counts(start + _deck_ids(g, p)):
		if seen.has(r[0]):
			continue
		seen[r[0]] = true
		var total: int = start.count(r[0])
		out.append({"card": r[0], "total": maxi(total, left.get(r[0], 0)), "left": left.get(r[0], 0)})
	return out


## [{card, count, chance}]: chance = copies / cards in the deck (the next draw).
static func remaining(g: Game, p: int) -> Array:
	var n: int = g.players[p].deck.size()
	return _counts(_deck_ids(g, p)).map(func(r): return {"card": r[0], "count": r[1], "chance": float(r[1]) / n})


## Card ids the opponent of viewer played, in order; "" = a Secret not revealed yet.
static func opponent_played(g: Game, viewer: int) -> Array:
	var out := []
	for entry in g.history:
		for ev in entry.events:
			if ev.type == "play" and ev.get("player", -1) == 1 - viewer:
				var e := g.ent(ev.entity)
				out.append("" if ev.get("secret", false) and e and e.zone == "SECRET" else ev.card)
	return out
