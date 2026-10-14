class_name Referee
extends RefCounted
## The game server's referee: the game started without a window with
## `-- --referee <port>` connects to the server on 127.0.0.1:<port> and checks the
## games there with the real rules engine. One JSON request per line, one JSON
## reply per line (docs/superpowers/specs/2026-10-15-server-design.md):
## new, act, drop, validate, draft, ping. One referee serves every game.

var games := {}  # game id -> Game


## Answers one request (a parsed JSON object).
func handle(req: Variant) -> Dictionary:
	if not req is Dictionary:
		return {"ok": false, "error": "not an object"}
	var game_id := str(req.get("game", ""))
	match req.get("op"):
		"ping":
			return {"ok": true, "version": str(ProjectSettings.get_setting("application/config/version", ""))}
		"new":
			return _new(game_id, req)
		"act":
			return _act(game_id, req.get("action"))
		"drop":
			games.erase(game_id)
			return {"ok": true, "game": game_id}
		"validate":
			var d := Deck.from_dict(req.get("deck"))
			if d == null:
				return {"ok": false, "error": "not a deck"}
			var why := d.validate()
			return {"ok": why == ""} if why == "" else {"ok": false, "error": why}
		"draft":
			return _draft(req)
	return {"ok": false, "error": "unknown op"}


func _new(game_id: String, req: Dictionary) -> Dictionary:
	var decks = req.get("decks")
	if game_id == "" or not decks is Array or decks.size() != 2 or not req.get("seed") is float:
		return {"ok": false, "game": game_id, "error": "bad new request"}
	var pair := []
	for d in decks:
		var deck := Deck.from_dict(d)
		if deck == null or deck.validate() != "":
			return {"ok": false, "game": game_id, "error": "bad deck"}
		pair.append({"hero": deck.hero, "deck": deck.cards.duplicate()})
	var g := Game.new(pair[0], pair[1], int(req.seed))
	games[game_id] = g
	return _state(game_id, g)


func _act(game_id: String, action: Variant) -> Dictionary:
	var g: Game = games.get(game_id)
	if g == null:
		return {"ok": false, "game": game_id, "error": "no such game"}
	if not action is Dictionary:
		return {"ok": false, "game": game_id, "error": "not an action"}
	if g.game_over:
		return _state(game_id, g)  # a move that crossed the end: nothing changes
	var r := g.apply(action)
	if not r.ok:
		return {"ok": false, "game": game_id, "error": str(r.get("error", "illegal"))}
	return _state(game_id, g)


func _state(game_id: String, g: Game) -> Dictionary:
	return {"ok": true, "game": game_id, "hash": g.state_hash(), "over": g.game_over, "winner": g.winner,
		"turn": g.turn, "current": g.current, "phase": g.phase}


## The Arena draft from its seed and picks (stateless: the server keeps them).
func _draft(req: Dictionary) -> Dictionary:
	if not req.get("seed") is float:
		return {"ok": false, "error": "no seed"}
	var d := ArenaDraft.new(int(req.seed))
	var hero = req.get("hero", -1)
	if hero is float and int(hero) >= 0 and int(hero) < 3:
		d.choose_hero(int(hero))
		var picks = req.get("picks", [])
		if picks is Array:
			for p in picks:
				if not p is float or int(p) < 0 or int(p) > 2:
					return {"ok": false, "error": "bad pick"}
				d.pick(int(p))
	return {"ok": true, "heroes": d.heroes, "hero": d.hero, "cards": d.cards, "offer": d.offer, "done": d.done()}


## Connects to the server and answers until the connection closes; then quits.
static func run(tree: SceneTree, port: int) -> void:
	var r := Referee.new()
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", port) != OK:
		printerr("referee: cannot connect to port %d" % port)
		tree.quit(1)
		return
	var buf := PackedByteArray()
	while true:
		peer.poll()
		var st := peer.get_status()
		if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
			break
		if st != StreamPeerTCP.STATUS_CONNECTED:
			OS.delay_msec(5)
			continue
		var n := peer.get_available_bytes()
		if n <= 0:
			OS.delay_msec(2)
			continue
		var got := peer.get_data(n)
		if got[0] != OK:
			break
		buf.append_array(got[1])
		var at := buf.find(10)
		while at >= 0:
			var line := buf.slice(0, at).get_string_from_utf8()
			buf = buf.slice(at + 1)
			var reply := r.handle(JSON.parse_string(line)) if line.strip_edges() != "" else {"ok": false, "error": "empty"}
			peer.put_data((JSON.stringify(reply) + "\n").to_utf8_buffer())
			at = buf.find(10)
	tree.quit()
