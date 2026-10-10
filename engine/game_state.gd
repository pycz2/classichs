class_name GameState
extends RefCounted
## Match state, event queue, death phase, auras and the primitives that card
## hooks use. Game (game.gd) adds turns, actions and legality on top.

const MAX_HAND := 10
const MAX_BOARD := 7
const MAX_MANA := 10
const MAX_QUEUE_STEPS := 5000
const HERO_POWERS := {
	"HERO_01": "VAN_HERO_01bp", "HERO_02": "VAN_HERO_02bp", "HERO_03": "VAN_HERO_03bp",
	"HERO_04": "VAN_HERO_04bp", "HERO_05": "VAN_HERO_05bp", "HERO_06": "VAN_HERO_06bp",
	"HERO_07": "VAN_HERO_07bp", "HERO_08": "VAN_HERO_08bp", "HERO_09": "VAN_HERO_09bp",
}

var rng := RandomNumberGenerator.new()
var players: Array[Player] = []
var entities: Dictionary = {}
var turn := 0
var current := 0
var phase := "MULLIGAN"
var pending: Dictionary = {}
var game_over := false
var winner := -1
var event_log: Array = []
## Full match history, never trimmed: [{"turn", "player", "action", "events"}].
## Entry 0 is {"action": {"type": "start"}} with the opening draws.
var history: Array = []
var queue: Array = []  # [Callable, Entity, Dictionary, bool needs_in_play]
var _next_id := 1
var _next_order := 1


func _init(p_seed: int) -> void:
	rng.seed = p_seed


func setup_players(hero0: String, hero1: String) -> void:
	for i in 2:
		var p := Player.new(i)
		var hero_id: String = [hero0, hero1][i]
		p.hero = new_entity(hero_id, i)
		_enter_play(p.hero)
		p.hero_power = new_entity(HERO_POWERS[hero_id], i)
		_enter_play(p.hero_power)
		players.append(p)


# --- entities -------------------------------------------------------------

func new_entity(card_id: String, controller: int) -> Entity:
	var e := Entity.new(_next_id, card_id, controller)
	entities[e.id] = e
	_next_id += 1
	return e


func ent(id: int) -> Entity:
	return entities.get(id)


func _enter_play(e: Entity) -> void:
	e.zone = "PLAY"
	e.play_order = _next_order
	_next_order += 1


func place_on_board(e: Entity, pos: int) -> void:
	var board := players[e.controller].board
	if pos < 0 or pos > board.size():
		pos = board.size()
	board.insert(pos, e)
	_enter_play(e)


func opponent(p: int) -> int:
	return 1 - p


func minions(p: int) -> Array[Entity]:
	return players[p].board.duplicate()


func all_minions() -> Array[Entity]:
	return _by_order(minions(0) + minions(1))


func chars(p: int) -> Array[Entity]:
	var out: Array[Entity] = [players[p].hero]
	out.append_array(players[p].board)
	return out


func all_chars() -> Array[Entity]:
	return _by_order(chars(0) + chars(1))


func hero(p: int) -> Entity:
	return players[p].hero


## Friendly minions of me, without me.
func others(me: Entity) -> Array[Entity]:
	var out: Array[Entity] = []
	for m in players[me.controller].board:
		if m != me:
			out.append(m)
	return out


## Summons for me's controller right of me (left-to-right board order).
func summon_right(me: Entity, card_id: String) -> Entity:
	var i := players[me.controller].board.find(me)
	return summon(me.controller, card_id, i + 1 if i >= 0 else -1)


func adjacent(m: Entity) -> Array[Entity]:
	var out: Array[Entity] = []
	var board := players[m.controller].board
	var i := board.find(m)
	if i < 0:
		return out
	if i > 0:
		out.append(board[i - 1])
	if i < board.size() - 1:
		out.append(board[i + 1])
	return out


## All entities whose hooks can trigger: heroes, hero powers, weapons, minions, secrets.
func in_play() -> Array[Entity]:
	var out: Array[Entity] = []
	for p in players:
		out.append(p.hero)
		out.append(p.hero_power)
		if p.weapon:
			out.append(p.weapon)
		out.append_array(p.board)
		out.append_array(p.secrets)
	return _by_order(out)


