extends TestCase
## Rise of Shadows on the client: a Twinspell copy flies from its spell into the hand place the spell left, a Lackey
## from the minion that made it, a Secret under Commander Rhyssa shows once and goes off twice, and the card texts
## the set's `text` hooks fill: Crystal Stag's "+N" variant after its text, Spirit of Lucentbark's count where its
## data stops, Drustvar Horror's spell names ("name:<id>"). The pack is built from packs/dal (tools/pack.py) and
## installed into this run's user dir; the tests make it the active pack and give Classic back at their end.

const YETI := "VAN_CS2_182"
const FIREBALL := "VAN_CS2_029"
const EYE := "VAN_EX1_132"  # Eye for an Eye
const RAY := "DAL_577"  # Ray of Frost: Twinspell, Freeze a minion
const CABLE_RAT := "DAL_400"  # EVIL Cable Rat: Battlecry: add a Lackey
const RHYSSA := "DAL_573"
const STAG := "DAL_799"
const SPIRIT := "DAL_357t"
const HORROR := "DAL_431t"
const LACKEYS := ["DAL_613", "DAL_614", "DAL_615", "DAL_739", "DAL_741"]

static var _pack: Pack


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _dal() -> bool:
	if _pack == null or not Packs.all().has(_pack):
		var out := OS.get_user_data_dir() + "/dal_test.cardpack"
		if not FileAccess.file_exists(out):
			var log := []
			var code := OS.execute("python3", [ProjectSettings.globalize_path("res://tools/pack.py"), "build",
				ProjectSettings.globalize_path("res://packs/dal"), "-o", out], log, true)
			if code != 0:
				check(false, "packs/dal builds: " + "".join(log).right(600))
				return false
		var r := Packs.install_file(out)
		if r.has("error"):
			check(false, "packs/dal installs: " + str(r.error))
			return false
		_pack = r.pack
	Packs.set_active(_pack)
	return true


func _classic() -> void:
	Packs.set_active(Packs.all().filter(func(p): return p.id() == Packs.CLASSIC and p.builtin())[0])


func _view(p0: Dictionary, p1 := {"hero": "HERO_01"}) -> MatchView:
	var v := MatchView.new()
	root().add_child(v)
	v.bind(H.scene(p0, p1, 0, [false, false]))
	return v


## Player 0 plays card_id (at target); the batch as the table gets it.
func _play(v: MatchView, card_id: String, target := -1) -> Dictionary:
	var m := v.controller
	var card: GameView.Ent = m.game.players[0].hand.filter(func(e): return e.card_id == card_id)[0]
	var r := m._apply({"type": "play", "player": 0, "entity": card.id, "target": target,
		"pos": m.game.players[0].board.size() if card.is_minion() else -1, "choice": -1})
	check(r.ok, "played " + card_id)
	return {"events": MatchView.twinspells(r.events), "snap": m.game.snapshot, "hist": m.game.history.size()}


static func _center(cv: Control) -> Vector2:
	return cv.position + cv.size * cv.scale / 2.0


func test_a_twinspell_copy_flies_from_its_spell_to_the_place_it_left() -> void:
	if not _dal():
		return
	var v := _view({"hero": "HERO_08", "hand": [YETI, RAY, YETI]}, {"hero": "HERO_01", "board": [YETI]})
	var hand: Array = v.g.players[0].hand.map(func(e): return e.id)
	var ray: int = hand[1]
	var item := _play(v, RAY, v.g.players[1].board[0].id)
	var kinds: Array = item.events.map(func(e): return e.type)
	var k := kinds.find("add_to_hand")
	check(k > kinds.find("play"), "the copy after the spell's play event: %s" % [kinds])
	var ev: Dictionary = item.events[k]
	eq([ev.get("twin"), ev.get("by_id"), ev.card], [true, ray, RAY + "ts"], "made by the spell")
	v._begin_batch(item)
	for st in MatchView.steps(item.events):
		if st.evs.has(ev):
			eq(v._hand_origin(ev), _center(v._flying[ray]), "from the spell shown big")
		v._play_step(st)
		if st.evs.has(ev):
			eq(v._stage.hand[0], [hand[0], ev.entity, hand[2]], "into the place the spell left")
	v._end_batch()
	eq(v.g.players[0].hand.map(func(e): return e.id), [hand[0], ev.entity, hand[2]], "where the game has it")
	v.free()
	_classic()


