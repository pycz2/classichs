extends SceneTree
## The UI audit's second player on its own server (tools/ui_audit/server.gd drives the first, in a window):
## registers or logs in Peer_Bob (tag peerbob), takes every friend request, and does what the driver writes to
## a command file, a line each: "add <tag>", "chat <user> <text>", "invite <user>", "play" (casual games
## against the auto-bots, one after another, the bot's moves a little slowly), "idle" (concedes, stops),
## "kick <user> <password>" (logs in as that player elsewhere: the window's client is kicked), "quit".
## Usage: TEST_USER_DIR=classichs-audit/peer godot --headless --path . --script res://tools/ui_audit/server_peer.gd --
##   <ws url> <invite key> <cardpack> <command file>

const USER := "Peer_Bob"
const PASSWORD := "peer password 1"
var url: String
var key: String
var cmd_file: String
var read_at := 0
var link: ServerLink
var other: ServerLink
var pack: Pack
var playing := false
var match_: Match
var session: ServerSession
var next_move := 0.0
var t := 0.0
var queued := false


func _init() -> void:
	var own := OS.get_environment("TEST_USER_DIR")
	if own != "":
		ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
		ProjectSettings.set_setting("application/config/custom_user_dir_name", own)
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	url = a[0]
	key = a[1]
	cmd_file = a[3]
	ServerLink.session_path = "user://peer_session.json"
	Replay.dir = "user://peer_replays"
	for p: Pack in Packs.all():  # (installed by an earlier run in this user dir: the copy takes minutes)
		if p.id() == "loot-2017":
			pack = p
	if pack == null:
		pack = Packs.install_file(a[2]).get("pack")
	Packs._active = pack
	Packs._changed()
	link = ServerLink.new()
	root.add_child(link)
	link.message.connect(_on_message)
	link.closed.connect(func(why): print("peer: closed ", why))
	link.opened.connect(func(): link.send({"t": "login", "user": USER, "password": PASSWORD}))
	link.open(url)
	print("peer: start")


func _deck() -> Deck:
	return Decks.templates()[0].deck


func _on_message(msg: Dictionary) -> void:
	match msg.t:
		"auth":
			if msg.get("ok", false):
				link.me = msg.get("me", {})
				print("peer: logged in ", link.me.get("user"))
				link.send({"t": "set_tag", "tag": "peerbob"})
				link.send({"t": "friends"})
				link.request_packs()  # (the queue names the game only for a pack the server lists)
			elif str(msg.get("code", "")) != "":
				print("peer: auth failed ", msg)
		"error":
			print("peer: error ", msg)
			if str(msg.get("code", "")) == "bad_login":
				link.send({"t": "register", "user": USER, "password": PASSWORD, "key": key})
			if queued and str(msg.get("code", "")) in ["queue", "deck"]:
				queued = false
		"friends":
			for f in msg.get("requests_in", []):
				link.send({"t": "friend_accept", "user": str(f.get("user", ""))})
		"queued":
			queued = true
		"match":
			queued = false
			session = link.session(msg, _deck())
			link.add_child(session)
			session.started.connect(func(m: Match):
				match_ = m
				session.add_child(m)
				print("peer: game started"))
		"game_over":
			print("peer: game over ", msg.get("result"))
			match_ = null


func _command(line: String) -> void:
	var p := line.strip_edges().split(" ", false, 2)
	if p.is_empty():
		return
	print("peer: command ", line)
	match p[0]:
		"add":
			link.send({"t": "friend_add", "tag": p[1]})
		"chat":
			link.send({"t": "msg", "to": p[1], "text": p[2] if p.size() > 2 else "?"})
		"invite":
			link.game_deck = _deck()
			link.send(link.with_pack({"t": "invite", "to": p[1], "deck": _deck().to_message()}))
		"play":
			playing = true
		"idle":
			playing = false
			if queued:
				link.send({"t": "unqueue"})
				queued = false
			if match_ and not match_.game.game_over:
				match_.submit({"type": "concede", "player": match_.viewer()})
		"kick":
			other = ServerLink.new()
			root.add_child(other)
			var u := p[1]
			var pw := p[2] if p.size() > 2 else ""
			other.opened.connect(func(): other.send({"t": "login", "user": u, "password": pw}))
			other.open(url)
		"quit":
			link.close()
			quit(0)


func _process(delta: float) -> bool:
	t += delta
	if FileAccess.file_exists(cmd_file):
		var text := FileAccess.get_file_as_string(cmd_file)
		if text.length() > read_at:
			var lines := text.substr(read_at).split("\n")
			var done := text.length()
			if not text.ends_with("\n"):  # a line half written: the next frame
				done -= lines[-1].length()
				lines.remove_at(lines.size() - 1)
			read_at = done
			for l in lines:
				_command(l)
	if playing and link.logged_in() and not link.packs.server.is_empty() and match_ == null and not queued and t > next_move:
		link.send(link.with_pack({"t": "queue", "mode": "casual", "deck": _deck().to_message()}))
		queued = true
		next_move = t + 3.0
	if match_ and not match_.game.game_over and t > next_move:
		var me := match_.viewer()
		var g: GameView = match_.game
		if not match_.waiting() and match_.legal().any(func(x): return x.player == me and x.type != "concede"):
			var tmp := Rules.new_id("peer")
			Rules.request({"op": "new", "game": tmp, "state": g.snapshot})
			match_.submit(Rules.request({"op": "bot", "game": tmp, "player": me}).get("action", {}))
			Rules.request({"op": "drop", "game": tmp})
			next_move = t + 1.6
	return false
