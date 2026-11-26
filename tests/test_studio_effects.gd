extends TestCase
## ClassicHS Studio's effect blocks (studio/studio_effects.gd): every block template the catalog allows
## compiles in a pack (Tiny Duel of tests/test_pack_tools.gd plus a card a block) and plays in a real
## engine game until its trigger fires, without a script error; key blocks do what they say.

const DIR := "user://test_studio_effects"
## The pack's names of the engine ids StudioEffects.keywords() gives (Tiny Duel's own, else the same).
const NAMES := {"ON_PLAY": "CRY", "ON_DEATH": "LAST_WORD", "TRAP": "AMBUSH", "GUARD": "WALL"}
const EXTRA_MECHANICS := ["COMBO", "AURA", "TRIGGER", "FREEZE", "SILENCE", "OFFER", "SPELL_SCALED", "HASTE", "QUICK",
	"BARRIER", "DOUBLE_ATTACK", "STEALTH", "SPELLPROOF", "IMMUNE", "POISON", "LIFESTEAL", "CANT_ATTACK"]
## The card field of a block for each action that needs one.
const CARD_FOR := {"summon": "cub", "transform": "cub", "add_card": "squire", "shuffle_card": "squire", "equip": "t_axe"}

static var _pack := ""  # the loaded pack's rules_hash
static var _cards := {}  # card id -> [trigger, type, block]


## A card of this type for the tests, with the pack names of its blocks' keywords.
static func _card(id: String, type: String, effect: Dictionary) -> Dictionary:
	var c := {"id": id, "type": type, "class": "NEUTRAL", "set": "token", "cost": 1, "script": "scripts/studio.lua#" + id}
	match type:
		"MINION":
			c.merge({"attack": 2, "health": 3})
		"WEAPON":
			c.merge({"attack": 2, "durability": 2})
		"CHAMPION":
			c.merge({"class": "SUN", "health": 20, "armor": 5, "power": "sunbeam"})
		"POWER":
			c.class = "SUN"
	var kws := StudioEffects.keywords(effect, type).map(func(k): return NAMES.get(k, k))
	if not kws.is_empty():
		c.keywords = kws
	return c


## Every block the catalog allows (problems() refuses the rest): card id -> [trigger, type, block].
static func _combos() -> Dictionary:
	var out := {}
	var kws := StudioEffects.KEYWORDS
	for w: Dictionary in StudioEffects.TRIGGERS:
		for type: String in w.types:
			for a: Dictionary in StudioEffects.ACTIONS:
				for t: Dictionary in StudioEffects.TARGETS:
					var b := {"when": w.id, "target": t.id, "do": a.id, "n": 1, "m": 1}
					if CARD_FOR.has(a.id):
						b.card = CARD_FOR[a.id]
					if a.id == "give_keyword":
						b.keyword = kws[out.size() % kws.size()].id
					if StudioEffects.problems({"blocks": [b]}, type).is_empty():
						out["t%d" % out.size()] = [w.id, type, b]
	return out


