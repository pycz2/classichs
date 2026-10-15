class_name Match
extends Node
## Runs one game: sends the actions to its authority and keeps the GameView the
## table draws. The authority is the local rules engine (training with the bot,
## hot-seat, tutorial, debug, peer-to-peer lockstep) or a game server (server
## games: actions go out as `act`, the server's `state` comes back through
## on_state(); this side never sees hidden cards). Lets the bot move.

signal changed(events: Array)
signal finished(winner: int)
## A local action in an online match: NetSession sends it with the state hash.
signal local_action(action: Dictionary, state_hash: String)
## The server refused this player's action (nothing changed).
signal refused(error: String)

## Screen shake on heavy damage; the settings screen (subproject 6) toggles it.
static var shake_enabled := true

var game := GameView.new()
## The game in the local engine ("" in a server game).
var id := ""
var bots: Array = [false, true]
## The player whose moves come from the network (-1 = no online opponent).
var remote := -1
## Seconds between bot actions; 0 = the bot moves at once (tests).
var bot_delay := 0.6
## The table may still be animating: the bot waits until this returns false.
var busy: Callable = func() -> bool: return false
## A server game: sends a message to the server ({"t": "act", "action": …}).
var server := Callable()
## The engine's state hash after the last action (local engine only).
var state_hash := ""
var _deadline := -1.0  # server game: seconds left to move when the last state came
var _deadline_ms := 0
var _waiting := false
var _legal = null  # cached legal actions (null: ask again)
var _bot_scheduled := false
var _finished := false


## A game in the local engine: req is the engine's `new` request without op and game
## ({decks, seed, first?, check?} | {scenario} | {mission}). "" or why it failed.
func setup(req: Dictionary, bot_players: Array) -> String:
	bots = bot_players
	id = Rules.new_id()
	var r := Rules.request(req.merged({"op": "new", "game": id}, true))
	if not r.ok:
		id = ""
		return str(r.get("error", "?"))
	state_hash = r.hash
	_sync()
	return ""


## A game on a server, from its first state (match + state messages).
func setup_server(send: Callable, you: int, state: Dictionary, own_deck: Array) -> void:
	server = send
	remote = 1 - you
	bots = [false, false]
	game.start_decks[you] = own_deck
	_take_state(state)


func is_server() -> bool:
	return server.is_valid()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and id != "":
		Rules.request({"op": "drop", "game": id})


func start() -> void:
	_after()


## The view and the new history entries from the engine.
func _sync() -> void:
	_legal = null
	game.update(Rules.request({"op": "snapshot", "game": id}).state)
	var h := Rules.request({"op": "history", "game": id, "from": game.history.size()})
	game.history.append_array(h.get("history", []))
	if game.start_decks == [[], []]:
		game.start_decks = h.get("start_decks", [[], []])


## The player who must act now.
func actor() -> int:
	if game.phase == "MULLIGAN":
		if remote >= 0 and not game.players[1 - remote].mulliganed:
			return 1 - remote  # online mulligans are simultaneous: the local player chooses now
		for p in 2:
			if not game.players[p].mulliganed and bots[p]:
				return p
		return 0 if not game.players[0].mulliganed else 1
	if not game.pending.is_empty():
		return game.pending.player
	return game.current


## The side shown face up: the human player, or whoever acts in hot-seat.
func viewer() -> int:
	if remote >= 0:
		return 1 - remote
	if bots[0] != bots[1]:
		return 0 if not bots[0] else 1
	return actor()


func is_bot_turn() -> bool:
	return not game.game_over and bots[actor()]


## The legal actions now (both players), in the engine's order.
func legal() -> Array:
	if _legal == null:
		_legal = plan([]).legal
	return _legal


## The game after the given actions (the table's queued orders) and its legal
## actions: {game: GameView, legal: Array}. A server game plans on its own view.
func plan(acts: Array) -> Dictionary:
	if acts.is_empty() and _legal != null:
		return {"game": game, "legal": _legal}
	var tmp := id
	if is_server() or not acts.is_empty():
		tmp = Rules.new_id("plan")
		var src := {"state": game.snapshot} if is_server() else {"copy": id}
		Rules.request(src.merged({"op": "new", "game": tmp}))
	for a in acts:
		Rules.request({"op": "act", "game": tmp, "action": a})
	var out := {"game": game, "legal": Rules.request({"op": "legal", "game": tmp}).get("actions", [])}
	if not acts.is_empty():
		out.game = GameView.new()
		out.game.update(Rules.request({"op": "snapshot", "game": tmp}).state)
	if tmp != id:
		Rules.request({"op": "drop", "game": tmp})
	if acts.is_empty():
		_legal = out.legal
	return out


## The position as a scenario (the debug table's JSON); {} in a server game.
func dump() -> Dictionary:
	return {} if id == "" else Rules.request({"op": "dump", "game": id}).get("scenario", {})


## Why a tutorial mission does not let player p end the turn yet ("" = it does), translated.
func end_turn_block(p: int) -> String:
	var why := str(Rules.request({"op": "end_turn_block", "game": id, "player": p}).get("block", ""))
	return "" if why == "" else TranslationServer.translate(why)


## A server game: an action was sent and its state has not come back yet.
func waiting() -> bool:
	return _waiting


