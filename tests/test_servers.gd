extends TestCase
## Several game servers (D14), one login per account (D15) and the server's game packs:
## the list in the settings, a connection and a saved session per server, `kicked`,
## the friends overlay per server, the packs list, download, upload and the `pack` field.

const ME := {"user": "anna", "tag": "Moon7", "arena": null, "season": "2026-10",
	"rank": {"rank": 18.0, "stars": 1.0, "streak": 0.0, "legend": null}}
const A := "ws://a.test:7377"
const B := "wss://b.test"


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _two_servers() -> void:
	Settings.data.servers = [{"url": A, "name": "Alpha"}, {"url": B, "name": "Beta"}]
	Settings.save()  # main reads the settings


## main with a fake connection per server.
func _main() -> Node:
	var m: Node = load("res://ui/main.tscn").instantiate()
	for e in Settings.data.servers:
		var l := FakeLink.new()
		l.url = e.url
		m.server_links.append(l)
	root().add_child(m)
	return m


func _login(l: FakeLink, user := "anna") -> void:
	var me := ME.duplicate(true)
	me.user = user
	l.dispatch({"t": "auth", "ok": true, "token": "tok-" + user, "me": me})
	l.dispatch({"t": "friends", "list": [{"user": "bob", "tag": "Bob1", "online": true, "status": "online"}],
		"requests_in": [], "requests_out": [], "blocked": []})


func test_settings_migrate_the_old_server_and_check_the_list() -> void:
	var f := FileAccess.open(Settings.path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"language": "en", "server": "wss://old.example:9000"}))
	f.close()
	Settings.load_settings()
	eq(Settings.data.servers, [{"url": "wss://old.example:9000", "name": "old.example"}], "the old address becomes the list")
	f = FileAccess.open(Settings.path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"language": "en", "servers": [{"url": A, "name": " Alpha "}, {"url": "http://bad"}, {"url": A}, {"url": B}]}))
	f.close()
	Settings.load_settings()
	eq(Settings.data.servers, [{"url": A, "name": "Alpha"}, {"url": B, "name": "b.test"}], "bad and repeated addresses dropped, names trimmed")
	eq(Settings.server_name(B), "b.test")
	DirAccess.remove_absolute(Settings.path)
	Settings.load_settings()
	eq(Settings.data.servers, [], "no server by default: the game plays without one, a server is added later")


## A first start with no server: the menu opens, nothing connects; the lobby button leads
## to the list where a server is added, and main makes its connection then.
func test_main_starts_without_a_server_and_one_is_added_later() -> void:
	var f := FileAccess.open(Settings.path, FileAccess.WRITE)  # no "servers": the default list
	f.store_string(JSON.stringify({"language": "en"}))
	f.close()
	Settings.load_settings()
	var m := _main()
	eq(m.server_links, [], "no connection")
	check(m.server_link == null, "no lobby server")
	check(m.screen is MainMenu, "the menu, not a wait for a server")
	eq(m.show_server(), null, "no server: no lobby")
	check(m.screen is SettingsView and m.screen.find_child("ServerList", true, false) != null, "the list to add one")
	check(m.screen.add_server("Mine", "wss://mine.example"), "added")
	eq(m.show_server().link.url, "wss://mine.example", "its lobby")
	eq(m.server_links.map(func(l): return l.url), ["wss://mine.example"], "and its connection")
	m.free()


func test_old_saved_session_is_read_as_its_server() -> void:
	var f := FileAccess.open(ServerLink.session_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"token": "t1", "server": A, "deck": {"name": "D", "hero": "HERO_08"}, "tab": "Arena"}))
	f.close()
	eq(ServerLink.saved_for(A), {"token": "t1", "deck": {"name": "D", "hero": "HERO_08"}, "tab": "Arena"}, "the old file is A's session")
	ServerLink.remember_for(B, {"token": "t2"})
	var all := ServerLink.saved_all()
	eq([all.servers.keys(), all.servers[A].token, all.servers[B].token], [[A, B], "t1", "t2"], "rewritten keyed by address")
	ServerLink.forget(A)
	eq(ServerLink.saved_for(A), {}, "forgotten")