## Builds the pack of every combination once (PackCheck: no errors) and loads it into the engine.
func _load(extra := {}) -> bool:
	if _pack != "" and extra.is_empty():
		return true
	_cards = _combos()
	_cards.merge(extra)
	var tiny: Dictionary = load("res://tests/test_pack_tools.gd").TINY
	var cards: Array = Rules.ints(JSON.parse_string(tiny["cards.json"]))
	var locale: Dictionary = JSON.parse_string(tiny["locales/en.json"])
	cards.append({"id": "t_axe", "type": "WEAPON", "class": "NEUTRAL", "set": "token", "cost": 1, "attack": 3, "durability": 2})
	var effects := {}
	for id: String in _cards:
		effects[id] = {"blocks": [_cards[id][2]]} if _cards[id][2] is Dictionary else _cards[id][2]
		cards.append(_card(id, _cards[id][1], effects[id]))
	for c: Dictionary in cards:
		if not locale.cards.has(c.id):
			locale.cards[c.id] = {"name": c.id, "text": StudioEffects.describe(_cards[c.id][2], c.type) if _cards.has(c.id) else ""}
	var rules: Dictionary = Rules.ints(JSON.parse_string(tiny["rules.json"]))
	for m: String in EXTRA_MECHANICS:
		rules.mechanics[m] = {"engine": m}
	var files := tiny.duplicate()
	files["cards.json"] = JSON.stringify(cards, " ")
	files["rules.json"] = JSON.stringify(rules, " ")
	files["locales/en.json"] = JSON.stringify(locale, " ")
	files["scripts/studio.lua"] = StudioEffects.script(cards, effects)
	var dir := DIR + "/pack"
	_wipe(dir)
	for p: String in files:
		DirAccess.make_dir_recursive_absolute((dir + "/" + p).get_base_dir())
		var f := FileAccess.open(dir + "/" + p, FileAccess.WRITE)
		f.store_string(files[p])
		f.close()
	var c := PackCheck.open_folder(dir)
	c.check()
	var bad := c.items.filter(func(it): return it.level == PackCheck.ERROR).map(func(it): return "%s:%d %s" % [it.file, it.line, it.text])
	eq(bad.slice(0, 5), [], "the pack of %d block cards checks clean" % _cards.size())
	if not c.load_engine():
		check(false, "the engine loads it: " + str(c.items.back()))
		return false
	_pack = c.rules_hash
	return true


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_wipe(dir + "/" + d)
	DirAccess.remove_absolute(dir)


## The scenario that lets card id's trigger fire, and the steps that fire it.
static func _scene(id: String, when: String, type: String) -> Dictionary:
	var me := {"hero": "sun_queen", "mana": 10, "max_mana": 10, "hand": [], "deck": ["squire", "squire", "squire"],
		"board": ["squire", "shield_bearer"]}
	var foe := {"hero": "moon_king", "mana": 10, "max_mana": 10, "hand": ["squire", "spark"], "deck": ["squire", "squire", "squire"],
		"board": ["squire", "cub"]}
	var sc := {"players": [me, foe]}
	var steps := []
	var hit := "sun_queen" if type == "WEAPON" else id  # who attacks
	var on_board := func(spec: Variant) -> void:
		if type == "WEAPON":
			me.weapon = spec if spec is Dictionary else {"card": id}
		else:
			me.board.insert(1, spec)
	match when:
		"play":
			if type == "POWER":
				me.hero_power = id
				steps = [["power"]]
			else:
				me.hand = [id]
				steps = [["play", id]]
		"combo":
			me.hand = ["spark", id]
			steps = [["play", "spark"], ["play", id]]
		"deathrattle":
			on_board.call({"card": id, "durability": 1} if type == "WEAPON" else {"card": id, "damage": 2})
			steps = [["attack", hit, "squire"]]
		"turn_end", "aura":
			on_board.call(id)
			steps = [["end"]]
		"turn_start":
			on_board.call(id)
			steps = [["end"], ["end"]]
		"friendly_summon":
			on_board.call(id)
			me.hand = ["squire"]
			steps = [["play", "squire"]]
		"spell_cast":
			on_board.call(id)
			me.hand = ["spark"]
			steps = [["play", "spark"]]
		"damaged", "attack":
			on_board.call(id)
			steps = [["attack", hit, "squire"]]
		"secret_attacked":
			me.secrets = [id]
			sc.current = 1
			steps = [["attack", "squire", "shield_bearer"]]  # past its Wall
		"secret_minion_played":
			me.secrets = [id]
			sc.current = 1
			steps = [["play", "squire"]]
		"secret_spell_cast":
			me.secrets = [id]
			sc.current = 1
			steps = [["play", "spark"]]
	return {"scenario": sc, "steps": steps}


