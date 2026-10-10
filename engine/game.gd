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


static func from_scenario(sc: Dictionary) -> Dictionary:
	return Scenario.build(sc)


func to_scenario() -> Dictionary:
	return Scenario.dump(self)


# --- apply ------------------------------------------------------------------

## Applies one action. Illegal actions change nothing.
func apply(action: Dictionary) -> Dictionary:
	var a := _normalize(action)
	if a.is_empty() or not legal_actions().has(a):
		return {"ok": false, "error": "illegal action %s" % JSON.stringify(a), "events": []}
	event_log = []
	var who := current
	match a.type:
		"mulligan": _do_mulligan(a.player, a.replace)
		"end_turn": _end_turn()
		"concede": _concede(a.player)
		_: _apply_play_action(a)
	resolve()
	_prune_pending()
	history.append({"turn": turn, "player": a.get("player", who), "action": a, "events": event_log})
	return {"ok": true, "error": "", "events": event_log}


## Converts JSON floats to ints and sorts mulligan ids, so equality checks work.
## Returns {} for malformed input (it comes from the network: never trust it).
func _normalize(action: Dictionary) -> Dictionary:
	var a := {}
	for k in action:
		if not k is String:
			return {}
		var v = action[k]
		if k == "type":
			if not v is String:
				return {}
		elif k == "replace":
			if not v is Array:
				return {}
			var ids: Array = []
			for x in v:
				var n = _as_int(x)
				if n == null:
					return {}
				ids.append(n)
			ids.sort()
			v = ids
		else:
			v = _as_int(v)
			if v == null:
				return {}
		a[k] = v
	return a if a.has("type") and a.has("player") else {}


## int for whole numbers (JSON gives floats), null otherwise.
func _as_int(v: Variant) -> Variant:
	if v is int:
		return v
	if v is float and v == floorf(v):
		return int(v)
	return null


func legal_actions() -> Array:
	var out := []
	if game_over:
		return out
	if phase == "MULLIGAN":
		for p in players:
			if not p.mulliganed:
				for ids in _subsets(p.ids(p.hand)):
					out.append({"type": "mulligan", "player": p.index, "replace": ids})
	else:
		out.append({"type": "end_turn", "player": current})
		_legal_play_actions(out)
	for p in 2:
		out.append({"type": "concede", "player": p})  # either player, any time
	return out


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

## Records p's choice; both mulligans run in a fixed order (0, then 1) once both
## have arrived, so the arrival order of the two actions cannot change the game.
func _do_mulligan(p: int, replace: Array) -> void:
	players[p].mulliganed = true
	players[p].mulligan_replace = replace
	log_event({"type": "mulligan_chosen", "player": p})
	if players[0].mulliganed and players[1].mulliganed:
		for i in 2:
			_run_mulligan(i, players[i].mulligan_replace)
		_finish_mulligan()


func _run_mulligan(p: int, replace: Array) -> void:
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
	log_event({"type": "mulligan", "player": p, "count": old.size()})


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


func _apply_play_action(a: Dictionary) -> void:
	match a.type:
		"play": _do_play(ent(a.entity), ent(a.target) if a.target >= 0 else null, a.pos, a.choice)
		"attack": _do_attack(ent(a.attacker), ent(a.defender))
		"hero_power": _do_hero_power(ent(a.target) if a.target >= 0 else null)
		"choose": _do_choose(ent(a.option))


func _legal_play_actions(out: Array) -> void:
	if not pending.is_empty():
		out.clear()
		for id: int in _pending_options():
			out.append({"type": "choose", "player": pending.player, "option": id})
		return
	var p := players[current]
	for e in p.hand:
		if cost(e) > p.mana or not _can_play(e):
			continue
		var choices: Array = [-1]
		var h := Cards.of(e.card_id)
		if h.has("choose_one"):
			choices = [0, 1]
		for choice: int in choices:
			for t: int in _play_targets(e, choice):
				for pos: int in _positions(e):
					out.append({"type": "play", "player": current, "entity": e.id, "target": t,
						"pos": pos, "choice": choice})
	var hp := p.hero_power
	if not hp.has("USED") and cost(hp) <= p.mana:
		var hh := Cards.of(hp.card_id)
		if hh.has("hero_power") and (not hh.has("can_play") or hh.can_play.call(self, hp)):
			for t: int in _spec_targets(hp, hh.get("target"), true, false):
				out.append({"type": "hero_power", "player": current, "target": t})
	for a in chars(current):
		if _can_attack(a):
			for d in _defenders(a):
				out.append({"type": "attack", "player": current, "attacker": a.id, "defender": d.id})


