class_name Tutorial
extends RefCounted
## One tutorial mission in play: Jaina's safety net, turn-end rules, hints and boss lines.

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
var _shown := {}
var _said := {}


func _init(n: int) -> void:
	number = n
	mission = Missions.get_mission(n)


## {"game": Game, "tutorial": Tutorial, "error": String}
static func start(n: int) -> Dictionary:
	var r := Missions.build(n)
	if r.error != "":
		return {"game": null, "tutorial": null, "error": r.error}
	var t := Tutorial.new(n)
	if t.mission.unlosable:
		r.game.hero(0).add_enchant({"hooks": "ench:tutorial_guard"})
	if t.mission.get("guarded", false):  # the boss can't be attacked while he has minions
		r.game.hero(1).give_tag("GUARDED")
	return {"game": r.game, "tutorial": t, "error": ""}


func _t(s: String) -> String:
	return TranslationServer.translate(s)


func _legal(g: Game, p: int) -> Array:
	return g.legal_actions().filter(func(a): return a.player == p)


## Why the turn can't end yet ("" = it can), as in the first original missions.
func end_turn_block(g: Game, p: int) -> String:
	if g.current != p or g.game_over:
		return ""
	var legal := _legal(g, p)
	if mission.block_mana and legal.any(func(a): return a.type == "play"):
		return _t("Not yet! You have more cards to play!")
	if mission.block_attack and legal.any(func(a): return a.type == "attack"):
		return _t("Not yet! You can still attack.")
	return ""


func _holds(key: String, g: Game, p: int) -> bool:
	var legal := _legal(g, p)
	var hand: Array = g.players[p].hand
	var enemy: Array = g.minions(1 - p)
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
func next_hint(g: Game, p: int) -> String:
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
func boss_line(g: Game) -> String:
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