## Plays card id's scenario to its trigger; [last reply, snapshot state] or a failure text.
func _play(id: String) -> Variant:
	var spec: Array = _cards[id]
	var s := _scene(id, spec[0], spec[1])
	var game := Rules.new_id("studio_fx")
	var r := Rules.request({"op": "new", "game": game, "pack": _pack, "scenario": s.scenario})
	if not r.get("ok", false):
		return "does not start: %s" % r.get("error", "?")
	for step: Array in s.steps:
		var state: Dictionary = Rules.request({"op": "snapshot", "game": game}).state
		var p := int(state.current)
		var act := _action(state, Rules.request({"op": "legal", "game": game, "player": p}).get("actions", []), step)
		if act.is_empty():
			Rules.request({"op": "drop", "game": game})
			return "no legal %s" % [step]
		r = Rules.request({"op": "act", "game": game, "action": act})
		for i in 3:  # a Discover waits for its choice
			if r.has("script_error"):
				break
			var picks: Array = []
			for q in 2:
				picks.append_array(Rules.request({"op": "legal", "game": game, "player": q}).get("actions", []).filter(func(x): return x.type == "choose"))
			if picks.is_empty():
				break
			r = Rules.request({"op": "act", "game": game, "action": picks[0]})
		if r.has("script_error") or not r.get("ok", false):
			Rules.request({"op": "drop", "game": game})
			return "%s: %s" % [step, r.get("script_error", r.get("error", "?"))]
	var state: Dictionary = Rules.request({"op": "snapshot", "game": game}).state
	Rules.request({"op": "drop", "game": game})
	return [r, state]


## The legal action a step means: play a card (a target if it takes one), use the power, attack an enemy
## minion with that card (a weapon: the hero), end the turn.
static func _action(state: Dictionary, legal: Array, step: Array) -> Dictionary:
	var card := func(e: Variant) -> String:
		return str(state.entities.get(str(int(e)), {}).get("card", ""))
	var pick := legal.filter(func(x: Dictionary) -> bool:
		match step[0]:
			"play":
				return x.type == "play" and card.call(x.entity) == step[1]
			"power":
				return x.type == "hero_power"
			"attack":
				return x.type == "attack" and card.call(x.attacker) == step[1] and card.call(x.defender) == step[2]
			"end":
				return x.type == "end_turn"
		return false)
	if pick.is_empty():
		return {}
	var aimed := pick.filter(func(x): return int(x.get("target", -1)) >= 0)
	return aimed[0] if not aimed.is_empty() else pick[0]


func test_every_block_template_compiles_and_plays() -> void:
	if not _load():
		return
	check(_cards.size() > 500, "many combinations: %d" % _cards.size())
	var bad := []
	for id: String in _cards:
		var got: Variant = _play(id)
		if got is String:
			bad.append("%s %s: %s / %s" % [_cards[id][1], _cards[id][2], got, StudioEffects.card_lua(id, _cards[id][1], {"blocks": [_cards[id][2]]})])
	eq(bad.size(), 0, "blocks that fail: " + "\n".join(bad.slice(0, 6)))


## The entity of side p whose card is card, its first one on the board (or anywhere).
static func _ent(state: Dictionary, p: int, card: String, zone := "PLAY") -> Dictionary:
	for e: String in state.entities:
		var x: Dictionary = state.entities[e]
		if int(x.ctrl) == p and x.card == card and x.zone == zone:
			return x
	return {}


## Plays one block on a card of its own; the final state, or {} (and a failure) when it failed.
func _run(when: String, type: String, block: Dictionary) -> Dictionary:
	var id := _id_of(when, type, block)
	if id == "":
		check(false, "no such combination: %s %s %s" % [when, type, block])
		return {}
	var got: Variant = _play(id)
	if got is String:
		check(false, "%s %s: %s" % [type, block, got])
		return {}
	return got[1]


func _id_of(when: String, type: String, block: Dictionary) -> String:
	for id: String in _cards:
		var c: Array = _cards[id]
		if c[0] == when and c[1] == type and c[2].target == block.target and c[2].do == block.do:
			return id
	return ""


