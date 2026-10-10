class_name Match
extends Node
## Runs one game: knows which players are bots, applies actions and lets the bot move.

signal changed(events: Array)
signal finished(winner: int)

## Screen shake on heavy damage; the settings screen (subproject 6) toggles it.
static var shake_enabled := true

var game: Game
var bots: Array = [false, true]
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
		for p in 2:
			if not game.players[p].mulliganed and bots[p]:
				return p
		return 0 if not game.players[0].mulliganed else 1
	if not game.pending.is_empty():
		return game.pending.player
	return game.current


## The side shown face up: the human player, or whoever acts in hot-seat.
func viewer() -> int:
	if bots[0] != bots[1]:
		return 0 if not bots[0] else 1
	return actor()


func is_bot_turn() -> bool:
	return not game.game_over and bots[actor()]


func submit(action: Dictionary) -> Dictionary:
	var r := game.apply(action)
	if r.ok:
		changed.emit(r.events)
		_after()
	return r


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
