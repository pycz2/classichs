class_name StudioEffects
extends RefCounted
## ClassicHS Studio: a card's effect made of building blocks, turned into the pack's Lua
## (docs/packs/api.md). An effect is {"blocks": [block, ...], "lua": ""}; a non-empty "lua" wins: it is
## the raw body of the card's hook-set table. A block is one action under one trigger:
## {"when": trigger id, "target": target id, "do": action id, "n": int, "m": int, "card": card id,
## "keyword": engine id}, only the fields its action needs (n and m default to 1).
## The labels are in English; the screen translates them with tr().

const TYPES := ["MINION", "SPELL", "WEAPON", "CHAMPION", "POWER"]
const MAX_N := 99

## Triggers. "event": the field of the trigger's event that the target "event" means (none: no such target).
const TRIGGERS := [
	{"id": "play", "label": "Battlecry / when played", "types": TYPES},
	{"id": "combo", "label": "Combo", "types": ["MINION", "SPELL", "WEAPON"]},
	{"id": "deathrattle", "label": "Deathrattle", "types": ["MINION", "WEAPON"]},
	{"id": "turn_start", "label": "At the start of your turn", "types": ["MINION", "WEAPON"]},
	{"id": "turn_end", "label": "At the end of your turn", "types": ["MINION", "WEAPON"]},
	{"id": "friendly_summon", "label": "After you summon a minion", "types": ["MINION", "WEAPON"], "event": "entity"},
	{"id": "spell_cast", "label": "After you cast a spell", "types": ["MINION", "WEAPON"]},
	{"id": "damaged", "label": "Whenever this takes damage", "types": ["MINION"]},
	{"id": "attack", "label": "Whenever this attacks", "types": ["MINION", "WEAPON"], "event": "defender"},
	{"id": "aura", "label": "Aura: while in play", "types": ["MINION"]},
	{"id": "secret_attacked", "label": "Secret: when an enemy attacks", "types": ["SPELL"], "event": "attacker"},
	{"id": "secret_minion_played", "label": "Secret: when the opponent plays a minion", "types": ["SPELL"], "event": "entity"},
	{"id": "secret_spell_cast", "label": "Secret: when the opponent casts a spell", "types": ["SPELL"]},
]

