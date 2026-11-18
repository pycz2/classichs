extends SceneTree
## Frames of the table's animations for a look by eye (the check page ~/ClassicHS-local/anim-check): one item of
## "the table shows what happens" at one size, played on a real table in a window with the animations on.
## Usage: godot --path . --script res://tools/anim_check.gd -- <out dir> <item> <desktop|phone>
## Items: 1 (an effect on a hand, a deck, a Hero Power), 2 (green and red numbers), 3 (cards shuffled into decks and
## added to hands from their source), 4 (hit and freeze together, the frost), 5 (End Turn turns over), 6 (Joust),
## 7 (Start of Game), 8 (a targeted spell aims as its light), 8opp (what the opponent sees of it), 9 (Secrets).
## Every user file goes to user://uitest_anim_* (never the player's own). Needs build/packs/gil.cardpack (./run_tests.sh
## or tools/build_packs.sh builds it): the cards of every set up to The Witchwood.

const YETI := "VAN_CS2_182"
const WISP := "VAN_CS2_231"
const OGRE := "VAN_CS2_200"
const FIREBALL := "VAN_CS2_029"

var out := ""
var item := ""
var phone := false
var view: MatchView
var m: Match
var plan: Array = []  # [msec, callable or a shot's label]
var shots: Array = []  # [{file, label, t}]
var t0 := -1
var at := 0
var n := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	item = args[1]
	phone = args.size() > 2 and args[2] == "phone"
	root.size = Vector2i(844, 390) if phone else Vector2i(1280, 720)
	Settings.path = "user://uitest_anim_settings.json"
	Progress.path = "user://uitest_anim_progress.json"
	DeckStore.path = "user://uitest_anim_decks.json"
	Profile.path = "user://uitest_anim_profile.json"
	ServerLink.session_path = "user://uitest_anim_session.json"
	Replay.dir = "user://uitest_anim_replays"
	Packs.user_dir = "user://uitest_anim_packs"
	DirAccess.make_dir_recursive_absolute(out)
	var r := Packs.install_file(ProjectSettings.globalize_path("res://build/packs/gil.cardpack"))
	assert(not r.has("error"), str(r.get("error", "")))
	Packs.set_active(r.pack)


func _process(_delta: float) -> bool:
	if t0 < 0:
		call("_item_" + item)  # (the tree runs now: the table's _ready comes with it)
		t0 = Time.get_ticks_msec()
		return false
	var now := Time.get_ticks_msec() - t0
	while at < plan.size() and now >= plan[at][0]:
		var step = plan[at]
		at += 1
		if step[1] is Callable:
			step[1].call()
		else:
			_shot(step[1], now)
	if at >= plan.size():
		var f := FileAccess.open("%s/%s-%s.json" % [out, item, "phone" if phone else "desktop"], FileAccess.WRITE)
		f.store_string(JSON.stringify(shots, " "))
		f.close()
		quit()
	return false


func _shot(label: String, now: int) -> void:
	var img := root.get_texture().get_image()
	var w := 844 if phone else 960
	img.resize(w, int(w * img.get_height() / float(img.get_width())), Image.INTERPOLATE_LANCZOS)
	var name := "%s-%s-%02d.jpg" % [item, "phone" if phone else "desktop", n]
	n += 1
	img.save_jpg("%s/%s" % [out, name], 0.88)
	shots.append({"file": name, "label": label, "t": now})


## A table from a scenario (Debug Table format), player 0 looking; the other side moves only when told to.
func _table(p0: Dictionary, p1: Dictionary, current := 0) -> void:
	for p in [p0, p1]:
		if not p.has("mana"):
			p["mana"] = 10
			p["max_mana"] = 10
	m = Match.new()
	m.bot_delay = 99999.0
	var why := m.setup({"scenario": {"current": current, "players": [p0, p1]}}, [false, true])
	assert(why == "", why)
	_show()


func _show() -> void:
	view = MatchView.new()
	root.add_child(view)
	view.bind(m)
	if phone:
		view.touch = true
		view.refresh()