func _by_order(arr: Array[Entity]) -> Array[Entity]:
	arr.sort_custom(func(a: Entity, b: Entity) -> bool: return a.play_order < b.play_order)
	return arr


func hooks_of(e: Entity) -> Dictionary:
	return {} if e.silenced else Cards.of(e.card_id)


# --- events and resolution --------------------------------------------------

func log_event(ev: Dictionary) -> void:
	event_log.append(ev)


## Logs the event and queues every matching "on" trigger (card and enchantment hooks).
func emit(ev: Dictionary) -> void:
	log_event(ev)
	for e in in_play():
		var h: Dictionary = hooks_of(e).get("on", {})
		if h.has(ev.type):
			queue.append([h[ev.type], e, ev, true])
		for ench: Dictionary in e.enchantments:
			if ench.has("hooks"):
				var eh: Dictionary = Cards.of(ench.hooks).get("on", {})
				if eh.has(ev.type):
					queue.append([eh[ev.type], e, ev, true])


## Calls matching "now" hooks at once. Used for replacement effects (Ice Block).
func emit_now(ev: Dictionary) -> void:
	for e in in_play():
		var h: Dictionary = hooks_of(e).get("now", {})
		if h.has(ev.type):
			h[ev.type].call(self, e, ev)


## Runs queued triggers, then the death phase, until nothing is left.
func resolve() -> void:
	var steps := 0
	while not game_over:
		while not queue.is_empty() and not game_over:
			steps += 1
			if steps > MAX_QUEUE_STEPS:
				push_warning("trigger chain stopped after %d steps" % MAX_QUEUE_STEPS)
				queue.clear()
				break
			var q: Array = queue.pop_front()
			var me: Entity = q[1]
			if q[3] and not (me.zone == "PLAY" or me.zone == "SECRET"):
				continue
			q[0].call(self, me, q[2])
		update_auras()
		if not _death_phase():
			break
	update_auras()


func _death_phase() -> bool:
	var dead: Array[Entity] = []
	for p in players:
		for m in p.board:
			if m.health() <= 0 or m.tags.get("TO_DESTROY", false):
				dead.append(m)
		if p.weapon and (int(p.weapon.tags.DURABILITY) <= 0 or p.weapon.tags.get("TO_DESTROY", false)):
			dead.append(p.weapon)
	_by_order(dead)
	for e in dead:
		var p := players[e.controller]
		if e.is_minion():
			e.tags["DIED_POS"] = p.board.find(e)
			p.board.erase(e)
		else:
			p.weapon = null
		e.zone = "GRAVEYARD"
	for e in dead:
		var h := hooks_of(e)
		if h.has("deathrattle"):
			queue.append([h.deathrattle, e, {}, false])
		for ench: Dictionary in e.enchantments:
			var eh := Cards.of(ench.get("hooks", ""))
			if eh.has("deathrattle"):
				queue.append([eh.deathrattle, e, {}, false])
		emit({"type": "death", "entity": e.id, "player": e.controller, "card": e.card_id,
			"minion": e.is_minion()})
	var heroes_dead: Array[int] = []
	for p in players:
		if p.hero.health() <= 0:
			heroes_dead.append(p.index)
	if not heroes_dead.is_empty():
		game_over = true
		phase = "OVER"
		winner = -1 if heroes_dead.size() == 2 else opponent(heroes_dead[0])
		queue.clear()
		log_event({"type": "game_over", "winner": winner})
		return false
	return not dead.is_empty()


func update_auras() -> void:
	var all := in_play()
	var before := {}
	for e in all:
		before[e.id] = [e.max_health(), e.health()]
		e.aura = {"atk": 0, "hp": 0, "tags": {}}
	for e in all:
		var h := hooks_of(e)
		if h.has("aura") and e.zone == "PLAY":
			h.aura.call(self, e)
	for e in all:
		e.fix_health(before[e.id][0], before[e.id][1])


func aura_add(t: Entity, atk: int, hp: int, tags := {}) -> void:
	t.aura.atk += atk
	t.aura.hp += hp
	for k in tags:
		if k == "SPELLPOWER":
			t.aura.tags[k] = int(t.aura.tags.get(k, 0)) + int(tags[k])
		else:
			t.aura.tags[k] = tags[k]


