class_name ServerLink
extends Node
## The connection to a game server (docs/superpowers/specs/2026-10-15-server-design.md):
## one WebSocket with JSON messages {"t": …}. It lives as long as the player stays
## on the server, across screens. A game's messages (state, act_error, emote,
## intent, game_over) go to its ServerSession; the server keeps the game.

signal opened
signal message(msg: Dictionary)
signal closed(reason: String)
## The server's game packs changed (`packs`: the list arrived or changed).
signal packs_changed
## A download's progress: bytes so far of total (total 0 = not known yet).
signal pack_progress(content_hash: String, done: int, total: int)
## A download ended: Packs.install's {pack} or {error} (translated).
signal pack_downloaded(content_hash: String, result: Dictionary)
## An upload ended: {pack} (the server's entry) or {error (translated), code}.
signal pack_uploaded(result: Dictionary)
## The count of the player's reports with news changed (reports_unread).
signal reports_unread_changed

## The saved sessions (user://, per player), one per connection (D14; by the connection's id:
## its address for the first one to it, so sessions saved before 0.40 stay):
## {"servers": {id: {token, deck: {name, hero}, mode, tab, kicked?}}, "last": id}.
## Tests point it at their own file.
const SESSION_DEFAULT_PATH := "user://server_session.json"
static var session_path := SESSION_DEFAULT_PATH
## Whether queue, invite, invite_accept, arena_start and me carry `pack` (the rules hash) to a
## server that knows packs (an older one refuses unknown fields).
static var send_pack := true
## Every connection is in this group (the settings find who is logged in).
const GROUP := "server_links"

var url := ""
## The connection's id in the list (Settings servers; "" = its address): its saved session is kept by it.
var id := "":
	get:
		return id if id != "" else url
var socket := WebSocketPeer.new()
var token := ""  # the session after login (also saved: the player stays logged in)
var me := {}  # the player's profile from the server
## A saved session is being resumed (the answer is an auth or an error).
var resuming := false
## Whether the server answers `chats` and `read` (asked once after login; an older server does not).
var has_chats := false
## Whether the server knows game packs (`packs`; asked after `chats`).
var has_packs := false
## Whether it keeps decks (`decks`; asked after `packs`) and settings per game (`game_settings`, then).
var has_decks := false
var has_settings := false
## The player's decks kept there (all games: {id, pack, name, hero, cards, created, updated}),
## kept up to date from `decks`, `deck_saved` and `deck_deleted`.
var decks: Array = []
## The player's settings per game kept there: {<pack id>: {art?, music?}} (`game_settings`).
var game_settings := {}
## Another login took the account (`kicked`): no resume by itself until the player logs in.
var kicked := false
## The sub-server stopped this connection (`kicked {reason}`: suspended, unavailable, deleted): its code, else "".
var stopped := ""
## What the player sees when a sub-server is stopped or full, by the server's code (translated where shown).
const STOPPED := {"server_suspended": "This server is suspended by the host",
	"server_unavailable": "This server is not available now: try later",
	"server_full": "This server has no room for new players", "server_deleted": "This server was deleted"}
## Registering needs an invite key (`signup_info`, asked once per connection; an older server
## refuses the question: no key).
var invite_only := false
var signup_asked := false
var _probing_signup := false
## The server's packs: {server: [pack], mine: [pack + enabled]}; a pack is
## {id, name: {lang: text}, version, rules_hash, content_hash, size, url} (server/README.md).
var packs := {"server": [], "mine": []}
## Downloads under way, till installed: content_hash -> PackInstall (its `request` meta: the HTTPRequest).
var downloading := {}
## The deck sent with the last queue, invite or acceptance: the server's game uses it.
var game_deck: Deck
var _probing := false
var _probing_packs := false
var _probing_decks := false
var _probing_settings := false
var _was_open := false
var _closed := true  # nothing to close before open()
var _games := {}  # game id -> ServerSession
var _replays := {}  # game id -> the player's seat: its replay is asked for after game_over, to keep