## Each server gets its own connection and resumes its own session; a kicked one waits.
func test_main_keeps_a_connection_per_server() -> void:
	_two_servers()
	Settings.data.servers.append({"url": "ws://c.test", "name": "Gamma"})
	Settings.save()
	ServerLink.remember_for(A, {"token": "ta"})
	ServerLink.remember_for(B, {"token": "tb"})
	ServerLink.remember_for("ws://c.test", {"token": "tc", "kicked": true})
	ServerLink.remember_last(B)
	var m := _main()
	var ls: Array = m.server_links
	eq(ls.map(func(l): return l.url), [A, B, "ws://c.test"], "a connection per server")
	eq(ls.map(func(l): return l.resuming), [true, true, false], "each resumes its own session; the kicked one does not")
	eq(m.server_link, ls[1], "the server chosen last is the lobby's")
	ls[0].opened.emit()
	eq(ls[0].of("resume"), [{"t": "resume", "token": "ta"}], "A's token to A")
	var c: FakeLink = ls[2]
	Settings.data.servers.remove_at(2)
	m.show_menu()
	eq([m.server_links.size(), c.up], [2, false], "a removed server's connection is closed")
	Settings.data.servers.append({"url": "ws://d.test", "name": "Delta"})
	m.show_menu()
	eq(m.server_links.back().url, "ws://d.test", "an added one gets its connection")
	var v: ServerView = m.show_server()
	check(v.find_child("ServerPick", true, false) != null, "several servers: a picker in the lobby")
	(v.find_child("ServerPick", true, false) as OptionButton).item_selected.emit(0)
	eq([m.server_link, ServerLink.last(), (m.screen as ServerView).link], [ls[0], A, ls[0]], "another server picked")
	m.free()


## D15: a second login elsewhere kicks this one: the session is kept but marked, no resume
## by itself, a notice; logging in again clears it.
func test_kicked_marks_the_session_and_waits_for_the_player() -> void:
	Settings.data.servers = [{"url": A, "name": "Alpha"}]
	Settings.save()
	var m := _main()
	var l: FakeLink = m.server_link
	_login(l)
	m.social._process(0.0)
	l.dispatch({"t": "kicked", "reason": "another_login"})
	eq([l.token, l.kicked, l.saved().get("kicked"), l.saved().get("token")], ["", true, true, "tok-anna"], "marked, the token kept on disk only")
	check(m.social._toast.visible and m.social._toast.text.contains(tr("You logged in on another device")), "the notice: " + m.social._toast.text)
	l.up = false
	m.social._process(0.0)
	eq([m.social.button.visible, m.social.visible], [false, true], "logged out; the notice stays")
	eq(l.can_resume(), false, "no resume by itself")
	var r := FakeLink.new()
	r.open_and_resume(A)
	eq(r.resuming, false, "not on the next start either")
	r.free()
	l.up = true
	var v: ServerView = m.show_server()
	eq(v.stage, "login", "the lobby asks")
	var here := v.find_child("PlayHere", true, false) as Button
	check(here != null, "Play here offered")
	here.pressed.emit()
	eq(l.of("resume"), [{"t": "resume", "token": "tok-anna"}], "the saved session on demand")
	l.dispatch({"t": "auth", "ok": true, "token": "tok-anna", "me": ME})
	eq([l.kicked, l.saved().get("kicked"), l.can_resume()], [false, null, true], "a login clears it")
	l.dispatch({"t": "kicked", "reason": "another_login"})
	eq([(m.screen as ServerView).stage, (m.screen as ServerView)._status.text], ["login", tr("You logged in on another device")], "the lobby says so")
	m.free()