func test_key_blocks_do_what_they_say() -> void:
	if not _load():
		return
	var s := _run("play", "SPELL", {"target": "chosen_enemy_minion", "do": "damage"})
	if s:
		check(_ent(s, 1, "squire").is_empty() or _ent(s, 1, "cub").is_empty(), "a spell's damage killed the enemy minion it hit")
	s = _run("play", "MINION", {"target": "my_hero", "do": "draw"})
	if s:
		eq(s.players[0].hand.size(), 1, "Battlecry: draw a card")
	s = _run("deathrattle", "MINION", {"target": "my_hero", "do": "summon"})
	if s:
		check(not _ent(s, 0, "cub").is_empty(), "Deathrattle: a Cub came")
	s = _run("aura", "MINION", {"target": "other_friendly_minions", "do": "buff"})
	if s:
		eq(int(_ent(s, 0, "squire").get("atk", 0)), 3, "the aura gives the other minions +1 Attack")
	s = _run("turn_end", "MINION", {"target": "enemy_hero", "do": "damage"})
	if s:
		eq(int(_ent(s, 1, "moon_king").get("health", 0)), 19, "at the end of the turn 1 damage to the enemy hero")
	s = _run("secret_minion_played", "SPELL", {"target": "event", "do": "destroy"})
	if s:
		eq(s.players[0].secrets.size(), 0, "the Secret went off")
		eq(s.players[1].board.size(), 2, "and destroyed the minion played")
	s = _run("play", "SPELL", {"target": "my_hero", "do": "discover"})
	if s:
		eq(s.players[0].hand.size(), 1, "the Discovered card is in the hand")
	s = _run("combo", "MINION", {"target": "my_hero", "do": "armor"})
	if s:
		eq(int(_ent(s, 0, "sun_queen").get("tags", {}).get("ARMOR", 0)), 1, "Combo: 1 Armor")
	s = _run("friendly_summon", "MINION", {"target": "event", "do": "buff"})
	if s:
		var squires: Array = s.players[0].board.map(func(e): return s.entities[str(int(e))]).filter(func(x): return x.card == "squire")
		check(squires.any(func(x): return int(x.atk) == 3), "the minion summoned got +1/+1")
	for when: String in ["play", "aura"]:
		var block := {"target": "chosen_friendly_minion" if when == "play" else "adjacent", "do": "give_keyword"}
		var id := _id_of(when, "MINION", block)
		var kw: String = _cards[id][2].keyword if id != "" else ""
		kw = NAMES.get(kw, kw)  # the snapshot has the pack's name
		s = _run(when, "MINION", block)
		if s:
			var has: bool = s.players[0].board.any(func(e):
				var x: Dictionary = s.entities[str(int(e))]
				return kw in x.get("tags", {}) or kw in x.get("aura", {}).get("tags", {}))
			check(has, "%s: a friendly minion has %s" % [when, kw])


func test_two_blocks_and_raw_lua_on_one_card() -> void:
	var fx := {"blocks": [{"when": "play", "target": "chosen_enemy_minion", "do": "damage", "n": 2},
		{"when": "combo", "target": "my_hero", "do": "draw", "n": 1},
		{"when": "deathrattle", "target": "all_enemy_minions", "do": "freeze"}]}
	eq(StudioEffects.problems(fx, "MINION"), [], "a fine card")
	var lua := StudioEffects.card_lua("a-b", "MINION", fx)
	check(lua.begins_with("cards[\"a-b\"] = {\n  target = \"enemy_minion\",\n  battlecry = function(g, me, t)\n"), lua)
	check("combo = function(g, me, t)\n    g.damage(me, t, 2)\n    g.draw(g.ctrl(me), 1)\n  end," in lua, "Combo: the play blocks, then its own: " + lua)
	eq(StudioEffects.keywords(fx, "MINION"), ["ON_PLAY", "COMBO", "ON_DEATH", "FREEZE"], "its keywords")
	eq(StudioEffects.describe(fx.blocks[0]), "Battlecry: Deal 2 damage to a chosen enemy minion.", "the English text")
	eq(StudioEffects.describe({"when": "turn_end", "target": "enemy_hero", "do": "draw", "n": 2}),
		"At the end of your turn, your opponent draws 2 card(s).", "another")
	eq(StudioEffects.describe({"when": "aura", "target": "adjacent", "do": "give_keyword", "keyword": "GUARD"}, "MINION"),
		"Adjacent minions have Taunt.", "an aura")
	eq(StudioEffects.describe({"when": "play", "target": "all_enemy_minions", "do": "damage", "n": 120}, "SPELL"),
		"Deal 99 damage to all enemy minions.", "a spell, a number clamped")
	var raw := {"blocks": fx.blocks, "lua": "target = \"any\",\nspell = function(g, me, t) g.damage(me, t, g.spell_dmg(me, 3)) end,"}
	eq(StudioEffects.card_lua("x", "SPELL", raw),
		"cards[\"x\"] = {\n  target = \"any\",\n  spell = function(g, me, t) g.damage(me, t, g.spell_dmg(me, 3)) end,\n}\n", "raw Lua wins")
	eq(StudioEffects.card_lua("x", "SPELL", {"blocks": [], "lua": ""}), "", "nothing: no Lua")
	var whole := StudioEffects.script([{"id": "x", "type": "SPELL"}, {"id": "y", "type": "MINION"}], {"x": raw})
	check(whole.begins_with("-- ") and "local cards = {}" in whole and whole.ends_with("return cards\n") and not "cards[\"y\"]" in whole, whole)


