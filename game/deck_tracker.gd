class_name DeckTracker
extends RefCounted
## Deck tracker data: the starting deck with the cards left and the chance to
## draw each one next, and what the opponent played (public information only).


static func _counts(ids: Array) -> Array:
	var d := Deck.new()
	d.cards.assign(ids)
	return d.sorted_counts()


static func _deck_ids(g: GameView, p: int) -> Array:
	return g.players[p].deck.map(func(e): return e.card_id)


## [{card, total, left, chance}] for the starting deck (cards put into the deck
## later count too); chance = copies left / cards in the deck (the next draw).
static func deck_view(g: GameView, p: int) -> Array:
	var n: int = g.players[p].deck.size()
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
		var l: int = left.get(r[0], 0)
		out.append({"card": r[0], "total": maxi(total, l), "left": l, "chance": float(l) / n if n > 0 else 0.0})
	return out


## Card ids the opponent of viewer played, in order; "" = a Secret not revealed yet.
static func opponent_played(g: GameView, viewer: int) -> Array:
	var out := []
	for entry in g.history:
		for ev in entry.events:
			if ev.type == "play" and ev.get("player", -1) == 1 - viewer:
				var e := g.ent(ev.entity)
				out.append("" if ev.get("secret", false) and e and e.zone == "SECRET" else ev.card)
	return out


## [{card, count}] the opponent played, in the order first played; each hidden
## Secret ("") is a row of its own.
static func opponent_counts(g: GameView, viewer: int) -> Array:
	var out := []
	var rows := {}
	for c in opponent_played(g, viewer):
		if rows.has(c):
			rows[c].count += 1
			continue
		var r := {"card": c, "count": 1}
		out.append(r)
		if c != "":
			rows[c] = r
	return out