## Targets. "kind": what they are (chosen, minion, char = minions and champions, hero, weapon);
## "many": a list; "spec": the card's target spec for a chosen one; "lua": the expression.
const TARGETS := [
	{"id": "chosen_any", "label": "A chosen character", "kind": "char", "spec": "any", "types": TYPES},
	{"id": "chosen_minion", "label": "A chosen minion", "kind": "minion", "spec": "minion", "types": TYPES},
	{"id": "chosen_enemy_minion", "label": "A chosen enemy minion", "kind": "minion", "spec": "enemy_minion", "types": TYPES},
	{"id": "chosen_friendly_minion", "label": "A chosen friendly minion", "kind": "minion", "spec": "friendly_minion", "types": TYPES},
	{"id": "chosen_enemy", "label": "A chosen enemy", "kind": "char", "spec": "enemy_char", "types": TYPES},
	{"id": "chosen_friendly", "label": "A chosen friendly character", "kind": "char", "spec": "friendly_char", "types": TYPES},
	{"id": "self", "label": "This minion", "kind": "minion", "lua": "me", "types": ["MINION"]},
	{"id": "my_hero", "label": "Your hero", "kind": "hero", "lua": "g.hero(g.ctrl(me))", "player": "g.ctrl(me)", "types": TYPES},
	{"id": "enemy_hero", "label": "The enemy hero", "kind": "hero", "lua": "g.hero(g.enemy(me))", "player": "g.enemy(me)", "types": TYPES},
	{"id": "all_minions", "label": "All minions", "kind": "minion", "many": true, "lua": "g.all_minions()", "types": TYPES},
	{"id": "all_enemy_minions", "label": "All enemy minions", "kind": "minion", "many": true, "lua": "g.minions(g.enemy(me))", "types": TYPES},
	{"id": "all_friendly_minions", "label": "All friendly minions", "kind": "minion", "many": true, "lua": "g.minions(g.ctrl(me))", "types": TYPES},
	{"id": "other_friendly_minions", "label": "Your other minions", "kind": "minion", "many": true, "lua": "g.others(me)", "types": TYPES},
	{"id": "all_enemies", "label": "All enemies", "kind": "char", "many": true, "lua": "g.chars(g.enemy(me))", "types": TYPES},
	{"id": "all_characters", "label": "All characters", "kind": "char", "many": true, "lua": "g.all_chars()", "types": TYPES},
	{"id": "random_enemy_minion", "label": "A random enemy minion", "kind": "minion", "lua": "g.random_alive(g.minions(g.enemy(me)))", "types": TYPES},
	{"id": "random_enemy", "label": "A random enemy", "kind": "char", "lua": "g.random_alive(g.chars(g.enemy(me)))", "types": TYPES},
	{"id": "random_friendly_minion", "label": "A random other friendly minion", "kind": "minion", "lua": "g.random_alive(g.others(me))", "types": TYPES},
	{"id": "adjacent", "label": "Adjacent minions", "kind": "minion", "many": true, "lua": "g.adjacent(me)", "types": ["MINION"]},
	{"id": "event", "label": "The minion or character of the trigger", "kind": "char", "types": TYPES},
	{"id": "my_weapon", "label": "Your weapon", "kind": "weapon", "lua": "g.weapon(g.ctrl(me))", "types": TYPES},
	{"id": "enemy_weapon", "label": "The enemy weapon", "kind": "weapon", "lua": "g.weapon(g.enemy(me))", "types": TYPES},
]

## Actions. "fields": what the block must give; "on": the target kinds it takes ("player": my_hero or
## enemy_hero say whose); "say" / "say_foe": the sentence (for the opponent), {n} {m} {card} {keyword} {target}.
const ACTIONS := [
	{"id": "damage", "label": "Deal N damage", "fields": ["n"], "on": ["char", "minion", "hero"], "types": TYPES,
		"say": "deal {n} damage to {target}"},
	{"id": "heal", "label": "Restore N Health", "fields": ["n"], "on": ["char", "minion", "hero"], "types": TYPES,
		"say": "restore {n} Health to {target}"},
	{"id": "draw", "label": "Draw N cards", "fields": ["n"], "on": ["player"], "types": TYPES,
		"say": "draw {n} card(s)", "say_foe": "your opponent draws {n} card(s)"},
	{"id": "summon", "label": "Summon a minion N times", "fields": ["card", "n"], "on": ["player"], "types": TYPES,
		"say": "summon {n} {card}", "say_foe": "summon {n} {card} for your opponent"},
	{"id": "buff", "label": "Give +N Attack / +M Health", "fields": ["n", "m"], "on": ["minion"], "types": TYPES,
		"say": "give {target} +{n}/+{m}"},
	{"id": "set_stats", "label": "Set Attack to N and Health to M", "fields": ["n", "m"], "on": ["minion"], "types": TYPES,
		"say": "set the Attack and Health of {target} to {n}/{m}"},
	{"id": "destroy", "label": "Destroy", "fields": [], "on": ["minion", "weapon"], "types": TYPES,
		"say": "destroy {target}"},
	{"id": "freeze", "label": "Freeze", "fields": [], "on": ["char", "minion", "hero"], "types": TYPES,
		"say": "freeze {target}"},
	{"id": "silence", "label": "Silence", "fields": [], "on": ["minion"], "types": TYPES,
		"say": "silence {target}"},
	{"id": "transform", "label": "Transform into a minion", "fields": ["card"], "on": ["minion"], "types": TYPES,
		"say": "transform {target} into {card}"},
	{"id": "give_keyword", "label": "Give a keyword", "fields": ["keyword"], "on": ["minion"], "types": TYPES,
		"say": "give {target} {keyword}"},
	{"id": "return_to_hand", "label": "Return to its owner's hand", "fields": [], "on": ["minion"], "types": TYPES,
		"say": "return {target} to its owner's hand"},
	{"id": "armor", "label": "Gain N Armor", "fields": ["n"], "on": ["player"], "types": TYPES,
		"say": "gain {n} Armor", "say_foe": "your opponent gains {n} Armor"},
	{"id": "gain_mana", "label": "Gain N Mana Crystals", "fields": ["n"], "on": ["player"], "types": TYPES,
		"say": "gain {n} Mana Crystal(s)", "say_foe": "your opponent gains {n} Mana Crystal(s)"},
	{"id": "add_mana", "label": "Gain N Mana this turn", "fields": ["n"], "on": ["player"], "types": TYPES,
		"say": "gain {n} Mana this turn only", "say_foe": "your opponent gains {n} Mana this turn only"},
	{"id": "add_card", "label": "Add a card to the hand N times", "fields": ["card", "n"], "on": ["player"], "types": TYPES,
		"say": "add {n} {card} to your hand", "say_foe": "add {n} {card} to your opponent's hand"},
	{"id": "shuffle_card", "label": "Shuffle a card into the deck N times", "fields": ["card", "n"], "on": ["player"], "types": TYPES,
		"say": "shuffle {n} {card} into your deck", "say_foe": "shuffle {n} {card} into your opponent's deck"},
	{"id": "discover", "label": "Discover a card", "fields": [], "on": ["player"], "mine_only": true, "types": TYPES,
		"say": "discover a card"},
	{"id": "equip", "label": "Equip a weapon", "fields": ["card"], "on": ["player"], "types": TYPES,
		"say": "equip {card}", "say_foe": "your opponent equips {card}"},
]

