class_name Tutorial
extends RefCounted
## One tutorial mission in play: hints and boss lines, from the active pack (tutorial.json `hints`:
## when each shows; locales `hints`, `missions`). Its rules (the champion's safety net, the boss
## guarded by his minions, the turn-end rules) are the engine's missions.

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


func _legal(_g: GameView, p: int) -> Array:
	return match_.legal().filter(func(a): return a.player == p) if match_ else []


## Whether hint `key` may show now: any of its conditions holds (docs/packs/format.md §12).
func _holds(key: String, g: GameView, p: int) -> bool:
	var conds = Missions.tutorial().get("hints", {}).get(key, [])
	return conds is Array and conds.any(func(c): return c is Dictionary and _cond(c, g, p))


func _cond(c: Dictionary, g: GameView, p: int) -> bool:
	var legal := _legal(g, p)
	var cards: Array = c.get("cards", []) if c.get("cards") is Array else []
	var kw := Packs.client_name(str(c.get("keyword", "")))
	var fits := func(id: String, tags: Callable) -> bool:
		return (cards.is_empty() or cards.has(id)) and (kw == "" or tags.call(kw))
	match str(c.get("if", "")):
		"always": return true
		"can_play": return legal.any(func(a): return a.type == "play")
		"can_attack": return legal.any(func(a): return a.type == "attack")
		"can_use_power": return legal.any(func(a): return a.type == "hero_power")
		"only_end_turn": return g.current == p and legal.all(func(a): return a.type in ["end_turn", "concede"])
		"mana": return g.current == p and g.players[p].max_mana >= int(c.get("at_least", 1))
		"in_hand": return g.players[p].hand.any(func(e): return fits.call(e.card_id, func(k): return e.card().get("mechanics", []).has(k)))
		"on_board": return g.all_minions().any(func(m): return fits.call(m.card_id, func(k): return m.has(k)))
		"enemy_minions": return not g.players[1 - p].board.is_empty()
		"enemy_weapon": return g.players[1 - p].weapon != null
	return false


## The next hint to show (each once), or "". The mission intro comes first.
func next_hint(g: GameView, p: int) -> String:
	if not _shown.has("intro"):
		_shown.intro = true
		return mission.intro
	if g.current != p:
		return ""
	for key in mission.hints:
		if not _shown.has(key) and _holds(key, g, p):
			_shown[key] = true
			return Packs.active().text(["hints", key])
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
			return mission.lines[key]
	return ""