## From msec t: label shots every `every` msec, count of them.
func _seq(t: int, label: String, count: int, every := 120) -> void:
	for i in count:
		plan.append([t + i * every, "%s %d/%d" % [label, i + 1, count]])


func _at(t: int, fn: Callable) -> void:
	plan.append([t, fn])


func _card(p: int, card: String) -> int:
	for e in m.game.players[p].hand:
		if e.card_id == card:
			return e.id
	return -1


func _play(p: int, card: String, target := -1) -> void:
	var e := m.game.ent(_card(p, card))
	var r := m.submit({"type": "play", "player": p, "entity": e.id, "target": target,
		"pos": m.game.players[p].board.size() if e.is_minion() else -1, "choice": -1})
	assert(r.get("ok", true), "%s: %s" % [card, r])


func _minion(p: int, i: int) -> int:
	return m.game.players[p].board[i].id


func _end(p: int) -> void:
	m.submit({"type": "end_turn", "player": p})


func _history() -> void:
	view._history.visible = true
	view._history.update_from(view.g, view.viewer())


## The hand's cards shown big in the middle (their numbers: green above the card's own, red below), for a look.
func _look_at_hand(p := 0) -> void:
	var hand: Array = m.game.players[p].hand
	for i in hand.size():
		var cv := CardView.make(hand[i].card_id, 1.25)
		cv.show_entity(hand[i], view.g)
		cv.position = Vector2(640 - hand.size() * 80 + i * 160, 200)
		cv.z_index = 80
		cv.name = "Look%d" % i
		view.add_child(cv)


func _unlook() -> void:
	for c in view.get_children():
		if c.name.begins_with("Look"):
			c.queue_free()


func _sort_plan() -> void:
	plan.sort_custom(func(a, b): return a[0] < b[0])


# --- the items -----------------------------------------------------------------------------------------------------

## An effect on cards in a hand (a light sweeps over it, their numbers green), on a deck (it swells), on a Hero Power.
func _item_1() -> void:
	_table({"hero": "HERO_08", "hand": ["CFM_753", YETI, "VAN_CS2_120", FIREBALL, "ICC_851", "AT_132"], "deck": [YETI, YETI, YETI, OGRE]},
		{"hero": "HERO_01", "deck": [YETI]})
	_seq(300, "before", 1)
	_at(600, func(): _play(0, "CFM_753"))
	_seq(700, "Grimestreet Outfitter: minions in the hand +1/+1", 22, 110)
	_at(3150, _look_at_hand)
	_seq(3250, "the hand's cards (a look): Attack and Health green", 1)
	_at(3400, _unlook)
	_at(3500, func(): _play(0, "ICC_851"))
	_seq(3600, "Prince Keleseth: minions in the deck +1/+1", 22, 110)
	_at(6200, func(): _play(0, "AT_132"))
	_seq(6300, "Justicar Trueheart: a better Hero Power", 22, 110)
	_at(9000, _history)
	_seq(9200, "history", 1)
	_sort_plan()


## Green and red numbers: spells cheaper (Sorcerer's Apprentice), minions dearer (Venture Co.), the weapon upgraded,
## the Hero Power made cheaper (Maiden of the Lake), minions in the hand buffed.
func _item_2() -> void:
	_table({"hero": "HERO_01", "board": ["VAN_EX1_608", "VAN_CS2_227"], "weapon": {"card": "VAN_CS2_106", "durability": 2},
		"hand": [FIREBALL, YETI, "VAN_EX1_409", "AT_085", "CFM_753", "VAN_CS2_106"], "mana": 20, "max_mana": 10}, {"hero": "HERO_08"})
	_at(200, _look_at_hand)
	_seq(400, "costs: spells cheaper (green), minions dearer (red)", 1)
	_at(500, _unlook)
	_at(700, func(): _play(0, "VAN_EX1_409"))
	_seq(800, "Upgrade!: the weapon +1/+1", 10, 110)
	_at(2400, func(): _play(0, "AT_085"))
	_seq(2500, "Maiden of the Lake: the Hero Power costs (1)", 14, 110)
	_at(4600, func(): _play(0, "CFM_753"))
	_seq(4700, "Grimestreet Outfitter: minions in the hand +1/+1", 22, 110)
	_at(7300, _look_at_hand)
	_seq(7400, "the hand's cards (a look)", 1)
	_sort_plan()


