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

## The saved sessions (user://, per player), one per server (D14):
## {"servers": {url: {token, deck: {name, hero}, mode, tab, kicked?}}, "last": url}.
## Tests point it at their own file.
const SESSION_DEFAULT_PATH := "user://server_session.json"
static var session_path := SESSION_DEFAULT_PATH
## Whether queue, invite, invite_accept, arena_start and me carry `pack` (the rules hash) to a
## server that knows packs (an older one refuses unknown fields).
static var send_pack := true
## Every connection is in this group (the settings find who is logged in).
const GROUP := "server_links"

var url := ""
var socket := WebSocketPeer.new()
var token := ""  # the session after login (also saved: the player stays logged in)
var me := {}  # the player's profile from the server
## A saved session is being resumed (the answer is an auth or an error).
var resuming := false
## Whether the server answers `chats` and `read` (asked once after login; an older server does not).
var has_chats := false
## Whether the server knows game packs (`packs`; asked after `chats`).
var has_packs := false
## Another login took the account (`kicked`): no resume by itself until the player logs in.
var kicked := false
## The server's packs: {server: [pack], mine: [pack + enabled]}; a pack is
## {id, name: {lang: text}, version, rules_hash, content_hash, size, url} (server/README.md).
var packs := {"server": [], "mine": []}
## Downloads under way: content_hash -> HTTPRequest.
var downloading := {}
## The deck sent with the last queue, invite or acceptance: the server's game uses it.
var game_deck: Deck
var _probing := false
var _probing_packs := false
var _was_open := false
var _closed := true  # nothing to close before open()
var _games := {}  # game id -> ServerSession


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


## This server's saved session.
func saved() -> Dictionary:
	return saved_for(url)


func remember(values: Dictionary) -> void:
	remember_for(url, values)


## The server's name in the list (its host when not there).
func display_name() -> String:
	return Settings.server_name(url)


## Logged in on an open connection.
func logged_in() -> bool:
	return token != "" and is_open()


## Whether a saved session would log in by itself (a token, not kicked out by another login).
func can_resume() -> bool:
	var s := saved_for(url)
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
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1 << 20
	socket.outbound_buffer_size = 1 << 20
	return socket.connect_to_url(address)


## Whether the connection was ever open (else the server could not be reached).
func was_open() -> bool:
	return _was_open


func is_open() -> bool:
	return socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func send(msg: Dictionary) -> void:
	if is_open():
		socket.send_text(JSON.stringify(msg))


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
	_games[s.game] = s  # a freed session is dropped on its next message
	return s


func _process(_d: float) -> void:
	socket.poll()
	var st := socket.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and not _was_open:
		_was_open = true
		opened.emit()
	while socket.get_available_packet_count() > 0:
		var text := socket.get_packet().get_string_from_utf8()
		var msg = JSON.parse_string(text)
		if msg is Dictionary and msg.get("t") is String:
			dispatch(msg)
	for h in downloading:
		var r: HTTPRequest = downloading[h]
		pack_progress.emit(h, r.get_downloaded_bytes(), maxi(r.get_body_size(), int(r.get_meta("size", 0))))
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
		closed.emit(_tr("You logged in on another device") if kicked else (why if why != "" else _tr("Connection lost")))


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
				remember({"token": token, "kicked": null})
				_probing = true
				send({"t": "chats"})
		"error":
			if resuming:
				resuming = false
				msg["resume"] = true  # the answer to the saved session: no one needs to be told
				if msg.get("code") != "rate_limited":
					remember({"token": null})
			elif _probing and msg.get("code") == "bad_request":  # an older server: no chats, no read
				_probing = false
				has_chats = false
				return
			elif _probing_packs and msg.get("code") == "bad_request":  # a server without packs
				_probing_packs = false
				has_packs = false
				return
		"chats":
			if _probing:
				_probing = false
				_probing_packs = true
				send({"t": "packs"})
			has_chats = true
		"packs":
			_probing_packs = false
			has_packs = true
			packs = {"server": _list(msg.get("server")), "mine": _list(msg.get("mine"))}
			packs_changed.emit()
		"kicked":  # another login took the account; the server closes this connection
			token = ""
			kicked = true
			resuming = false
			remember({"kicked": true})
		"logged_out":
			token = ""
			_clear_packs()
	if msg.t in ["state", "act_error", "emote", "intent", "game_over"]:
		var id := str(msg.get("game", ""))
		var s = _games.get(id)
		if s != null and not is_instance_valid(s):
			_games.erase(id)
		elif s != null:
			s.on_message(msg)
		if msg.t != "game_over":
			return
	message.emit(msg)


static func _list(v: Variant) -> Array:
	return v.filter(func(e): return e is Dictionary) if v is Array else []


func _clear_packs() -> void:
	var had: bool = not (packs.server.is_empty() and packs.mine.is_empty())
	packs = {"server": [], "mine": []}
	has_packs = false
	_probing_packs = false
	if had:
		packs_changed.emit()