func test_the_opponents_twinspell_copy_is_found_though_hidden() -> void:
	if not _dal():
		return
	var play := {"type": "play", "player": 1, "entity": 20, "kind": "spell", "card": RAY, "target": 5}
	var copy := {"type": "add_to_hand", "player": 1, "entity": 40, "card": ""}
	eq(MatchView.twinspells([copy, play]), [play, copy.merged({"by": RAY, "by_id": 20, "twin": true})], "after the play, made by it")
	var other := {"type": "add_to_hand", "player": 1, "entity": 40, "card": YETI}
	eq(MatchView.twinspells([other, play]), [other, play], "another card: as it was")
	var fireball := play.merged({"card": FIREBALL}, true)
	eq(MatchView.twinspells([copy, fireball]), [copy, fireball], "a spell without a copy card: as it was")
	_classic()


func test_a_lackey_comes_from_the_minion_that_made_it() -> void:
	if not _dal():
		return
	var v := _view({"hero": "HERO_08", "hand": [CABLE_RAT]})
	var rat: int = v.g.players[0].hand[0].id
	var item := _play(v, CABLE_RAT)
	var ev: Dictionary = item.events.filter(func(e): return e.type == "add_to_hand")[0]
	check(ev.card in LACKEYS and ev.by_id == rat, "a Lackey made by the Rat")
	v._begin_batch(item)
	for st in MatchView.steps(item.events):
		if st.evs.has(ev):
			eq(v._hand_origin(ev), v._center_of(rat), "from the Rat on the board")
		v._play_step(st)
	v._end_batch()
	v.free()
	_classic()


func test_a_secret_under_rhyssa_shows_once_and_goes_off_twice() -> void:
	if not _dal():
		return
	var v := _view({"hero": "HERO_08", "hand": [FIREBALL]}, {"hero": "HERO_04", "board": [RHYSSA], "secrets": [EYE]})
	var me: int = v.g.hero(0).id
	var item := _play(v, FIREBALL, v.g.hero(1).id)
	var steps := MatchView.steps(item.events)
	var kinds: Array = steps.map(func(s): return s.k)
	eq(kinds.count("secret"), 1, "revealed once: %s" % [kinds])
	var hits := steps.slice(kinds.find("secret")).filter(func(s): return s.k == "hit" and s.evs[0].get("target") == me)
	eq(hits.size(), 2, "its damage twice, each a hit of its own")
	v._begin_batch(item)
	for st in steps:
		v._play_step(st)
	v._end_batch()
	eq(v.g.hero(0).health(), 30 - 12, "the game agrees")
	v.free()
	_classic()


func test_crystal_stag_shows_its_count_or_ready_after_its_text() -> void:
	if not _dal():
		return
	var base := "Rush. Battlecry: If you've restored 5 Health this game, summon a copy of this."
	eq(CardText.text(STAG, "en"), base, "in the collection: the text alone")
	eq(CardText.text(STAG, "en", 0, ["+1", "3"]), base + " (3 left!)", "in a game: the count")
	eq(CardText.text(STAG, "en", 0, ["+2"]), base + " (Ready!)", "and ready")
	check(CardText.rich(STAG, "en", 0, ["+1", "3"]).ends_with("[i](3 left!)[/i]"), "in italics")
	eq(CardText.text(STAG, "de", 0, ["+1", "3"]).right(15), "habt. (Noch 3!)", "a space where the German puts none")
	check(CardText.text(STAG, "ru", 0, ["+1", "3"]).ends_with("(еще 3 ед.)"), "Russian")
	_classic()


func test_spirit_of_lucentbark_shows_the_count_where_its_text_stops() -> void:
	if not _dal():
		return
	eq(CardText.text(SPIRIT, "en"), "When you restore 5 Health, awaken this minion.", "without a count: none of the dangling bracket")
	eq(CardText.text(SPIRIT, "en", 0, ["3"]), "When you restore 5 Health, awaken this minion.\n(3)", "with it")
	check(CardText.text(SPIRIT, "de", 0, ["3"]).ends_with("habt. (Noch 3)"), "German")
	check(CardText.text(SPIRIT, "ru", 0, ["3"]).ends_with("(осталось: 3)"), "Russian")
	check(CardText.rich(SPIRIT, "en", 0, ["3"]).ends_with("[i](3)[/i]"), "in italics")
	_classic()


func test_drustvar_horror_names_its_spells() -> void:
	if not _dal():
		return
	eq(CardText.text(HORROR, "en", 0, ["name:" + RAY, "name:" + FIREBALL]), "Battlecry: Cast Ray of Frost and Fireball.", "the names")
	eq(CardText.text(HORROR, "ru", 0, ["name:" + RAY, "name:" + FIREBALL]),
		"Боевой клич: вы разыгрываете заклинания «%s» и «%s»." % [CardText.name(RAY, "ru"), CardText.name(FIREBALL, "ru")], "in Russian")
	_classic()