## Cards shuffled into a deck and added to a hand fly from their source: Beneath the Grounds (into the opponent's
## deck), Burgle (from the opponent's class), Thoughtsteal (from the opponent's deck), the opponent's Gang Up.
func _item_3() -> void:
	_table({"hero": "HERO_03", "hand": ["AT_035", "AT_033", "VAN_EX1_339"], "deck": [YETI, YETI]},
		{"hero": "HERO_02", "hand": ["BRM_007", WISP], "board": [YETI], "deck": [OGRE, OGRE, YETI, YETI]})
	_seq(300, "before", 1)
	_at(500, func(): _play(0, "AT_035"))
	_seq(600, "Beneath the Grounds: 3 Ambushes into the opponent's deck", 16, 110)
	_at(3000, func(): _play(0, "AT_033"))
	_seq(3100, "Burgle: 2 cards from the opponent's class", 14, 110)
	_at(5300, func(): _play(0, "VAN_EX1_339"))
	_seq(5400, "Thoughtsteal: copies from the opponent's deck", 14, 110)
	_at(7600, func(): _end(0))
	_at(9000, func(): _play(1, "BRM_007", _minion(1, 0)))
	_seq(9100, "the opponent's Gang Up: 3 copies into their deck", 18, 110)
	_at(11500, _history)
	_seq(11700, "history", 1)
	_sort_plan()


## Hit and freeze land together (Frostbolt, Cone of Cold, Water Elemental's blow); the frost spreads, then melts.
func _item_4() -> void:
	_table({"hero": "HERO_08", "hand": ["VAN_CS2_024", "VAN_EX1_275"], "board": ["VAN_CS2_033"]},
		{"hero": "HERO_01", "board": [YETI, YETI, YETI, YETI]})
	_at(400, func(): _play(0, "VAN_CS2_024", _minion(1, 0)))
	_seq(500, "Frostbolt: the hit and the freeze together", 14, 100)
	_at(2600, func(): _play(0, "VAN_EX1_275", _minion(1, 2)))
	_seq(2700, "Cone of Cold: three hit and frozen at once", 14, 100)
	_at(4800, func(): m.submit({"type": "attack", "player": 0, "attacker": _minion(0, 0), "defender": _minion(1, 3)}))
	_seq(4900, "Water Elemental's blow freezes", 12, 100)
	_at(6600, func(): _end(0))
	_at(8000, func(): _end(1))
	_seq(8200, "the frost melts (their turn is over)", 24, 150)
	_sort_plan()


## End Turn turns over when the turn changes.
func _item_5() -> void:
	_table({"hero": "HERO_08"}, {"hero": "HERO_01"})
	_seq(300, "own turn", 1)
	_at(600, func(): _end(0))
	_seq(620, "End Turn -> Enemy Turn", 14, 45)
	_at(2600, func(): _end(1))
	_seq(2620, "Enemy Turn -> End Turn", 14, 45)
	_sort_plan()


## Joust: a card out of each deck, whose is which, the costs, the winner; the opponent's Joust too.
func _item_6() -> void:
	_table({"hero": "HERO_04", "hand": ["AT_104"], "deck": [OGRE, OGRE, OGRE]},
		{"hero": "HERO_01", "hand": ["AT_104"], "deck": [WISP, YETI, WISP]})
	_at(400, func(): _play(0, "AT_104"))
	_seq(500, "your Joust: 6 against the opponent's", 26, 130)
	_at(4300, func(): _end(0))
	_at(5800, func(): _play(1, "AT_104"))
	_seq(5900, "the opponent's Joust", 26, 130)
	_at(9600, _history)
	_seq(9800, "history", 1)
	_sort_plan()