static func _tr(text: String) -> String:
	return str(TranslationServer.translate(text))


func _init() -> void:
	add_to_group(GROUP)


## The whole saved file (the old single-session form is read as its server's entry).
static func saved_all() -> Dictionary:
	var j := JSON.new()
	if not FileAccess.file_exists(session_path) or j.parse(FileAccess.get_file_as_string(session_path)) != OK or not j.data is Dictionary:
		return {"servers": {}}
	var d: Dictionary = j.data
	if d.get("servers") is Dictionary:
		return d
	var old := d.duplicate()  # {token, server, deck, mode, tab}
	var at := str(old.get("server", ""))
	if at == "":
		at = Settings.data.servers[0].url if not Settings.data.servers.is_empty() else ""
	old.erase("server")
	return {"servers": {at: old} if at != "" and not old.is_empty() else {}, "last": at}


static func _save_all(d: Dictionary) -> void:
	var f := FileAccess.open(session_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))


## The saved session of a server ({} when there is none).
static func saved_for(address: String) -> Dictionary:
	var e = saved_all().servers.get(address)
	return e if e is Dictionary else {}


## Merges values into a server's saved session (null removes one).
static func remember_for(address: String, values: Dictionary) -> void:
	var d := saved_all()
	var e := saved_for(address)
	for k in values:
		if values[k] == null:
			e.erase(k)
		else:
			e[k] = values[k]
	d.servers[address] = e
	_save_all(d)


## Forgets everything saved for a server (it was removed from the list).
static func forget(address: String) -> void:
	var d := saved_all()
	d.servers.erase(address)
	_save_all(d)


## The server chosen last in the lobby ("" = none yet).
static func last() -> String:
	return str(saved_all().get("last", ""))


static func remember_last(address: String) -> void:
	var d := saved_all()
	d["last"] = address
	_save_all(d)


## This connection's saved session.
func saved() -> Dictionary:
	return saved_for(id)


func remember(values: Dictionary) -> void:
	remember_for(id, values)


## The connection's name in the list (its host when not there).
func display_name() -> String:
	return Settings.server_name(id)


## Logged in on an open connection.
func logged_in() -> bool:
	return token != "" and is_open()


## Whether a saved session would log in by itself (a token, not kicked out by another login).
func can_resume() -> bool:
	var s := saved_for(id)
	return str(s.get("token", "")) != "" and not s.get("kicked", false)


## Opens the connection; with a saved session for this address it logs in again
## by itself (resume), unless another login took it (`kicked`) or force says so
## (the player asked to play here again). A rejected session is forgotten.
func open_and_resume(address: String, force := false) -> Error:
	var err := open(address)
	var s := saved()
	if err == OK and str(s.get("token", "")) != "" and (force or not s.get("kicked", false)):
		resuming = true
		opened.connect(func():
			if resuming:
				send({"t": "resume", "token": s.token}), CONNECT_ONE_SHOT)
	return err


## The saved session on an open connection, asked for by the player (after `kicked`).
func resume_saved() -> void:
	var t := str(saved().get("token", ""))
	if t != "" and is_open():
		resuming = true
		send({"t": "resume", "token": t})


func log_out() -> void:
	send({"t": "logout"})
	token = ""
	me = {}
	_clear_packs()
	remember({"token": null, "kicked": null})


func open(address: String) -> Error:
	url = address
	_closed = false
	_was_open = false
	resuming = false
	token = ""
	invite_only = false
	signup_asked = false
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1 << 20
	socket.outbound_buffer_size = 1 << 20
	return socket.connect_to_url(socket_url(address))


## The game's websocket of a server address: the main one at /, a sub-server's at /s/<name>/ (its router's root).
static func socket_url(address: String) -> String:
	return address + "/" if address.split("://")[-1].contains("/") else address


## Whether the connection was ever open (else the server could not be reached).
func was_open() -> bool:
	return _was_open