# --- primitives -------------------------------------------------------------

func _id(e: Entity) -> int:
	return e.id if e else -1


func damage(src: Entity, t: Entity, amount: int) -> int:
	if t == null or t.zone != "PLAY" or amount <= 0:
		return 0
	var pre := {"type": "predamage", "source": _id(src), "target": t.id, "amount": amount}
	emit_now(pre)
	amount = pre.amount
	if amount <= 0 or t.has("IMMUNE"):
		return 0
	if t.has("DIVINE_SHIELD"):
		t.tags.erase("DIVINE_SHIELD")
		log_event({"type": "divine_shield_lost", "target": t.id})
		return 0
	if t.is_hero():
		var absorbed := mini(int(t.tags.ARMOR), amount)
		t.tags.ARMOR -= absorbed
		amount -= absorbed
		if amount <= 0:
			log_event({"type": "armor_lost", "target": t.id, "amount": absorbed})
			return 0
	t.damage += amount
	if src and src.is_minion() and src.has("STEALTH"):
		src.tags.erase("STEALTH")
	emit({"type": "damage", "source": _id(src), "target": t.id, "amount": amount,
		"player": t.controller})
	return amount


func heal(src: Entity, t: Entity, amount: int) -> int:
	if t == null or t.zone != "PLAY" or amount <= 0:
		return 0
	if src and players[src.controller].hero.has("HEAL_IS_DAMAGE"):
		return damage(src, t, amount)
	var healed := mini(amount, t.damage)
	if healed <= 0:
		return 0
	t.damage -= healed
	emit({"type": "heal", "source": _id(src), "target": t.id, "amount": healed})
	return healed


func destroy(e: Entity) -> void:
	if e and e.zone == "PLAY":
		e.tags["TO_DESTROY"] = true


func summon(p: int, card_id: String, pos := -1) -> Entity:
	if players[p].board.size() >= MAX_BOARD:
		return null
	return summon_entity(new_entity(card_id, p), pos)


## Puts an existing entity (for example a card from the hand) onto the board as a summon.
func summon_entity(e: Entity, pos := -1) -> Entity:
	if players[e.controller].board.size() >= MAX_BOARD:
		return null
	place_on_board(e, pos)
	e.give_tag("EXHAUSTED")
	emit({"type": "summon", "entity": e.id, "player": e.controller, "card": e.card_id})
	emit({"type": "after_summon", "entity": e.id, "player": e.controller, "card": e.card_id})
	return e


func draw(p: int, count := 1) -> Array[Entity]:
	var out: Array[Entity] = []
	var pl := players[p]
	for i in count:
		if pl.deck.is_empty():
			pl.fatigue += 1
			log_event({"type": "fatigue", "player": p, "amount": pl.fatigue})
			damage(null, pl.hero, pl.fatigue)
			continue
		var e: Entity = pl.deck.pop_back()
		if pl.hand.size() >= MAX_HAND:
			e.zone = "GRAVEYARD"
			log_event({"type": "burn", "player": p, "entity": e.id, "card": e.card_id})
			continue
		e.zone = "HAND"
		pl.hand.append(e)
		out.append(e)
		emit({"type": "draw", "player": p, "entity": e.id, "card": e.card_id})
	return out


## Draws a specific card from p's deck (burns it if the hand is full).
func draw_entity(p: int, e: Entity) -> void:
	var pl := players[p]
	if not pl.deck.has(e):
		return
	pl.deck.erase(e)
	if pl.hand.size() >= MAX_HAND:
		e.zone = "GRAVEYARD"
		log_event({"type": "burn", "player": p, "entity": e.id, "card": e.card_id})
		return
	e.zone = "HAND"
	pl.hand.append(e)
	emit({"type": "draw", "player": p, "entity": e.id, "card": e.card_id})


func add_to_hand(p: int, card_id: String) -> Entity:
	if players[p].hand.size() >= MAX_HAND:
		return null
	var e := new_entity(card_id, p)
	e.zone = "HAND"
	players[p].hand.append(e)
	log_event({"type": "add_to_hand", "player": p, "entity": e.id, "card": card_id})
	return e