# --- game packs on the server (server/README.md, "Game packs") ---------------------------

## Asks for the server's packs again (the answer is `packs`, then packs_changed).
func request_packs() -> void:
	send({"t": "packs"})


## The server's HTTP address: ws://host:port → http://host:port (wss → https).
func http_base() -> String:
	var rest := url.split("://")[-1].get_slice("/", 0)
	return ("https://" if url.begins_with("wss://") else "http://") + rest


## A message with the game it plays (`pack`: the rules hash of p, else of the active pack)
## when the server lists that game (send_pack); without `pack` the server plays its default
## (an older server, or Classic on a server without packs: its built-in rules).
func with_pack(msg: Dictionary, p: Pack = null) -> Dictionary:
	p = p if p else Packs.active()
	if send_pack and not server_pack_for(p).is_empty():
		msg["pack"] = p.rules_hash()
	return msg


## Asks for the profile with the rank in the active game (`me {pack}`).
func request_me() -> void:
	send(with_pack({"t": "me"}))


## The server's entry for a pack the player has ({} when the server does not list it): the
## same rules (a different picture set plays the same game). friendly: the player's own
## uploads count too (only friendly games use them; queues use the server's packs).
func server_pack_for(p: Pack, friendly := true) -> Dictionary:
	if p == null:
		return {}
	for e in packs.server + (packs.mine if friendly else []):
		if str(e.get("rules_hash", "")) == p.rules_hash():
			return e
	return {}


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


## Downloads a server pack (GET /packs/<content_hash>.cardpack with the session token),
## installs it if its files give that content hash: pack_progress, then pack_downloaded.
func download_pack(entry: Dictionary) -> void:
	var h := str(entry.get("content_hash", ""))
	if h == "" or downloading.has(h):
		return
	var r := _http("/packs/%s.cardpack" % h, HTTPClient.METHOD_GET, PackedByteArray(), _downloaded.bind(entry))
	if r:
		r.set_meta("size", int(entry.get("size", 0)))
		downloading[h] = r


func _downloaded(code: int, body: PackedByteArray, entry: Dictionary) -> void:
	var h := str(entry.get("content_hash", ""))
	downloading.erase(h)
	var res := {}
	if code == 401:
		res = {"error": _tr("Log in to the server again")}
	elif code == 404:
		res = {"error": _tr("The server no longer has this game")}
	elif code != 200:
		res = {"error": _tr("The download failed (%s)") % (str(code) if code > 0 else "-")}
	else:
		res = Packs.install(body, "downloaded", {"server": url}, h)
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
	_http("/packs", HTTPClient.METHOD_POST, bytes, _uploaded)


## The server's answers to an upload (server/README.md): code -> the player's words.
const UPLOAD_ERRORS := {"auth_required": "Log in to the server again", "bad_token": "Log in to the server again",
	"exists": "You have uploaded this game already", "too_many": "You have the most games this server keeps: delete one first",
	"too_large": "The game is too big for this server", "empty": "The upload broke off", "bad_body": "The upload broke off"}


func _uploaded(code: int, body: PackedByteArray) -> void:
	var j = JSON.parse_string(body.get_string_from_utf8())
	var d: Dictionary = j if j is Dictionary else {}
	if code == 201 and d.get("pack") is Dictionary:
		pack_uploaded.emit({"pack": d.pack})
		return
	var c := str(d.get("code", str(code)))
	var text: String = _tr(UPLOAD_ERRORS[c]) if UPLOAD_ERRORS.has(c) else ""
	if c == "invalid":
		text = _tr("The server refused the game: %s") % str(d.get("error", ""))
	elif text == "":
		text = _tr("The server could not take the game (%s)") % c
	pack_uploaded.emit({"error": text, "code": c})


## Deletes one of the player's uploads (`pack_delete`; the answer is a new `packs`).
func delete_pack(content_hash: String) -> void:
	send({"t": "pack_delete", "content_hash": content_hash})


## An HTTP request to the server with the session token; done(code, body) gets the answer
## (code 0: no answer). Tests replace it.
func _http(path: String, method: int, body: PackedByteArray, done: Callable) -> HTTPRequest:
	var r := HTTPRequest.new()
	r.use_threads = not OS.has_feature("web")
	add_child(r)
	r.request_completed.connect(func(result: int, code: int, _h, data: PackedByteArray):
		r.queue_free()
		done.call(code if result == HTTPRequest.RESULT_SUCCESS else 0, data))
	var headers := PackedStringArray(["Authorization: Bearer " + token])
	if method == HTTPClient.METHOD_POST:
		headers.append("Content-Type: application/octet-stream")
	if r.request_raw(http_base() + path, headers, method, body) != OK:
		r.queue_free()
		done.call(0, PackedByteArray())
		return null
	return r