func is_open() -> bool:
	return socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func send(msg: Dictionary) -> void:
	if is_open():
		var text := JSON.stringify(msg)
		PerfLog.count("ws_out")
		PerfLog.count("ws_out_kb", text.length() / 1024.0)
		socket.send_text(text)


## Whether registering needs an invite key: the answer comes as `signup_info` (invite_only).
func request_signup_info() -> void:
	signup_asked = true
	_probing_signup = true
	send({"t": "signup_info"})


func close() -> void:
	resuming = false
	token = ""
	_clear_packs()
	if not _closed:
		_closed = true
		socket.close()


## A session for a game the server started (`match`); its messages go to it.
func session(msg: Dictionary, d: Deck) -> ServerSession:
	var s := ServerSession.new()
	s.setup(self, msg, str(me.get("user", "")), d)
	_add_game(s)
	return s


## Keeps a session for its game's messages; the freed ones go (one entry a game otherwise, for good).
func _add_game(s: ServerSession) -> void:
	for id in _games.keys():
		if not is_instance_valid(_games[id]):
			_games.erase(id)
	_games[s.game] = s


## A session for a game the player watches (`spectating`): read only, fed by `spectate_state`.
func watch(msg: Dictionary) -> ServerSession:
	var s := ServerSession.new()
	s.watch = true
	var names = msg.get("players", [])
	var seat := clampi(int(msg.get("seat", 0)), 0, 1)
	var name_of := func(p: int) -> String: return str(names[p]) if names is Array and names.size() == 2 else ""
	s.setup(self, {"game": msg.get("game", ""), "mode": msg.get("mode", "casual"), "you": seat, "pack": msg.get("pack", ""),
		"opponent": {"user": name_of.call(1 - seat)}}, name_of.call(seat), null)
	s.full = msg.get("full", false) == true
	s.started_ms = Time.get_ticks_msec() - int(float(msg.get("elapsed", 0)) * 1000.0)
	for x in _games.values():  # the server shows one game per spectator: an older one is over
		if is_instance_valid(x) and x.watch:
			x._done = true
	_add_game(s)
	return s


func _process(_d: float) -> void:
	socket.poll()
	var st := socket.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _was_open:
		_was_open = true
		opened.emit()
	while socket.get_available_packet_count() > 0:
		var t0 := Time.get_ticks_usec()
		var text := socket.get_packet().get_string_from_utf8()
		var msg = JSON.parse_string(text)
		PerfLog.time("ws_parse", t0)
		PerfLog.count("ws_in")
		PerfLog.count("ws_in_kb", text.length() / 1024.0)
		if msg is Dictionary and msg.get("t") is String:
			dispatch(msg)
	for h in downloading:
		var j: PackInstall = downloading[h]
		var r = j.get_meta("request") if j.has_meta("request") else null
		if j.stage == "receiving" and is_instance_valid(r):
			j.done = r.get_downloaded_bytes()
			j.total = maxi(r.get_body_size(), j.total)
			j.changed.emit()
		pack_progress.emit(h, j.done, j.total)
	if st == WebSocketPeer.STATE_CLOSED and not _closed:
		_closed = true
		resuming = false
		token = ""
		_clear_packs()
		var why := socket.get_close_reason()
		if why == "another_login" and not kicked:  # the kick told in the close frame (its text may be lost with the close)
			dispatch({"t": "kicked", "reason": why})
		for s in _games.values():
			if is_instance_valid(s):
				s.on_closed()
		var lost := _tr(STOPPED[stopped]) if stopped != "" else (why if why != "" else _tr("Connection lost"))
		closed.emit(_tr("You logged in on another device") if kicked else lost)