## Keywords an action can give (engine ids, docs/packs/format.md §4), with Hearthstone's names.
const KEYWORDS := [
	{"id": "GUARD", "label": "Taunt"},
	{"id": "HASTE", "label": "Charge"},
	{"id": "QUICK", "label": "Rush"},
	{"id": "BARRIER", "label": "Divine Shield"},
	{"id": "DOUBLE_ATTACK", "label": "Windfury"},
	{"id": "STEALTH", "label": "Stealth"},
	{"id": "SPELLPROOF", "label": "Elusive"},
	{"id": "IMMUNE", "label": "Immune"},
	{"id": "POISON", "label": "Poisonous"},
	{"id": "LIFESTEAL", "label": "Lifesteal"},
	{"id": "CANT_ATTACK", "label": "Can't attack"},
]

## The play hook of each card type.
const PLAY_HOOK := {"MINION": "battlecry", "WEAPON": "battlecry", "CHAMPION": "battlecry", "SPELL": "spell", "POWER": "hero_power"}
## The `on` hook of a trigger and the condition that makes it this card's.
const ON := {
	"turn_start": ["turn_start", "ev.player == g.ctrl(me)"],
	"turn_end": ["turn_end", "ev.player == g.ctrl(me)"],
	"friendly_summon": ["after_summon", "g.mine(me, ev) and ev.entity ~= me"],
	"spell_cast": ["after_spell", "g.mine(me, ev)"],
	"damaged": ["damage", "ev.target == me"],
	"attack": ["attack", "ev.attacker == me"],
}
## A Secret's event and condition ("" = any such event of the opponent's turn).
const SECRET := {
	"secret_attacked": ["attack", ""],
	"secret_minion_played": ["after_summon", "ev.played and not g.mine(me, ev)"],
	"secret_spell_cast": ["play", "ev.kind == \"spell\" and not g.mine(me, ev)"],
}
## Offers three different random collectible cards; the chosen one goes into the hand (on_choose).
const DISCOVER_LUA := """local function discover(g, me)
  local pool = {}
  for _, c in ipairs(g.collectible()) do
    local kind = g.info(c).type
    if kind ~= "CHAMPION" and kind ~= "POWER" then
      pool[#pool + 1] = c
    end
  end
  g.shuffle(pool)
  local opts = {}
  for i = 1, 3 do
    if pool[i] then
      opts[#opts + 1] = g.create(g.ctrl(me), pool[i])
    end
  end
  if #opts > 0 then
    g.request_choice(me, opts)
  end
end
"""


