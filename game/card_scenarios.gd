class_name CardScenarios
extends RefCounted
## The scenario library of the debug tools (Interaction test, the walk through a pack): for any card of the
## active pack (a) generic scenarios made from what the card is — its type, the pack's keywords on it and its
## hooks in the engine (Battlecry, Deathrattle, Choose One, an aura, triggers, a Secret…) — and (b) the
## hand-written tests of data/card_tests (CardTests; the tricky interactions too). Each is a CardTests test
## with `card`, `key`, `title`, `expect` (what should happen) and, without steps, `do` (what to do).
## The tester's marks (passed / failed / a note per scenario, the checklist per card) are kept per pack in
## user://card_marks.json; export() gives them as JSON for an agent to fix the failed ones.

const DEFAULT_PATH := "user://card_marks.json"
## Tests point it at their own file.
static var path := DEFAULT_PATH
## The checklist of a card in the walk (English keys, translated).
const CHECKLIST := ["Enter", "Attack", "Death", "Sounds", "Lines", "Animations"]
## kind -> [title, what should happen] of the generic scenarios (English keys, translated; %s: a card's name).
const KINDS := {
	"play": ["Play it", "It enters with its sound, its line and, for a Legendary, its music; its Battlecry or effect happens (Echo: a copy for this turn; Twinspell: the copy in the hand)."],
	"choice": ["Play it: %s", "The chosen option's effect happens; the other's does not."],
	"power": ["Use it", "The Hero Power's effect, sound and animation."],
	"targets": ["Its targets", "Drag it: only the characters it may target glow."],
	"attack_minion": ["Attack a minion", "Its attack sound and line play; both take damage."],
	"attack_hero": ["Attack the enemy hero", "Its attack sound and line play; the hero takes damage."],
	"rush": ["Play it and attack at once", "Charge or Rush: it attacks the turn it comes."],
	"damage": ["It takes damage", "The damage shows (a Divine Shield pops instead); its effects on damage happen."],
	"death": ["It dies", "Its death sound plays; its Deathrattle happens."],
	"silence": ["It is silenced", "Its text, keywords and buffs are gone."],
	"return": ["It returns to the hand", "It goes back to its owner's hand as a fresh card."],
	"copy": ["It is copied", "Faceless Manipulator becomes a copy of it, buffs included."],
	"transform": ["It is transformed", "It turns into a Sheep; nothing of it is left."],
	"steal": ["It is stolen", "It changes sides with its buffs."],
	"freeze": ["It is frozen", "It shows as Frozen and can't attack on its next turn."],
	"doubled": ["Doubled by %s", "Its effect happens twice."],
	"adjacent": ["Next to %s, place %s", "Only a minion next to it gets the bonus."],
	"champion": ["With %s", "It gets the aura's bonus while that minion lives."],
	"own_aura": ["Its aura, a minion at place %s", "The minions it affects show the bonus; the others don't."],
	"spell_damage": ["With Spell Damage +2", "Its damage or effect grows by 2."],
	"secret_play": ["Against the enemy's Secrets (played)", "Mirror Entity and Repentance go off: revealed with their sound."],
	"secret_attack": ["Against the enemy's Secrets (attack)", "Freezing Trap or Explosive Trap goes off as it attacks."],
	"secret_spell": ["Against the enemy's Counterspell", "The spell is countered; its mana is spent."],
	"secret_trigger": ["The Secret goes off", "When its condition happens it is revealed with its sound and does its effect."],
	"quest": ["The Quest in play", "Its progress shows; play the cards it counts to complete it."],
	"trigger": ["Its triggers over two turns", "Its 'whenever' and start/end of turn effects happen at their moments."],
	"magnetic": ["Magnetic onto a Mech", "It merges into the Mech: the Mech gets its stats and keywords."],
	"combo": ["Combo", "Played after another card, its Combo effect happens."],
}
## The engine's doubling tags (a minion's aura on its owner's hero) -> what of a card they double.
const DOUBLING := {"DOUBLE_ON_PLAY": "battlecry", "DOUBLE_ON_DEATH": "deathrattle", "BOTH_CHOICES": "choose_one",
	"DOUBLE_TRAP": "secret", "DOUBLE_TURN_END": "turn_end", "DOUBLE_COMBO": "combo", "POWER_MULTIPLIER": "spell_power",
	"POWER_DOUBLE": "hero_power"}
