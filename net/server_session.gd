class_name ServerSession
extends Node
## One game on a game server, which keeps the only game state
## (docs/superpowers/specs/2026-10-15-thin-client-design.md, "Server games"):
## the server sends `match`, then a `state` (this player's view, the events,
## the result with the turn's deadline) after the start and after every action;
## the client answers with `act`, and gets `act_error` when the server refuses.
## Emotes and intents go through the server. The same face to MatchView as a
## NetSession (started, failed, emotes, intents, leave).

signal started(m: Match)
signal failed(reason: String)
signal emote_received(player: int, id: String)
signal intent_received(intent: Dictionary)

const GAME_OVER_TEXT := {"disconnect": "Connection lost", "aborted": "The game was stopped by the server",
	"illegal": "Something does not add up: your game and the server's differ. Nobody is banned."}

## Anything with send(msg: Dictionary): the ServerLink.
var link: Object
var game := ""
var mode := "casual"
var you := 0
var rejoin := false
var player_name := ""
var remote_name := ""
var deck: Deck
var match_: Match
## Why the session ended: "left", "connection", "desync" (the server's game differs).
var failure_kind := ""
var transport = null  # (a NetSession has one; MatchView asks)
var _done := false
## The game's pack (`match.pack`, a rules hash) while this device still has to get it; its
## states wait in _held (a state is the whole view: the last one is enough).
var _want_pack := ""
var _held := {}


func setup(p_link: Object, msg: Dictionary, p_name: String, d: Deck) -> void:
	link = p_link
	game = str(msg.get("game", ""))
	mode = str(msg.get("mode", "casual"))
	you = clampi(int(msg.get("you", 0)), 0, 1)
	rejoin = msg.get("rejoin", false) == true
	var opp = msg.get("opponent", {})
	remote_name = Profile.clean(str(opp.get("user", ""))) if opp is Dictionary else ""
	player_name = Profile.clean(p_name)
	deck = d
	_want_pack = str(msg.get("pack", ""))
	_use_pack()


## The table shows the game's pack: one this device has becomes the active one at once; else
## the server's file is downloaded first (a rejoin on another device, or after the file was deleted).
func _use_pack() -> void:
	var act := Packs.active()
	if _want_pack == "" or act == null or act.rules_hash() == _want_pack:
		_want_pack = ""
		return
	var have := Packs.find_rules(_want_pack)
	if have:
		Packs.set_active(have)
		_want_pack = ""
		return
	if not link is ServerLink:
		return
	var entry := {}
	for e in link.packs.server + link.packs.mine:
		if str(e.get("rules_hash", "")) == _want_pack:
			entry = e
	if entry.is_empty() and not link.has_packs:  # the list comes a moment after the login
		link.packs_changed.connect(_use_pack, CONNECT_ONE_SHOT)
		return
	if entry.is_empty():
		_fail_pack(TranslationServer.translate("The server no longer has this game"))
		return
	link.pack_downloaded.connect(_on_pack_downloaded)
	link.download_pack(entry)


func _on_pack_downloaded(_h: String, res: Dictionary) -> void:
	if _want_pack == "" or _done:
		return
	var p = res.get("pack")
	if not p is Pack or p.rules_hash() != _want_pack:
		if res.has("error"):
			_fail_pack(str(res.error))
		return
	link.pack_downloaded.disconnect(_on_pack_downloaded)
	Packs.set_active(p)
	_want_pack = ""
	if not _held.is_empty():
		var h := _held
		_held = {}
		on_message(h)


func _fail_pack(reason: String) -> void:
	_done = true
	failure_kind = "connection"
	failed.emit(reason)


func send(msg: Dictionary) -> void:
	if link:
		msg["game"] = game
		link.send(msg)


## A message of this game from the server.
func on_message(msg: Dictionary) -> void:
	if _done:
		return
	match msg.get("t"):
		"state":
			if not msg.get("view") is Dictionary or not msg.get("result") is Dictionary:
				return
			if _want_pack != "":
				_held = msg
				return
			if match_ == null:
				match_ = Match.new()
				match_.setup_server(send, you, msg, Array(deck.cards) if deck and not rejoin else [])
				match_.refused.connect(func(e): push_warning("the server refused a move: " + e))
				started.emit(match_)
			else:
				match_.on_state(msg)
		"act_error":
			if match_:
				match_.on_act_error(msg)
		"emote":
			if match_ and NetSession.EMOTES.has(msg.get("id")) and int(msg.get("from", you)) != you:
				emote_received.emit(1 - you, msg.id)
		"intent":
			var i := NetSession.clean_intent(msg.get("i"))
			if match_ and not i.is_empty() and int(msg.get("from", you)) != you:
				intent_received.emit(i)
		"game_over":
			_done = true
			var reason := str(msg.get("reason", "over"))
			if reason != "over" and not (match_ and match_.game.game_over):
				failure_kind = "desync" if reason == "illegal" else "connection"
				failed.emit(TranslationServer.translate(str(msg.get("message", GAME_OVER_TEXT.get(reason, "Connection lost")))))


## The connection to the server is gone.
func on_closed() -> void:
	if _done or (match_ and match_.game.game_over):
		return
	_done = true
	failure_kind = "connection"
	var kicked: bool = link is ServerLink and link.kicked  # another login took the account (and this game)
	failed.emit(TranslationServer.translate("You logged in on another device" if kicked else "Connection lost"))


func send_emote(id: String) -> void:
	if NetSession.EMOTES.has(id):
		send({"t": "emote", "id": id})


func send_intent(intent: Dictionary) -> void:
	if not _done:
		send({"t": "intent", "i": intent})


## Leaving a running game on a server loses it (the concede action).
func leave() -> void:
	if not _done and match_ and not match_.game.game_over:
		send({"t": "act", "action": {"type": "concede", "player": you}})
	failure_kind = "left"
	_done = true
