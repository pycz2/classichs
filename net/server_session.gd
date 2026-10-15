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
	failed.emit(TranslationServer.translate("Connection lost"))


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
