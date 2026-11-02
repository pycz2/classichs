extends TestCase
## Decks kept on the server: the tick on each deck in the deck list (DeckListView).

const URL := "ws://decks.test:7377"


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func _deck(name: String, n := 30) -> Deck:
	var d := Deck.new()
	d.name = name
	d.cards.assign(Decks.basic("MAGE").slice(0, n))
	return d


## The deck list over a fake server with these local decks; logged_in: the server has
## answered `decks` with list.
func _view(local: Array, logged_in := true, list := []) -> DeckListView:
	DeckStore.save_all(local)
	var v := DeckListView.new()
	var l := FakeLink.new()
	l.url = URL
	root().add_child(l)
	v.link = l
	root().add_child(v)
	if logged_in:
		l.dispatch({"t": "auth", "ok": true, "token": "x", "me": {"user": "anna"}})
		l.dispatch({"t": "decks", "list": list})
	return v


func _free(v: DeckListView) -> void:
	var l := v.link
	v.free()
	l.free()


func _tick(v: DeckListView, i: int) -> Button:
	var row := v.list.get_child(i)
	return row.find_child("Server", true, false) as Button if row else null


func _sent(v: DeckListView, t: String) -> Array:
	return (v.link as FakeLink).of(t)


func test_no_tick_without_a_server_session() -> void:
	DeckStore.save_all([_deck("A")])
	var alone := DeckListView.new()
	root().add_child(alone)
	check(alone.list.get_child_count() == 1 and _tick(alone, 0) == null, "no server: no tick")
	alone.free()
	var v := _view([_deck("A")], false)
	check(_tick(v, 0) == null, "not logged in: no tick")
	v.link.dispatch({"t": "auth", "ok": true, "token": "x", "me": {"user": "anna"}})
	eq(_sent(v, "decks").size(), 1, "the login asks for the server's decks")
	check(_tick(v, 0) == null, "no tick before the server says it keeps decks")
	v.link.dispatch({"t": "decks", "list": []})
	check(_tick(v, 0) != null and not _tick(v, 0).button_pressed, "then a tick, off")
	(v.link as FakeLink).up = false
	v.refresh()
	check(_tick(v, 0) == null, "the connection gone: no tick")
	_free(v)


func test_tick_saves_to_the_server_and_untick_deletes_there() -> void:
	var v := _view([_deck("A"), _deck("B")])
	_tick(v, 1).button_pressed = true
	var s: Array = _sent(v, "deck_save")
	eq(s.size(), 1, "ticked: saved to the server")
	eq([s[0].deck.name, s[0].deck.cards.size(), s[0].has("id")], ["B", 30, false], "a new deck there")
	check(_tick(v, 1).button_pressed, "the tick stays on while the answer is on the way")
	v.link.dispatch({"t": "deck_saved", "ref": s[0].ref, "deck": {"id": 42, "pack": Packs.CLASSIC, "name": "B",
		"hero": "HERO_08", "cards": s[0].deck.cards, "updated": 1000}})
	eq(v.server_id(v.decks[1]), 42, "the local copy keeps the server id")
	eq(DeckStore.load_all()[1].servers, {URL: {"id": 42, "at": 1000}}, "and saves it")
	eq(_sent(v, "deck_save").size(), 1, "nothing more to send")
	_tick(v, 1).button_pressed = false
	eq(_sent(v, "deck_delete"), [{"t": "deck_delete", "id": 42}], "unticked: deleted there")
	eq(DeckStore.load_all()[1].servers, {}, "kept here only")
	eq(DeckStore.load_all().size(), 2, "both decks stay")
	_free(v)