## Helper cards of the scenes: Classic's, in every pack built on it (a scenario needing one the pack lacks is left out).
const WISP := "VAN_CS2_231"
const YETI := "VAN_CS2_182"
const MOONFIRE := "VAN_CS2_008"
const ARCANE_EXPLOSION := "VAN_CS2_025"
const NETHER := "VAN_EX1_312"  # Twisting Nether
const SIPHON := "VAN_EX1_309"  # Siphon Soul
const MASS_DISPEL := "VAN_EX1_626"
const VANISH := "VAN_NEW1_004"
const FACELESS := "VAN_EX1_564"
const POLYMORPH := "VAN_CS2_022"
const MIND_CONTROL := "VAN_CS1_113"
const FROST_NOVA := "VAN_CS2_026"
const SECRETS_ON_PLAY := ["VAN_EX1_294", "VAN_EX1_379"]  # Mirror Entity, Repentance
const SECRETS_ON_ATTACK := ["VAN_EX1_611", "VAN_EX1_610"]  # Freezing Trap, Explosive Trap
const COUNTERSPELL := "VAN_EX1_287"
const CHAMPION := "VAN_CS2_222"  # Stormwind Champion
const AXE := "VAN_CS2_106"  # Fiery War Axe

static var _pack: Pack  # the pack the caches below are for
static var _doublers := {}  # doubling engine id -> a minion with that aura
static var _adjacent := ""  # a minion with an adjacent aura
static var _mech := ""  # a plain Mech
static var _fill := ""  # the decks' card
static var _marks = null  # pack id -> card id -> {"s": {key: {"mark", "note"}}, "check": {item: mark}}


## The scenarios of a card: the hand-written ones (tests: CardTests.load_all(), given or loaded), then the generic ones.
static func for_card(id: String, tests = null) -> Array:
	var own: Array = (tests if tests is Dictionary else CardTests.load_all()).get(id, [])
	for t in own:
		if not t.has("expect"):
			t.expect = ""
	return own + generic(id)