## Everything the screen lists: {triggers, targets, actions, keywords}.
static func catalog() -> Dictionary:
	return {"triggers": TRIGGERS, "targets": TARGETS, "actions": ACTIONS, "keywords": KEYWORDS}


static func _find(list: Array, id: Variant) -> Dictionary:
	for it: Dictionary in list:
		if it.id == id:
			return it
	return {}


static func _blocks(effect: Dictionary) -> Array:
	var b: Variant = effect.get("blocks", [])
	return b if b is Array else []


static func _lua(effect: Dictionary) -> String:
	return str(effect.get("lua", "")).strip_edges()


static func _num(block: Dictionary, key: String) -> int:
	return clampi(int(block.get(key, 1)), 0, MAX_N)


static func _is_chosen(target_id: Variant) -> bool:
	return str(target_id).begins_with("chosen_")


## What is wrong with an effect for a card of this type, in English; empty: fine. Raw Lua is not
## checked here (the pack check compiles it).
static func problems(effect: Dictionary, card_type: String) -> Array:
	var out := []
	if not TYPES.has(card_type):
		return ["unknown card type '%s'" % card_type]
	if _lua(effect) != "":
		return out
	var blocks := _blocks(effect)
	var chosen := ""
	var secret := ""
	for i in blocks.size():
		var b: Variant = blocks[i]
		var at := "block %d" % (i + 1)
		if not b is Dictionary:
			out.append(at + ": not a block")
			continue
		var w := _find(TRIGGERS, b.get("when"))
		var t := _find(TARGETS, b.get("target"))
		var a := _find(ACTIONS, b.get("do"))
		if w.is_empty():
			out.append("%s: unknown trigger '%s'" % [at, b.get("when")])
		if t.is_empty():
			out.append("%s: unknown target '%s'" % [at, b.get("target")])
		if a.is_empty():
			out.append("%s: unknown action '%s'" % [at, b.get("do")])
		if w.is_empty() or t.is_empty() or a.is_empty():
			continue
		if not w.types.has(card_type):
			out.append("%s: '%s' does not fit a %s card" % [at, w.label, card_type])
		if not t.types.has(card_type):
			out.append("%s: '%s' does not fit a %s card" % [at, t.label, card_type])
		if not a.types.has(card_type):
			out.append("%s: '%s' does not fit a %s card" % [at, a.label, card_type])
		if SECRET.has(w.id):
			if secret != "" and secret != w.id:
				out.append("%s: a Secret has one trigger" % at)
			secret = w.id
		if _is_chosen(t.id):
			if not ["play", "combo"].has(w.id):
				out.append("%s: a chosen target works only when played or with Combo" % at)
			elif chosen != "" and chosen != t.id:
				out.append("%s: two different chosen targets on one card" % at)
			else:
				chosen = t.id
		if t.id == "event" and not w.has("event"):
			out.append("%s: '%s' has no minion or character of its own" % [at, w.label])
		var kind: String = t.kind
		if t.id == "event" and w.get("event") == "entity":
			kind = "minion"
		if a.on.has("player"):
			if not ["my_hero", "enemy_hero"].has(t.id):
				out.append("%s: '%s' needs whose: your hero or the enemy hero" % [at, a.label])
			elif a.get("mine_only", false) and t.id != "my_hero":
				out.append("%s: '%s' is only for you" % [at, a.label])
		elif not a.on.has(kind):
			out.append("%s: '%s' does not work on '%s'" % [at, a.label, t.label])
		if w.id == "aura":
			if not ["buff", "give_keyword"].has(a.id):
				out.append("%s: an aura can only give +Attack/+Health or a keyword" % at)
			if not t.get("many", false) and t.id != "self":
				out.append("%s: an aura works on a fixed group of minions" % at)
		if a.fields.has("card") and not (b.get("card") is String and _ID.search(b.card) != null):
			out.append("%s: '%s' needs a card" % [at, a.label])
		if a.fields.has("keyword") and _find(KEYWORDS, b.get("keyword")).is_empty():
			out.append("%s: '%s' needs a keyword" % [at, a.label])
	if secret != "" and blocks.any(func(b): return b is Dictionary and not SECRET.has(b.get("when"))):
		out.append("a Secret has only blocks of its Secret trigger")
	return out


