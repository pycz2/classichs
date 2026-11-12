extends RefCounted
## The match screen (Kobolds & Catacombs, every card up to it): the mulligan (3 and 4 cards, its timer), a
## full table (10 cards in hand, 7 minions a side with long names, buffs and keyword marks, secrets, weapons),
## a hovered hand card and minion with their keyword boxes, a quest, a Death Knight hero card, the choice
## windows (Discover, Adapt, Choose One, Kazakus), a Joust, the history, the deck tracker, the rope, emotes,
## the game menu, the settings over the table, the concede question, a hint, aiming, the result screens.

const SHAMAN := "HERO_02"
const MAGE := "HERO_08"
const WARRIOR := "HERO_01"
const ROGUE := "HERO_03"
const WARLOCK := "HERO_07"
const DRUID := "HERO_06"
const PALADIN := "HERO_04"
const DECK := ["VAN_CS2_120", "OG_200", "OG_218", "OG_310", "OG_109", "OG_096", "OG_085", "BRM_008", "OG_221",
	"LOE_116", "OG_308", "GVG_101", "UNG_047", "CFM_646", "UNG_202"]
## Ten cards with long names and long Russian texts (a Spellstone and a Death Knight among them).
const HAND := ["ICC_912", "UNG_843", "LOE_053", "AT_048", "LOE_110", "OG_282", "LOOT_101", "LOOT_216", "LOOT_103", "ICC_834"]
const BUFF := {"atk": 4, "hp": 4, "src": "VAN_CS2_092"}  # Blessing of Kings
const FULL := {"current": 0, "turn": 12, "seed": 5, "players": [
	{"hero": SHAMAN, "mana": 10, "max_mana": 10, "damage": 7, "armor": 12, "weapon": {"card": "LOOT_542", "enchantments": [{"atk": 3, "src": "VAN_CS2_074"}]},
		"secrets": ["VAN_EX1_289", "AT_002", "VAN_EX1_130"], "hand": HAND, "deck": DECK,
		"board": [{"card": "LOOT_358", "tags": ["TAUNT", "DIVINE_SHIELD"], "enchantments": [BUFF]},
			{"card": "OG_200", "tags": ["POISONOUS", "LIFESTEAL"], "damage": 2},
			{"card": "OG_218", "tags": ["WINDFURY", "STEALTH"]},
			{"card": "OG_310", "tags": ["FROZEN"], "enchantments": [{"atk": 12, "hp": 12, "src": "VAN_CS2_092"}]},
			{"card": "VAN_CS2_197", "tags": ["DIVINE_SHIELD"]},
			{"card": "OG_085", "tags": ["TAUNT", "POISONOUS", "LIFESTEAL", "WINDFURY"]},
			{"card": "ICC_912", "silenced": true}]},
	{"hero": MAGE, "mana": 3, "max_mana": 10, "damage": 18, "armor": 3, "weapon": "VAN_CS2_106",
		"secrets": ["VAN_EX1_289", "AT_002"], "hand": HAND, "deck": DECK,
		"board": [{"card": "BRM_008", "tags": ["STEALTH"]}, {"card": "OG_221", "tags": ["DIVINE_SHIELD"]},
			{"card": "LOE_116", "enchantments": [BUFF]}, {"card": "OG_308", "damage": 5},
			{"card": "GVG_101", "tags": ["FROZEN", "TAUNT"]}, "UNG_047", {"card": "CFM_646", "tags": ["TAUNT"]}]}]}

var a
var m: Node


func run(a_) -> void:
	a = a_
	m = await a.open_game()
	await _mulligan()
	await _full_table()
	await _history()
	await _quest_and_secrets()
	await _hero_card()
	await _choices()
	await _results()
	m.show_game_menu()
	await a.settle(0.3)


func _start(scene: Dictionary, bots := [false, false]) -> MatchView:
	m.show_game_menu()
	await a.settle(0.2)
	var v: MatchView = m.start_match({"scenario": scene}, bots, false)
	if v == null:
		a.error("the scene does not start")
		return null
	await a.settle(0.8)
	v.set_process(false)  # no hover from wherever the real mouse is (MatchView._track_hand_hover reads it)
	return v


func _do(v: MatchView, steps: Array, settle := true) -> bool:
	for s in steps:
		var act := CardTests.action(v.controller, s)
		var res: Dictionary = act if act.has("error") else v.controller.submit(act)
		if act.has("error") or not res.get("ok", false):
			a.error("step %s: %s" % [s, res.get("error", act.get("error", "?"))])
			return false
		if settle:
			await a.settle(0.4)
	return true


