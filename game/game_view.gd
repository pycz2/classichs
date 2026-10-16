class_name GameView
extends RefCounted
## The game as the table draws it, built from the engine's snapshots (Rules
## `snapshot`, or a server's `state.view`) with the names the screens read.
## Entities keep their objects across updates (views hold them): update()
## changes them in place. A player's view hides the opponent's hand and Secrets
## (card "") and every deck.

const COIN := "GAME_005"

var turn := 0
var current := 0
var phase := "MULLIGAN"
## {} or {player, source, options, zones}: an open card choice (Tracking).
var pending := {}
var game_over := false
var winner := -1
var players: Array[Seat] = []
## The deck lists the match started with (the deck tracker); a server game knows only its own.
var start_decks: Array = [[], []]
## [{turn, player, action, events}], entry 0 is the start (the Match keeps it).
var history: Array = []
## -1: everything is known; 0/1: the view of that player.
var view := -1
var snapshot := {}
var _ents := {}


func _init() -> void:
	players.assign([Seat.new(0), Seat.new(1)])


## One card in the match, as the engine last showed it.
class Ent:
	extends RefCounted
	var id := 0
	var card_id := ""  # "" = hidden from this view
	var controller := 0
	var zone := "SETASIDE"
	var play_order := 0
	var damage := 0
	var tags := {}
	var enchantments := []
	var eot_tags := []
	var aura := {"atk": 0, "hp": 0, "tags": {}, "src": {}}
	var silenced := false
	var _atk := 0
	var _max_health := 0
	var _cost := 0

	func card() -> Dictionary:
		return CardDb.card(card_id)

	func type() -> String:
		return card().get("type", "")

	func is_minion() -> bool:
		return type() == "MINION"

	func is_hero() -> bool:
		return type() == "HERO"

	func is_weapon() -> bool:
		return type() == "WEAPON"

	func race() -> String:
		return card().get("race", "")

	## A hero's includes its weapon on its own turn (the engine's hero_atk).
	func atk() -> int:
		return _atk

	func max_health() -> int:
		return _max_health

	func health() -> int:
		return _max_health - damage

	func has(tag: String) -> bool:
		return bool(tags.get(tag, false)) or bool(aura.get("tags", {}).get(tag, false))

	func spellpower() -> int:
		return int(tags.get("SPELLPOWER", 0)) + int(aura.get("tags", {}).get("SPELLPOWER", 0))

	func copy() -> Ent:
		var e := Ent.new()
		e.set_from(id, {})
		for k in ["card_id", "controller", "zone", "play_order", "damage", "silenced", "_atk", "_max_health", "_cost"]:
			e.set(k, get(k))
		e.tags = tags.duplicate(true)
		e.enchantments = enchantments.duplicate(true)
		e.eot_tags = eot_tags.duplicate()
		e.aura = aura.duplicate(true)
		return e

	func set_from(p_id: int, d: Dictionary) -> void:
		id = p_id
		card_id = str(d.get("card", ""))
		controller = int(d.get("ctrl", 0))
		zone = str(d.get("zone", "SETASIDE"))
		play_order = int(d.get("order", 0))
		damage = int(d.get("dmg", 0))
		tags = d.get("tags", {})
		enchantments = d.get("ench", [])
		eot_tags = d.get("eot", [])
		silenced = bool(d.get("sil", false))
		aura = d.get("aura", {"atk": 0, "hp": 0, "tags": {}, "src": {}})
		var names := Packs.renames()  # a pack's own mechanic names (and its trap zone) in the client's words
		if not names.is_empty():
			zone = names.get(zone, zone)
			tags = GameView.renamed(tags, names)
			eot_tags = eot_tags.map(func(t): return names.get(t, t))
			if aura.get("tags") is Dictionary:
				aura.tags = GameView.renamed(aura.tags, names)
		_atk = int(d.get("atk", 0))
		_max_health = int(d.get("max_health", 0))
		_cost = int(d.get("cost", card().get("cost", 0)))


