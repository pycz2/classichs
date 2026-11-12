extends RefCounted
## The Witchwood (packs/gil): its game menu, the collection by its set, big cards of its new mechanics (Echo,
## Rush, the worgen that swap in the hand, Start of Game, Shudderwock), table scenes from its card tests
## (data/card_tests/gil.json) with the hovered card and the history, and a real game start with Start of Game
## (Baku's odd deck, Genn's even deck). Run: tools/ui_audit.py gil --packs ~/ClassicHS-local/gil-custom-art.cardpack

const BIG := ["GIL_820", "GIL_692", "GIL_826", "GIL_504", "GIL_528", "GIL_201", "GIL_207", "GIL_607t", "GIL_113",
	"GIL_578", "GIL_618", "GIL_529", "GIL_200t", "GIL_202"]
## [card test id, its index, shot name, steps to play (-1: all), hover ref or null, history?]
const SCENES := [
	["GIL_207", 0, "echo_militia", 1, {"side": 0, "zone": "hand", "index": 0}, false],
	["GIL_607t", 0, "echo_rush_mastiff", 1, {"side": 0, "zone": "board", "index": 0}, false],
	["GIL_113", 0, "rush_worgen", 1, {"side": 0, "zone": "board", "index": 0}, false],
	["GIL_528", 0, "swap_messenger", -1, {"side": 0, "zone": "hand", "index": 0}, false],
	["GIL_201", 0, "swap_peasant", -1, {"side": 0, "zone": "hand", "index": 0}, false],
	["GIL_820", 0, "shudderwock", -1, null, true],
	["GIL_504", 0, "hagatha", -1, {"side": 0, "zone": "power"}, true],
	["GIL_680", 0, "echo_walnut", 2, null, false],
]
var a
var m: Node
var tests: Dictionary


func run(audit) -> void:
	a = audit
	a.root.gui_disable_input = true  # (the real mouse never takes a hover away)
	tests = JSON.parse_string(FileAccess.get_file_as_string("res://data/card_tests/gil.json"))
	m = await a.open_game()
	await a.shot("gil_menu", "The Witchwood's game menu")
	m.show_collection()
	await a.settle()
	m.screen.edit_deck(0)
	await a.settle()
	var c: CollectionView = m.screen.browser
	var pick := c.find_child("SetFilter", true, false) as OptionButton
	var i := CollectionView.set_keys().find("GILNEAS")
	if pick and i >= 0:
		pick.select(i + 1)
		pick.item_selected.emit(i + 1)
	await a.settle()
	await a.shot("gil_collection", "The deck builder's collection filtered by the Witchwood set")
	for id in BIG:
		await _big(c, id)
	m.show_game_menu()
	await a.settle(0.4)
	for sc in SCENES:
		await _scene(sc)
	for card in ["GIL_826", "GIL_692"]:
		await _start_of_game(card)


func _big(c: CollectionView, id: String) -> void:
	var card := CardDb.card(id)
	if card.is_empty():
		a.error("no card " + id)
		return
	var classes: Array = card.get("classes", [])
	c.set_tab(str(classes[0]) if not classes.is_empty() else str(card.get("cardClass", "NEUTRAL")))
	var pick := c.find_child("SetFilter", true, false) as OptionButton
	if pick:  # every set: a token (a swapped form) is no collectible card of the set's list
		pick.select(0)
		pick.item_selected.emit(0)
	var search := c.find_child("Search", true, false) as LineEdit
	search.text = CardText.name(id)
	search.text_changed.emit(search.text)
	await a.wait(0.2)
	var hit: CardView = null
	for v in c._grid.get_children():
		if v is CardView and v.card_id == id:
			hit = v
	if hit == null:
		print("note: %s is not in the collection (a token): its big card is skipped" % id)
	else:
		c._on_hover(hit, true)
		await a.wait(0.6)
		await a.shot("gil_card_" + id, "The big card: " + CardText.name(id))
		c._on_hover(null, false)
	search.text = ""
	search.text_changed.emit("")


func _scene(sc: Array) -> void:
	var name: String = "gil_" + str(sc[2])
	if not (a.want(name) or a.want(name + "_card") or a.want(name + "_history")):
		return
	var t: Dictionary = tests[sc[0]][sc[1]]
	var v: MatchView = m.start_match({"scenario": t.scene}, [false, false], false)
	if v == null:
		a.error("scene %s does not start" % name)
		m.show_game_menu()
		return
	await a.settle(0.6)
	var steps: Array = t.get("steps", [])
	var n: int = steps.size() if int(sc[3]) < 0 else mini(int(sc[3]), steps.size())
	for k in n:
		var act := CardTests.action(v.controller, steps[k])
		var res: Dictionary = act if act.has("error") else v.controller.submit(act)
		if act.has("error") or not res.get("ok", false):
			a.error("scene %s, step %d: %s" % [name, k + 1, res.get("error", "?")])
			break
		await a.settle(0.4)
	a.root.warp_mouse(Vector2(640, 330))
	await a.settle(0.6)
	await a.shot(name, t.title)
	if sc[4] != null:
		var id := CardTests.entity(v.controller.game, sc[4])
		var hand: Array = v.g.players[v.viewer()].hand
		var at := hand.find(v.g.ent(id))
		if at >= 0:
			var f: Dictionary = TableLayout.hand(hand.size(), true)[at]
			a.root.warp_mouse(Vector2(f.pos.x + CardView.SIZE.x * f.scale / 2.0, 700))
			await a.wait(0.7)
			await a.shot(name + "_card", t.title + " (the hand card hovered)")
			a.root.warp_mouse(Vector2(640, 330))
			await a.wait(0.3)
		elif v._views.has(id):
			v._on_hover(v._views[id], true)
			await a.wait(0.6)
			await a.shot(name + "_card", t.title + " (hovered)")
			v._on_hover(v._views[id], false)
	if sc[5]:
		var strip: HistoryStrip = v._strip
		for k in strip._items.size():
			if strip._items[k][0] is String and strip._items[k].size() > 2:
				strip.hover(k)
				await a.wait(0.6)
				await a.shot(name + "_history", t.title + " (the history's last card)")
				strip.hover(-1)
				break
	m.show_game_menu()
	await a.wait(0.2)


## A real game with the ready deck that holds this Start of Game card: the start (its effect) and after the mulligan.
func _start_of_game(card: String) -> void:
	var name := "gil_start_" + card
	var deck: Deck = null
	for t in Decks.templates():
		if Array(t.deck.cards).has(card):
			deck = t.deck
	if deck == null:
		a.error("no ready deck with " + card)
		return
	var v: MatchView = m.start_match({"decks": [{"hero": deck.hero, "cards": Array(deck.cards)},
		{"hero": deck.hero, "cards": Array(deck.cards)}], "seed": 7}, [false, true], false, "easy")
	if v == null:
		a.error(name + " does not start")
		return
	for k in 3:  # the Start of Game card's reveal, in its first moments
		await a.wait(0.25)
		await a.shot("%s_reveal%d" % [name, k + 1], "Start of Game: the reveal of %s, %.2f s after the start" % [CardText.name(card), 0.25 * (k + 1)])
	await a.wait(0.5)
	await a.shot(name, "Start of Game: a game with %s in the deck, at its start" % CardText.name(card))
	var me := v.viewer()
	v.controller.submit({"type": "mulligan", "player": me, "replace": []})
	await a.settle(1.5)
	await a.shot(name + "_after", "Start of Game: after the mulligan (%s)" % CardText.name(card))
	m.show_game_menu()
	await a.wait(0.2)
