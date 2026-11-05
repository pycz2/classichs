extends TestCase
## A game played through a server: its decks are the server's (ServerLink keeps them, DeckStore
## gives them, DeckListView changes them there); "Copy local decks"; an older server.

const URL := "ws://decks.test:7377"


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func _cards(n := 30) -> Array:
	return Decks.basic("MAGE").slice(0, n)


## A logged-in fake server through the probes after login (chats, packs, decks, game_settings),
## with these decks there.
func _link(list := []) -> FakeLink:
	var l := FakeLink.new()
	l.url = URL
	root().add_child(l)
	l.dispatch({"t": "auth", "ok": true, "token": "x", "me": {"user": "anna"}})
	l.dispatch({"t": "chats", "list": []})
	l.dispatch({"t": "packs", "server": [], "mine": []})
	l.dispatch({"t": "decks", "list": list})
	l.dispatch({"t": "game_settings", "games": {}})
	return l


## The deck list of a server game.
func _view(list := []) -> DeckListView:
	DeckStore.link = _link(list)
	var v := DeckListView.new()
	root().add_child(v)
	return v


func _free(v: DeckListView) -> void:
	var l := v.link
	v.free()
	l.free()
	DeckStore.link = null


func _sent(v: DeckListView, t: String) -> Array:
	return (v.link as FakeLink).of(t)


func test_the_probes_after_login_learn_what_the_server_keeps() -> void:
	var l := _link([{"id": 1, "pack": Packs.CLASSIC, "name": "Mine", "hero": "HERO_08", "cards": _cards(), "updated": 5},
		{"id": 2, "pack": "org.other.game", "name": "Other", "hero": "HERO_08", "cards": _cards(), "updated": 5}])
	eq(l.sent.map(func(m): return m.t), ["chats", "packs", "decks", "game_settings"], "asked one after another")
	check(l.has_decks and l.has_settings, "it keeps decks and settings per game")
	eq(l.decks_of(Packs.active()).map(func(d): return [d.name, d.servers[URL].id]), [["Mine", 1]], "this game's, with their ids")
	DeckStore.link = l
	eq(DeckStore.load_all().map(func(d): return d.name), ["Mine"], "a server game's decks are the server's")
	DeckStore.link = null
	eq(DeckStore.load_all().size(), 10, "this device's are its own")
	l.dispatch({"t": "deck_saved", "deck": {"id": 3, "pack": Packs.CLASSIC, "name": "New", "hero": "HERO_08", "cards": [], "updated": 9}})
	l.dispatch({"t": "deck_deleted", "id": 1})
	eq(l.decks_of(Packs.active()).map(func(d): return d.name), ["New"], "kept up to date")
	l.free()


## An older server: no decks (before 0.32), no settings per game (before 0.40); the probes' refusals are silent.
func test_an_older_server_keeps_no_decks() -> void:
	var l := FakeLink.new()
	l.url = URL
	root().add_child(l)
	var heard := []
	l.message.connect(func(m): heard.append(m.t))
	l.dispatch({"t": "auth", "ok": true, "token": "x", "me": {"user": "anna"}})
	l.dispatch({"t": "chats", "list": []})
	l.dispatch({"t": "packs", "server": [], "mine": []})
	l.dispatch({"t": "error", "code": "bad_request", "text": "unknown variant decks"})
	check(not l.has_decks and not l.has_settings, "no decks there (before 0.32), so no settings either")
	eq(l.sent.back().t, "decks", "nothing more asked")
	var l2 := FakeLink.new()  # 0.32: decks, no settings per game
	l2.url = URL
	root().add_child(l2)
	l2.message.connect(func(m): heard.append(m.t))
	for msg in [{"t": "auth", "ok": true, "token": "x", "me": {"user": "anna"}}, {"t": "chats", "list": []},
			{"t": "packs", "server": [], "mine": []}, {"t": "decks", "list": []},
			{"t": "error", "code": "bad_request", "text": "unknown variant game_settings"}]:
		l2.dispatch(msg)
	check(l2.has_decks and not l2.has_settings, "decks, no settings")
	check(not heard.has("error"), "nobody is told about the probes: %s" % [heard])
	l2.free()
	var m: Node = load("res://ui/main.tscn").instantiate()
	m.server_link = l
	root().add_child(m)
	m.mode = "server"
	l.has_decks = false
	m.enter_game(Packs.active())
	check(DeckStore.link == null, "a server without decks: the game's decks stay on this device")
	m.free()
	DeckStore.link = null