static func renamed(d: Dictionary, names: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[names.get(k, k)] = d[k]
	return out


## One side of the match.
class Seat:
	extends RefCounted
	var index := 0
	var hero: Ent
	var hero_power: Ent
	var weapon: Ent = null
	var hand: Array = []
	## Known deck cards (the top card last): all in a full view, none in a player's view
	## (but the own deck of a server game, from its list, in no order).
	var deck: Array = []
	var deck_count := 0
	var board: Array = []
	var secrets: Array = []
	var mana := 0
	var max_mana := 0
	var overload_owed := 0
	var overload_locked := 0
	var fatigue := 0
	var cards_played_this_turn := 0
	var minions_played_this_turn := 0
	var cost_mods: Array = []
	var mulliganed := false
	var mulligan_replace: Array = []
	var spell_damage := 0

	func _init(i: int) -> void:
		index = i


## Takes a snapshot (the engine's `snapshot` state).
func update(s: Dictionary) -> void:
	snapshot = s
	view = int(s.get("view", -1))
	turn = int(s.get("turn", 0))
	current = int(s.get("current", 0))
	phase = str(s.get("phase", "PLAY"))
	pending = s.get("pending", {})
	game_over = bool(s.get("game_over", false))
	winner = int(s.get("winner", -1))
	if s.has("start_decks"):
		start_decks = s.start_decks
	var seen := {}
	for k in s.get("entities", {}):
		var id := int(k)
		var e: Ent = _ents.get(id)
		if e == null:
			e = Ent.new()
			_ents[id] = e
		e.set_from(id, s.entities[k])
		seen[id] = true
	for id in _ents.keys():
		if not seen.has(id):
			_ents.erase(id)  # back into a deck the view does not show
	for i in 2:
		var d: Dictionary = s.players[i]
		var p := players[i]
		p.hero = ent(int(d.hero))
		p.hero_power = ent(int(d.power))
		p.weapon = ent(int(d.get("weapon", -1)))
		p.hand = _list(d.hand)
		p.deck = _list(d.get("deck", []))
		p.deck_count = int(d.get("deck_count", p.deck.size()))
		p.board = _list(d.board)
		p.secrets = _list(d.secrets)
		p.mana = int(d.mana)
		p.max_mana = int(d.max_mana)
		p.overload_owed = int(d.get("ol_owed", 0))
		p.overload_locked = int(d.get("ol_locked", 0))
		p.fatigue = int(d.get("fatigue", 0))
		p.cards_played_this_turn = int(d.get("played", 0))
		p.minions_played_this_turn = int(d.get("minions_played", 0))
		p.cost_mods = d.get("cost_mods", [])
		p.mulliganed = bool(d.get("mulliganed", false))
		p.mulligan_replace = d.get("mulligan_replace", [])
		p.spell_damage = int(d.get("spell_damage", 0))
	if view >= 0 and p_deck_unknown(view):
		players[view].deck = _own_deck(view)


func p_deck_unknown(p: int) -> bool:
	return players[p].deck.is_empty() and players[p].deck_count > 0 and start_decks[p].size() == 30


## The own deck in a player's view: the engine numbers deck cards in list order
## before the shuffle (heroes and powers 1-4, then 30 + 30), so a hidden id of the
## own range is a card still in the deck.
## ponytail: relies on that numbering (rust/engine README "Known leak"); a server that remaps ids breaks the tracker only.
func _own_deck(p: int) -> Array:
	var out := []
	var cards: Array = start_decks[p]
	for k in cards.size():
		if not _ents.has(5 + 30 * p + k):
			var e := Ent.new()
			e.set_from(5 + 30 * p + k, {"card": cards[k], "ctrl": p, "zone": "DECK"})
			out.append(e)
	return out


func _list(ids: Array) -> Array:
	var out := []
	for id in ids:
		var e := ent(int(id))
		if e:
			out.append(e)
	return out


func ent(id: int) -> Ent:
	return _ents.get(id)


func hero(p: int) -> Ent:
	return players[p].hero


func opponent(p: int) -> int:
	return 1 - p


## The cost now, with every modifier (a card the view hides: its printed cost, 0).
func cost(e: Ent) -> int:
	return e._cost if e else 0


func hero_atk(e: Ent) -> int:
	return e._atk if e else 0


func minions(p: int) -> Array:
	return players[p].board


func all_minions() -> Array:
	return players[0].board + players[1].board