static var _ID := RegEx.create_from_string("^[A-Za-z0-9_][A-Za-z0-9_.-]*$")


## A Lua string literal.
static func _q(s: String) -> String:
	return "\"%s\"" % s.c_escape()


## The Lua lines of one block (its trigger's hook adds the indentation).
static func _lines(b: Dictionary, card_type: String) -> Array:
	var a: String = b.get("do")
	var t := _find(TARGETS, b.get("target"))
	var w: String = b.get("when")
	var n := _num(b, "n")
	var m := _num(b, "m")
	var card := _q(str(b.get("card", "")))
	var player: String = t.get("player", "g.ctrl(me)")
	var times := func(line: String) -> Array:
		return [line] if n == 1 else ["for _ = 1, %d do %s end" % [n, line]]
	match a:
		"draw":
			return ["g.draw(%s, %d)" % [player, n]]
		"armor":
			return ["g.gain_armor(%s, %d)" % [player, n]]
		"gain_mana":
			return ["g.gain_mana(%s, %d)" % [player, n]]
		"add_mana":
			return ["g.add_mana(%s, %d)" % [player, n]]
		"equip":
			return ["g.equip(%s, %s)" % [player, card]]
		"discover":
			return ["discover(g, me)"]
		"add_card":
			return times.call("g.add_to_hand(%s, %s)" % [player, card])
		"shuffle_card":
			return times.call("g.add_to_deck(%s, %s)" % [player, card])
		"summon":
			if card_type == "MINION" and t.id == "my_hero" and w == "deathrattle":
				return times.call("g.summon(g.ctrl(me), %s, g.died_pos(me))" % card)
			if card_type == "MINION" and t.id == "my_hero" and w != "aura":
				return times.call("g.summon_right(me, %s)" % card)
			return times.call("g.summon(%s, %s)" % [player, card])
	var x := "x" if t.get("many", false) else _target_lua(t, w)
	var line := ""
	match a:
		"damage":
			var amt := str(n)
			if card_type == "SPELL":
				amt = "g.spell_dmg(me, %d)" % n
			elif card_type == "POWER":
				amt = "g.hp_dmg(me, %d)" % n
			line = "g.damage(me, %s, %s)" % [x, amt]
		"heal":
			line = "g.heal(me, %s, %s)" % [x, ("g.heal_amt(me, %d)" % n) if card_type in ["SPELL", "POWER"] else str(n)]
		"buff":
			line = ("g.aura_add(%s, %d, %d)" if w == "aura" else "g.buff(%s, %d, %d)") % [x, n, m]
		"set_stats":
			line = "g.set_stats(%s, %d, %d)" % [x, n, m]
		"destroy":
			line = "g.destroy(%s)" % x
		"freeze":
			line = "g.freeze(%s)" % x
		"silence":
			line = "g.silence(%s)" % x
		"transform":
			line = "g.transform(%s, %s)" % [x, card]
		"give_keyword":
			var kw := str(b.get("keyword", ""))
			line = ("g.aura_add(%s, 0, 0, { %s = true })" if w == "aura" else "g.give_tag(%s, %s)") % [x, kw if w == "aura" else _q(kw)]
		"return_to_hand":
			line = "g.return_to_hand(%s)" % x
	if t.get("many", false):
		return ["for _, x in ipairs(%s) do %s end" % [t.lua, line]]
	return [line]


