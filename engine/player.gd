class_name Player
extends RefCounted

var index: int
var hero: Entity
var hero_power: Entity
var weapon: Entity = null
var hand: Array[Entity] = []
var deck: Array[Entity] = []  # the last element is the top card
var board: Array[Entity] = []
var secrets: Array[Entity] = []
var mana := 0
var max_mana := 0
var overload_owed := 0
var overload_locked := 0
var fatigue := 0
var cards_played_this_turn := 0
var minions_played_this_turn := 0
## One-shot or timed cost changes: {"kind": "spell"|"secret"|"minion"|"any",
## "set": int or "delta": int, "until": "use"|"turn_end", "turn": int}
var cost_mods: Array = []
var mulliganed := false
var mulligan_replace: Array = []


func _init(p_index: int) -> void:
	index = p_index


func ids(arr: Array[Entity]) -> Array[int]:
	var out: Array[int] = []
	for e in arr:
		out.append(e.id)
	return out


## Copy that points at the entities of another state (same ids).
func copy(ents: Dictionary) -> Player:
	var p := Player.new(index)
	var pick := func(e: Entity) -> Entity: return ents[e.id] if e else null
	p.hero = pick.call(hero)
	p.hero_power = pick.call(hero_power)
	p.weapon = pick.call(weapon)
	for pair in [[hand, p.hand], [deck, p.deck], [board, p.board], [secrets, p.secrets]]:
		for e in pair[0]:
			pair[1].append(ents[e.id])
	p.mana = mana
	p.max_mana = max_mana
	p.overload_owed = overload_owed
	p.overload_locked = overload_locked
	p.fatigue = fatigue
	p.cards_played_this_turn = cards_played_this_turn
	p.minions_played_this_turn = minions_played_this_turn
	p.cost_mods = cost_mods.duplicate(true)
	p.mulliganed = mulliganed
	p.mulligan_replace = mulligan_replace.duplicate()
	return p


func snapshot() -> Dictionary:
	return {"hero": hero.id, "power": hero_power.id, "weapon": weapon.id if weapon else -1,
		"hand": ids(hand), "deck": ids(deck), "board": ids(board), "secrets": ids(secrets),
		"mana": mana, "max_mana": max_mana, "ol_owed": overload_owed, "ol_locked": overload_locked,
		"fatigue": fatigue, "played": cards_played_this_turn, "minions_played": minions_played_this_turn,
		"cost_mods": cost_mods, "mulliganed": mulliganed, "mulligan_replace": mulligan_replace}