func _ref(side: int, zone: String, index := 0) -> Dictionary:
	return {"side": side, "zone": zone, "index": index}


## A hand card risen as under the mouse (what MatchView._track_hand_hover does; the real mouse stays out).
func _hover_hand(v: MatchView, i: int) -> void:
	var hand: Array = v.g.players[v.viewer()].hand
	v._hover_hand = hand[i].id
	v.refresh()
	var f: Dictionary = TableLayout.hand(hand.size(), true, i)[i]
	v._show_tips(hand[i].card_id, Rect2(f.pos, CardView.SIZE * f.scale))
	await a.wait(0.7)


func _unhover_hand(v: MatchView) -> void:
	v._hover_hand = -1
	v.refresh()
	v._show_tips("", Rect2())
	await a.wait(0.4)


## Runs the turn timer a moment by hand (the view's _process is off in the shots).
func _tick(v: MatchView, left: float) -> void:
	v.timer_enabled = true
	v.tick(0.01)
	v._time_left = left
	v.tick(0.01)


func _mulligan() -> void:
	var ts: Array = Decks.templates()
	var d0: Deck = ts[0].deck
	var d1: Deck = ts[min(5, ts.size() - 1)].deck
	m.show_game_menu()
	await a.settle(0.2)
	var v: MatchView = m.start_match({"decks": [{"hero": d0.hero, "cards": Array(d0.cards)},
		{"hero": d1.hero, "cards": Array(d1.cards)}], "seed": 11}, [false, false], false)
	v.set_process(false)
	await a.settle(2.0)
	await a.shot("mulligan_first", "The mulligan of the first player (3 cards)")
	var row := v._overlay.find_children("*", "CardView", true, false) if v._overlay else []
	if row.size() > 1:
		row[1].marked = true
		row[1].queue_redraw()
	_tick(v, 7.5)
	await a.wait(0.5)
	await a.shot("mulligan_timer", "The mulligan: a card marked to replace, the last seconds counting down")
	v.timer_enabled = false
	(v.find_child("MulliganTimer", true, false) as Label).visible = false
	_confirm(v)
	await a.settle(3.0)
	await a.shot("mulligan_second", "The mulligan of the second player (4 cards, the Coin comes after)")
	_confirm(v)
	await a.settle(3.0)
	await a.shot("first_turn", "The first turn after the mulligan")


## The mulligan's Confirm, as a click does (the hot-seat's next player gets their own cards).
func _confirm(v: MatchView) -> void:
	var b := v._overlay.find_child("Confirm", true, false) as Button if v._overlay else null
	if b:
		b.pressed.emit()
	else:
		a.error("no mulligan Confirm")