func _can_play(e: Entity) -> bool:
	var p := players[e.controller]
	if e.is_minion() and p.board.size() >= MAX_BOARD:
		return false
	if e.card().get("mechanics", []).has("SECRET"):
		for s in p.secrets:
			if s.card_id == e.card_id:
				return false
	var h := Cards.of(e.card_id)
	return not h.has("can_play") or h.can_play.call(self, e)


func _combo_active(e: Entity) -> bool:
	return players[e.controller].cards_played_this_turn > 0


## Target ids for playing e with the given choice. [-1] means "no target".
## An empty array means e cannot be played.
func _play_targets(e: Entity, choice: int) -> Array:
	var is_spell := e.type() == "SPELL"
	return _spec_targets(e, _target_spec(e, choice, _combo_active(e)), is_spell, not is_spell)


## The target spec that applies when e is played with this choice and combo state.
func _target_spec(e: Entity, choice: int, combo: bool) -> Variant:
	var h := Cards.of(e.card_id)
	if h.has("combo_target"):
		return h.combo_target if combo else null
	if choice >= 0:
		return Cards.of(h.choose_one[choice]).get("target")
	return h.get("target")


func _spec_targets(e: Entity, spec: Variant, is_spell: bool, optional: bool) -> Array:
	if spec == null:
		return [-1]
	var ids: Array = []
	for t in targets(e, spec, is_spell):
		ids.append(t.id)
	if ids.is_empty() and optional:
		return [-1]
	return ids


func _positions(e: Entity) -> Array:
	if not e.is_minion():
		return [-1]
	return range(players[e.controller].board.size() + 1)


func _can_attack(a: Entity) -> bool:
	if attack_value(a) <= 0 or a.has("FROZEN") or a.has("CANT_ATTACK"):
		return false
	if a.is_minion() and a.has("EXHAUSTED") and not a.has("CHARGE"):
		return false
	var limit := 2 if a.has("WINDFURY") or (a.is_hero() and players[a.controller].weapon
		and players[a.controller].weapon.has("WINDFURY")) else 1
	return int(a.tags.get("ATTACKS", 0)) < limit


func _defenders(a: Entity) -> Array[Entity]:
	var all: Array[Entity] = []
	var taunts: Array[Entity] = []
	for t in chars(opponent(a.controller)):
		if t.has("STEALTH"):
			continue
		all.append(t)
		if t.is_minion() and t.has("TAUNT"):
			taunts.append(t)
	return taunts if not taunts.is_empty() else all


# --- play -------------------------------------------------------------------

func _do_play(e: Entity, t: Entity, pos: int, choice: int) -> void:
	var p := players[e.controller]
	p.mana -= cost(e)
	consume_cost_mods(e)
	p.hand.erase(e)
	var combo := _combo_active(e)
	p.cards_played_this_turn += 1
	p.overload_owed += int(e.card().get("overload", 0))
	match e.type():
		"MINION": _play_minion(e, t, pos, choice, combo)
		"SPELL": _play_spell(e, t, choice, combo)
		"WEAPON": _play_weapon(e, t, combo)


func _run_effect(e: Entity, key: String, t: Entity, choice: int, combo: bool) -> void:
	var h := Cards.of(e.card_id)
	if t == null and _target_spec(e, choice, combo) != null:
		return  # targeted effect with no target (none was valid, or it left play)
	if choice >= 0:
		Cards.of(h.choose_one[choice]).effect.call(self, e, t)
	elif combo and h.has("combo"):
		h.combo.call(self, e, t)
	elif h.has(key):
		h[key].call(self, e, t)


func _play_minion(e: Entity, t: Entity, pos: int, choice: int, combo: bool) -> void:
	players[e.controller].minions_played_this_turn += 1
	place_on_board(e, pos)
	e.give_tag("EXHAUSTED")
	emit({"type": "play", "entity": e.id, "player": e.controller, "kind": "minion",
		"target": t.id if t else -1, "card": e.card_id})
	emit({"type": "summon", "entity": e.id, "player": e.controller, "card": e.card_id})
	resolve()
	if game_over or e.zone != "PLAY":
		return
	if t and t.zone != "PLAY":
		t = null
	_run_effect(e, "battlecry", t, choice, combo)
	resolve()
	if game_over or e.zone != "PLAY":
		return
	emit({"type": "after_summon", "entity": e.id, "player": e.controller, "card": e.card_id,
		"played": true})


