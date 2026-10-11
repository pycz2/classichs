class_name Scenario
extends RefCounted
## Builds a Game in PLAY phase from a position description, and back.
## Used by the debug table (subproject 2) and for reproducing bugs.

const SKIP_TAGS := ["TO_DESTROY", "DIED_POS"]


static func build(sc: Dictionary) -> Dictionary:
	var err := _validate(sc)
	if err != "":
		return {"game": null, "error": err}
	var ps: Array = sc.players
	var g := Game.new({"hero": ps[0].hero, "deck": []}, {"hero": ps[1].hero, "deck": []},
		int(sc.get("seed", 1)), int(sc.get("current", 0)), false)
	g.phase = "PLAY"
	g.turn = int(sc.get("turn", 1))
	for i in 2:
		_fill_player(g, i, ps[i])
	g.queue.clear()
	g.event_log = []
	g.update_auras()
	return {"game": g, "error": ""}


static func _fill_player(g: Game, i: int, d: Dictionary) -> void:
	var p := g.players[i]
	p.mulliganed = true
	if d.has("hero_power") and d.hero_power != p.hero_power.card_id:
		p.hero_power.zone = "SETASIDE"
		p.hero_power = g.new_entity(d.hero_power, i)
		g._enter_play(p.hero_power)
	p.hero.damage = int(d.get("damage", 0))
	p.hero.tags.ARMOR = int(d.get("armor", 0))
	p.hero.tags["ATTACKS"] = int(d.get("hero_attacks", 0))
	p.mana = int(d.get("mana", 0))
	p.max_mana = int(d.get("max_mana", 0))
	p.overload_owed = int(d.get("overload_owed", 0))
	p.overload_locked = int(d.get("overload_locked", 0))
	p.fatigue = int(d.get("fatigue", 0))
	p.cards_played_this_turn = int(d.get("cards_played", 0))
	p.minions_played_this_turn = int(d.get("minions_played", 0))
	p.cost_mods = _ints(d.get("cost_mods", []))
	if d.get("hero_power_used", false):
		p.hero_power.give_tag("USED")
	if d.get("hero_power_locked", false):
		p.hero_power.give_tag("LOCKED")  # tutorial: no hero power yet
	for item in d.get("deck", []):
		var spec := _spec(item)
		var e := g.new_entity(spec.card, i)
		e.zone = "DECK"
		_apply_spec(e, spec)
		p.deck.append(e)
	for item in d.get("hand", []):
		var spec := _spec(item)
		var e := g.new_entity(spec.card, i)
		e.zone = "HAND"
		_apply_spec(e, spec)
		p.hand.append(e)
	for m in d.get("board", []):
		var spec := _spec(m)
		var e := g.new_entity(spec.card, i)
		g.place_on_board(e, -1)
		_apply_spec(e, spec)
		if spec.get("exhausted", false):
			e.give_tag("EXHAUSTED")
	var w = d.get("weapon")
	if w != null:
		var spec := _spec(w)
		var e := g.new_entity(spec.card, i)
		p.weapon = e
		g._enter_play(e)
		if spec.has("durability"):
			e.tags.DURABILITY = int(spec.durability)
		_apply_spec(e, spec)
	if d.has("hero_state"):
		_apply_spec(p.hero, d.hero_state)
	for item in d.get("secrets", []):
		var e := g.new_entity(_spec(item).card, i)
		g._enter_play(e)
		e.zone = "SECRET"
		p.secrets.append(e)


static func _spec(v: Variant) -> Dictionary:
	return {"card": v} if v is String else v


static func _apply_spec(e: Entity, spec: Dictionary) -> void:
	if spec.get("silenced", false):
		e.silence()
	if spec.has("tags_exact"):
		e.tags = _ints(spec.tags_exact)
	for t: String in spec.get("tags", []):
		e.give_tag(t)
	for t: String in spec.get("eot_tags", []):
		e.give_tag(t, true)
	for ench in spec.get("enchantments", []):
		e.add_enchant(_ints(ench))
	e.damage = int(spec.get("damage", 0))
	if spec.has("attacks"):
		e.tags["ATTACKS"] = int(spec.attacks)


## JSON gives floats; the engine uses ints only.
static func _ints(v: Variant) -> Variant:
	if v is float:
		return int(v)
	if v is Array:
		return v.map(func(x): return _ints(x))
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _ints(v[k])
		return out
	return v


const NUMBER_FIELDS := ["damage", "armor", "hero_attacks", "mana", "max_mana", "overload_owed",
	"overload_locked", "fatigue", "cards_played", "minions_played"]
const SPEC_LISTS := ["tags", "eot_tags", "enchantments"]


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


## Type errors in an entity spec (board item, weapon, hero_state, hand/deck item).
static func _check_spec(at: String, item: Variant) -> String:
	if not item is Dictionary:
		return ""
	for k in SPEC_LISTS:
		if item.has(k) and not item[k] is Array:
			return "%s.%s: must be a list" % [at, k]
	for e in item.get("enchantments", []):
		if not e is Dictionary:
			return at + ".enchantments: items must be objects"
	if item.has("tags_exact") and not item.tags_exact is Dictionary:
		return at + ".tags_exact: must be an object"
	for k in ["damage", "durability", "attacks"]:
		if item.has(k) and not _is_number(item[k]):
			return "%s.%s: must be a number" % [at, k]
	return ""