func _full_table() -> void:
	var v := await _start(FULL)
	if v == null:
		return
	await a.shot("board_full", "A full table: 10 cards in hand, 7 minions a side with long names, buffs, keyword marks, secrets, weapons, armor")
	await _hover_hand(v, 0)
	await a.shot("hand_hover_first", "The first hand card (long Russian text) risen under the mouse, with its keyword boxes")
	await _hover_hand(v, 9)
	await a.shot("hand_hover_last", "The last hand card (a Death Knight hero card) risen under the mouse")
	await _hover_hand(v, 8)
	await a.shot("hand_hover_spellstone", "A Spellstone in hand risen under the mouse")
	await _unhover_hand(v)
	var me := v.g.players[0]
	var foe := v.g.players[1]
	for pair in [["minion_hover_keywords", me.board[5].id, "A minion with four keywords hovered: the big card and its keyword boxes"],
			["minion_hover_buffed", me.board[3].id, "A frozen minion with a big buff hovered"],
			["enemy_minion_hover", foe.board[4].id, "An enemy minion hovered"],
			["weapon_hover", me.weapon.id if me.weapon else -1, "The own weapon (Kingsbane, buffed) hovered"],
			["secret_hover", me.secrets[0].id if not me.secrets.is_empty() else -1, "An own secret hovered"]]:
		if v._views.has(pair[1]):
			v._on_hover(v._views[pair[1]], true)
			await a.wait(0.5)
			await a.shot(pair[0], pair[2])
			v._on_hover(v._views[pair[1]], false)
		else:
			a.error("nothing to hover: " + pair[0])
	v.click_entity(me.board[2].id)  # aiming an attack
	await a.wait(0.4)
	await a.shot("aiming", "A minion chosen to attack: the arrow and the hint")
	v.cancel()
	v.show_hint(TranslationServer.translate("Waiting for the opponent…") + " " + TranslationServer.translate("Choose a target"), 3.0)
	await a.wait(0.3)
	await a.shot("hint", "A hint line over the table")
	v._wheel.visible = true
	await a.wait(0.3)
	await a.shot("emote_wheel", "The emote buttons around the own hero")
	v._wheel.visible = false
	v.show_emote(0, "threaten")
	v.show_emote(1, "well_played")
	await a.wait(0.5)
	await a.shot("emote_bubbles", "Emote bubbles of both heroes")
	await a.wait(3.2)  # (the bubbles fade)
	_tick(v, MatchView.timer("fuse") * 0.55)
	await a.wait(0.5)
	await a.shot("rope", "The rope burning in the last seconds of the turn, the turn clock")
	v.timer_enabled = false
	v._rope.visible = false
	(v.find_child("TrackerButton", true, false) as Button).pressed.emit()
	await a.wait(0.6)
	await a.shot("tracker", "The deck tracker open over the full table")
	(v.find_child("TrackerButton", true, false) as Button).pressed.emit()
	await a.wait(0.5)
	v._menu.visible = true
	await a.wait(0.3)
	await a.shot("game_menu_open", "The game menu (the gear)")
	v._menu.visible = false
	v.open_settings()
	await a.settle(0.5)
	await a.shot("settings_over_match", "The settings opened from the match")
	var s := v.find_child("SettingsView", true, false)
	if s:
		s.queue_free()
	await a.wait(0.3)
	v._on_concede()
	await a.wait(0.5)
	await a.shot("concede_confirm", "The question before conceding")
	v._close_overlay()


func _history() -> void:
	var sc := FULL.duplicate(true)
	sc.players[0].board = sc.players[0].board.slice(0, 4)
	sc.players[1].board = sc.players[1].board.slice(0, 4)
	sc.players[0].hand = ["VAN_CS2_062", "LOOT_101", "AT_048", "LOOT_216"]
	var v := await _start(sc, [false, true])
	if v == null:
		return
	await _do(v, [{"do": "attack", "attacker": _ref(0, "board", 2), "defender": _ref(1, "board", 2)},
		{"do": "play", "card": _ref(0, "hand", 0)},
		{"do": "end_turn"}])
	await a.settle(3.0)
	await a.shot("history_strip", "The history strip after a few moves of both sides")
	var strip: HistoryStrip = v._strip
	var tiles := []
	for i in strip._items.size():
		if strip._items[i][0] is String and strip._items[i].size() > 2:
			tiles.append(i)
	if not tiles.is_empty():
		strip.hover(tiles[0])
		await a.wait(0.6)
		await a.shot("history_hover", "A history tile hovered: the move's cards")
		strip.hover(-1)
	v._history.visible = true
	await a.wait(0.5)
	await a.shot("history_panel", "The history panel (the game menu's History)")
	v._history.visible = false


func _quest_and_secrets() -> void:
	var v := await _start({"current": 0, "turn": 6, "seed": 3, "players": [
		{"hero": MAGE, "mana": 10, "max_mana": 10, "hand": ["UNG_028", "VAN_EX1_289", "AT_002", "VAN_EX1_294", "VAN_CS2_024"],
			"deck": DECK, "board": ["UNG_020"]},
		{"hero": ROGUE, "mana": 10, "max_mana": 10, "hand": ["UNG_067"], "secrets": [], "deck": DECK, "board": ["VAN_CS2_120"]}]})
	if v == null:
		return
	await _do(v, [{"do": "play", "card": _ref(0, "hand", 0)}, {"do": "play", "card": _ref(0, "hand", 0)},
		{"do": "play", "card": _ref(0, "hand", 0)}, {"do": "play", "card": _ref(0, "hand", 0)}])
	await a.shot("quest_secrets", "A quest and three secrets of the own hero")
	for k in v._views:
		var w: EntityView = v._views[k]
		if is_instance_valid(w) and w.get_meta("kind", "") == "quest":
			v._on_hover(w, true)
			await a.wait(0.5)
			await a.shot("quest_hover", "The quest hovered: its progress")
			v._on_hover(w, false)
			break