## The generic scenarios of a card, from its type, keywords and hooks.
static func generic(id: String) -> Array:
	_cache()
	var out := []
	if not CardDb.has(id):
		return out
	var c := CardDb.card(id)
	var type: String = c.get("type", "")
	var mech: Array = c.get("mechanics", [])
	var h := Rules.hooks(id)
	var hand0 := {"side": 0, "zone": "hand", "index": 0}
	var opts: Array = h.get("choose_one", [])
	var play := {"do": "play", "card": hand0, "any": true}
	if opts.size() > 1:
		play.choice = 0  # (a Choose One card is played with an option)
	# what most cards ask for: damaged and undamaged, small and big minions to target, a weapon (Deadly Poison)
	var hurt := {"card": YETI, "damage": 1}
	var two := {"board": [hurt, WISP]}
	var me_two := {"hand": [id], "board": [hurt], "weapon": AXE} if type == "SPELL" else {"hand": [id], "board": [hurt]}
	var after: Array = [{"do": "choose", "option": 0}] if mech.has("DISCOVER") or mech.has("ADAPT") else []
	var secret: bool = h.get("secret", false) or mech.has("SECRET")
	var quest: bool = mech.has("QUEST")
	var attack := int(c.get("attack", 0)) > 0 and not mech.has("CANT_ATTACK")
	# Spell Damage counts: the keyword, or a number its text marks with $ (the cards' own mark)
	var scaled: bool = mech.has("AFFECTED_BY_SPELL_POWER") or str(c.get("text", {}).get("enUS", "") if c.get("text") is Dictionary else "").contains("$")
	match type:
		"MINION", "SPELL", "WEAPON", "HERO":
			if opts.size() > 1:
				for i in opts.size():
					_add(out, id, "choice", me_two, two, [play.merged({"choice": i}, true)] + after, str(i),
						[CardText.name(str(opts[i])) if CardDb.has(str(opts[i])) else str(i + 1)])
			else:
				_add(out, id, "play", me_two, two, [play] + after)
			if h.get("target", false):
				_add(out, id, "targets", me_two, two, [])
		"HERO_POWER":  # (a power without hooks does nothing: its scene only)
			var use: Array = [{"do": "hero_power", "any": true}] + after if h.get("hero_power", false) else []
			_add(out, id, "power", {"hero_power": id, "board": [hurt]}, two, use)
	var mine := {"side": 0, "zone": "board", "index": 0}
	var theirs := {"side": 1, "zone": "board", "index": 0}
	if type == "MINION":
		if attack:
			_add(out, id, "attack_minion", {"board": [id]}, {"board": [YETI]}, [{"do": "attack", "attacker": mine, "defender": theirs}])
			_add(out, id, "attack_hero", {"board": [id]}, {}, [{"do": "attack", "attacker": mine, "defender": {"side": 1, "zone": "hero"}}])
			if mech.has("CHARGE") or mech.has("RUSH"):
				_add(out, id, "rush", {"hand": [id]}, {"board": [YETI]}, [play, {"do": "attack", "attacker": mine, "defender": theirs}])
			_add(out, id, "secret_attack", {"board": [id]}, {"secrets": SECRETS_ON_ATTACK},
				[{"do": "attack", "attacker": mine, "defender": {"side": 1, "zone": "hero"}}])
		var spell := {"do": "play", "card": hand0}
		_add(out, id, "damage", {"hand": [ARCANE_EXPLOSION]}, {"board": [id]}, [spell])
		_add(out, id, "death", {"board": [id], "hand": [NETHER]}, {}, [spell])
		_add(out, id, "silence", {"hand": [MASS_DISPEL]}, {"board": [id]}, [spell])
		_add(out, id, "return", {"board": [id], "hand": [VANISH]}, {}, [spell])
		_add(out, id, "copy", {"board": [id], "hand": [FACELESS]}, {}, [spell.merged({"target": mine})])
		if not mech.has("ELUSIVE"):
			_add(out, id, "transform", {"board": [id], "hand": [POLYMORPH]}, {}, [spell.merged({"target": mine})])
			if not mech.has("STEALTH"):
				_add(out, id, "steal", {"hand": [MIND_CONTROL]}, {"board": [id]}, [spell.merged({"target": theirs})])
		_add(out, id, "freeze", {"hand": [FROST_NOVA]}, {"board": [id]}, [spell])
		_add(out, id, "secret_play", {"hand": [id]}, {"secrets": SECRETS_ON_PLAY}, [play] + after)
		if _adjacent != "":
			for pos in 4:
				_add(out, id, "adjacent", {"board": [WISP, _adjacent, WISP], "hand": [id]}, {}, [play.merged({"pos": pos})] + after,
					str(pos), [CardText.name(_adjacent), str(pos + 1)])
		if CardDb.has(CHAMPION):
			_add(out, id, "champion", {"board": [CHAMPION], "hand": [id]}, {}, [play] + after, "", [CardText.name(CHAMPION)])
		if h.get("aura", false):
			for pos in 4:
				_add(out, id, "own_aura", {"board": [WISP, id, WISP], "hand": [WISP]}, {"board": [WISP]},
					[{"do": "play", "card": hand0, "pos": pos}], str(pos), [str(pos + 1)])
		if mech.has("MODULAR") and _mech != "":
			_add(out, id, "magnetic", {"board": [_mech], "hand": [id]}, {}, [play.merged({"pos": 0})])
	if type == "WEAPON" and attack:
		var hero := {"side": 0, "zone": "hero"}
		_add(out, id, "attack_minion", {"weapon": id}, {"board": [YETI]}, [{"do": "attack", "attacker": hero, "defender": theirs}])
		_add(out, id, "attack_hero", {"weapon": id}, {}, [{"do": "attack", "attacker": hero, "defender": {"side": 1, "zone": "hero"}}])
	if (h.has("on") and type in ["MINION", "WEAPON"] or h.has("hand")) and not secret:
		var me := {"hand": [MOONFIRE, WISP]}
		if not h.has("on") or type not in ["MINION", "WEAPON"]:
			me.hand.append(id)  # it works from the hand
		elif type == "MINION":
			me.board = [id]
		else:
			me.weapon = id
		_add(out, id, "trigger", me, {"board": [WISP]}, [{"do": "play", "card": hand0, "any": true}, {"do": "play", "card": hand0},
			{"do": "end_turn"}, {"do": "end_turn"}])
	if type == "SPELL":
		if quest:
			_add(out, id, "quest", {"secrets": [id], "hand": [WISP, MOONFIRE]}, {}, [])
		elif secret:
			_add(out, id, "secret_trigger", {"board": [YETI], "hand": [MOONFIRE, WISP]}, {"secrets": [id], "board": [WISP]}, _trigger_steps())
		else:
			_add(out, id, "secret_spell", me_two, {"secrets": [COUNTERSPELL], "board": [hurt]}, [play] + after)
		if scaled:
			_add(out, id, "spell_damage", me_two.merged({"board": [{"card": WISP, "tags": [{Packs.pack_name("SPELLPOWER"): 2}]}, hurt]}, true), two, [play] + after)
	if h.get("combo", false) and CardDb.has(_coin()):
		_add(out, id, "combo", me_two.merged({"hand": [_coin(), id]}, true), two, [{"do": "play", "card": hand0}, play] + after)
	for eng in _doublers:
		var d: String = _doublers[eng]
		var name := [CardText.name(d)]
		match DOUBLING[eng]:
			"battlecry":
				if h.get("battlecry", false) and type == "MINION":
					_add(out, id, "doubled", {"board": [d, hurt], "hand": [id]}, two, [play] + after + after, d, name)
			"deathrattle":
				if h.get("deathrattle", false) and type == "MINION" and not mech.has("ELUSIVE"):
					_add(out, id, "doubled", {"board": [d, id], "hand": [SIPHON]}, {}, [{"do": "play", "card": hand0,
						"target": {"side": 0, "zone": "board", "index": 1}}], d, name)
			"choose_one":
				if h.has("choose_one"):
					_add(out, id, "doubled", me_two.merged({"board": [d, hurt]}, true), two, [{"do": "play", "card": hand0, "any": true}], d, name)
			"secret":
				if secret and not quest:
					_add(out, id, "doubled", {"board": [YETI], "hand": [MOONFIRE, WISP]}, {"secrets": [id], "board": [d]}, _trigger_steps(), d, name)
			"turn_end":
				if "turn_end" in h.get("on", []) and type == "MINION":
					_add(out, id, "doubled", {"board": [d, id]}, {}, [{"do": "end_turn"}], d, name)
			"combo":
				if h.get("combo", false) and CardDb.has(_coin()):
					_add(out, id, "doubled", me_two.merged({"board": [d, hurt], "hand": [_coin(), id]}, true), two, [{"do": "play", "card": hand0}, play], d, name)
			"spell_power":
				if type == "SPELL" and scaled:
					_add(out, id, "doubled", me_two.merged({"board": [d, hurt]}, true), two, [play] + after, d, name)
			"hero_power":
				if type == "HERO_POWER":
					_add(out, id, "doubled", {"board": [d, hurt], "hero_power": id}, two, [{"do": "hero_power", "any": true}], d, name)
	return out