static func _target_lua(t: Dictionary, when: String) -> String:
	if _is_chosen(t.id):
		return "t"
	if t.id == "event":
		return "ev." + str(_find(TRIGGERS, when).get("event", "entity"))
	return t.lua


## One hook: `name = function(args) ... end,` with its lines, at the given indent.
static func _hook(name: String, args: String, lines: Array, pad := "  ") -> String:
	var s := "%s%s = function(%s)\n" % [pad, name, args]
	for l: String in lines:
		s += "%s  %s\n" % [pad, l]
	return s + pad + "end,\n"


## The Lua chunk `cards["<id>"] = { ... }` of one card; "" when the effect has no blocks and no Lua.
static func card_lua(card_id: String, card_type: String, effect: Dictionary) -> String:
	var lua := _lua(effect)
	if lua != "":
		var body := ""
		for l in lua.split("\n"):
			body += ("  " + l if l.strip_edges() != "" else "") + "\n"
		return "cards[%s] = {\n%s}\n" % [_q(card_id), body]
	var blocks := _blocks(effect).filter(func(b): return b is Dictionary)
	if blocks.is_empty():
		return ""
	var of := func(w: String) -> Array:
		var out := []
		for b: Dictionary in blocks:
			if b.get("when") == w:
				out.append_array(_lines(b, card_type))
		return out
	var s := ""
	var play_spec := ""
	var combo_spec := ""
	for b: Dictionary in blocks:
		var t := _find(TARGETS, b.get("target"))
		if _is_chosen(t.get("id")):
			if b.get("when") == "play":
				play_spec = t.spec
			elif b.get("when") == "combo":
				combo_spec = t.spec
	if play_spec != "":
		s += "  target = %s,\n" % _q(play_spec)
	elif combo_spec != "":
		s += "  combo_target = %s,\n" % _q(combo_spec)
	var play: Array = of.call("play")
	var combo: Array = of.call("combo")
	if not play.is_empty():
		s += _hook(PLAY_HOOK.get(card_type, "battlecry"), "g, me, t", play)
	if not combo.is_empty():
		s += _hook("combo", "g, me, t", play + combo)
	var dr: Array = of.call("deathrattle")
	if not dr.is_empty():
		s += _hook("deathrattle", "g, me", dr)
	var on := ""
	for w: String in ON:
		var lines: Array = of.call(w)
		if lines.is_empty():
			continue
		var cond: String = ON[w][1]
		if w == "attack" and card_type == "WEAPON":
			cond = "ev.attacker == g.hero(g.ctrl(me))"
		on += _hook(ON[w][0], "g, me, ev", ["if %s then" % cond] + lines.map(func(l): return "  " + l) + ["end"], "    ")
	if on != "":
		s += "  on = {\n%s  },\n" % on
	var aura: Array = of.call("aura")
	if not aura.is_empty():
		s += _hook("aura", "g, me", aura)
	for w: String in SECRET:
		var lines: Array = of.call(w)
		if lines.is_empty():
			continue
		s += "  secret = {\n    event = %s,\n" % _q(SECRET[w][0])
		if SECRET[w][1] != "":
			s += "    cond = function(g, me, ev) return %s end,\n" % SECRET[w][1]
		s += _hook("effect", "g, me, ev", lines, "    ") + "  },\n"
		break
	if blocks.any(func(b): return b.get("do") == "discover"):
		s += "  on_choose = function(g, me, option) g.add_to_hand(g.ctrl(me), g.card(option)) end,\n"
	return "cards[%s] = {\n%s}\n" % [_q(card_id), s]