static func _validate(sc: Dictionary) -> String:
	var ps = sc.get("players")
	if not ps is Array or ps.size() != 2:
		return "players: need exactly 2"
	for k in ["seed", "current", "turn"]:
		if sc.has(k) and not _is_number(sc[k]):
			return k + ": must be a number"
	if int(sc.get("current", 0)) not in [0, 1]:
		return "current: must be 0 or 1"
	for i in 2:
		var d = ps[i]
		var at := "players[%d]" % i
		if not d is Dictionary or not d.has("hero"):
			return at + ": hero is required"
		var e := _check_card(at + ".hero", d.hero, "HERO")
		if e != "":
			return e
		for k in NUMBER_FIELDS:
			if d.has(k) and not _is_number(d[k]):
				return "%s.%s: must be a number" % [at, k]
		if d.has("cost_mods") and not d.cost_mods is Array:
			return at + ".cost_mods: must be a list"
		if d.has("hero_state"):
			if not d.hero_state is Dictionary:
				return at + ".hero_state: must be an object"
			e = _check_spec(at + ".hero_state", d.hero_state)
			if e != "":
				return e
		if not d.has("hero_power") and not GameState.HERO_POWERS.has(d.hero):
			return at + ".hero_power: required for hero " + str(d.hero)
		if d.has("hero_power"):
			e = _check_card(at + ".hero_power", d.hero_power, "HERO_POWER")
			if e != "":
				return e
		for zone in [["hand", ""], ["deck", ""], ["board", "MINION"], ["secrets", "SPELL"]]:
			var list = d.get(zone[0], [])
			if not list is Array:
				return "%s.%s: must be a list" % [at, zone[0]]
			for j in list.size():
				var item = list[j]
				var id = item if item is String else (item.get("card") if item is Dictionary else null)
				e = _check_card("%s.%s[%d]" % [at, zone[0], j], id, zone[1])
				if e == "":
					e = _check_spec("%s.%s[%d]" % [at, zone[0], j], item)
				if e != "":
					return e
		if d.get("board", []).size() > GameState.MAX_BOARD:
			return at + ".board: more than 7 minions"
		if d.get("hand", []).size() > GameState.MAX_HAND:
			return at + ".hand: more than 10 cards"
		if d.get("weapon") != null:
			var w = d.weapon
			if not (w is String or w is Dictionary):
				return at + ".weapon: must be a card id or an object"
			e = _check_card(at + ".weapon", w if w is String else w.get("card"), "WEAPON")
			if e == "":
				e = _check_spec(at + ".weapon", w)
			if e != "":
				return e
		if int(d.get("max_mana", 0)) > GameState.MAX_MANA or int(d.get("mana", 0)) < 0:
			return at + ": mana out of range"
	return ""


static func _check_card(at: String, id: Variant, type: String) -> String:
	if not id is String or not CardDb.has(id):
		return "%s: unknown card %s" % [at, id]
	if type != "" and CardDb.card(id).type != type:
		return "%s: %s is not a %s" % [at, id, type.to_lower().replace("_", " ")]
	return ""


static func dump(g: GameState) -> Dictionary:
	var ps := []
	for p in g.players:
		var board := []
		for m in p.board:
			board.append(_dump_entity(m))
		ps.append({
			"hero": p.hero.card_id, "hero_power": p.hero_power.card_id,
			"damage": p.hero.damage, "armor": int(p.hero.tags.ARMOR),
			"hero_attacks": int(p.hero.tags.get("ATTACKS", 0)),
			"mana": p.mana, "max_mana": p.max_mana,
			"overload_owed": p.overload_owed, "overload_locked": p.overload_locked,
			"fatigue": p.fatigue, "cards_played": p.cards_played_this_turn,
			"hero_power_used": p.hero_power.has("USED"),
			"hero_power_locked": p.hero_power.has("LOCKED"),
			"cost_mods": p.cost_mods.duplicate(true),
			"minions_played": p.minions_played_this_turn,
			"hero_state": _dump_entity(p.hero),
			"hand": p.hand.map(func(e: Entity): return _dump_entity(e)),
			"deck": p.deck.map(func(e: Entity) -> String: return e.card_id),
			"board": board,
			"weapon": _dump_entity(p.weapon) if p.weapon else null,
			"secrets": p.secrets.map(func(e: Entity) -> String: return e.card_id),
		})
	return {"seed": 1, "current": g.current, "turn": g.turn, "players": ps}


static func _dump_entity(e: Entity) -> Dictionary:
	var tags := {}
	for k in e.tags:
		if not SKIP_TAGS.has(k):
			tags[k] = e.tags[k]
	var d := {"card": e.card_id, "damage": e.damage, "tags_exact": tags,
		"enchantments": e.enchantments.duplicate(true), "silenced": e.silenced,
		"eot_tags": e.eot_tags.duplicate()}
	if e.is_weapon():
		d["durability"] = int(e.tags.DURABILITY)
	return d