## A spell, a minion and an attack: what sets off most Secrets of the other side.
static func _trigger_steps() -> Array:
	var hand0 := {"side": 0, "zone": "hand", "index": 0}
	return [{"do": "play", "card": hand0, "target": {"side": 1, "zone": "hero"}}, {"do": "play", "card": hand0, "pos": 1},
		{"do": "attack", "attacker": {"side": 0, "zone": "board", "index": 0}, "defender": {"side": 1, "zone": "hero"}}]


## Adds a generic scenario (unless the pack lacks a card of its scene): the card's class hero against another,
## 10 mana (more when the hand costs more), a few cards in each deck.
static func _add(out: Array, id: String, kind: String, me: Dictionary, foe: Dictionary, steps: Array, key := "", args := []) -> void:
	var scene := {"current": 0, "players": [_side(id, me, true), _side(id, foe, false)]}
	if not CardTests.scene_cards(scene).all(CardDb.has):
		return
	var words: Array = KINDS[kind]
	var title := TranslationServer.translate(words[0])
	var t := {"card": id, "kind": kind, "key": kind + (":" + key if key != "" else ""), "generic": true,
		"title": title % args if not args.is_empty() else title, "expect": TranslationServer.translate(words[1]),
		"scene": scene, "steps": steps}
	if steps.is_empty():
		t.do = t.expect
	out.append(t)