## Each server has its own friends and chats; with one logged in the panel has no tabs.
func test_social_keeps_each_server_apart() -> void:
	_two_servers()
	var m := _main()
	var a: FakeLink = m.server_links[0]
	var b: FakeLink = m.server_links[1]
	var s: Social = m.social
	_login(a)
	s._process(0.0)
	s.button.pressed.emit()
	eq(s.find_child("ServerTabs", true, false).visible, false, "one server: no tabs")
	_login(b, "anna2")
	b.dispatch({"t": "friends", "list": [{"user": "zed", "tag": null, "online": true, "status": "in_game"}],
		"requests_in": [], "requests_out": [], "blocked": []})
	s._process(0.0)
	s.rebuild_panel()
	var tabs := s.find_child("ServerTabs", true, false)
	eq([tabs.visible, tabs.get_child_count()], [true, 2], "a tab per server")
	eq(s.friends.list.map(func(f): return f.user), ["bob"], "the panel shows A")
	eq(s.online_count(), 2, "the button counts friends on both servers")
	(tabs.get_child(1) as Button).pressed.emit()
	eq(s.friends.list.map(func(f): return f.user), ["zed"], "B's friends")
	b.dispatch({"t": "msg", "from": "bob", "text": "hi from B", "at": 1.0})
	var w := s.find_child("Chat_bob" + ("@" + B).validate_node_name(), true, false) as Social.ChatWindow
	check(w != null and w.srv.link == b, "B's bob has his own window")
	check(s.find_child("Chat_bob", true, false) == null, "A's bob has none")
	w.input.text_submitted.emit("hello")
	eq([a.of("msg").size(), b.of("msg")], [0, [{"t": "msg", "to": "bob", "text": "hello"}]], "the answer goes to B")
	a.dispatch({"t": "invite", "from": "bob"})
	(s.find_child("InviteDecline", true, false) as Button).pressed.emit()
	eq([a.of("invite_decline").size(), b.of("invite_decline").size()], [1, 0], "the invite answered on its server")
	m.free()


func test_packs_list_and_download() -> void:
	var l := FakeLink.new()
	l.url = "ws://h.test:7377"
	l.dispatch({"t": "auth", "ok": true, "token": "x", "me": ME})
	l.dispatch({"t": "chats", "list": []})
	eq(l.of("packs").size(), 1, "the packs asked after the chats")
	l.dispatch({"t": "error", "code": "bad_request", "text": "unknown variant `packs`"})
	eq(l.has_packs, false, "a server without packs: no error shown")
	eq([l.http_base(), _base("wss://x.org/ws"), _base("ws://[::1]:7")], ["http://h.test:7377", "https://x.org", "http://[::1]:7"])
	var bytes := FileAccess.get_file_as_bytes("res://packs/neon.cardpack")
	var n0: Pack = null
	for p in Packs.all():
		if p.builtin() and p.id() != Packs.CLASSIC:
			n0 = p
	var entry := {"id": "neon", "name": {"en": "Neonfall"}, "version": "1.0.0", "rules_hash": n0.rules_hash(), "content_hash": Packs.content_hash(n0),
		"size": bytes.size(), "url": "/packs/x.cardpack"}
	var changed := [0]
	l.packs_changed.connect(func(): changed[0] += 1)
	l.dispatch({"t": "packs", "server": [entry], "mine": []})
	eq([changed[0], l.packs.server.size(), l.has_packs], [1, 1, true], "the list and the signal")
	var neon := ServerLink.local_pack(entry)
	check(neon != null and neon.builtin() and neon.id() != Packs.CLASSIC, "the same pack is the player's (by the hashes of format.md)")
	eq(ServerLink.local_pack({"rules_hash": entry.rules_hash, "content_hash": "other art"}), neon, "the same rules will do")
	eq(ServerLink.local_pack({"rules_hash": "other rules", "content_hash": entry.content_hash}), null, "other rules will not")
	eq(l.server_pack_for(neon), entry, "the server's entry of a pack the player has")
	var got := []
	l.pack_downloaded.connect(func(h, res): got.append([h, res]))
	l.download_pack(entry)
	eq([l.http.size(), l.http[0].path, l.http[0].method], [1, "/packs/%s.cardpack" % entry.content_hash, HTTPClient.METHOD_GET], "GET the file")
	l.http[0].done.call(200, bytes.slice(0, 1000))
	eq([got[0][0], got[0][1].get("error")], [entry.content_hash, tr("The download is damaged: try again")], "a broken file is refused")
	l.download_pack(entry)
	l.http[1].done.call(200, bytes)
	check(got[1][1].get("pack") is Pack and got[1][1].pack.id() == neon.id(), "installed (already there: the same pack)")
	l.download_pack(entry)
	l.http[2].done.call(401, PackedByteArray())
	eq(got[2][1].get("error"), tr("Log in to the server again"), "401")
	l.dispatch({"t": "logged_out"})
	eq([l.packs, changed[0]], [{"server": [], "mine": []}, 2], "cleared on logout")
	l.free()


