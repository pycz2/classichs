extends SceneTree
## End-to-end check of a running game server: two clients in one process register
## (or log in), queue in a mode, get matched, play the game with the bot's moves
## (chosen on each client's own view) as server games (the server keeps the game,
## sends each its view), and print the result and ranks. Needs the server: cargo run in server/ (port 7377).
## Arena: both draft a deck (the first hero, the first card of each offer), then play.
## The game pack: a built-in one by id (classic-2014, neon; default: the active one); the
## queue names it by rules_hash, the decks are its first two ready decks (else Basic decks).
## Usage: godot --headless --path . --script res://tools/server_e2e.gd -- [casual|ranked|arena] [ws://localhost:7377] [pack id]

var mode := "casual"
var url := "ws://localhost:7377"
var links: Array[ServerLink] = []
var matches: Array = [null, null]
var sessions: Array = [null, null]
var results: Array = [{}, {}]
var drafts: Array = [{}, {}]
var t := 0.0
var step := 0
var stamp := str(int(Time.get_unix_time_from_system())).right(6)
var pack: Pack


func _initialize() -> void:
	ServerLink.session_path = "user://e2e_session.json"  # never the player's saved login
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	if args.size() > 1:
		url = args[1]
	pack = Packs.active()
	for p in Packs.all():
		if args.size() > 2 and p.id() == args[2]:
			pack = p
	Packs._active = pack  # this run only: not saved in the player's settings
	Packs._changed()
	for i in 2:
		var l := ServerLink.new()
		root.add_child(l)
		links.append(l)
		var k := i
		l.message.connect(func(msg): _on_message(k, msg))
		l.open(url)
	print("e2e: %s on %s, pack %s %s (%s)" % [mode, url, pack.id(), pack.version(), pack.rules_hash()])


## Player i's deck: the pack's ready decks in order, else a Basic Mage and Warrior.
func _deck(i: int) -> Dictionary:
	var ready := pack.files().filter(func(f): return f.begins_with("decks/") and f.ends_with(".json"))
	ready.sort()
	if ready.size() > 0:
		var d: Dictionary = pack.json(ready[i % ready.size()])
		return {"name": str(d.get("id", "deck")), "hero": str(d.get("champion", d.get("hero", ""))), "cards": d.get("cards", [])}
	var cls: String = ["MAGE", "WARRIOR"][i]
	return {"name": cls, "hero": Decks.hero(cls), "cards": Decks.basic(cls)}


func _on_message(i: int, msg: Dictionary) -> void:
	match msg.t:
		"auth":
			print("client %d auth ok=%s me=%s" % [i, msg.get("ok"), msg.get("me", {})])
			if msg.get("ok", false):
				links[i].me = msg.get("me", {})
				if mode == "arena":
					links[i].send({"t": "arena_start", "pack": pack.rules_hash()})
				else:
					links[i].send({"t": "queue", "mode": mode, "deck": _deck(i), "pack": pack.rules_hash()})
			else:
				_fail("auth: %s" % msg)
		"arena":
			var st: Dictionary = msg.state
			drafts[i] = st
			if str(st.get("hero", "")) == "":
				links[i].send({"t": "arena_hero", "i": 0})
			elif not st.get("done", false):
				links[i].send({"t": "arena_pick", "i": 0})
			else:
				print("client %d drafted %s with %d cards" % [i, st.hero, st.cards.size()])
				links[i].send({"t": "arena_queue"})
		"error":
			print("client %d error: %s" % [i, msg])
		"match":
			print("client %d match: %s" % [i, msg])
			if str(msg.get("pack", "")) != pack.rules_hash():
				_fail("the game is in another pack: %s" % msg.get("pack"))
			var d := Deck.from_dict(_deck(i))
			if mode == "arena":
				d = Deck.from_dict({"name": "Arena", "hero": drafts[i].hero, "cards": drafts[i].cards, "arena": true})
			var s := links[i].session(msg, d)
			links[i].add_child(s)
			sessions[i] = s
			s.started.connect(func(m: Match):
				matches[i] = m
				s.add_child(m))
			s.failed.connect(func(r): _fail("session %d failed: %s" % [i, r]))
		"game_over":
			results[i] = msg
			print("client %d game_over: %s" % [i, msg])


func _fail(why: String) -> void:
	printerr("E2E FAIL: " + why)
	DirAccess.remove_absolute(ServerLink.session_path)
	quit(1)


func _process(delta: float) -> bool:
	t += delta
	if t > 240.0:
		_fail("timeout at step %d" % step)
		return true
	if step == 0 and links.all(func(l): return l.is_open()):
		step = 1
		for i in 2:
			links[i].send({"t": "register", "user": "e2e%s_%d" % [stamp, i], "password": "correct horse %d" % i})
	if step == 1 and matches.all(func(m): return m != null):
		step = 2
		print("both games started; seats %d and %d" % [sessions[0].you, sessions[1].you])
	if step == 2:
		for i in 2:
			var m: Match = matches[i]
			if m.game.game_over:
				continue
			var me := m.viewer()
			var g: GameView = m.game
			if not m.waiting() and m.legal().any(func(a): return a.player == me and a.type != "concede"):
				var tmp := Rules.new_id("e2e")  # the bot on this client's view (it sees no hidden card)
				Rules.request({"op": "new", "game": tmp, "state": g.snapshot})
				m.submit(Rules.request({"op": "bot", "game": tmp, "player": me}).get("action", {}))
				Rules.request({"op": "drop", "game": tmp})
		if matches.all(func(m): return m.game.game_over) and results.all(func(r): return not r.is_empty()):
			DirAccess.remove_absolute(ServerLink.session_path)
			print("E2E OK: winner %d, turns %d, results %s / %s" % [matches[0].game.winner, matches[0].game.turn, results[0].get("result"), results[1].get("result")])
			quit(0)
			return true
	return false
