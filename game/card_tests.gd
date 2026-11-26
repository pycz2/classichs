class_name CardTests
extends RefCounted
## Test scenes for every card (data/card_tests/*.json, format in its README.md): a
## scene to build (the Debug Table's scenario format) and steps to play in it, so a
## card's play, attack, death and effects can be watched in a real game; what should
## happen (`expect`) and, where it can be checked, the checks of the end position (`check`).

const DIR := "res://data/card_tests"


## card id -> [test, ...] from every file in data/card_tests, for the cards of the active pack. A test that names
## a "script" is for the packs whose card uses that script (a card a later pack changed: Warsong Commander); a test
## whose scene has a card the pack lacks is left out. Each test gets its `card` and its `key` ("kind: title").
## only: just this file's tests (tools/check_card_tests.gd).
static func load_all(only := "") -> Dictionary:
	var out := {}
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	var scripts := {}
	if Packs.active():
		for c: Dictionary in Packs.active().cards():
			scripts[c.id] = str(c.get("script", ""))
	for f in d.get_files():
		if not f.ends_with(".json") or (only != "" and f != only):
			continue
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(DIR + "/" + f)) != OK or not j.data is Dictionary:
			push_warning("card tests: cannot read " + f)
			continue
		for id in j.data:
			if CardDb.has(id):  # (the tests are written for Classic's cards)
				for t in j.data[id]:
					if (t.has("script") and str(t.script) != scripts.get(id, "")) or not scene_cards(t.get("scene")).all(CardDb.has):
						continue
					t.card = id
					t.key = "%s: %s" % [t.get("kind", "?"), t.get("title", "")]
					out.get_or_add(id, []).append(t)
	return out


## Every card id a scene names (heroes, powers, the zones).
static func scene_cards(scene: Variant) -> Array:
	var out := []
	var players = scene.get("players") if scene is Dictionary else null
	for p in players if players is Array else []:
		if not p is Dictionary:
			continue
		var items: Array = [p.get("hero"), p.get("hero_power"), p.get("weapon")]
		for z in ["hand", "deck", "board", "secrets"]:
			items.append_array(p.get(z) if p.get(z) is Array else [])
		for it in items:
			var id = it.get("card") if it is Dictionary else it
			if id is String:
				out.append(id)
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
## {"do": "end_turn"}, {"do": "choose", "option": n} (an offered entity id, else the n-th offered card, 0-based).
## `"any": true` on a play or a Hero Power: the first legal target there is (and option, unless it gives one).
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
		"choose":  # option n: an offered entity id, else the n-th offered card (0-based)
			var opts: Array = g.pending.get("options", []).map(func(o): return int(o))
			var n := int(step.get("option", 0))
			want = {"type": "choose", "option": n if opts.has(n) else (opts[n] if n < opts.size() else -1)}
		_:
			return {"error": "unknown step %s" % str(step)}
	if step.get("any", false):
		want.erase("target")
		if not step.has("choice"):
			want.erase("choice")
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


## Why the position is not what the checks want ("" = it is). A check: {"at": ref, "card": id ("" = nothing
## there), "atk": n, "health": n, "has": tag, "not": tag} or {"count": {"side": s, "zone": z}, "is": n}
## (z: hand, board, secret, deck).
static func check(g: GameView, checks: Array) -> String:
	for c in checks:
		if not c is Dictionary:
			return "not a check: %s" % str(c)
		if c.has("count"):
			var p := g.players[int(c["count"].get("side", 0))]
			var z := str(c["count"].get("zone", ""))
			var n: int = p.deck_count if z == "deck" else ({"hand": p.hand, "board": p.board, "secret": p.secrets}.get(z, []) as Array).size()
			if n != int(c.get("is", 0)):
				return "%s: %d, not %d" % [DebugTable._ref(c["count"]), n, int(c.get("is", 0))]
			continue
		var id := entity(g, c.get("at"))
		var e: GameView.Ent = g.ent(id) if id >= 0 else null
		var at := DebugTable._ref(c.get("at"))
		if c.has("card") and (e.card_id if e else "") != str(c.card):
			return "%s: %s, not %s" % [at, e.card_id if e else "nothing", c.card]
		if e == null:
			if c.has("card"):
				continue
			return "%s: nothing" % at
		for k in ["atk", "health"]:
			if c.has(k) and e.call(k) != int(c[k]):
				return "%s %s: %d, not %d" % [at, k, e.call(k), int(c[k])]
		if c.has("has") and not e.has(Packs.client_name(str(c.has))):
			return "%s: no %s" % [at, c.has]
		if c.has("not") and e.has(Packs.client_name(str(c["not"]))):
			return "%s: %s" % [at, c["not"]]
	return ""


## Builds the test's scene and plays all its steps, then its checks; {"match", "error", "step"}.
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
	why = check(m.game, test.get("check", []))
	return {"match": m, "error": "check: " + why if why != "" else "", "step": steps.size()}
