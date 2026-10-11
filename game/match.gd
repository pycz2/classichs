class_name Match
extends Node
## Runs one game: knows which players are bots, applies actions and lets the bot move.

signal changed(events: Array)
signal finished(winner: int)
## A local action in an online match: NetSession sends it with the state hash.
signal local_action(action: Dictionary, state_hash: String)

## Screen shake on heavy damage; the settings screen (subproject 6) toggles it.
static var shake_enabled := true

var game: Game
var bots: Array = [false, true]
## The player whose moves come from the network (-1 = no online opponent).
var remote := -1
## Seconds between bot actions; 0 = the bot moves at once (tests).
var bot_delay := 0.6
var _bot_scheduled := false
var _finished := false


func setup(g: Game, bot_players: Array) -> void:
	game = g
	bots = bot_players


func start() -> void:
	_after()


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


func submit(action: Dictionary) -> Dictionary:
	if remote >= 0 and int(action.get("player", -1)) == remote:
		return {"ok": false, "error": "the online opponent moves for this player", "events": []}
	var r := game.apply(action)
	if r.ok:
		if remote >= 0:
			local_action.emit(action, game.state_hash())
		changed.emit(r.events)
		_after()
	return r


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
	var r := game.apply(action)
	if not r.ok:
		push_warning("illegal remote action: " + r.error)
		return TranslationServer.translate("an illegal action")
	if expected_hash != "" and expected_hash != game.state_hash():
		return TranslationServer.translate("the game states differ")
	changed.emit(r.events)
	_after()
	return ""


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
		if is_bot_turn():
			_bot_step()
			_after())


func _bot_step() -> void:
	var r := game.apply(Bot.choose(game, actor()))
	if not r.ok:
		push_error("bot made an illegal move: " + r.error)
		game.apply({"type": "concede", "player": actor()})
		return
	changed.emit(r.events)
