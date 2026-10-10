class_name Bot
extends RefCounted
## Greedy one-step bot: tries every legal action on a clone and keeps the best
## one if it beats ending the turn. Sees hidden information (training only).

const WIN := 100000.0
const MULLIGAN_MAX_COST := 3


## Position value for player p: own side minus the opponent's side.
static func value(g: GameState, p: int) -> float:
	if g.game_over:
		return 0.0 if g.winner == -1 else (WIN if g.winner == p else -WIN)
	return _side(g, p, true) - _side(g, g.opponent(p), false)


static func _side(g: GameState, p: int, own: bool) -> float:
	var pl: Player = g.players[p]
	var v := float(pl.hero.health() + int(pl.hero.tags.ARMOR))
	for m in pl.board:
		v += 1.5 * m.atk() + m.health()
		if m.has("TAUNT"):
			v += 1.0
		if m.has("DIVINE_SHIELD"):
			v += m.atk()
	if pl.weapon:
		v += 0.5 * pl.weapon.atk() * int(pl.weapon.tags.DURABILITY)
	if own:
		v += 1.0 * pl.hand.size()
	return v


## The action player p should take now ({} if p has nothing to do).
static func choose(g: Game, p: int) -> Dictionary:
	var legal: Array = g.legal_actions().filter(func(a): return a.player == p and a.type != "concede")
	if legal.is_empty():
		return {}
	if g.phase == "MULLIGAN":
		return _mulligan(g, p, legal)
	var best: Dictionary = {}
	var best_score := -INF
	var last := g.players[p].board.size()
	for a in legal:
		if a.type == "play" and a.pos >= 0 and a.pos != last:
			continue  # ponytail: rightmost slot only; adjacency-aware placement if the bot needs it
		if a.type == "end_turn":
			if value(g, p) > best_score:
				best = a
				best_score = value(g, p)
			continue
		var c: Game = g.clone()
		if not c.apply(a).ok:
			continue
		var s := value(c, p)
		if s > best_score + 0.01 or best.is_empty():
			best = a
			best_score = s
	return best


static func _mulligan(g: Game, p: int, legal: Array) -> Dictionary:
	var replace: Array = []
	for e in g.players[p].hand:
		if g.cost(e) > MULLIGAN_MAX_COST:
			replace.append(e.id)
	replace.sort()
	for a in legal:
		if a.replace == replace:
			return a
	return legal[0]
