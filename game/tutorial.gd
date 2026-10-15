class_name Tutorial
extends RefCounted
## One tutorial mission in play: hints and boss lines. Its rules (Jaina's safety
## net, the boss guarded by his minions, the turn-end rules) are the engine's missions.

const HINTS := {
	"play": "Click a card in your hand to play it. Minions go on the board.",
	"attack": "Click a minion that can attack, then click an enemy to attack it.",
	"end_turn": "Nothing more to do? Press End Turn.",
	"mana": "You get one more Mana Crystal every turn. Spend it all!",
	"raid_leader": "Raid Leader gives your other minions +1 Attack.",
	"trade": "Kill enemy minions before they become a problem!",
	"battlecry": "A Battlecry happens when you play the card from your hand.",
	"tooltip": "Hover over any card to read it.",
	"taunt": "Minions with Taunt must be attacked first. Play one to protect your hero!",
	"heal": "Some cards restore Health. Use them on a damaged hero or minion.",
	"buff": "Some cards make your minions stronger.",
	"charge": "Minions with Charge can attack right away.",
	"hero_power": "Your Hero Power deals 1 damage. You can use it once per turn.",
	"weapon": "Weapons let heroes attack. Each attack costs 1 Durability.",
}

var number: int
var mission: Dictionary
## The mission's match (its legal actions; the engine plays the mission's rules).
var match_: Match
var _shown := {}
var _said := {}


func _init(n: int, m: Match = null) -> void:
	number = n
	mission = Missions.get_mission(n)
	match_ = m


func _t(s: String) -> String:
	return TranslationServer.translate(s)


func _legal(_g: GameView, p: int) -> Array:
	return match_.legal().filter(func(a): return a.player == p) if match_ else []


func _holds(key: String, g: GameView, p: int) -> bool:
	var legal := _legal(g, p)
	var hand: Array = g.players[p].hand
	var enemy: Array = g.players[1 - p].board
	match key:
		"play": return legal.any(func(a): return a.type == "play")
		"attack": return legal.any(func(a): return a.type == "attack")
		"end_turn": return g.current == p and legal.all(func(a): return a.type in ["end_turn", "concede"])
		"mana": return g.current == p and g.players[p].max_mana >= 2
		"raid_leader": return hand.any(func(e): return e.card_id == "VAN_CS2_122")
		"trade": return not enemy.is_empty()
		"battlecry": return hand.any(func(e): return e.card().get("mechanics", []).has("BATTLECRY"))
		"tooltip": return true
		"taunt": return hand.any(func(e): return e.card().get("mechanics", []).has("TAUNT")) \
			or g.all_minions().any(func(m): return m.has("TAUNT"))
		"heal": return hand.any(func(e): return e.card_id in ["VAN_EX1_011", "VAN_DS1_055", "VAN_CS2_117", "VAN_EX1_583"])
		"buff": return hand.any(func(e): return e.card_id in ["VAN_EX1_019", "VAN_CS2_122", "VAN_CS2_222"])
		"charge": return hand.any(func(e): return e.card().get("mechanics", []).has("CHARGE"))
		"hero_power": return legal.any(func(a): return a.type == "hero_power")
		"weapon": return g.players[1 - p].weapon != null
	return false


## The next hint to show (each once), or "". The mission intro comes first.
func next_hint(g: GameView, p: int) -> String:
	if not _shown.has("intro"):
		_shown.intro = true
		return _t(mission.intro)
	if g.current != p:
		return ""
	for key in mission.hints:
		if not _shown.has(key) and _holds(key, g, p):
			_shown[key] = true
			return _t(HINTS[key])
	return ""


## The boss's next line ("" = nothing new): at the start, at half health, on defeat.
func boss_line(g: GameView) -> String:
	var boss := g.hero(1)
	for key in ["start", "hurt", "defeat"]:
		if _said.has(key):
			continue
		var due: bool = key == "start" or (key == "hurt" and boss.health() * 2 <= boss.max_health()) \
			or (key == "defeat" and g.game_over and g.winner == 0)
		if due:
			_said[key] = true
			return _t(mission.lines[key])
	return ""
