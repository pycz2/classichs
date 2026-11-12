extends TestCase
## Kobolds & Catacombs on the client: a Lesser Spellstone's "@" hint, cards that change in the hand (Spellstones,
## Unidentified items), Recruit (a minion out of a deck), cards cast when drawn, cards shuffled back into a deck.
## The active pack is Classic: the cards here are put into CardDb for the test and taken out after it.

const STONE := "TEST_SPELLSTONE"
const DARK := "TEST_DORMANT"
const FATE := "TEST_FATE"
const RECRUIT := "TEST_RECRUIT"
const CANDLE := "TEST_CANDLE"
const YETI := "VAN_CS2_182"


func _add_cards() -> void:
	CardDb.has(STONE)  # loaded
	CardDb._cards[STONE] = {"id": STONE, "type": "SPELL", "cardClass": "WARRIOR", "set": "VANILLA", "cost": 1,
		"name": {"enUS": "Lesser Jasper Spellstone"},
		"text": {"enUS": "Deal $2 damage to a minion. @<i>(Gain 3 Armor to upgrade.)</i>",
			"ruRU": "Наносит $2 ед. урона выбранному существу. @<i>(Получите 3 ед. брони для улучшения.)</i>"}}
	CardDb._cards[DARK] = {"id": DARK, "type": "MINION", "cardClass": "NEUTRAL", "set": "VANILLA", "cost": 4,
		"attack": 20, "health": 20, "name": {"enUS": "The Darkness"}, "text": {"enUS": "@"}}
	CardDb._cards[FATE] = {"id": FATE, "type": "MINION", "cardClass": "DRUID", "set": "VANILLA", "cost": 4,
		"attack": 5, "health": 3, "name": {"enUS": "Fatespinner"}, "text": {"enUS": "Both.@First.@Second."}}
	CardDb._cards[RECRUIT] = {"id": RECRUIT, "type": "SPELL", "cardClass": "NEUTRAL", "set": "VANILLA", "cost": 6,
		"name": {"enUS": "Gather Your Party"}, "text": {"enUS": "<b>Recruit</b> a minion."},
		"referencedTags": ["SUMMON_FROM_DECK"]}
	CardDb._cards[CANDLE] = {"id": CANDLE, "type": "SPELL", "cardClass": "NEUTRAL", "set": "VANILLA", "cost": 4,
		"name": {"enUS": "Darkness Candle"}, "text": {"enUS": "Snuff out a candle. Draw a card."}}


func _remove_cards() -> void:
	for id in [STONE, DARK, FATE, RECRUIT, CANDLE]:
		CardDb._cards.erase(id)


func test_a_spellstone_shows_its_whole_text_and_variants_still_split() -> void:
	_add_cards()
	eq(CardText.text(STONE, "en"), "Deal 2 damage to a minion. (Gain 3 Armor to upgrade.)", "no @, the hint kept")
	eq(CardText.text(STONE, "ru"), "Наносит 2 ед. урона выбранному существу. (Получите 3 ед. брони для улучшения.)", "Russian")
	check(CardText.rich(STONE, "en").contains("[i](Gain 3 Armor to upgrade.)[/i]"), "the hint in italics")
	eq(CardText.text(DARK, "en"), "", "The Darkness's dormant form: no text, no @")
	eq(CardText.text(FATE, "en"), "Both.", "Fatespinner: the variant both players see")
	eq(CardText.text(FATE, "en", 0, ["@2"]), "Second.", "and its player's")
	var e := GameView.Ent.new()
	e.set_from(9, {"card": FATE, "ctrl": 0, "zone": "PLAY", "choice": 1})
	var cv := CardView.make(FATE)
	cv.show_entity(e, GameView.new())
	eq(cv.text_args, ["@2"], "a big card shows the chosen variant to its player")
	cv.free()
	_remove_cards()