## A message from the server: a game's message goes to its channel, the rest to
## `message`. The session is kept here: saved on login, forgotten when refused.
func dispatch(msg: Dictionary) -> void:
	match msg.t:
		"auth":
			resuming = false
			if msg.get("ok", false):
				token = str(msg.get("token", ""))
				me = msg.get("me", {}) if msg.get("me") is Dictionary else {}
				kicked = false
				stopped = ""
				remember({"token": token, "kicked": null})
				_probing = true
				send({"t": "chats"})
				send_queued_reports()  # problem reports written offline
				request_reports()  # how many of the player's reports have news
		"error":
			if resuming:
				resuming = false
				msg["resume"] = true  # the answer to the saved session: no one needs to be told
				if msg.get("code") != "rate_limited":
					remember({"token": null})
			elif _probing_signup and msg.get("code") == "bad_request":  # before 0.50: no invite keys
				_probing_signup = false
				invite_only = false
				return
			elif _probing and msg.get("code") == "bad_request":  # an older server: no chats, no read
				_probing = false
				has_chats = false
				return
			elif _probing_packs and msg.get("code") == "bad_request":  # a server without packs
				_probing_packs = false
				has_packs = false
				return
			elif _probing_decks and msg.get("code") == "bad_request":  # a server without decks (before 0.32)
				_probing_decks = false
				return
			elif _probing_settings and msg.get("code") == "bad_request":  # without settings per game (before 0.40)
				_probing_settings = false
				return
			elif not _replays.is_empty() and msg.get("code") in ["bad_request", "not_found"]:  # no replays (before 0.50)
				_replays.erase(_replays.keys()[0])
				return
		"pack_stage":  # how the player's upload goes on the server (receiving, checking, trial, storing, done)
			for up: PackInstall in PackInstall.jobs:
				if up.upload and up.file.get_file() == msg.get("upload") and msg.get("stage") != "done":
					up.stage = str(msg.stage)
					var bytes: bool = msg.stage == "receiving"  # (the other stages have no measure)
					up.done = int(msg.get("done", 0)) if bytes else 0
					up.total = int(msg.get("total", 0)) if bytes else 0
					up.changed.emit()
		"me":  # the profile changed (a tag set, a game's result): every screen reads it from here
			if msg.get("me") is Dictionary:
				me = msg.me
		"reports_unread":  # an admin answered a report of the player's or changed its state
			_set_unread(int(msg.get("n", 0)))
		"signup_info":
			_probing_signup = false
			invite_only = msg.get("invite_only", false) == true
		"chats":
			if _probing:
				_probing = false
				_probing_packs = true
				send({"t": "packs"})
			has_chats = true
		"packs":
			if _probing_packs:
				_probing_decks = true
				send({"t": "decks"})
			_probing_packs = false
			has_packs = true
			packs = {"server": _list(msg.get("server")), "mine": _list(msg.get("mine"))}
			packs_changed.emit()
		"decks":
			if _probing_decks:
				_probing_decks = false
				_probing_settings = true
				send({"t": "game_settings"})
			has_decks = true
			decks = _list(msg.get("list"))
		"deck_saved":
			var d = msg.get("deck")
			if d is Dictionary:
				decks = decks.filter(func(x): return int(x.get("id", 0)) != int(d.get("id", 0))) + [d]
		"deck_deleted":
			decks = decks.filter(func(x): return int(x.get("id", 0)) != int(msg.get("id", 0)))
		"game_settings":
			_probing_settings = false
			has_settings = true
			game_settings = msg.get("games") if msg.get("games") is Dictionary else {}
		"kicked":  # another login took the account, or its sub-server stopped; the server closes this connection
			token = ""
			resuming = false
			if STOPPED.has(str(msg.get("reason", ""))):
				stopped = str(msg.reason)
			else:
				kicked = true
				remember({"kicked": true})
		"logged_out":
			token = ""
			_clear_packs()
		"replay":  # a finished game of this player's, kept among the last replays
			var id := str(msg.get("game", ""))
			if _replays.has(id):
				var r := Replay.from_data(msg.get("data"))
				if r:
					r.data.me = _replays[id]
					Replay.keep(r)
				_replays.erase(id)
				return
	if msg.t in ["state", "act_error", "emote", "intent", "game_over", "spectate_state", "spectate_end"]:
		var id := str(msg.get("game", ""))
		var s = _games.get(id)
		if s != null and not is_instance_valid(s):
			_games.erase(id)
		elif s != null:
			s.on_message(msg)
			if msg.t == "game_over" and not s.watch:
				_replays[id] = s.you
				send({"t": "replay", "game": id})
		if not msg.t in ["game_over", "spectate_end"]:
			return
	message.emit(msg)