func _hero_card() -> void:
	var v := await _start({"current": 0, "turn": 9, "seed": 3, "players": [
		{"hero": WARRIOR, "mana": 10, "max_mana": 10, "armor": 4, "hand": ["ICC_834", "ICC_481"], "deck": DECK, "board": ["OG_218", "UNG_047"]},
		{"hero": MAGE, "mana": 10, "max_mana": 10, "deck": DECK, "board": ["BRM_008", "OG_221", "OG_308"]}]})
	if v == null:
		return
	await _do(v, [{"do": "play", "card": _ref(0, "hand", 0)}])
	await a.settle(1.0)
	await a.shot("hero_card", "A Death Knight hero card played (Scourgelord Garrosh): the new hero, hero power, armor, weapon")
	var hp: int = v.g.players[0].hero_power.id
	if v._views.has(hp):
		v._on_hover(v._views[hp], true)
		await a.wait(0.5)
		await a.shot("hero_power_hover", "The Death Knight's new hero power hovered")
		v._on_hover(v._views[hp], false)


func _choices() -> void:
	for c in [["discover", "LOE_003", "Discover (Ethereal Conjurer): the choice of three spells"],
			["adapt", "UNG_100", "Adapt (Verdant Longneck): the choice of three adaptations"],
			["kazakus", "CFM_621", "Kazakus: the choice of the potion's cost"]]:
		var v := await _start({"current": 0, "turn": 9, "seed": 4, "players": [
			{"hero": DRUID if c[0] == "adapt" else MAGE, "mana": 10, "max_mana": 10, "hand": [c[1]], "deck": DECK, "board": ["OG_218"]},
			{"hero": WARLOCK, "mana": 10, "max_mana": 10, "deck": DECK, "board": ["BRM_008"]}]})
		if v == null:
			continue
		if not await _do(v, [{"do": "play", "card": _ref(0, "hand", 0)}]):
			continue
		await a.settle(0.6)
		await a.shot(c[0], c[2])
		if c[0] == "kazakus" and v._overlay:  # a click on the first potion (the window closes, the next opens)
			var cards := v._overlay.find_children("*", "CardView", true, false)
			cards[0].clicked.emit(cards[0])
			await a.settle(0.8)
			await a.shot("kazakus_second", "Kazakus: the choice of the first ingredient (long texts)")
	var v := await _start({"current": 0, "turn": 9, "seed": 4, "players": [
		{"hero": DRUID, "mana": 10, "max_mana": 10, "hand": ["VAN_EX1_166", "UNG_101", "AT_104"], "deck": DECK, "board": ["OG_218"]},
		{"hero": WARLOCK, "mana": 10, "max_mana": 10, "deck": DECK, "board": ["BRM_008"]}]})
	if v == null:
		return
	v.click_entity(v.g.players[0].hand[1].id)
	await a.wait(0.6)
	await a.shot("choose_one", "Choose One (Shellshifter): the two choices")
	v._close_overlay()
	v.cancel()
	await a.wait(0.3)
	await _do(v, [{"do": "play", "card": _ref(0, "hand", 2)}], false)
	await a.wait(0.7)
	await a.shot("joust", "A Joust (Tuskarr Jouster): the two revealed cards")
	await a.settle(0.5)


func _results() -> void:
	var base := {"current": 0, "turn": 9, "seed": 4, "players": [
		{"hero": WARLOCK, "mana": 10, "max_mana": 10, "damage": 27, "hand": ["VAN_CS2_062"], "deck": DECK, "board": [{"card": "VAN_CS2_120"}]},
		{"hero": PALADIN, "mana": 10, "max_mana": 10, "damage": 27, "deck": DECK, "board": ["OG_221"]}]}
	for r in [["result_win", [{"do": "attack", "attacker": _ref(0, "board", 0), "defender": _ref(1, "hero")}, {"do": "attack", "attacker": _ref(0, "hero"), "defender": _ref(1, "hero")}], "The result: victory"],
			["result_draw", [{"do": "play", "card": _ref(0, "hand", 0)}], "The result: a draw (Hellfire kills both heroes)"],
			["result_lose", [], "The result: defeat (conceded)"]]:
		var sc := base.duplicate(true)
		if r[0] == "result_win":
			sc.players[1].damage = 28
		var v := await _start(sc, [false, true])
		if v == null:
			continue
		if r[0] == "result_lose":
			v.controller.submit({"type": "concede", "player": 0})
		elif r[0] == "result_win":
			await _do(v, r[1].slice(0, 1))
		else:
			await _do(v, r[1])
		await a.settle(1.0)
		await a.wait(3.0)  # the losing hero shatters, then the result grows in
		await a.shot(r[0], r[2])
