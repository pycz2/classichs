class_name Game
extends GameState
## Match setup, turns, actions and legality.

const COIN := "GAME_005"


## deal=false skips the opening draws (used by Scenario.build).
func _init(p0: Dictionary, p1: Dictionary, p_seed: int, first := -1, deal := true) -> void:
	super(p_seed)
	setup_players(p0.hero, p1.hero)
	for i in 2:
		var deck: Array = [p0, p1][i].deck
		for card_id: String in deck:
			var e := new_entity(card_id, i)
			e.zone = "DECK"
			players[i].deck.append(e)
		shuffle(players[i].deck)
	current = first if first >= 0 else rng.randi_range(0, 1)
	if deal:
		draw(current, 3)
		draw(opponent(current), 4)
	history.append({"turn": 0, "player": current, "action": {"type": "start"}, "events": event_log})
	event_log = []


# --- apply ------------------------------------------------------------------

## Applies one action. Illegal actions change nothing.
func apply(action: Dictionary) -> Dictionary:
	var a := _normalize(action)
	if not legal_actions().has(a):
		return {"ok": false, "error": "illegal action %s" % JSON.stringify(a), "events": []}
	event_log = []
	var who := current
	match a.type:
		"mulligan": _do_mulligan(a.player, a.replace)
		"end_turn": _end_turn()
		"concede": _concede(a.player)
		_: _apply_play_action(a)
	resolve()
	history.append({"turn": turn, "player": a.get("player", who), "action": a, "events": event_log})
	return {"ok": true, "error": "", "events": event_log}


## Converts JSON floats to ints and sorts mulligan ids, so equality checks work.
func _normalize(action: Dictionary) -> Dictionary:
	var a := {}
	for k: String in action:
		var v = action[k]
		if v is float:
			v = int(v)
		elif k == "replace":
			var ids: Array = []
			for x in v:
				ids.append(int(x))
			ids.sort()
			v = ids
		a[k] = v
	return a


## Hook point for task 6 (play, attack, hero_power, choose).
func _apply_play_action(_a: Dictionary) -> void:
	pass


func legal_actions() -> Array:
	var out := []
	if game_over:
		return out
	if phase == "MULLIGAN":
		for p in players:
			if not p.mulliganed:
				for ids in _subsets(p.ids(p.hand)):
					out.append({"type": "mulligan", "player": p.index, "replace": ids})
		return out
	out.append({"type": "end_turn", "player": current})
	out.append({"type": "concede", "player": current})
	_legal_play_actions(out)
	return out


## Hook point for task 6.
func _legal_play_actions(_out: Array) -> void:
	pass


func _subsets(ids: Array[int]) -> Array:
	var out := []
	for mask in 1 << ids.size():
		var s: Array = []
		for i in ids.size():
			if mask & (1 << i):
				s.append(ids[i])
		s.sort()
		out.append(s)
	return out


# --- mulligan and turns -----------------------------------------------------

func _do_mulligan(p: int, replace: Array) -> void:
	var pl := players[p]
	var old: Array[Entity] = []
	for id: int in replace:
		var e := ent(id)
		pl.hand.erase(e)
		old.append(e)
	draw(p, old.size())
	for e in old:
		e.zone = "DECK"
		pl.deck.append(e)
	shuffle(pl.deck)
	pl.mulliganed = true
	log_event({"type": "mulligan", "player": p, "count": old.size()})
	if players[0].mulliganed and players[1].mulliganed:
		_finish_mulligan()


func _finish_mulligan() -> void:
	add_to_hand(opponent(current), COIN)
	phase = "PLAY"
	_start_turn()


func _start_turn() -> void:
	var p := players[current]
	turn += 1
	p.max_mana = mini(MAX_MANA, p.max_mana + 1)
	p.overload_locked = p.overload_owed
	p.overload_owed = 0
	p.mana = maxi(0, p.max_mana - p.overload_locked)
	p.cards_played_this_turn = 0
	p.minions_played_this_turn = 0
	p.hero_power.tags.erase("USED")
	for c in chars(current):
		c.tags.erase("EXHAUSTED")
		c.tags["ATTACKS"] = 0
	log_event({"type": "turn_start", "player": current, "turn": turn})
	emit({"type": "turn_start", "player": current})
	resolve()
	if not game_over:
		draw(current)


func _end_turn() -> void:
	emit({"type": "turn_end", "player": current})
	resolve()
	if game_over:
		return
	for e in in_play():
		e.remove_eot()
	for pl in players:
		pl.cost_mods = pl.cost_mods.filter(func(m: Dictionary) -> bool: return m.turn > turn)
	for c in chars(current):
		if c.has("FROZEN") and not (c.tags.get("FROZEN_THIS_TURN", false) and int(c.tags.get("ATTACKS", 0)) > 0):
			c.tags.erase("FROZEN")
		c.tags.erase("FROZEN_THIS_TURN")
	log_event({"type": "turn_end", "player": current})
	current = opponent(current)
	_start_turn()


func _concede(p: int) -> void:
	game_over = true
	phase = "OVER"
	winner = opponent(p)
	log_event({"type": "game_over", "winner": winner})