func test_history_lines_of_the_new_events() -> void:
	_add_cards()
	var m := H.game([YETI])
	var g := m.game
	var yeti: int = g.players[0].hand[0].id
	var rows := func(evs: Array, viewer: int) -> Array:
		return HistoryText.rows({"turn": 1, "player": 0, "action": {"type": "end_turn"}, "events": evs}, g, viewer, "en").map(func(r): return r.text)
	var recruit := {"type": "summon", "entity": yeti, "player": 0, "card": YETI, "by": RECRUIT, "by_id": 99}
	eq(rows.call([recruit], 0), ["Chillwind Yeti is summoned from your deck"], "Recruit")
	eq(rows.call([recruit], 1), ["Chillwind Yeti is summoned from Opponent's deck"], "the opponent's Recruit")
	eq(rows.call([recruit.merged({"by": YETI}, true)], 0), ["Chillwind Yeti is summoned"], "another summon")
	var candle := {"type": "cast_when_drawn", "player": 1, "entity": 70, "card": CANDLE}
	eq(rows.call([candle], 0), ["Opponent draws Darkness Candle: it casts itself"], "shown to both players")
	eq(rows.call([candle.merged({"player": 0}, true)], 0), ["You draw Darkness Candle: it casts itself"], "mine")
	var kingsbane := {"type": "to_deck", "player": 0, "entity": 40, "card": "", "by": YETI, "by_id": 40}
	eq(rows.call([kingsbane], 1), ["Chillwind Yeti is shuffled into Opponent's deck"], "a card that shuffles itself back")
	var swap := []
	for i in 3:
		swap.append({"type": "to_deck", "player": 1, "entity": 50 + i, "card": "", "by": YETI, "by_id": 7})
	swap.append({"type": "to_deck", "player": 0, "entity": 60, "card": "", "by": YETI, "by_id": 7})
	eq(rows.call(swap, 0), ["3 cards are shuffled into Opponent's deck", "A card is shuffled into your deck"],
		"King Togwaggle's swap: one row per deck")
	_remove_cards()


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _key(d: Dictionary, id: int) -> Variant:
	return str(id) if d.has(str(id)) else id


func test_a_card_changing_in_the_hand_takes_its_place() -> void:
	var v := MatchView.new()
	root().add_child(v)
	v.bind(H.scene({"hero": "HERO_08", "hand": [H.WISP]}, {"hero": "HERO_01"}, 0, [false, false]))
	var snap: Dictionary = v.controller.game.snapshot.duplicate(true)
	var old: int = v.g.players[0].hand[0].id
	var n := int(snap.next_id)
	var ents: Dictionary = snap.entities
	var e: Dictionary = ents[_key(ents, old)].duplicate(true)
	e.card = YETI
	ents[_key(ents, old)].zone = "SETASIDE"
	ents[str(n) if ents.has(str(old)) else n] = e
	snap.players[0].hand = [n]
	snap.next_id = n + 1
	var ev := {"type": "transform", "from": old, "entity": n, "player": 0, "card": YETI}
	var item := {"events": [ev], "snap": snap, "hist": v.controller.game.history.size()}
	v._begin_batch(item)
	for st in MatchView.steps(item.events):
		v._step_apply(st)
	check(v._views.has(n) and v._views[n] is CardView and v._views[n].card_id == YETI, "the new card in the hand")
	check(not v._views.has(old), "the old one gone")
	v._end_batch()
	v.free()


func test_a_minion_out_of_a_deck_comes_from_the_deck() -> void:
	var v := MatchView.new()
	root().add_child(v)
	v.bind(H.scene({"hero": "HERO_08", "deck": [YETI, YETI], "hand": [H.WISP]}, {"hero": "HERO_01"}, 0, [false, false]))
	var snap: Dictionary = v.controller.game.snapshot.duplicate(true)
	var hand: int = v.g.players[0].hand[0].id
	var deck: Array = snap.players[0].get("deck", [])
	var d := int(deck[0]) if not deck.is_empty() else hand - 1  # (a player's view lists no deck: an id below the hand's)
	var ents: Dictionary = snap.entities
	ents[str(d) if ents.has(str(hand)) else d] = {"card": YETI, "ctrl": 0, "zone": "PLAY", "order": 50, "atk": 4, "health": 5,
		"max_health": 5, "type": "MINION"}
	snap.players[0].board = [d]
	var evs := [{"type": "summon", "entity": d, "player": 0, "card": YETI, "by": "VAN_CS2_029", "by_id": 99},
		{"type": "summon", "entity": hand, "player": 0, "card": H.WISP}]
	v._begin_batch({"events": evs, "snap": snap, "hist": v.controller.game.history.size()})
	eq(v._from_deck.keys(), [d], "the deck's card comes out of the deck, the hand's not")
	v._end_batch()
	v.free()


func test_a_card_cast_when_drawn_shows_instead_of_going_to_the_hand() -> void:
	var evs := [{"type": "draw", "player": 0, "entity": 40, "card": CANDLE},
		{"type": "cast_when_drawn", "player": 0, "entity": 40, "card": CANDLE},
		{"type": "draw", "player": 0, "entity": 41, "card": YETI}]
	eq(MatchView.steps(evs).map(func(s): return s.k), ["topdeck", "card"], "the candle is shown, then the next card is drawn")
