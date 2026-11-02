extends SceneTree
## Plays a game pack quickly, without the game's screens: loads the .cardpack into the rules
## engine (which compiles every card script), then plays bot-vs-bot games with the pack's ready
## decks (decks/*.json) and reports how each ended. A script error is printed with its file and
## line and makes the exit code 1. Like the server's check of an uploaded pack, smaller.
## Usage: godot --headless --path . --script res://tools/pack_try.gd -- <file.cardpack> [games]

const MAX_ACTIONS := 2000


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: godot --headless --path . --script res://tools/pack_try.gd -- <file.cardpack> [games]")
		quit(2)
		return
	quit(_run(args[0], int(args[1]) if args.size() > 1 else 3))


func _run(path: String, games: int) -> int:
	if not ClassDB.class_exists("RulesEngine"):
		print("ERROR: the rules engine is missing (rules/bin): build it with tools/build_rules.sh")
		return 1
	var engine: Object = ClassDB.instantiate("RulesEngine")
	var call := func(req: Dictionary) -> Dictionary:
		return JSON.parse_string(str(engine.call_json(JSON.stringify(req))))
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		print("ERROR: cannot read ", path)
		return 1
	var loaded: Dictionary = call.call({"op": "load_pack", "data": Marshalls.raw_to_base64(bytes)})
	if not loaded.ok:
		print("ERROR: the engine refuses the pack: ", loaded.get("error", "?"))
		return 1
	print("loaded %s %s, rules_hash %s" % [loaded.id, loaded.version, loaded.pack])
	var decks := _decks(path)
	if decks.is_empty():
		print("ERROR: the pack has no decks/*.json to play with")
		return 1
	var failed := 0
	for i in games:
		var d0: Dictionary = decks[i % decks.size()]
		var d1: Dictionary = decks[(i + 1) % decks.size()]
		var game := "try%d" % i
		var r: Dictionary = call.call({"op": "new", "game": game, "pack": loaded.pack, "seed": 1000 + i,
			"decks": [{"hero": d0.champion, "cards": d0.cards}, {"hero": d1.champion, "cards": d1.cards}]})
		if not r.ok:
			print("ERROR: game %d (%s vs %s) does not start: %s" % [i + 1, d0.name, d1.name, r.get("error", "?")])
			failed += 1
			continue
		var actions := 0
		while not r.get("over", false) and actions < MAX_ACTIONS:
			var moved := false
			for p in 2:  # in the mulligan both players act; then the current one
				var b: Dictionary = call.call({"op": "bot", "game": game, "player": p})
				if b.get("action") is Dictionary:
					r = call.call({"op": "act", "game": game, "action": b.action})
					moved = true
					actions += 1
					break
			if not moved or not r.ok:
				break
		var how := "turn %d, %d actions" % [int(r.get("turn", 0)), actions]
		if r.has("script_error"):
			print("ERROR: game %d (%s vs %s): a card script failed at %s:\n  %s" % [i + 1, d0.name, d1.name, how, r.script_error])
			failed += 1
		elif not r.get("over", false):
			print("ERROR: game %d (%s vs %s) got stuck at %s: %s" % [i + 1, d0.name, d1.name, how, r.get("error", "no move")])
			failed += 1
		else:
			var w := int(r.get("winner", -1))
			print("game %d: %s vs %s, %s, %s" % [i + 1, d0.name, d1.name, how,
				"a draw" if w < 0 else "won by " + [d0.name, d1.name][w]])
		call.call({"op": "drop", "game": game})
	print("%d games, %d failed" % [games, failed])
	return 1 if failed else 0


## The pack's ready decks: [{name, champion, cards}], by file name.
func _decks(path: String) -> Array:
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return []
	var out := []
	var files := Array(z.get_files())
	files.sort()
	for f: String in files:
		if f.begins_with("decks/") and f.ends_with(".json"):
			var d = JSON.parse_string(z.read_file(f).get_string_from_utf8())
			if d is Dictionary and d.has("champion") and d.has("cards"):
				out.append({"name": str(d.get("name", f.get_file())), "champion": d.champion, "cards": d.cards})
	z.close()
	return out