static func _list(v: Variant) -> Array:
	return v.filter(func(e): return e is Dictionary) if v is Array else []


func _clear_packs() -> void:
	var had: bool = not (packs.server.is_empty() and packs.mine.is_empty())
	packs = {"server": [], "mine": []}
	has_packs = false
	_probing_packs = false
	has_decks = false
	has_settings = false
	_probing_decks = false
	_probing_settings = false
	decks = []
	game_settings = {}
	if had:
		packs_changed.emit()


# --- decks and settings per game kept on the server (server/README.md, "Decks", "Game settings")

## The player's decks of a game kept here (each knows its id here: Deck.servers[url]); of a version of a pack, the
## decks of that version (the deck's `version`; a server that keeps none: the pack's).
func decks_of(p: Pack) -> Array[Deck]:
	var out: Array[Deck] = []
	for sd in decks:
		if p and str(sd.get("pack", "")) == p.id() and (sd.get("version") == null or str(sd.version) == p.version_id):
			var d := Deck.from_dict(sd)
			if d:
				d.servers[url] = {"id": int(sd.get("id", 0)), "at": int(sd.get("updated", 0))}
				out.append(d)
	return out


## The player's choice for a game kept here ("art", "music"; "" = none yet).
func game_setting(p: Pack, kind: String) -> String:
	var mine = game_settings.get(p.id(), {}) if p else {}
	return str(mine.get(kind, "")) if mine is Dictionary else ""


## Keeps a choice for a game here (`game_settings_set`; the answer brings them all back).
func set_game_setting(p: Pack, kind: String, value: String) -> void:
	var mine: Dictionary = game_settings.get(p.id(), {}) if game_settings.get(p.id()) is Dictionary else {}
	mine[kind] = value
	game_settings[p.id()] = mine
	send(with_pack({"t": "game_settings_set", "settings": {kind: value}}, p))


# --- game packs on the server (server/README.md, "Game packs") ---------------------------

## Asks for the server's packs again (the answer is `packs`, then packs_changed).
func request_packs() -> void:
	send({"t": "packs"})


## The server's HTTP address: ws://host:port/s/x → http://host:port/s/x (wss → https; a sub-server's path kept).
func http_base() -> String:
	var rest := url.split("://")[-1].trim_suffix("/")
	return ("https://" if url.begins_with("wss://") else "http://") + rest


## A message with the game it plays (`pack`: the rules hash of p, else of the active pack)
## when the server lists that game (send_pack); without `pack` the server plays its default
## (an older server, or Classic on a server without packs: its built-in rules).
func with_pack(msg: Dictionary, p: Pack = null) -> Dictionary:
	p = p if p else Packs.active()
	if send_pack and not server_pack_for(p).is_empty():
		msg["pack"] = p.rules_hash()
	return msg


## Asks for the profile with the rank in the active game (`me {pack, format}`: a version with Standard and Wild
## has a ladder in each; the chosen one, Standard first, as the Play screen queues).
func request_me() -> void:
	var msg := with_pack({"t": "me"})
	var f := str(saved().get("format", ""))
	var fs := CardDb.formats()
	if msg.has("pack") and fs.size() > 1:
		msg["format"] = f if fs.has(f) else str(fs[0])
	send(msg)