func discard_random(p: int, count := 1) -> void:
	for i in count:
		var e: Entity = random_choice(players[p].hand)
		if e == null:
			return
		players[p].hand.erase(e)
		e.zone = "GRAVEYARD"
		emit({"type": "discard", "player": p, "entity": e.id, "card": e.card_id})


func buff(e: Entity, atk: int, hp: int, eot := false) -> void:
	e.add_enchant({"atk": atk, "hp": hp, "eot": eot})
	log_event({"type": "buff", "target": e.id, "atk": atk, "hp": hp})


## Sets Attack and/or Health (-1 keeps the value). Setting Health clears damage.
func set_stats(e: Entity, atk := -1, hp := -1) -> void:
	var ench := {}
	if atk >= 0:
		ench["set_atk"] = atk
	if hp >= 0:
		ench["set_hp"] = hp
		e.damage = 0
	e.add_enchant(ench)
	log_event({"type": "buff", "target": e.id, "set_atk": atk, "set_hp": hp})


func silence(e: Entity) -> void:
	e.silence()
	log_event({"type": "silence", "target": e.id})


func freeze(e: Entity) -> void:
	if e == null or e.zone != "PLAY":
		return
	e.tags["FROZEN"] = true
	if e.controller == current:
		e.tags["FROZEN_THIS_TURN"] = true
	log_event({"type": "freeze", "target": e.id})


func transform(e: Entity, card_id: String) -> Entity:
	var board := players[e.controller].board
	var i := board.find(e)
	if i < 0:
		return null
	var n := new_entity(card_id, e.controller)
	board[i] = n
	n.zone = "PLAY"
	n.play_order = e.play_order
	n.give_tag("EXHAUSTED")
	e.zone = "SETASIDE"
	log_event({"type": "transform", "from": e.id, "to": n.id, "card": card_id})
	return n


func return_to_hand(e: Entity) -> void:
	var p := players[e.controller]
	if not p.board.has(e):
		return
	p.board.erase(e)
	e.zone = "SETASIDE"
	var n := add_to_hand(e.controller, e.card_id)
	log_event({"type": "return_to_hand", "entity": e.id, "new": _id(n)})


func take_control(e: Entity, p: int) -> void:
	if e.controller == p or not players[e.controller].board.has(e):
		return
	players[e.controller].board.erase(e)
	if players[p].board.size() >= MAX_BOARD:
		e.zone = "GRAVEYARD"
		log_event({"type": "destroy", "target": e.id})
		return
	e.controller = p
	players[p].board.append(e)
	e.give_tag("EXHAUSTED")
	log_event({"type": "take_control", "target": e.id, "player": p})


func equip(p: int, card_id: String) -> Entity:
	return equip_entity(new_entity(card_id, p))


func equip_entity(w: Entity) -> Entity:
	var pl := players[w.controller]
	if pl.weapon:
		pl.weapon.zone = "GRAVEYARD"
		log_event({"type": "destroy", "target": pl.weapon.id})
	pl.weapon = w
	_enter_play(w)
	emit({"type": "equip", "player": w.controller, "entity": w.id, "card": w.card_id})
	return w


func gain_armor(p: int, n: int) -> void:
	players[p].hero.tags.ARMOR += n
	log_event({"type": "armor", "player": p, "amount": n})


## Full crystals by default. empty=true adds empty crystals (Wild Growth).
func gain_mana(p: int, n: int, empty := false) -> void:
	var pl := players[p]
	for i in n:
		if pl.max_mana < MAX_MANA:
			pl.max_mana += 1
			if not empty:
				pl.mana += 1
	log_event({"type": "mana", "player": p, "max": pl.max_mana, "mana": pl.mana})


func _velen(p: int) -> int:
	return 2 if players[p].hero.has("DOUBLE_HEAL_DAMAGE") else 1


func spell_dmg(me: Entity, n: int) -> int:
	var sp := 0
	for m in players[me.controller].board:
		sp += m.spellpower()
	return (n + sp) * _velen(me.controller)


func hp_dmg(me: Entity, n: int) -> int:
	return n * _velen(me.controller)


func heal_amt(me: Entity, n: int) -> int:
	return n * _velen(me.controller)