func submit(action: Dictionary) -> Dictionary:
	if remote >= 0 and int(action.get("player", -1)) == remote:
		return {"ok": false, "error": "the online opponent moves for this player", "events": []}
	if is_server():
		if game.game_over:
			return {"ok": false, "error": "the game is over", "events": []}
		_waiting = true
		server.call({"t": "act", "action": action})
		return {"ok": true, "error": "", "events": []}
	var r := _apply(action)
	if r.ok:
		if remote >= 0:
			local_action.emit(action, state_hash)
		changed.emit(r.events)
		_after()
	return r


func _apply(action: Variant) -> Dictionary:
	var r := Rules.request({"op": "act", "game": id, "action": action})
	if not r.ok:
		return {"ok": false, "error": str(r.get("error", "?")), "events": []}
	state_hash = r.hash
	_sync()
	return {"ok": true, "error": "", "events": r.get("events", [])}


## The online turn timer ran out for player p: keep the mulligan hand, take the
## first option of an open choice, end the turn. These are normal moves, sent to the
## peer as usual. A server plays them itself.
func timeout(p: int) -> void:
	if is_server():
		return
	for i in 3:
		if game.game_over:
			return
		var pick := {}
		for a in legal():
			if a.player != p:
				continue
			if (a.type == "mulligan" and a.replace.is_empty()) or a.type == "choose":
				pick = a
				break
			if a.type == "end_turn" and game.pending.is_empty():
				pick = a
		if pick.is_empty():
			return
		submit(pick)
		if pick.type != "choose":
			return


## Applies the online opponent's action. "" on success, else the reason it was refused.
## expected_hash "" skips the state check (moves both players may make at once: mulligan, concede).
func submit_remote(action: Variant, expected_hash: String) -> String:
	if not action is Dictionary:
		return TranslationServer.translate("a broken action")
	var pl = action.get("player")
	if not (pl is int or pl is float) or int(pl) != remote:
		return TranslationServer.translate("an action for the wrong player")
	if game.game_over:
		return ""  # e.g. a move that crossed a concede: the game is already decided
	var r := _apply(action)
	if not r.ok:
		push_warning("illegal remote action: " + r.error)
		return TranslationServer.translate("an illegal action")
	if expected_hash != "" and expected_hash != state_hash:
		return TranslationServer.translate("the game states differ")
	changed.emit(r.events)
	_after()
	return ""


# --- server games -------------------------------------------------------------------

## A `state` from the server: {view, events, result: {over, winner, turn, current, phase, deadline}}.
func on_state(msg: Dictionary) -> void:
	var who := actor()
	_take_state(msg)
	var events: Array = msg.get("events", [])
	if not events.is_empty():
		var a := _guess_action(events, who)
		game.history.append({"turn": game.turn, "player": a.player, "action": a, "events": events})
		if a.player == 1 - remote:
			_waiting = false  # the state of this player's move (not one of the opponent's in between)
	if game.game_over:
		_waiting = false
	changed.emit(events)
	_after()


func _take_state(msg: Dictionary) -> void:
	_legal = null
	game.update(msg.get("view", {}))
	if game.history.is_empty():
		game.history.append({"turn": 0, "player": game.current, "action": {"type": "start"}, "events": msg.get("events", [])})
	var res: Dictionary = msg.get("result", {})
	_deadline = float(res.get("deadline", -1))
	_deadline_ms = Time.get_ticks_msec()


func on_act_error(msg: Dictionary) -> void:
	_waiting = false
	refused.emit(str(msg.get("error", "")))


## Server game: the seconds left to move in this turn (or the mulligan), -1 = no limit known.
func time_left() -> float:
	if _deadline < 0.0:
		return -1.0
	return maxf(0.0, _deadline - (Time.get_ticks_msec() - _deadline_ms) / 1000.0)


## The action behind a server state's events (for the history): the server sends
## what happened, not what was asked.
static func _guess_action(events: Array, who: int) -> Dictionary:
	for ev in events:
		match ev.type:
			"play":
				return {"type": "play", "player": ev.player, "entity": ev.entity, "target": ev.get("target", -1)}
			"attack":
				return {"type": "attack", "player": ev.get("player", who), "attacker": ev.attacker, "defender": ev.defender}
			"hero_power":
				return {"type": "hero_power", "player": ev.player, "entity": ev.entity, "target": ev.get("target", -1)}
			"mulligan_chosen":
				return {"type": "mulligan", "player": ev.player}
			"turn_end":
				return {"type": "end_turn", "player": ev.player}
	return {"type": "", "player": who}


# --- bot -------------------------------------------------------------------------

func _after() -> void:
	if game.game_over:
		if not _finished:
			_finished = true
			finished.emit(game.winner)
		return
	if not is_bot_turn() or _bot_scheduled:
		return
	if bot_delay <= 0.0:
		while is_bot_turn():
			_bot_step()
		_after()
		return
	if not is_inside_tree():
		return  # the screen was left; nobody plays this match any more
	_bot_scheduled = true
	get_tree().create_timer(bot_delay).timeout.connect(func():
		_bot_scheduled = false
		if busy.call():
			_after()  # look again a moment later
			return
		if is_bot_turn():
			_bot_step()
			_after())


func _bot_step() -> void:
	var p := actor()
	var r := _apply(Rules.request({"op": "bot", "game": id, "player": p}).get("action"))
	if not r.ok:
		push_error("bot made an illegal move: " + r.error)
		_apply({"type": "concede", "player": p})
		return
	changed.emit(r.events)