## The server's entry for a pack the player has ({} when the server does not list it): the
## same rules (a different picture set plays the same game). friendly: the player's own
## uploads count too (only friendly games use them; queues use the server's packs).
func server_pack_for(p: Pack, friendly := true) -> Dictionary:
	if p == null:
		return {}
	for e in packs.server + (packs.mine if friendly else []):
		if entry_rules(e).has(p.rules_hash()):
			return e
	return {}


## The rules hashes a server entry plays: its own (the default version) and its versions' (format.md §13).
static func entry_rules(e: Dictionary) -> Array:
	var out := [str(e.get("rules_hash", ""))]
	var vs = e.get("versions", [])
	for v in vs if vs is Array else []:
		if v is Dictionary:
			out.append(str(v.get("rules_hash", "")))
	return out


## Why games of the pack cannot be played here (translated; "" = they can). A server without
## packs (an older one, or none installed) plays its built-in Classic rules.
func game_problem(p: Pack, friendly := false) -> String:
	if p == null:
		return ""
	if p.id() == Packs.CLASSIC and (not has_packs or packs.server.is_empty()):
		return ""
	if server_pack_for(p, friendly).is_empty():
		return _tr("This server does not have this game")
	return ""


func has_game(p: Pack, friendly := false) -> bool:
	return game_problem(p, friendly) == ""


## The player's pack for a server entry, or null: the same file (content_hash, D9) first,
## else the same rules.
static func local_pack(entry: Dictionary) -> Pack:
	var same_rules: Pack = null
	for p in Packs.all():
		if p.rules_hash() != str(entry.get("rules_hash", "")):
			continue
		if Packs.content_hash(p) == str(entry.get("content_hash", "")):
			return p
		if same_rules == null:
			same_rules = p
	return same_rules


## Whether an entry is the player's own upload.
func is_mine(entry: Dictionary) -> bool:
	return packs.mine.any(func(e): return e.get("content_hash") == entry.get("content_hash"))


## Downloads a server pack (GET /packs/<content_hash>.cardpack with the session token) straight
## into a file, then installs it in the background if its files give that content hash
## (PackInstall): pack_progress, then pack_downloaded.
func download_pack(entry: Dictionary) -> void:
	var h := str(entry.get("content_hash", ""))
	if h == "" or downloading.has(h):
		return
	var j := PackInstall.receiving(ServerView.entry_title(entry), "downloaded", {"server": url}, h)
	j.total = int(entry.get("size", 0))
	j.finished.connect(_installed.bind(h))
	downloading[h] = j.start()
	var r := _http("/packs/%s.cardpack" % h, HTTPClient.METHOD_GET, PackedByteArray(), _downloaded.bind(j), j.file)
	if r:
		j.set_meta("request", r)


func _downloaded(code: int, _body: PackedByteArray, j: PackInstall) -> void:
	if code == 401:
		j.finish({"error": _tr("Log in to the server again")})
	elif code == 404:
		j.finish({"error": _tr("The server no longer has this game")})
	elif code != 200:
		j.finish({"error": _tr("The download failed (%s)") % (str(code) if code > 0 else "-")})
	else:
		j.received()


func _installed(res: Dictionary, h: String) -> void:
	downloading.erase(h)
	if str(res.get("error", "")) in [Packs.ERRORS[2], Packs.ERRORS[3]]:
		res = {"error": _tr("The download is damaged: try again"), "detail": res.get("detail", "")}
	pack_downloaded.emit(h, res)


## Uploads one of the player's packs (POST /packs, the file as the body): pack_uploaded;
## the server sends a new `packs` after it.
func upload_pack(p: Pack) -> void:
	var bytes := Packs.bytes_of(p)
	if bytes.is_empty():
		pack_uploaded.emit({"error": _tr("Cannot read the pack"), "code": "read"})
		return
	var up := PackInstall.receiving(p.title(), "upload")  # (shown on the screens; the server tells its stages by its file name)
	up.upload = true
	up.total = bytes.size()
	_http("/packs", HTTPClient.METHOD_POST, bytes, _uploaded.bind(up.start()), "", up.file.get_file())