func random_choice(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[rng.randi_range(0, arr.size() - 1)]


## Random entity from arr that is in play and not already dying (health > 0).
func random_alive(arr: Array) -> Entity:
	return random_choice(arr.filter(func(e: Entity) -> bool: return e.zone == "PLAY" and e.health() > 0))


func shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _spec_ok(src: Entity, spec: Variant, t: Entity) -> bool:
	if spec is Array:
		for s in spec:
			if not _spec_ok(src, s, t):
				return false
		return true
	if spec is Callable:
		return spec.call(self, src, t)
	var mine := t.controller == src.controller
	match spec:
		T.ANY: return true
		T.MINION: return t.is_minion()
		T.ENEMY_MINION: return t.is_minion() and not mine
		T.FRIENDLY_MINION: return t.is_minion() and mine
		T.ENEMY_CHAR: return not mine
		T.FRIENDLY_CHAR: return mine
		T.ENEMY_HERO: return t.is_hero() and not mine
	push_error("unknown target spec %s" % spec)
	return false


## Characters that src may target. Enemy Stealth is never targetable;
## Elusive blocks spells and hero powers (is_spell=true).
func targets(src: Entity, spec: Variant, is_spell := false) -> Array[Entity]:
	var out: Array[Entity] = []
	for t in all_chars():
		if t.controller != src.controller and t.has("STEALTH"):
			continue
		if is_spell and t.has("ELUSIVE"):
			continue
		if _spec_ok(src, spec, t):
			out.append(t)
	return out


func secret_ready(me: Entity) -> bool:
	return me.zone == "SECRET" and current != me.controller


func reveal(me: Entity) -> void:
	players[me.controller].secrets.erase(me)
	me.zone = "GRAVEYARD"
	emit({"type": "secret_revealed", "entity": me.id, "player": me.controller, "card": me.card_id})


func request_choice(me: Entity, options: Array[int]) -> void:
	pending = {"player": me.controller, "source": me.id, "options": options}
	log_event({"type": "choice", "player": me.controller, "options": options})


func add_cost_mod(p: int, mod: Dictionary) -> void:
	mod["turn"] = turn
	players[p].cost_mods.append(mod)


func _mod_applies(mod: Dictionary, e: Entity) -> bool:
	match mod.kind:
		"any": return true
		"minion": return e.is_minion()
		"spell": return e.type() == "SPELL"
		"secret": return e.type() == "SPELL" and e.card().get("mechanics", []).has("SECRET")
	return false


func cost(e: Entity) -> int:
	var c: int = e.card().get("cost", 0)
	var h := Cards.of(e.card_id)
	if h.has("cost_mod"):
		c += h.cost_mod.call(self, e)
	for src in in_play():
		var sh := hooks_of(src)
		if sh.has("cost_aura") and src.zone == "PLAY":
			c = sh.cost_aura.call(self, src, e, c)
	for mod: Dictionary in players[e.controller].cost_mods:
		if mod.turn == turn and _mod_applies(mod, e):
			c = mod.set if mod.has("set") else c + mod.delta
	return maxi(0, c)


## Removes "until": "use" mods that applied to e (called when e is played).
func consume_cost_mods(e: Entity) -> void:
	var pl := players[e.controller]
	pl.cost_mods = pl.cost_mods.filter(
		func(m: Dictionary) -> bool: return not (m.until == "use" and m.turn == turn and _mod_applies(m, e)))


## Hero attack: weapon attack counts only on the controller's own turn.
func hero_atk(hero: Entity) -> int:
	var v := hero.atk()
	var w := players[hero.controller].weapon
	if w and hero.controller == current:
		v += w.atk()
	return v


func attack_value(e: Entity) -> int:
	return hero_atk(e) if e.is_hero() else e.atk()


# --- serialization ----------------------------------------------------------

func to_dict() -> Dictionary:
	var ents := {}
	for id: int in entities:
		ents[str(id)] = entities[id].snapshot()
	var ps := []
	for p in players:
		ps.append(p.snapshot())
	return {"turn": turn, "current": current, "phase": phase, "rng": str(rng.state),
		"next_id": _next_id, "next_order": _next_order, "pending": pending,
		"game_over": game_over, "winner": winner, "entities": ents, "players": ps}


func state_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(JSON.stringify(to_dict()).to_utf8_buffer())
	return ctx.finish().hex_encode()