## The whole scripts/studio.lua: every card of cards (the cards.json array) whose effect (effects: card
## id -> effect) makes Lua. Each such card points at `scripts/studio.lua#<id>`.
static func script(cards: Array, effects: Dictionary) -> String:
	var s := "-- Made by ClassicHS Studio from the cards' effect blocks.\nlocal cards = {}\n\n" + DISCOVER_LUA + "\n"
	for c: Variant in cards:
		if not c is Dictionary or not effects.get(c.get("id")) is Dictionary:
			continue
		var chunk := card_lua(str(c.id), str(c.get("type", "MINION")), effects[c.id])
		if chunk != "":
			s += chunk + "\n"
	return s + "return cards\n"


## The engine ids of the mechanics the card should carry for its blocks (the project maps them to the
## pack's names): ON_PLAY, ON_DEATH, COMBO, TRAP, AURA, TRIGGER, FREEZE, SILENCE, OFFER, SPELL_SCALED.
static func keywords(effect: Dictionary, card_type: String) -> Array:
	var out := []
	var add := func(k: String) -> void:
		if not out.has(k):
			out.append(k)
	for b: Variant in _blocks(effect):
		if not b is Dictionary:
			continue
		var w := str(b.get("when"))
		if w == "play" and card_type in ["MINION", "WEAPON", "CHAMPION"]:
			add.call("ON_PLAY")
		elif w == "deathrattle":
			add.call("ON_DEATH")
		elif w == "combo":
			add.call("COMBO")
		elif w == "aura":
			add.call("AURA")
		elif SECRET.has(w):
			add.call("TRAP")
		elif ON.has(w):
			add.call("TRIGGER")
		match str(b.get("do")):
			"freeze":
				add.call("FREEZE")
			"silence":
				add.call("SILENCE")
			"discover":
				add.call("OFFER")
			"damage":
				if card_type == "SPELL":
					add.call("SPELL_SCALED")
	return out


const _SAY_WHEN := {
	"play": "Battlecry: ", "combo": "Combo: ", "deathrattle": "Deathrattle: ",
	"turn_start": "At the start of your turn, ", "turn_end": "At the end of your turn, ",
	"friendly_summon": "After you summon a minion, ", "spell_cast": "After you cast a spell, ",
	"damaged": "Whenever this takes damage, ", "attack": "Whenever this attacks, ", "aura": "",
	"secret_attacked": "Secret: When an enemy attacks, ", "secret_minion_played": "Secret: When your opponent plays a minion, ",
	"secret_spell_cast": "Secret: When your opponent casts a spell, ",
}


## A short English sentence for a block, as the card's text could say it ("Battlecry: Deal 2 damage to a
## chosen enemy minion."). A spell's or a power's play block has no "Battlecry:".
static func describe(block: Dictionary, card_type := "MINION") -> String:
	var w := _find(TRIGGERS, block.get("when"))
	var t := _find(TARGETS, block.get("target"))
	var a := _find(ACTIONS, block.get("do"))
	if w.is_empty() or t.is_empty() or a.is_empty():
		return ""
	var say: String = a.say
	if t.id == "enemy_hero" and a.has("say_foe"):
		say = a.say_foe
	var kw := _find(KEYWORDS, block.get("keyword"))
	var target: String = t.label
	if w.id == "aura":
		say = "{target} have +{n}/+{m}" if a.id == "buff" else "{target} have {keyword}"
	else:
		target = target.left(1).to_lower() + target.substr(1)
	var text := say.format({"n": _num(block, "n"), "m": _num(block, "m"), "card": str(block.get("card", "")),
		"keyword": kw.get("label", ""), "target": target})
	var head: String = _SAY_WHEN.get(w.id, "")
	if w.id == "play" and not card_type in ["MINION", "WEAPON", "CHAMPION"]:
		head = ""
	if head == "" or head.ends_with(": "):
		text = text.left(1).to_upper() + text.substr(1)
	return head + text + "."