## The server's answers to an upload (server/README.md): code -> the player's words.
const UPLOAD_ERRORS := {"auth_required": "Log in to the server again", "bad_token": "Log in to the server again",
	"exists": "You have uploaded this game already", "too_many": "You have the most games this server keeps: delete one first",
	"too_large": "The game is too big for this server", "empty": "The upload broke off", "bad_body": "The upload broke off"}


func _uploaded(code: int, body: PackedByteArray, up: PackInstall) -> void:
	var j = JSON.parse_string(body.get_string_from_utf8())
	var d: Dictionary = j if j is Dictionary else {}
	if code == 201 and d.get("pack") is Dictionary:
		up.finish({"pack": d.pack})
		pack_uploaded.emit({"pack": d.pack})
		return
	var c := str(d.get("code", str(code)))
	var text: String = _tr(UPLOAD_ERRORS[c]) if UPLOAD_ERRORS.has(c) else ""
	if c == "invalid":
		text = _tr("The server refused the game: %s") % str(d.get("error", ""))
	elif text == "":
		text = _tr("The server could not take the game (%s)") % c
	up.finish({"error": text, "code": c})
	pack_uploaded.emit({"error": text, "code": c})


## Deletes one of the player's uploads (`pack_delete`; the answer is a new `packs`).
func delete_pack(content_hash: String) -> void:
	send({"t": "pack_delete", "content_hash": content_hash})


# --- problem reports (server/README.md, "Reports") ---------------------------------------

## Reports waiting to go (offline, not logged in, or the server could not take them yet): one JSON file
## each, the body of POST /reports. Tests point it at their own folder.
static var reports_dir := "user://reports_queue"
static var _reports_sending := {}  # path -> true while its request is under way (on any connection)

## The server's answers to a report: code -> the player's words.
const REPORT_ERRORS := {"auth_required": "Log in to the server again", "bad_token": "Log in to the server again",
	"bad_text": "Write what happened (up to 4000 characters)", "bad_screen": "The screenshot is damaged: remove it",
	"bad_voice": "The voice message is damaged: record it again",
	"too_large": "The report is too big: remove the screenshot or record a shorter voice message",
	"too_many": "You have sent many reports this hour", "not_found": "This report is no longer on the server"}


## Keeps a report to send after the next login; its file's path.
static func queue_report(report: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(reports_dir)
	var path := "%s/%d_%d.json" % [reports_dir, Time.get_unix_time_from_system(), randi()]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report))
	return path


## The reports waiting to go, oldest first.
static func queued_reports() -> Array:
	if not DirAccess.dir_exists_absolute(reports_dir):
		return []
	var out := Array(DirAccess.get_files_at(reports_dir)).filter(func(f): return f.ends_with(".json"))
	out.sort()
	return out.map(func(f): return reports_dir + "/" + f)


## Sends a report (kept in the queue till the server answers): done({id}) or done({error, code, kept}).
func send_report(report: Dictionary, done: Callable) -> void:
	_send_report_file(queue_report(report), done)


## The player's reports (threads) with an answer or a change not seen yet (GET /reports, `reports_unread`).
var reports_unread := 0


## The player's reports (GET /reports): done({list, unread}) or done({error, code}); the unread count is kept.
func request_reports(done := Callable()) -> void:
	_http("/reports", HTTPClient.METHOD_GET, PackedByteArray(), func(code: int, body: PackedByteArray):
		var d := _report_answer(code, body, 200)
		if d.has("list"):
			_set_unread(int(d.get("unread", 0)))
		if done.is_valid():
			done.call(d))


## One report with its messages (GET /reports/<id>; opening it clears its unread mark): done({id, state,
## messages, …}) or done({error, code}). The unread count is asked again after it.
func request_report(id: int, done: Callable) -> void:
	_http("/reports/%d" % id, HTTPClient.METHOD_GET, PackedByteArray(), func(code: int, body: PackedByteArray):
		var d := _report_answer(code, body, 200)
		if done.is_valid():
			done.call(d)
		if not d.has("error"):
			request_reports())