func test_every_change_goes_to_the_server() -> void:
	var v := _view([{"id": 7, "pack": Packs.CLASSIC, "name": "A", "hero": "HERO_08", "cards": _cards(10), "updated": 50}])
	var local := DeckStore.count_local(Packs.CLASSIC)
	eq(v.decks.map(func(d): return d.name), ["A"], "the server's decks of this game")
	check(v.find_child("Server", true, false) == null, "no ticks: every deck is the server's")
	v.edit_deck(0)
	v.browser.click_card("VAN_CS2_029")
	var s: Array = _sent(v, "deck_save")
	eq([s[-1].id, s[-1].deck.cards.size(), s[-1].get("pack")], [7, 11, null], "a card added: saved there by its id")
	v.remove_card("VAN_CS2_029")
	eq(_sent(v, "deck_save")[-1].deck.cards.size(), 10, "a card removed")
	v._name_edit.text_changed.emit("Fire")
	eq(_sent(v, "deck_save")[-1].deck.name, "Fire", "renamed")
	v.close_deck()
	var d := v.new_deck("HERO_01")
	var new: Dictionary = _sent(v, "deck_save")[-1]
	check(not new.has("id") and new.has("ref"), "a new deck: a new one there")
	v.link.dispatch({"t": "deck_saved", "ref": new.ref, "deck": {"id": 8, "pack": Packs.CLASSIC, "name": d.name,
		"hero": "HERO_01", "cards": [], "updated": 60}})
	eq(v.server_id(d), 8, "with its id there")
	v.close_deck()
	v.delete_deck(0)
	eq(_sent(v, "deck_delete"), [{"t": "deck_delete", "id": 7}], "deleted there")
	eq(DeckStore.count_local(Packs.CLASSIC), local, "this device's decks untouched")
	_free(v)


func test_a_refused_save_says_why() -> void:
	var v := _view()
	v.new_deck("HERO_08")
	v.close_deck()
	v.link.dispatch({"t": "error", "code": "decks_full", "text": "You have 100 decks on this server: delete one first"})
	eq(v.decks.size(), 0, "not kept")
	eq(v.message.text, "You have 100 decks on this server: delete one first", "the reason")
	_free(v)


## "Copy local decks": the decks of this device made in a game of the same rules, ticked, copied there.
func test_copy_local_decks() -> void:
	var v := _view()
	check(v.find_child("CopyLocalDecks", true, false) != null, "the button in a server game")
	v.show_copy_local()
	var ticks := v.find_child("LocalDecks", true, false).get_children()
	eq(ticks.size(), 10, "this device's ten decks of this game")
	(ticks[0] as CheckBox).button_pressed = true
	(ticks[7] as CheckBox).button_pressed = true
	(v.find_child("DoCopy", true, false) as Button).pressed.emit()
	var s: Array = _sent(v, "deck_save")
	eq(s.map(func(m): return m.deck.name), ["Control Warrior", "Freeze Mage"], "the ticked ones, copied")
	check(s.all(func(m): return m.has("ref") and not m.has("id")), "as new decks there")
	eq(v.decks.size(), 2, "in the list")
	eq(DeckStore.count_local(Packs.CLASSIC), 10, "still here too")
	_free(v)
	var alone := DeckListView.new()
	root().add_child(alone)
	check(alone.find_child("CopyLocalDecks", true, false) == null, "not without a server")
	alone.free()


## The pack's decks of the same rules are offered, another game's are not.
func test_copy_offers_only_the_same_rules() -> void:
	var v := _view()
	DeckStore.write(DeckStore.file("neon"), [{"name": "Neon deck", "hero": "iris_null", "cards": []}])
	eq(v.local_decks().size(), 10, "Classic's only")
	DirAccess.remove_absolute(DeckStore.file("neon"))
	_free(v)


## A deck kept on the server is queued without this device's notes about it (servers: the
## server refused the field, and the search never ended); a refused queue stops the search.
func test_a_server_deck_is_queued_and_a_refusal_stops_the_search() -> void:
	var l := _link([{"id": 4, "pack": Packs.CLASSIC, "name": "Mine", "hero": "HERO_08", "cards": _cards(), "updated": 5}])
	var v := ServerView.new()
	v.link = l
	root().add_child(v)
	var classic: Pack = Packs.all().filter(func(p): return p.id() == Packs.CLASSIC)[0]
	v.deck = l.decks_of(classic)[0]
	check(not v.deck.servers.is_empty(), "the deck knows its server")
	v.queue("ranked")
	var sent: Dictionary = l.of("queue").back().deck
	eq(sent.keys(), ["name", "hero", "cards"], "only what the server takes")
	eq(v.queued, "ranked", "searching")
	l.dispatch({"t": "error", "code": "bad_request", "text": "unknown field"})
	eq(v.queued, "", "refused: no longer searching")
	v.free()
	l.free()
