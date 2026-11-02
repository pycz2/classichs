class_name Missions
extends RefCounted
## The tutorial of the active pack (its tutorial.json, docs/packs/format.md §12): the missions in
## order, the unlock rule, each mission's boss, reward, hints, texts and intro pages. A mission's
## decks and rules are the engine's (missions/<n>.json; its game is the engine's `new` with `mission`).


## The active pack's tutorial.json ({} when it has none).
static func tutorial() -> Dictionary:
	var p := Packs.active()
	return p.tutorial() if p else {}


## The mission ids in the order the tutorial plays them.
static func ids() -> Array:
	return tutorial().get("missions", []).map(func(m): return int(m.get("id", 0)) if m is Dictionary else 0)


static func count() -> int:
	return ids().size()


## The mission after n in the tutorial (0 = n is the last).
static func next(n: int) -> int:
	var l := ids()
	var i := l.find(n)
	return l[i + 1] if i >= 0 and i + 1 < l.size() else 0


## Mission n: {id, boss, reward, hints, intro, lines {start, hurt, defeat}, reward_line, pages, effect},
## its texts in the interface language.
static func get_mission(n: int) -> Dictionary:
	var p := Packs.active()
	var m = p.json("missions/%d.json" % n) if p else null
	if not m is Dictionary:
		m = {}
	var t: Dictionary = {}
	for x in tutorial().get("missions", []):
		if x is Dictionary and int(x.get("id", 0)) == n:
			t = x
	var say := func(path: Array) -> String: return p.text(["missions", str(n)] + path) if p else ""
	var lines := {}
	for k in ["start", "hurt", "defeat"]:
		lines[k] = say.call(["lines", k])
	return {"id": n, "boss": str(m.get("boss", "")), "reward": str(m.get("reward", "")), "hints": m.get("hints", []),
		"intro": say.call(["intro"]), "lines": lines, "reward_line": say.call(["reward_line"]),
		"pages": t.get("intro", []) if t.get("intro") is Array else [], "effect": t.get("effect")}