func _play_spell(e: Entity, t: Entity, choice: int, combo: bool) -> void:
	var is_secret: bool = e.card().get("mechanics", []).has("SECRET")
	e.zone = "SETASIDE"
	var ev := {"type": "play", "entity": e.id, "player": e.controller, "kind": "spell",
		"secret": is_secret, "target": t.id if t else -1, "card": e.card_id, "countered": false}
	emit(ev)
	resolve()
	if game_over:
		return
	if is_secret:
		if ev.countered:
			e.zone = "GRAVEYARD"
		else:
			players[e.controller].secrets.append(e)
			_enter_play(e)
			e.zone = "SECRET"
		emit({"type": "after_spell", "entity": e.id, "player": e.controller, "card": e.card_id})
		return
	if not ev.countered:
		var nt: Entity = ent(ev.target) if ev.target >= 0 else null
		if nt == null or nt.zone == "PLAY":
			_run_effect(e, "spell", nt, choice, combo)
			resolve()
	e.zone = "GRAVEYARD"
	if not game_over:
		emit({"type": "after_spell", "entity": e.id, "player": e.controller, "card": e.card_id})


func _play_weapon(e: Entity, t: Entity, combo: bool) -> void:
	emit({"type": "play", "entity": e.id, "player": e.controller, "kind": "weapon",
		"target": t.id if t else -1, "card": e.card_id})
	resolve()
	if game_over:
		return
	_run_effect(e, "battlecry", t, -1, combo)
	resolve()
	if not game_over:
		equip_entity(e)


# --- attack -----------------------------------------------------------------

func _do_attack(a: Entity, d: Entity) -> void:
	a.tags["ATTACKS"] = int(a.tags.get("ATTACKS", 0)) + 1
	a.tags.erase("STEALTH")
	var ev := {"type": "attack", "attacker": a.id, "defender": d.id, "player": a.controller}
	emit(ev)
	resolve()
	if game_over or a.zone != "PLAY" or a.controller != current:
		return
	d = ent(ev.defender)
	if d == null or d.zone != "PLAY":
		return
	var weapon := players[a.controller].weapon if a.is_hero() else null
	var immune: bool = weapon != null and Cards.of(weapon.card_id).get("immune_while_attacking", false)
	if immune:
		a.give_tag("IMMUNE")
	var a_dmg := attack_value(a)
	var d_dmg := attack_value(d)
	damage(a, d, a_dmg)
	damage(d, a, d_dmg)
	if immune:
		a.tags.erase("IMMUNE")
	if weapon and weapon.zone == "PLAY":
		var wh := Cards.of(weapon.card_id)
		if not wh.has("durability_on_attack") or wh.durability_on_attack.call(self, weapon, d):
			weapon.tags.DURABILITY = int(weapon.tags.DURABILITY) - 1
	emit({"type": "after_attack", "attacker": a.id, "defender": d.id, "player": a.controller})


# --- hero power and choice --------------------------------------------------

func _do_hero_power(t: Entity) -> void:
	var p := players[current]
	var hp := p.hero_power
	p.mana -= cost(hp)
	hp.give_tag("USED")
	Cards.of(hp.card_id).hero_power.call(self, hp, t)
	emit({"type": "hero_power", "player": current, "entity": hp.id, "target": t.id if t else -1})


## Offered options that are still in the zone they were offered from.
func _pending_options() -> Array:
	return pending.options.filter(func(id: int) -> bool: return ent(id).zone == pending.zones[str(id)])


func _do_choose(option: Entity) -> void:
	var src := ent(pending.source)
	var still := _pending_options()
	pending = {}
	Cards.of(src.card_id).on_choose.call(self, src, option, still)


## A choice whose options all left their zone (drawn by a trigger, say) is dropped.
func _prune_pending() -> void:
	if not pending.is_empty() and _pending_options().is_empty():
		log_event({"type": "choice_cancelled", "player": pending.player})
		pending = {}
