extends SceneTree
## Records games played by the GDScript engine as JSONL fixtures for the Rust
## engine's parity test (rust/engine/tests/parity.rs): the setup, then per step
## the action, ok/error, a hash of the events and the state hash.
##
## godot --headless --path . --script res://tools/engine_record.gd -- \
##     --out rust/engine/tests/fixtures --games 120 --reps 1 --extra 4 --seed 1
## The big set (gitignored): --out rust/engine/tests/fixtures/big --games 3000 --reps 4 --extra 25 --seed 2
## Writes games.jsonl (random/bot games), scenarios.jsonl (every card test scene,
## `reps` random positions per playable card that start by playing it, tutorial
## missions; `extra` random/bot steps after each) and misc.jsonl (RNG, mulligan
## seeds, Arena drafts, deck validation). --full stores whole event lists
## instead of hashes; --only N records game N of games.jsonl alone.

const HEROES := ["HERO_01", "HERO_02", "HERO_03", "HERO_04", "HERO_05", "HERO_06", "HERO_07", "HERO_08", "HERO_09"]
const MAX_STEPS := 400

var r := RandomNumberGenerator.new()
var full := false
var reps := 3
var extra := 12
var playable: Array = []  # every MINION, SPELL and WEAPON card id
var minion_ids: Array = []
var secret_ids: Array = []
var weapon_ids: Array = []
var power_ids: Array = []
var hero_ids: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "rust/engine/tests/fixtures"
	var games := 300
	var seed := 1
	var only := -1
	var i := 0
	while i < args.size():
		match args[i]:
			"--out": out = args[i + 1]; i += 1
			"--games": games = int(args[i + 1]); i += 1
			"--seed": seed = int(args[i + 1]); i += 1
			"--only": only = int(args[i + 1]); i += 1
			"--reps": reps = int(args[i + 1]); i += 1
			"--extra": extra = int(args[i + 1]); i += 1
			"--full": full = true
		i += 1
	r.seed = seed
	for id: String in CardDb.all_ids():
		var c := CardDb.card(id)
		match c.type:
			"MINION":
				playable.append(id)
				minion_ids.append(id)
			"WEAPON":
				playable.append(id)
				weapon_ids.append(id)
			"SPELL":
				playable.append(id)
				if c.get("mechanics", []).has("SECRET"):
					secret_ids.append(id)
			"HERO_POWER":
				if Cards.of(id).has("hero_power"):
					power_ids.append(id)
			"HERO":
				hero_ids.append(id)
	for arr in [playable, minion_ids, secret_ids, weapon_ids, power_ids, hero_ids]:
		arr.sort()
	DirAccess.make_dir_recursive_absolute(out)
	if only >= 0:
		_record_games(out + "/only.jsonl", games, only)
	else:
		_record_misc(out + "/misc.jsonl")
		_record_scenarios(out + "/scenarios.jsonl")
		_record_games(out + "/games.jsonl", games, -1)
	Cards.unload()
	quit()


func _short(s: String) -> String:
	return s.sha256_text().substr(0, 16)


# --- games ------------------------------------------------------------------