static func _side(id: String, d: Dictionary, mine: bool) -> Dictionary:
	var heroes: Array = Decks.heroes().values()
	var c := CardDb.card(id)
	var cls := str(c.get("cardClass", ""))
	if c.get("classes") is Array and not c.classes.is_empty():  # a multi-class card: its first class
		cls = str(c.classes[0])
	var own: String = Decks.heroes().get(cls, heroes[0] if not heroes.is_empty() else "")
	var hero: String = own if mine else heroes.filter(func(x): return x != own).front() if heroes.size() > 1 else own
	var out := {"hero": hero, "max_mana": 10, "mana": 10, "deck": [_fill, _fill, _fill, _fill]}
	out.merge(d, true)
	if mine:
		var cost := 0
		for x in out.get("hand", []):
			cost += int(CardDb.card(x.card if x is Dictionary else x).get("cost", 0)) if CardDb.has(x.card if x is Dictionary else x) else 0
		out.mana = maxi(10, cost)
	return out


static func _coin() -> String:
	return str(Packs.active().rules().get("start", {}).get("coin", "")) if Packs.active() else ""


## The pack's helpers: the doubling minions (a card whose script gives its owner's hero a doubling tag in its aura),
## a minion with an adjacent aura, a plain Mech, the decks' card.
static func _cache() -> void:
	var p := Packs.active()
	if p == _pack:
		return
	_pack = p
	_doublers = {}
	_adjacent = ""
	_mech = ""
	var ids := walk_ids()  # (the first of a kind by set: Baron Rivendare before Necromechanic)
	_fill = "VAN_CS2_120" if CardDb.has("VAN_CS2_120") else (WISP if CardDb.has(WISP) else "")
	var mechs: Dictionary = p.rules().get("mechanics", {}) if p else {}
	var tag_of := {}  # pack tag -> doubling engine id
	for name in mechs:
		var eng := str(mechs[name].get("engine", name)) if mechs[name] is Dictionary else str(name)
		if DOUBLING.has(eng):
			tag_of[name] = eng
	var files := {}
	var scripts := {}
	for c: Dictionary in p.cards() if p else []:
		scripts[c.id] = str(c.get("script", ""))
	for id in ids:
		var c := CardDb.card(id)
		if c.get("type") != "MINION":
			continue
		if _fill == "" and c.get("collectible", false):
			_fill = id
		var mech: Array = c.get("mechanics", [])
		if _adjacent == "" and c.get("collectible", false) and mech.has("ADJACENT_BUFF"):
			_adjacent = id
		if _mech == "" and c.get("collectible", false) and c.get("race") == "MECHANICAL" and mech.is_empty() and Rules.hooks(id).is_empty():
			_mech = id
		var s: String = scripts.get(id, "")
		if not s.contains("#") or not c.get("collectible", false):
			continue
		var f := s.get_slice("#", 0)
		if not files.has(f):
			files[f] = CardDb._script_chunks(p, f)[0]
		var text: String = files[f].get(s.get_slice("#", 1), "")
		if not text.contains("aura_add"):
			continue
		for tag in tag_of:
			if not _doublers.has(tag_of[tag]) and RegEx.create_from_string("\\b%s\\s*=" % tag).search(text):
				_doublers[tag_of[tag]] = id