func _base(url: String) -> String:
	var l := ServerLink.new()
	l.url = url
	var b := l.http_base()
	l.free()
	return b


func test_upload_answers() -> void:
	var l := FakeLink.new()
	l.url = A
	l.token = "tk"
	var got := []
	l.pack_uploaded.connect(func(r): got.append(r))
	l.upload_pack(Packs.active())
	eq([l.http[0].path, l.http[0].method, l.http[0].body.size() > 0], ["/packs", HTTPClient.METHOD_POST, true], "POST the file")
	var answers := [[409, {"error": "This pack is uploaded already", "code": "exists"}], [409, {"error": "10 packs", "code": "too_many"}],
		[413, {"error": "big", "code": "too_large"}], [422, {"error": "manifest.json: id must be …", "code": "invalid"}],
		[400, {"error": "Send the file", "code": "empty"}], [401, {"error": "x", "code": "bad_token"}], [500, {}]]
	for a in answers:
		l.http[0].done.call(a[0], JSON.stringify(a[1]).to_utf8_buffer())
	eq(got.map(func(r): return r.code), ["exists", "too_many", "too_large", "invalid", "empty", "bad_token", "500"])
	eq(got[0].error, tr("You have uploaded this game already"))
	eq(got[3].error, tr("The server refused the game: %s") % "manifest.json: id must be …", "the server's reason")
	l.http[0].done.call(201, JSON.stringify({"pack": {"id": "x", "content_hash": "h"}}).to_utf8_buffer())
	eq(got.back(), {"pack": {"id": "x", "content_hash": "h"}}, "201: the server's entry")
	l.delete_pack("h")
	eq(l.of("pack_delete"), [{"t": "pack_delete", "content_hash": "h"}])
	l.free()


