extends SceneTree
## End-to-end check of a running game server: two clients in one process register
## (or log in), queue in a mode, get matched, play the game with the bot's moves
## through NetSession over the server (the referee checks every move), and print
## the result and ranks. Needs the server: cargo run in server/ (port 7377).
## Arena: both draft a deck (the first hero, the first card of each offer), then play.
## Usage: godot --headless --path . --script res://tools/server_e2e.gd -- [casual|ranked|arena] [ws://localhost:7377]

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


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	if args.size() > 1:
		url = args[1]
	for i in 2:
		var l := ServerLink.new()
		root.add_child(l)
		links.append(l)
		var k := i
		l.message.connect(func(msg): _on_message(k, msg))
		l.open(url)
	print("e2e: %s on %s" % [mode, url])


func _deck(cls: String) -> Dictionary:
	return {"name": cls, "hero": Decks.hero(cls), "cards": Decks.basic(cls)}


func _on_message(i: int, msg: Dictionary) -> void:
	match msg.t:
		"auth":
			print("client %d auth ok=%s me=%s" % [i, msg.get("ok"), msg.get("me", {})])
			if msg.get("ok", false):
				links[i].me = msg.get("me", {})
				if mode == "arena":
					links[i].send({"t": "arena_start"})
				else:
					links[i].send({"t": "queue", "mode": mode, "deck": _deck(["MAGE", "WARRIOR"][i])})
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
			var ch := links[i].channel(str(msg.game))
			var s := NetSession.new()
			s.seed_override = int(msg.get("seed", -1))
			var d := Deck.from_dict(_deck(["MAGE", "WARRIOR"][i]))
			if mode == "arena":
				d = Deck.from_dict({"name": "Arena", "hero": drafts[i].hero, "cards": drafts[i].cards, "arena": true})
				d.arena = true
			s.arena = mode == "arena"
			s.setup(ch, msg.get("host", false) == true, str(links[i].me.get("user", "")), d)
			links[i].add_child(ch)
			links[i].add_child(s)
			sessions[i] = s
			s.started.connect(func(m: Match): matches[i] = m)
			s.failed.connect(func(r): _fail("session %d failed: %s" % [i, r]))
			s.say_hello()
		"game_over":
			results[i] = msg
			print("client %d game_over: %s" % [i, msg])


func _fail(why: String) -> void:
	printerr("E2E FAIL: " + why)
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
		print("both games started; same state: %s" % [matches[0].game.state_hash() == matches[1].game.state_hash()])
	if step == 2:
		for i in 2:
			var m: Match = matches[i]
			if m.game.game_over:
				continue
			var me := m.viewer()
			var g: Game = m.game
			var mine: bool = (g.phase == "MULLIGAN" and not g.players[me].mulliganed) or (g.phase != "MULLIGAN" and g.current == me and g.pending.is_empty())
			if mine:
				var a := Bot.choose(g, me)
				m.submit(a)
		if matches.all(func(m): return m.game.game_over) and results.all(func(r): return not r.is_empty()):
			print("E2E OK: winner %d, turns %d, results %s / %s" % [matches[0].game.winner, matches[0].game.turn, results[0].get("result"), results[1].get("result")])
			quit(0)
			return true
	return false