## Start of Game: Baku the Mooneater and Prince Malchezaar (yours: an odd deck), Genn Greymane (the opponent's: even).
func _item_7() -> void:
	var odd := ["GIL_826", "KAR_096"]
	var even := ["GIL_692"]
	for i in 14:
		odd.append_array(["VAN_CS2_168", "VAN_CS2_125"])
	for i in 15:
		even.append(YETI)
	for i in 14:
		even.append("VAN_CS2_172")
	m = Match.new()
	m.bot_delay = 99999.0
	var why := m.setup({"decks": [{"hero": "HERO_08", "cards": odd}, {"hero": "HERO_01", "cards": even}], "seed": 3, "first": 0, "check": false}, [false, true])
	assert(why == "", why)
	_show()
	_seq(600, "the mulligan", 1)
	_at(900, func(): m.submit({"type": "mulligan", "player": 0, "replace": []}))
	_at(1600, func(): m.submit({"type": "mulligan", "player": 1, "replace": []}))
	_seq(1700, "Start of Game", 64, 130)
	_at(10200, _history)
	_seq(10400, "history", 1)
	_sort_plan()


## A targeted spell aims as its light (the card is gone while it aims), and is a card again back over the hand.
func _item_8() -> void:
	_table({"hero": "HERO_08", "hand": [FIREBALL, "VAN_CS2_024", YETI]}, {"hero": "HERO_01", "board": [YETI]})
	var path := []
	_at(600, func():
		var id := _card(0, FIREBALL)
		var v: EntityView = view._views[id]
		var from := v.position + v.size * v.scale / 2.0
		view._press = {"id": id, "at": from}
		view._start_drag()
		path.append(from))
	for i in 10:  # up to the Yeti
		_at(700 + i * 60, func():
			var to := view._center_of(_minion(1, 0))
			view._drag_to(path[0].lerp(to, (i + 1) / 10.0)))
	_seq(760, "aiming: the card is its light", 12, 70)
	for i in 8:  # back down over the hand
		_at(1800 + i * 60, func():
			var to := view._center_of(_minion(1, 0))
			view._drag_to(to.lerp(Vector2(640, 690), (i + 1) / 8.0)))
	_seq(1860, "back over the hand: a card again", 8, 70)
	_at(2600, func():
		view._press = {}
		view._dragging = false
		view._drop_at(Vector2(640, 690), _card(0, FIREBALL)))
	_seq(2700, "dropped back in the hand", 4, 120)
	_sort_plan()


## What the opponent sees while you aim a spell: only the arrow from your card's back.
func _item_8opp() -> void:
	_table({"hero": "HERO_08", "board": [YETI]}, {"hero": "HERO_01", "hand": [FIREBALL, WISP, YETI]})
	for i in 10:
		_at(500 + i * 60, func():
			var theirs := _card(1, FIREBALL)
			var to := view._center_of(_minion(0, 0)).lerp(view._center_of(theirs), 1.0 - (i + 1) / 10.0)
			view.apply_intent({"k": "aim", "from": theirs, "to": _minion(0, 0) if i == 9 else -1, "x": to.x, "y": 720.0 - to.y}))
	_seq(560, "the opponent aims a spell: the arrow, no card", 12, 70)
	_sort_plan()


## A Secret going off shows over its place, with its sound: the opponent's Explosive Trap, your Ice Barrier.
func _item_9() -> void:
	_table({"hero": "HERO_08", "board": [YETI], "secrets": ["VAN_EX1_289"]},
		{"hero": "HERO_05", "board": [YETI], "secrets": ["VAN_EX1_610"]})
	_at(500, func(): m.submit({"type": "attack", "player": 0, "attacker": _minion(0, 0), "defender": m.game.hero(1).id}))
	_seq(600, "the opponent's Explosive Trap", 20, 110)
	_at(3600, func(): _end(0))
	_at(5000, func(): m.submit({"type": "attack", "player": 1, "attacker": _minion(1, 0), "defender": m.game.hero(0).id}))
	_seq(5100, "your Ice Barrier", 20, 110)
	_at(8000, _history)
	_seq(8200, "history", 1)
	_sort_plan()
