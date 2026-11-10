extends TestCase
## The admin panel's replay player (ui/replay_app.gd): the game id from the address, the replay
## and its pack fetched from the admin API (a fake fetch here), the replay view, the errors.

var urls: Array = []


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## A Classic game the bots played, as the server's replay JSON.
func _replay_text() -> String:
	var m := Match.new()
	m.bot_delay = 0.0
	m.setup({"decks": [{"hero": "HERO_08", "cards": Decks.basic("MAGE")}, {"hero": "HERO_01", "cards": Decks.basic("WARRIOR")}],
		"seed": 5}, [true, true])
	m.start()
	var t := Replay.from_match(m, ["Alice", "Bob"], "casual", 0).to_text()
	m.free()
	return t


## A fetch that answers from a table {url: [code, bytes]} (404 for anything else).
func _fake(answers: Dictionary) -> Callable:
	return func(url: String) -> Dictionary:
		urls.append(url)
		var a: Array = answers.get(url, [404, PackedByteArray()])
		return {"code": a[0], "body": a[1]}


func _app(answers: Dictionary, game := "g1") -> ReplayApp:
	var a := ReplayApp.new()
	a.game_id = game
	a.base = "http://admin.test"
	a.fetch = _fake(answers)
	root().add_child(a)  # (_ready loads: with a fetch that answers at once, before this returns)
	return a


func test_game_id_from_the_address() -> void:
	eq(ReplayApp._query_game("?game=dbfa9fb606aced47"), "dbfa9fb606aced47", "the id")
	eq(ReplayApp._query_game("?x=1&game=a%20b"), "a b", "among others, decoded")
	eq(ReplayApp._query_game(""), "", "none")


func test_loads_the_replay_with_the_pack_here() -> void:
	urls = []
	var text := _replay_text()
	var a := _app({"http://admin.test/admin/api/games/g1/replay": [200, text.to_utf8_buffer()]})
	eq(urls, ["http://admin.test/admin/api/games/g1/replay"], "only the replay: its pack is here")
	check(a.view != null and a.view.is_inside_tree(), "the replay view shows")
	eq(a.view.replay.size(), Replay.from_text(text).size(), "that replay")
	check(not a.status.visible, "no loading text over it")
	var closed := [false]
	a.closed.connect(func(): closed[0] = true)
	(a.view.find_child("ReplayBack", true, false) as Button).pressed.emit()
	check(closed[0], "Back asks the panel to close the player")
	a.free()


func test_fetches_the_pack_it_does_not_have() -> void:
	urls = []
	var text := _replay_text()
	var rules: String = Replay.from_text(text).data.pack
	var classic := Packs.find_rules(rules)
	var bytes := Packs.bytes_of(classic)
	Packs._list = Packs.all().filter(func(p: Pack): return p != classic)  # this device has no Classic
	var pack_url := "http://admin.test/admin/api/pack_files/" + rules
	var a := _app({"http://admin.test/admin/api/games/g1/replay": [200, text.to_utf8_buffer()], pack_url: [200, bytes]})
	eq(urls, ["http://admin.test/admin/api/games/g1/replay", pack_url], "the replay, then its pack by rules hash")
	check(a.view != null, "shown: " + a.status.text)
	var got := Packs.active()
	check(got != classic and got.rules_hash() == rules and not got.builtin(), "the downloaded pack plays it")
	a.free()
	Packs.rescan()
	for p: Pack in Packs.all():
		if not p.builtin() and p.rules_hash() == rules:
			Packs.remove(p)
	# the server does not have it either
	Packs._list = Packs.all().filter(func(p: Pack): return p.rules_hash() != rules)
	a = _app({"http://admin.test/admin/api/games/g1/replay": [200, text.to_utf8_buffer()]})
	eq(a.view, null, "nothing to show")
	check(a.status.visible and a.status.text.contains("This replay needs the game"), "says which game is missing: " + a.status.text)
	a.free()
	Packs.rescan()


func test_errors_stay_on_the_screen() -> void:
	urls = []
	var a := _app({})
	eq(a.view, null, "no view")
	eq(a.status.text, "Cannot load the replay of this game (not on the server)", "a game without a replay")
	a.free()
	a = _app({"http://admin.test/admin/api/games/g1/replay": [401, "{}".to_utf8_buffer()]})
	check(a.status.text.contains("log in to the admin panel again"), "the session ended: " + a.status.text)
	a.free()
	a = _app({"http://admin.test/admin/api/games/g1/replay": [200, "{\"format\": \"other\"}".to_utf8_buffer()]})
	check(a.status.text.begins_with("Cannot load the replay"), "not a replay: " + a.status.text)
	a.free()
	urls = []
	a = _app({}, "")
	eq(urls, [], "no game id: nothing asked")
	check(a.status.text.begins_with("No game to show"), a.status.text)
	a.free()