func test_every_change_of_a_kept_deck_goes_to_the_server() -> void:
	var a := _deck("A", 10)
	a.servers = {URL: {"id": 7, "at": 50}}
	var b := _deck("B", 10)
	var v := _view([a, b], true, [{"id": 7, "pack": Packs.CLASSIC, "name": "A", "hero": "HERO_08", "cards": Array(a.cards), "updated": 50}])
	eq(_sent(v, "deck_save"), [], "the same on both sides: nothing sent")
	v.edit_deck(0)
	v.browser.click_card("VAN_CS2_029")
	var s: Array = _sent(v, "deck_save")
	eq(s.size(), 1, "a card added: saved there")
	eq([s[-1].id, s[-1].deck.cards.size()], [7, 11], "by its id")
	v.remove_card("VAN_CS2_029")
	eq(_sent(v, "deck_save")[-1].deck.cards.size(), 10, "a card removed")
	v._name_edit.text_changed.emit("Fire")
	eq(_sent(v, "deck_save")[-1].deck.name, "Fire", "renamed")
	v.close_deck()
	var n := _sent(v, "deck_save").size()
	v.edit_deck(1)
	v.browser.click_card("VAN_CS2_029")
	eq(_sent(v, "deck_save").size(), n, "an unticked deck stays here")
	v.close_deck()
	v.delete_deck(0)
	eq(_sent(v, "deck_delete"), [{"t": "deck_delete", "id": 7}], "a kept deck deleted: deleted there too")
	_free(v)


## After login: a deck from another device joins the list, one changed there replaces this
## copy, one changed only here is sent, one gone from there stays here only, other games' stay out.
func test_merge_after_login() -> void:
	var same := _deck("Same")
	same.servers = {URL: {"id": 1, "at": 100}}
	var theirs := _deck("Old name")
	theirs.servers = {URL: {"id": 2, "at": 100}}
	var mine := _deck("Changed here", 20)
	mine.servers = {URL: {"id": 3, "at": 100}}
	var gone := _deck("Gone there")
	gone.servers = {URL: {"id": 4, "at": 100}, "ws://other:1": {"id": 9, "at": 5}}
	var local := _deck("Local")
	var cards := Array(_deck("x").cards)
	var list := [
		{"id": 1, "pack": Packs.CLASSIC, "name": "Same", "hero": "HERO_08", "cards": cards, "updated": 100},
		{"id": 2, "pack": Packs.CLASSIC, "name": "New name", "hero": "HERO_08", "cards": cards.slice(0, 5), "updated": 200},
		{"id": 3, "pack": Packs.CLASSIC, "name": "Changed here", "hero": "HERO_08", "cards": cards, "updated": 100},
		{"id": 5, "pack": Packs.CLASSIC, "name": "From the phone", "hero": "HERO_01", "cards": Decks.basic("WARRIOR"), "updated": 300},
		{"id": 6, "pack": "org.other.game", "name": "Another game", "hero": "HERO_08", "cards": cards, "updated": 300},
	]
	var v := _view([same, theirs, mine, gone, local], true, list)
	var names := v.decks.map(func(d): return d.name)
	eq(names, ["Same", "New name", "Changed here", "Gone there", "Local", "From the phone"], "merged by server id")
	eq(v.decks[1].cards.size(), 5, "changed there: the server's copy")
	eq(v.decks[1].servers[URL].at, 200, "now matching it")
	eq(_sent(v, "deck_save").map(func(m): return [m.id, m.deck.cards.size()]), [[3, 20]], "changed only here: sent")
	eq(v.decks[3].servers, {"ws://other:1": {"id": 9, "at": 5}}, "gone there: kept here, other servers untouched")
	eq([v.decks[5].hero, v.server_id(v.decks[5])], ["HERO_01", 5], "from another device, with its id")
	eq(DeckStore.load_all().size(), 6, "saved")
	check(_tick(v, 5).button_pressed and not _tick(v, 4).button_pressed, "ticks show which are kept")
	_free(v)


func test_a_refused_save_unticks_and_says_why() -> void:
	var v := _view([_deck("A")])
	_tick(v, 0).button_pressed = true
	v.link.dispatch({"t": "error", "code": "decks_full", "text": "You have 100 decks on this server: delete one first"})
	check(not _tick(v, 0).button_pressed and not v.on_server(v.decks[0]), "not kept")
	eq(v.message.text, "You have 100 decks on this server: delete one first", "the reason")
	_free(v)