func test_problems() -> void:
	var p := func(blocks: Array, type := "MINION") -> Array:
		return StudioEffects.problems({"blocks": blocks}, type)
	check(p.call([{"when": "nope", "target": "self", "do": "damage"}])[0].contains("unknown trigger"), "an unknown trigger")
	check(not p.call([{"when": "deathrattle", "target": "self", "do": "damage"}], "SPELL").is_empty(), "a spell has no Deathrattle")
	check(not p.call([{"when": "play", "target": "chosen_any", "do": "damage"}, {"when": "play", "target": "chosen_minion", "do": "buff"}]).is_empty(),
		"two different chosen targets")
	eq(p.call([{"when": "play", "target": "chosen_minion", "do": "damage"}, {"when": "combo", "target": "chosen_minion", "do": "buff"}]), [],
		"the same chosen target twice is fine")
	check(not p.call([{"when": "turn_end", "target": "chosen_any", "do": "damage"}]).is_empty(), "a chosen target only when played")
	check(not p.call([{"when": "play", "target": "all_minions", "do": "draw"}]).is_empty(), "a player action needs whose")
	check(not p.call([{"when": "play", "target": "my_hero", "do": "buff"}]).is_empty(), "a minion action on a hero")
	check(not p.call([{"when": "play", "target": "my_hero", "do": "summon"}]).is_empty(), "summon without a card")
	check(not p.call([{"when": "play", "target": "self", "do": "give_keyword", "keyword": "FLYING"}]).is_empty(), "an unknown keyword")
	check(not p.call([{"when": "aura", "target": "other_friendly_minions", "do": "damage"}]).is_empty(), "an aura only buffs")
	check(not p.call([{"when": "play", "target": "event", "do": "damage"}]).is_empty(), "play has no event")
	check(not p.call([{"when": "play", "target": "my_hero", "do": "draw"}, {"when": "secret_attacked", "target": "my_hero", "do": "armor"}], "SPELL").is_empty(),
		"a Secret has only its trigger")
	check(not p.call([{"when": "play", "target": "enemy_hero", "do": "discover"}]).is_empty(), "Discover is for you")
	eq(StudioEffects.problems({"blocks": [{"when": "nope"}], "lua": "spell = function(g, me) end,"}, "SPELL"), [], "raw Lua: the blocks are not used")
	eq(StudioEffects.keywords({"blocks": [{"when": "secret_spell_cast", "target": "enemy_hero", "do": "damage"},
		{"when": "secret_spell_cast", "target": "my_hero", "do": "discover"}]}, "SPELL"), ["TRAP", "SPELL_SCALED", "OFFER"], "a Secret's keywords")
	var cat := StudioEffects.catalog()
	eq([cat.triggers.size() >= 13, cat.targets.size() >= 20, cat.actions.size() >= 15], [true, true, true], "the catalog")