## A reply in a report's thread (POST /reports/<id> {text, screen}): done({message}) or done({error, code}).
func reply_report(id: int, text: String, screen_png: PackedByteArray, done: Callable) -> void:
	var body := JSON.stringify({"text": text, "screen": Marshalls.raw_to_base64(screen_png) if not screen_png.is_empty() else ""})
	_http("/reports/%d" % id, HTTPClient.METHOD_POST, body.to_utf8_buffer(), func(code: int, data: PackedByteArray):
		if done.is_valid():
			done.call(_report_answer(code, data, 201)), "", "", "application/json")


func _set_unread(n: int) -> void:
	reports_unread = n
	reports_unread_changed.emit()


## The server's answer about reports: its JSON when the code is ok, else {error (the player's words), code}.
func _report_answer(code: int, body: PackedByteArray, ok: int) -> Dictionary:
	var j = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else null
	var d: Dictionary = j if j is Dictionary else {}
	if code == ok:
		return d
	var c := str(d.get("code", str(code)))
	var text: String = _tr(REPORT_ERRORS[c]) if REPORT_ERRORS.has(c) else ""
	if code == 0:
		text = _tr("No answer from the server")
	elif text == "":
		text = _tr("The server could not take the report (%s)") % c
	return {"error": text, "code": c}


## Sends the reports waiting to go (after a login).
## ponytail: any server's login takes the whole queue (a report does not remember its server).
func send_queued_reports() -> void:
	for path in queued_reports():
		if not _reports_sending.has(path):
			_send_report_file(path, Callable())


## POST /reports with a waiting report: taken (201) or bad (another 4xx) it leaves the queue; it stays
## when there was no answer, the login is gone (401), there were too many (429), the server has no
## reports (404, 405: an older one) or failed (5xx).
func _send_report_file(path: String, done: Callable) -> void:
	_reports_sending[path] = true
	_http("/reports", HTTPClient.METHOD_POST, FileAccess.get_file_as_bytes(path), func(code: int, body: PackedByteArray):
		_reports_sending.erase(path)
		var res := _report_answer(code, body, 201)
		if code == 201:
			res = {"id": int(res.report.get("id", 0)) if res.get("report") is Dictionary else 0}
		else:
			res["kept"] = code == 0 or code in [401, 404, 405, 429] or code >= 500
		if not res.get("kept", false):
			DirAccess.remove_absolute(path)
		if done.is_valid():
			done.call(res), "", "", "application/json")


## An HTTP request to the server with the session token; done(code, body) gets the answer
## (code 0: no answer). to_file: the answer goes straight into that file (body empty); upload_id:
## the server tells the stages of this upload by it (`pack_stage`); content_type: a POST body's.
## Tests replace it.
func _http(path: String, method: int, body: PackedByteArray, done: Callable, to_file := "", upload_id := "", content_type := "application/octet-stream") -> HTTPRequest:
	var r := HTTPRequest.new()
	r.use_threads = not OS.has_feature("web")
	r.download_file = to_file
	r.download_chunk_size = 1 << 22  # (the browser takes a chunk a frame: 64 KiB ones made a 60 MB pack take 20 s)
	add_child(r)
	r.request_completed.connect(func(result: int, code: int, _h, data: PackedByteArray):
		r.queue_free()
		done.call(code if result == HTTPRequest.RESULT_SUCCESS else 0, data))
	var headers := PackedStringArray(["Authorization: Bearer " + token])
	if method == HTTPClient.METHOD_POST:
		headers.append("Content-Type: " + content_type)
		if upload_id != "":
			headers.append("X-Upload-Id: " + upload_id)
	if r.request_raw(http_base() + path, headers, method, body) != OK:
		r.queue_free()
		done.call(0, PackedByteArray())
		return null
	return r