func _record_games(path: String, n: int, only: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	for k in n:
		var gseed := r.randi()
		var plan := _plan(k, gseed)
		if only >= 0 and k != only:
			continue
		var g := Game.new(plan.p0, plan.p1, plan.seed, plan.first)
		var setup := {"kind": "new", "p0": plan.p0, "p1": plan.p1, "seed": plan.seed, "first": plan.first}
		_play(f, "game%d" % k, g, setup, plan.bot, plan.rr)
		if k % 50 == 0:
			print("games: %d" % k)
	f.close()


## Everything about game k comes from its own seed, so --only reproduces it.
func _plan(k: int, gseed: int) -> Dictionary:
	var rr := RandomNumberGenerator.new()
	rr.seed = gseed
	var decks := []
	for i in 2:
		var hero: String = HEROES[rr.randi_range(0, 8)]
		var kind := rr.randi_range(0, 2)
		var deck: Array = []
		if kind == 0:
			deck = Decks.basic(Decks.card_class(hero))
		elif kind == 1:  # any 30 cards of the whole pool
			var pool := CardDb.collectible().filter(func(id): return CardDb.card(id).type != "HERO")
			for j in 30:
				deck.append(pool[rr.randi_range(0, pool.size() - 1)])
		else:  # class and neutral cards
			var cls := Decks.card_class(hero)
			var pool := CardDb.collectible().filter(func(id):
				var c := CardDb.card(id)
				return c.type != "HERO" and (c.cardClass == cls or c.cardClass == "NEUTRAL"))
			for j in 30:
				deck.append(pool[rr.randi_range(0, pool.size() - 1)])
		decks.append({"hero": hero, "deck": deck})
	var bots := [0.0, 0.3, 0.7, 1.0]
	return {"p0": decks[0], "p1": decks[1], "seed": rr.randi_range(0, 2000000000) * (1 if k % 7 else -1),
		"first": rr.randi_range(-1, 1), "bot": bots[k % 4], "rr": rr}


## Plays g to the end (or MAX_STEPS): the actor takes Bot.choose with
## probability bot, else a random legal action; sometimes an illegal one.
func _play(f: FileAccess, id: String, g: Game, setup: Dictionary, bot: float, rr: RandomNumberGenerator,
		scripted: Array = []) -> void:
	var steps := []
	var start_events: Array = g.history[0].events if not g.history.is_empty() else []
	var line := {"id": id, "setup": setup, "h0": _short(g.state_hash()), "e0": _events(start_events), "steps": steps}
	for a in scripted:
		steps.append(_step(g, a, -1))
	var n := 0
	while not g.game_over and n < MAX_STEPS:
		n += 1
		var actor := _actor(g)
		var legal := g.legal_actions().filter(func(a): return a.player == actor and a.type != "concede")
		if rr.randf() < 0.03:
			steps.append(_step(g, _illegal(g, rr, legal), -1))
			continue
		if rr.randf() < 0.002:
			steps.append(_step(g, {"type": "concede", "player": rr.randi_range(0, 1)}, -1))
			continue
		if legal.is_empty():
			break
		var a: Dictionary
		var by_bot := -1
		if rr.randf() < bot:
			a = Bot.choose(g, actor)
			by_bot = actor
		else:
			var plays := legal.filter(func(x): return x.type != "end_turn")
			if not plays.is_empty() and rr.randf() < 0.75:
				a = plays[rr.randi_range(0, plays.size() - 1)]
			else:
				a = legal[rr.randi_range(0, legal.size() - 1)]
		steps.append(_step(g, a, by_bot))
	line["dump"] = _short(JSON.stringify(Scenario.dump(g)))
	f.store_line(JSON.stringify(line))


func _actor(g: Game) -> int:
	if not g.pending.is_empty():
		return g.pending.player
	if g.phase == "MULLIGAN":
		return 0 if not g.players[0].mulliganed else 1
	return g.current


func _events(events: Array) -> Variant:
	return events if full else _short(JSON.stringify(events))


func _step(g: Game, a: Dictionary, by_bot: int) -> Dictionary:
	var s := {"a": a, "l": _short(JSON.stringify(g.legal_actions()))}
	if by_bot >= 0:
		s["b"] = by_bot
	var res := g.apply(a)
	s["ok"] = res.ok
	if not res.ok:
		s["err"] = res.error
	s["e"] = _events(res.events)
	s["h"] = _short(g.state_hash())
	return s


## An action the engine must refuse (or accept, if it happens to be legal).
func _illegal(g: Game, rr: RandomNumberGenerator, legal: Array) -> Dictionary:
	var base: Dictionary = legal[rr.randi_range(0, legal.size() - 1)].duplicate() if not legal.is_empty() \
		else {"type": "end_turn", "player": g.current}
	match rr.randi_range(0, 6):
		0: base.player = 1 - int(base.player)
		1: base["target"] = rr.randi_range(-1, g._next_id + 2)
		2: base["extra"] = 1
		3: base.erase("type")
		4:  # floats as JSON gives them: still legal
			for k in base:
				if base[k] is int:
					base[k] = float(base[k])
		5: base["type"] = ["play", "attack", "hero_power", "choose", "mulligan", "dance"][rr.randi_range(0, 5)]
		6: base["player"] = 0.5
	return base


# --- scenarios ----------------------------------------------------------------

func _record_scenarios(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	var rr := RandomNumberGenerator.new()
	rr.seed = r.randi()
	# 1. every card test scene, its steps, then some more play
	var tests := CardTests.load_all()
	var ids: Array = tests.keys()
	ids.sort()
	var n := 0
	for id in ids:
		for t: Dictionary in tests[id]:
			var b := Scenario.build(t.scene)
			if b.error != "":
				continue
			var g: Game = b.game
			var setup := {"kind": "scenario", "scenario": t.scene}
			var acts := []
			for step in t.steps:
				var a := CardTests.action(g, step)
				if a.has("error"):
					break
				acts.append(a)
				g.apply(a)
			var g2: Game = Scenario.build(t.scene).game
			_play_scripted(f, "test:%s:%d" % [id, n], g2, setup, acts, rr, extra)
			n += 1
	print("card tests: %d" % n)
	# 2. random positions: every playable card in hand, with random boards
	for rep in reps:
		for id in playable:
			var sc := _random_scene(rr, id)
			var b := Scenario.build(sc)
			if b.error != "":
				push_error("scene for %s: %s" % [id, b.error])
				continue
			var g: Game = b.game
			var plays := g.legal_actions().filter(func(a): return a.type == "play" and g.ent(a.entity).card_id == id)
			var first := [plays[rr.randi_range(0, plays.size() - 1)]] if not plays.is_empty() else []
			_play_scripted(f, "pos:%s:%d" % [id, rep], g, {"kind": "scenario", "scenario": sc}, first, rr, extra * 2)
	print("positions done")
	# 3. tutorial missions
	for m in range(1, Missions.count() + 1):
		for rep in reps + 1:
			var t := Tutorial.start(m)
			_play_scripted(f, "mission:%d:%d" % [m, rep], t.game, {"kind": "mission", "n": m}, [], rr, 30 * extra)
	f.close()


## Scripted actions first, then `more` steps of random/bot play.
func _play_scripted(f: FileAccess, id: String, g: Game, setup: Dictionary, acts: Array,
		rr: RandomNumberGenerator, more: int) -> void:
	var steps := []
	var line := {"id": id, "setup": setup, "h0": _short(g.state_hash()), "e0": _events([]), "steps": steps}
	for a in acts:
		steps.append(_step(g, a, -1))
	var bot: float = [0.0, 0.5, 1.0][rr.randi_range(0, 2)]
	for k in more:
		if g.game_over:
			break
		var actor := _actor(g)
		var legal := g.legal_actions().filter(func(a): return a.player == actor and a.type != "concede")
		if legal.is_empty():
			break
		if rr.randf() < bot:
			steps.append(_step(g, Bot.choose(g, actor), actor))
		else:
			var plays := legal.filter(func(x): return x.type != "end_turn")
			var pick: Array = plays if not plays.is_empty() and rr.randf() < 0.8 else legal
			steps.append(_step(g, pick[rr.randi_range(0, pick.size() - 1)], -1))
	line["dump"] = _short(JSON.stringify(Scenario.dump(g)))
	f.store_line(JSON.stringify(line))


func _pick(rr: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[rr.randi_range(0, arr.size() - 1)]


func _random_minion(rr: RandomNumberGenerator) -> Variant:
	var m := {"card": _pick(rr, minion_ids)}
	match rr.randi_range(0, 7):
		0: m["damage"] = rr.randi_range(1, 2)
		1: m["exhausted"] = true
		2: m["tags"] = [_pick(rr, ["TAUNT", "DIVINE_SHIELD", "STEALTH", "WINDFURY", "FROZEN", "CHARGE"])]
		3: m["enchantments"] = [{"atk": rr.randi_range(0, 3), "hp": rr.randi_range(0, 3), "eot": rr.randi_range(0, 1) == 1}]
		4: m["silenced"] = true
	return m if m.size() > 1 else m.card


## A position where `card` is in the current player's hand with mana to play it.
func _random_scene(rr: RandomNumberGenerator, card: String) -> Dictionary:
	var ps := []
	var cur := rr.randi_range(0, 1)
	for i in 2:
		var hero: String = _pick(rr, HEROES) if rr.randf() < 0.9 else _pick(rr, hero_ids)
		var d := {"hero": hero, "mana": 10, "max_mana": 10}
		if not GameState.HERO_POWERS.has(hero) or rr.randf() < 0.15:
			d["hero_power"] = _pick(rr, power_ids)
		var hand := []
		for k in rr.randi_range(0, 6):
			hand.append(_pick(rr, playable))
		if i == cur:
			hand.insert(rr.randi_range(0, hand.size()), card)
		d["hand"] = hand
		var deck := []
		for k in rr.randi_range(0, 12):
			deck.append(_pick(rr, playable))
		d["deck"] = deck
		var board := []
		for k in rr.randi_range(0, 7 if i != cur else 6):
			board.append(_random_minion(rr))
		d["board"] = board
		if rr.randf() < 0.3:
			d["weapon"] = _pick(rr, weapon_ids)
		if rr.randf() < 0.3:
			var s := []
			for k in rr.randi_range(1, 3):
				var sid: String = _pick(rr, secret_ids)
				if not s.has(sid):
					s.append(sid)
			d["secrets"] = s
		if rr.randf() < 0.3:
			d["damage"] = rr.randi_range(0, 25)
		if rr.randf() < 0.2:
			d["armor"] = rr.randi_range(0, 8)
		if rr.randf() < 0.1:
			d["cards_played"] = rr.randi_range(1, 2)  # combo
		ps.append(d)
	return {"current": cur, "turn": rr.randi_range(1, 20), "seed": rr.randi_range(1, 1000000), "players": ps}


# --- misc ---------------------------------------------------------------------

func _record_misc(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	for s in [0, 1, 42, -5, 123456789, 9223372036854775807, -9223372036854775808]:
		var g := RandomNumberGenerator.new()
		g.seed = s
		var ri := []
		for k in 40:
			ri.append(g.randi_range(0, k))
		var rf := []
		for k in 20:
			rf.append("%.17f" % g.randf())
		f.store_line(JSON.stringify({"t": "rng", "seed": s, "range": ri, "randf": rf, "state": str(g.state),
			"randi": g.randi()}))
		f.store_line(JSON.stringify({"t": "mulligan_seed", "seed": s, "out": [Game.mulligan_seed(s, 0), Game.mulligan_seed(s, 1)]}))
	var ref := Referee.new()
	for k in 60:
		var req := {"op": "draft", "seed": float(r.randi_range(0, 1000000))}
		if k % 6 != 0:
			req["hero"] = float(r.randi_range(0, 2))
			var picks := []
			for j in r.randi_range(0, 31):
				picks.append(float(r.randi_range(0, 2)))
			req["picks"] = picks
		f.store_line(JSON.stringify({"t": "ref", "req": req, "out": ref.handle(req)}))
	for k in 60:
		var hero: String = _pick(r, HEROES)
		var cards := []
		var pool := CardDb.collectible()
		var size := 30 if k % 3 else r.randi_range(25, 31)
		for j in size:
			cards.append(_pick(r, pool) if k % 2 else _pick(r, Decks.basic(Decks.card_class(hero))))
		var req := {"op": "validate", "deck": {"hero": hero, "cards": cards, "arena": k % 5 == 0}}
		f.store_line(JSON.stringify({"t": "ref", "req": req, "out": ref.handle(req)}))
	f.close()