## The cards of the active pack in the walk's order: by set (the pack's order), collectible first, by cost, by id.
static func walk_ids() -> Array:
	var sets: Array = Packs.active().rules().get("sets", []) if Packs.active() else []
	var key := func(id: String) -> Array:
		var c := CardDb.card(id)
		return [sets.find(c.get("set", "")), 0 if c.get("collectible", false) else 1, int(c.get("cost", 0)), id]
	var ids := CardDb.all_ids()
	ids.sort_custom(func(a, b): return key.call(a) < key.call(b))
	return ids


# --- marks ---------------------------------------------------------------------

static func _all() -> Dictionary:
	if _marks == null:
		var j := JSON.new()
		_marks = j.data if FileAccess.file_exists(path) and j.parse(FileAccess.get_file_as_string(path)) == OK and j.data is Dictionary else {}
	return _marks


## The active pack's marks: card id -> {"s": {scenario key: {"mark": "passed"|"failed"|"note", "note": text}}, "check": {item: mark}}.
static func marks() -> Dictionary:
	return _all().get_or_add(Packs.active().id() if Packs.active() else "", {})


static func card_marks(id: String) -> Dictionary:
	return marks().get(id, {"s": {}, "check": {}})


## A scenario's mark ("" clears it), kept at once.
static func set_mark(id: String, key: String, mark: String, note := "") -> void:
	var m: Dictionary = marks().get_or_add(id, {"s": {}, "check": {}})
	if mark == "":
		m.s.erase(key)
	else:
		m.s[key] = {"mark": mark, "note": note}
	_save()


## A checklist item's mark ("" clears it).
static func set_check(id: String, item: String, mark: String) -> void:
	var m: Dictionary = marks().get_or_add(id, {"s": {}, "check": {}})
	if mark == "":
		m.check.erase(item)
	else:
		m.check[item] = mark
	_save()


static func _save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_all(), " "))


## Forget the marks read (tests change the path).
static func reset() -> void:
	_marks = null


## The active pack's marks as JSON for an agent: every marked card with its name, checklist and marked scenarios
## (title, mark, note, what should happen, and the scene and steps to play it again).
static func export() -> String:
	var tests := CardTests.load_all()
	var cards := []
	var all := marks()
	var ids := all.keys()
	ids.sort()
	for id in ids:
		if not CardDb.has(id):
			continue
		var m: Dictionary = all[id]
		var by_key := {}
		for t in for_card(id, tests):
			by_key[t.key] = t
		var scen := []
		for k in m.get("s", {}):
			var t: Dictionary = by_key.get(k, {})
			scen.append({"key": k, "title": t.get("title", k), "mark": m.s[k].get("mark", ""), "note": m.s[k].get("note", ""),
				"expect": t.get("expect", ""), "scene": t.get("scene", {}), "steps": t.get("steps", [])})
		cards.append({"id": id, "name": CardText.name(id, "enUS"), "checklist": m.get("check", {}), "scenarios": scen})
	var p := Packs.active()
	return JSON.stringify({"format": "classichs-card-marks/1", "pack": p.id() if p else "", "version": p.version() if p else "",
		"cards": cards}, " ")
