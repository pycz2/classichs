class_name CardTests
extends RefCounted
## Test scenes for every card (data/card_tests/*.json, format in its README.md): a
## scene to build (the Debug Table's scenario format) and steps to play in it, so a
## card's play, attack, death and effects can be watched in a real game.

const DIR := "res://data/card_tests"


## card id -> [test, ...] from every file in data/card_tests.
static func load_all() -> Dictionary:
	var out := {}
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(DIR + "/" + f)) != OK or not j.data is Dictionary:
			push_warning("card tests: cannot read " + f)
			continue
		for id in j.data:
			out[id] = (out.get(id, []) as Array) + (j.data[id] as Array)
	return out


## The entity a step points at: {"side": 0|1, "zone": "hand"|"board"|"secret", "index": n}
## or {"side": s, "zone": "hero"|"weapon"|"power"}; -1 when there is none.
static func entity(g: GameView, ref) -> int:
	if not ref is Dictionary:
		return -1
	var p := g.players[int(ref.get("side", 0))]
	var i := int(ref.get("index", 0))
	match str(ref.get("zone", "")):
		"hand":
			return p.hand[i].id if i < p.hand.size() else -1
		"board":
			return p.board[i].id if i < p.board.size() else -1
		"secret":
			return p.secrets[i].id if i < p.secrets.size() else -1
		"hero":
			return p.hero.id
		"weapon":
			return p.weapon.id if p.weapon else -1
		"power":
			return p.hero_power.id
	return -1


## The legal game action for a step, or {"error": "..."}.
## Steps: {"do": "play", "card": ref, "target": ref?, "pos": n?, "choice": n?},
## {"do": "attack", "attacker": ref, "defender": ref}, {"do": "hero_power", "target": ref?},
## {"do": "end_turn"}, {"do": "choose", "option": n} (Tracking's card choice).
static func action(m: Match, step: Dictionary) -> Dictionary:
	var g := m.game
	var me: int = g.pending.player if not g.pending.is_empty() else g.current
	var want := {}
	match str(step.get("do", "")):
		"play":
			want = {"type": "play", "entity": entity(g, step.get("card")), "target": entity(g, step.get("target")),
				"choice": int(step.get("choice", -1))}
			if step.has("pos"):
				want.pos = int(step.pos)
		"attack":
			want = {"type": "attack", "attacker": entity(g, step.get("attacker")), "defender": entity(g, step.get("defender"))}
		"hero_power":
			want = {"type": "hero_power", "target": entity(g, step.get("target"))}
		"end_turn":
			want = {"type": "end_turn"}
		"choose":
			want = {"type": "choose", "option": int(step.get("option", 0))}
		_:
			return {"error": "unknown step %s" % str(step)}
	var legal := m.legal()
	for a in legal:
		var ok := true
		for k in want:
			if k == "pos" and a.get("pos", -1) < 0:
				continue
			if a.get(k, -1 if k in ["target", "choice"] else null) != want[k]:
				ok = false
				break
		if ok:
			return a
	var kinds := {}
	for a in legal:
		kinds[a.type] = true
	return {"error": "not legal now: %s (player %d may: %s)" % [str(want), me, ", ".join(kinds.keys())]}


## Builds the test's scene and plays all its steps; {"match", "error", "step"}.
static func run(test: Dictionary) -> Dictionary:
	var m := Match.new()
	m.bots = [false, false]
	var why := m.setup({"scenario": test.get("scene", {})}, [false, false])
	if why != "":
		m.free()
		return {"match": null, "error": "scene: " + why, "step": -1}
	var steps: Array = test.get("steps", [])
	for i in steps.size():
		var a := action(m, steps[i])
		if a.has("error"):
			return {"match": m, "error": a.error, "step": i}
		var res := m.submit(a)
		if not res.ok:
			return {"match": m, "error": res.error, "step": i}
	return {"match": m, "error": "", "step": steps.size()}
