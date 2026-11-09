class_name Replay
extends RefCounted
## A finished game to watch again: its setup (the players with their heroes and 30 cards, the
## seed, who goes first, the pack) and every applied action in order (mulligans and choices too),
## the result and the final state hash (the server's format, server/README.md "Replays"; a
## .chsreplay file is this JSON). The rules engine plays it again: build(k) is the game after
## k actions. The last KEEP games are kept in Replay.dir (local games from the Match history,
## server games fetched with `replay {game}` after their game_over).

const FORMAT := "classichs-replay"
const EXT := "chsreplay"
const KEEP := 10
static var dir := "user://replays"

## {format, v, game, mode, pack, pack_id, pack_name, started, ended, players: [{name, hero,
## cards}], seed, first, actions, result: {winner, reason, turns}, hash, me?} (me: the seat of
## this device's player, shown at the bottom).
var data := {}
var _game := ""  # the engine's game at action _at ("" = none yet)
var _at := -1
var _turns: Array = []  # the turn after k actions, k = 0..size()


## A replay from its JSON (null when it is not one).
static func from_data(d: Variant) -> Replay:
	if not d is Dictionary or d.get("format") != FORMAT or int(d.get("v", 0)) != 1:
		return null
	var pl = d.get("players")
	if not pl is Array or pl.size() != 2 or not d.get("actions") is Array or str(d.get("pack", "")) == "":
		return null
	for p in pl:
		if not p is Dictionary or not p.get("cards") is Array:
			return null
	var r := Replay.new()
	r.data = Rules.ints(d.duplicate(true))
	return r


static func from_text(text: String) -> Replay:
	var j := JSON.new()
	return from_data(j.data) if j.parse(text) == OK else null


static func from_file(path: String) -> Replay:
	return from_text(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null


func to_text() -> String:
	return JSON.stringify(data)


func to_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_text())
	f.close()
	return true


## The file name to export as: "alice-vs-bob-2026-11-09.chsreplay".
func file_name() -> String:
	var d := Time.get_date_string_from_unix_time(int(data.get("ended", 0)))
	var n := "%s-vs-%s-%s" % [name(0), name(1), d]
	return n.validate_filename().replace(" ", "_") + "." + EXT


## A local game that ended (Match.setup with decks and a seed): names by seat, mode "training",
## "code" or "hotseat", me = the seat of this device's player.
static func from_match(m: Match, names: Array, mode: String, me: int) -> Replay:
	var req := m.setup_req
	var actions := []
	for h in m.game.history.slice(1):
		actions.append(h.action)
	var p := Packs.active()
	var players := []
	for i in 2:
		players.append({"name": names[i], "hero": str(req.decks[i].hero), "cards": Array(req.decks[i].cards)})
	var now := int(Time.get_unix_time_from_system())
	return from_data({"format": FORMAT, "v": 1, "game": "local-%d-%d" % [now, randi() % 100000], "mode": mode,
		"pack": p.rules_hash(), "pack_id": p.id(), "pack_name": p.title(),
		"started": m.started, "ended": now, "players": players, "seed": req.seed, "first": int(req.get("first", -1)),
		"actions": actions, "result": {"winner": m.game.winner, "reason": "over", "turns": m.game.turn},
		"hash": m.state_hash, "me": me})


func size() -> int:
	return data.actions.size()


func name(p: int) -> String:
	return str(data.players[p].get("name", ""))


func hero(p: int) -> String:
	return str(data.players[p].get("hero", ""))


func winner() -> int:
	return int(data.get("result", {}).get("winner", -1))


func me() -> int:
	return clampi(int(data.get("me", 0)), 0, 1)


## The engine's `new` request of this game (without op and game).
func setup_req() -> Dictionary:
	var decks := []
	for p in data.players:
		decks.append({"hero": str(p.hero), "cards": Array(p.cards)})
	var req := {"decks": decks, "seed": int(data.seed), "check": false}
	if int(data.get("first", -1)) in [0, 1]:
		req.first = int(data.first)
	return req


## The installed pack this replay was played with (null: not on this device).
func pack() -> Pack:
	return Packs.find_rules(str(data.pack))


## "" when this device can play it again, else what is missing (translated).
func missing() -> String:
	if pack() == null:
		return TranslationServer.translate("This replay needs the game %s (rules %s)") % [str(data.get("pack_name", data.get("pack_id", "?"))), str(data.pack).left(8)]
	return ""


## The engine's game after k actions (built again from the start when going back). Needs the
## replay's pack active. False when the engine refused it.
func seek(k: int) -> bool:
	k = clampi(k, 0, size())
	if _game == "" or k < _at:
		drop()
		_game = Rules.new_id("replay")
		var req := setup_req().merged({"op": "new", "game": _game})
		var rules := Rules.engine_pack(pack()) if pack() else ""
		if rules != "":
			req.pack = rules  # its own rules, whichever game is active
		if not Rules.request(req).ok:
			_game = ""
			return false
		_at = 0
	while _at < k:
		if not Rules.request({"op": "act", "game": _game, "action": data.actions[_at]}).get("ok", false):
			return false
		_at += 1
	return true


## The game after k actions (null when it can't be built).
func build(k: int) -> GameView:
	if not seek(k):
		return null
	var g := GameView.new()
	g.update(Rules.request({"op": "snapshot", "game": _game}).state)
	g.history = Rules.request({"op": "history", "game": _game}).get("history", [])
	return g


## The engine's state hash after k actions.
func hash_at(k: int) -> String:
	return str(Rules.request({"op": "hash", "game": _game}).get("hash", "")) if seek(k) else ""


## The turn after k actions (0: the mulligan), for every k in 0..size().
func turns() -> Array:
	if _turns.is_empty() and seek(size()):
		for h in Rules.request({"op": "history", "game": _game}).get("history", []):
			_turns.append(int(h.turn))
	return _turns


## The index where each turn starts: [[turn, k]] (k actions played when turn t begins).
func turn_starts() -> Array:
	var out := []
	var t := turns()
	for k in t.size():
		if k == 0 or t[k] != t[k - 1]:
			out.append([t[k], k])
	return out


## The engine's game goes when the replay does.
func drop() -> void:
	if _game != "":
		Rules.request({"op": "drop", "game": _game})
	_game = ""
	_at = -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _game != "":
		Rules.request({"op": "drop", "game": _game})  # (no method calls while being freed)


# --- the store of the last games -------------------------------------------------------

## Keeps a replay among the last KEEP (the same game again replaces itself; the oldest go). at:
## its place in the order (unix s; default its end; an import: now).
static func keep(r: Replay, at := -1) -> void:
	if r == null:
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var id := str(r.data.get("game", "")).validate_filename()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with("_" + id + "." + EXT):
			DirAccess.remove_absolute(dir.path_join(f))
	r.to_file(dir.path_join("%012d_%s.%s" % [at if at >= 0 else int(r.data.get("ended", 0)), id, EXT]))
	var files := _files()
	for f in files.slice(KEEP):
		DirAccess.remove_absolute(dir.path_join(f))


static func _files() -> Array:
	if not DirAccess.dir_exists_absolute(dir):
		return []
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f: String): return f.ends_with("." + EXT))
	files.sort()
	files.reverse()  # newest first
	return files


## The kept replays, newest first.
static func kept() -> Array[Replay]:
	var out: Array[Replay] = []
	for f in _files():
		var r := from_file(dir.path_join(f))
		if r:
			r.set_meta("file", dir.path_join(f))
			out.append(r)
	return out


static func forget(r: Replay) -> void:
	if r.has_meta("file"):
		DirAccess.remove_absolute(r.get_meta("file"))