## `pack` stays out of the messages until the server takes it (phase D); a game the server
## does not play is not queued.
func test_pack_field_and_games_panel() -> void:
	var v := ServerView.new()
	var l := FakeLink.new()
	l.url = A
	v.link = l
	l.dispatch({"t": "auth", "ok": true, "token": "x", "me": ME})
	root().add_child(v)
	eq(ServerView.rank_name(18), CardText.name("VAN_EX1_608"), "Classic ranks are named after their emblem cards")
	eq([ServerView.rank_name(1), ServerView.rank_name(0)], [tr("Innkeeper"), tr("Legend")], "and the pack's names")
	v.queue("casual")
	check(not l.of("queue")[0].has("pack"), "no pack field to a server that lists no packs (it plays its built-in Classic)")
	v.unqueue()
	var neon: Pack = null
	for p in Packs.all():
		if p.builtin() and p.id() != Packs.CLASSIC:
			neon = p
	var bytes := Packs.bytes_of(neon)
	var entry := {"id": neon.id(), "name": {"en": "Neonfall"}, "version": "1", "rules_hash": neon.rules_hash(), "content_hash": "other art", "size": bytes.size()}
	var classic := {"id": Packs.CLASSIC, "name": {"en": "Classic"}, "version": "1", "rules_hash": Packs.all()[0].rules_hash(), "content_hash": "c1", "size": 1}
	l.dispatch({"t": "packs", "server": [classic], "mine": []})
	v.queue("casual")
	eq(l.of("queue")[1].get("pack"), Packs.all()[0].rules_hash(), "the rules hash of the game goes with the queue")
	v.unqueue()
	l.dispatch({"t": "packs", "server": [entry], "mine": [{"id": "own", "name": {"en": "Mine"}, "version": "2", "rules_hash": "q", "content_hash": "c0ffee", "size": 10, "enabled": true}]})
	eq(l.game_problem(Packs.all()[0]), tr("This server does not have this game"), "a server with packs, without Classic")
	(v.find_child("GamesButton", true, false) as Button).pressed.emit()
	var panel := v.find_child("GamesPanel", true, false)
	check(panel != null, "the server's games")
	var row := panel.find_child("Game_" + entry.content_hash.left(12), true, false)
	(row.find_child("Use", true, false) as Button).pressed.emit()
	eq(Packs.active().id(), neon.id(), "Use switches the active game")
	eq(l.of("me").back(), {"t": "me", "pack": neon.rules_hash()}, "and asks for the rank in it")
	check(v.find_child("GamesPanel", true, false).find_child("Game_" + entry.content_hash.left(12), true, false).find_child("Use", true, false) == null, "in use now")
	eq(l.game_problem(neon), "", "listed: played here")
	v.queue("casual")
	eq(l.of("queue").back().get("pack"), neon.rules_hash(), "queued in it")
	v.unqueue()
	var mine := v.find_child("Game_c0ffee", true, false)
	check(mine.find_child("Download", true, false) != null, "not installed: Download")
	(mine.find_child("Delete", true, false) as Button).pressed.emit()
	eq(l.of("pack_delete").size(), 0, "the first press only asks")
	(v.find_child("Game_c0ffee", true, false).find_child("Delete", true, false) as Button).pressed.emit()
	eq(l.of("pack_delete"), [{"t": "pack_delete", "content_hash": "c0ffee"}], "the second deletes")
	Packs.set_active(Packs.all()[0])
	v.free()
	l.free()


## The settings' server list: add, rename, log out, remove.
func test_settings_server_list() -> void:
	Settings.data.servers = [{"url": "ws://localhost:7377", "name": "localhost"}]
	var s := SettingsView.new()
	root().add_child(s)
	(s.find_child("Servers", true, false) as Button).pressed.emit()
	var box := s.find_child("ServerList", true, false)
	check(box != null, "the list opens")
	eq(s.add_server("Mine", "http://nope"), false, "only ws:// or wss://")
	eq(s.add_server("Mine", "wss://mine.example"), true)
	eq(Settings.data.servers.map(func(e): return e.name), ["localhost", "Mine"], "added")
	var row := s.find_child("Server1", true, false)
	var name_ed := row.find_child("Name", true, false) as LineEdit
	name_ed.text = "Home"
	name_ed.text_submitted.emit("Home")
	eq(Settings.data.servers[1].name, "Home", "renamed")
	ServerLink.remember_for("wss://mine.example", {"token": "t"})
	s.show_servers()
	row = s.find_child("Server1", true, false)
	eq((row.find_child("Who", true, false) as Label).text, tr("Logged in"))
	(row.find_child("Logout", true, false) as Button).pressed.emit()
	eq(ServerLink.saved_for("wss://mine.example").get("token"), null, "logged out")
	row = s.find_child("Server1", true, false)
	(row.find_child("Remove", true, false) as Button).pressed.emit()
	eq(Settings.data.servers.size(), 2, "the first press only asks")
	(row.find_child("Remove", true, false) as Button).pressed.emit()
	eq(Settings.data.servers.map(func(e): return e.url), ["ws://localhost:7377"], "removed")
	s.free()
