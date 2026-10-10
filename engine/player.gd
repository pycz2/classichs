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


func _init(p_index: int) -> void:
	index = p_index


func ids(arr: Array[Entity]) -> Array[int]:
	var out: Array[int] = []
	for e in arr:
		out.append(e.id)
	return out


func snapshot() -> Dictionary:
	return {"hero": hero.id, "power": hero_power.id, "weapon": weapon.id if weapon else -1,
		"hand": ids(hand), "deck": ids(deck), "board": ids(board), "secrets": ids(secrets),
		"mana": mana, "max_mana": max_mana, "ol_owed": overload_owed, "ol_locked": overload_locked,
		"fatigue": fatigue, "played": cards_played_this_turn, "minions_played": minions_played_this_turn,
		"cost_mods": cost_mods, "mulliganed": mulliganed}
