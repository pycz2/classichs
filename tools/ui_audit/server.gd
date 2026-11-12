extends RefCounted
## Everything through a game server, against the audit's own server (AUDIT_SERVER, default ws://127.0.0.1:7391:
## invite-only, the key AUDIT_KEY, auto-bots after a few seconds) and its second player (tools/ui_audit/
## server_peer.gd: Peer_Bob, commands through AUDIT_PEER_CMD): the connections, the login and its errors,
## registering with an invite key, the server's home, friends and chat, watching a friend's game, a friendly
## invite, the game menu, the lobby (casual, ranked, the search), a ranked game and its result, the Arena (ticket,
## heroes, draft, run, a game), tournaments (the form, a page, bots, the deck picker, the bracket, the match
## panel, a tournament game), a lost connection and a login from another device. Each pass (a language and a
## size) registers its own account (Aud<n>).

var url := OS.get_environment("AUDIT_SERVER") if OS.get_environment("AUDIT_SERVER") != "" else "ws://127.0.0.1:7391"
var key := OS.get_environment("AUDIT_KEY") if OS.get_environment("AUDIT_KEY") != "" else "audit-key-0001"
var peer_cmd := OS.get_environment("AUDIT_PEER_CMD") if OS.get_environment("AUDIT_PEER_CMD") != "" else "/tmp/uiaudit-server/peer_cmd"
var db := OS.get_environment("AUDIT_DB") if OS.get_environment("AUDIT_DB") != "" else "/tmp/uiaudit-server/audit.db"
const PEER := "Peer_Bob"
const PASSWORD := "audit password 1"
var n := 0  # the pass
var a  # the audit (tools/ui_audit.gd)
var m: Node
var user := ""
var link: ServerLink


func run(audit) -> void:
	a = audit
	n += 1
	user = "Aud%d%d%s" % [int(Time.get_unix_time_from_system()) % 100000, n, a.lang]  # (new on every run)
	var servers := [
		{"id": url, "url": url, "name": "Аудит" if a.lang == "ru" else "Audit"},
		{"id": "wss://hearthstone-classic-tournaments.very-long-domain-name.example.org:7377/play",
			"url": "wss://hearthstone-classic-tournaments.very-long-domain-name.example.org:7377/play", "name": "Турниры по выходным у Вадима и Кати"},
		{"id": "ws://127.0.0.1:1", "url": "ws://127.0.0.1:1", "name": "Old LAN"},
	]
	DirAccess.remove_absolute(ServerLink.session_path)  # no saved login: this pass logs in by hand
	m = await a.open(null, {"servers": servers})
	await _connections(servers)
	if not await _login(servers[0].id):
		a.error("pass %d: no login, the rest skipped" % n)
		return
	link = m.server_link
	await _home()
	await _friends()
	await _lobby()
	await _arena()
	await _tournaments()
	await _lost()


func t(s: String) -> String:
	return TranslationServer.translate(s)


func peer(line: String) -> void:
	var f := FileAccess.open(peer_cmd, FileAccess.READ_WRITE)
	if f == null:
		a.error("no peer command file " + peer_cmd)
		return
	f.seek_end()
	f.store_line(line)
	f.close()


## Waits until cond() is true (false after the time).
func until(cond: Callable, seconds := 20.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > seconds * 1000:
			return false
		await a.process_frame
	return true


func find(name: String) -> Node:
	return m.find_child(name, true, false)


# --- connections, login ----------------------------------------------------------------------

func _connections(servers: Array) -> void:
	var c: ConnectionsView = m.show_connections()
	await a.settle(1.5)
	await a.shot("connections", "Game servers: three connections (one with a long name and address, one unreachable)")
	(c.find_child("NewName", true, false) as LineEdit).text = "Сервер моего друга из соседнего подъезда" if a.lang == "ru" else "My friend's server from next door"
	(c.find_child("NewUrl", true, false) as LineEdit).text = "not a server address"
	c.add_server((c.find_child("NewName", true, false) as LineEdit).text, "not a server address")
	await a.settle(0.4)
	await a.shot("connections_add_bad", "Adding a server with a wrong address (the address turns red)")
	var rm := c.find_child("Server1", true, false).find_child("Remove", true, false) as Button
	rm.pressed.emit()
	await a.settle(0.3)
	await a.shot("connections_remove_armed", "Remove pressed once: \"Remove? Press again\"")
	m.open_connection(servers[2].id)
	await a.settle(2.5)
	await a.shot("login_unreachable", "Opening an unreachable server (ws://127.0.0.1:1)")


func _login(id: String) -> bool:
	m.open_connection(id)
	var ok := await until(func(): return m.screen is ServerView and m.screen.stage == "login" and m.server_link.signup_asked and m.server_link.invite_only, 15.0)
	await a.settle(0.8)
	if not ok:
		a.error("pass %d: no invite-only login form" % n)
	await a.shot("login_form", "The login of an invite-only server: name, password, invite key")
	var v: ServerView = m.screen
	var status := v.find_child("Status", true, false) as Label
	var cases := [["login", PEER, "wrong password 123", "", "login_wrong_password", "Logging in with a wrong password"],
		["register", PEER, PASSWORD, key, "register_taken", "Registering a name that is taken"],
		["register", user, PASSWORD, "not-a-real-invite-key", "register_bad_key", "Registering with a wrong invite key"],
		["register", user, PASSWORD, "", "register_no_key", "Registering without the invite key"],
		["login", "ab", "short", "", "login_short", "A name and password that are too short"]]
	for c in cases:
		(v.find_child("User", true, false) as LineEdit).text = c[1]
		(v.find_child("Password", true, false) as LineEdit).text = c[2]
		(v.find_child("InviteKey", true, false) as LineEdit).text = c[3]
		status.text = ""
		v.log_in(c[0], c[1], c[2], c[3])
		await until(func(): return status.text != "" and status.text != t("Connecting…"), 8.0)
		await a.settle(0.3)
		await a.shot(c[4], c[5])
	(v.find_child("User", true, false) as LineEdit).text = user
	(v.find_child("InviteKey", true, false) as LineEdit).text = key
	v.log_in("register", user, PASSWORD, key)
	if not await until(func(): return m.screen is ServerHome, 15.0):
		a.error("pass %d: registering %s failed: %s" % [n, user, status.text if is_instance_valid(status) else "?"])
		return false
	return true


# --- the server's home, friends --------------------------------------------------------------

func _home() -> void:
	await until(func(): return not m.server_link.packs.server.is_empty(), 10.0)
	await a.settle(1.0)
	await a.shot("server_home", "The server's home: the player, Friends, the server's games")
	var scroll: Array = m.screen.find_children("*", "ScrollContainer", true, false)
	if not scroll.is_empty():
		scroll[0].scroll_vertical = 100000
		await a.wait(0.4)
		await a.shot("server_home_bottom", "The server's home scrolled to the end of its games")
	m.screen.show_upload()
	await a.settle(0.4)
	await a.shot("server_home_upload", "The server's home: Upload a game")
	var up: Node = m.screen.find_child("UploadPanel", true, false)
	if up:
		up.free()
	var dl: String = ["gvg-2014", "brm-2015", "tgt-2015", "loe-2015", "og-2016", "kara-2016"][(n - 1) % 6]
	for e in m.screen.entries():
		if str(e.get("id", "")) == dl and ServerLink.local_pack(e) == null:
			m.server_link.download_pack(e)
			m.screen._build()
			await a.wait(0.8)
			await a.shot("server_home_downloading", "The server's home while a game downloads")
			break


func _friends() -> void:
	var s: Social = m.social
	s.show_panel(true)
	await a.settle(0.6)
	await a.shot("friends_no_tag", "Friends, a new account: no tag yet")
	var tag := user.to_lower()
	link.send({"t": "set_tag", "tag": tag})
	link.request_me()
	await until(func(): return str(link.me.get("tag", "")) != "", 5.0)
	s.rebuild_panel()
	await a.settle(0.6)
	await a.shot("friends_tag", "Friends: the tag is set")
	peer("add " + tag)
	await until(func(): return not s.friends.get("requests_in", []).is_empty(), 10.0)
	await a.settle(0.5)
	await a.shot("friends_request", "A friend request came (a toast and the request in the list)")
	link.send({"t": "friend_accept", "user": PEER})
	await until(func(): return s.friends.get("list", []).size() > 0, 10.0)
	await until(func(): return s.status.get(PEER, "") == "in_game", 40.0)
	await a.settle(0.6)
	await a.shot("friends_list", "Friends: Peer_Bob is a friend, in a game (Watch)")
	var row := s.find_child("Friend_" + PEER, true, false) as Control
	if row:
		s._more(PEER, row)
		await a.wait(0.5)
		await a.shot("friends_more", "A friend's More menu (Remove, Block)")
		var menu := s.find_child("FriendMenu", true, false)
		if menu:
			menu.hide()
	var long_ru := "Привет! Сыграем после этого матча? У меня новая колода на кобольдах и катакомбах, хочу проверить её против твоего жреца с Нефритовым големом, а ещё рассказать про турнир в субботу вечером."
	var long_en := "Hi! Shall we play after this match? I have a new Kobolds and Catacombs deck and want to try it against your Jade priest, and also tell you about the tournament on Saturday evening."
	peer("chat %s %s" % [user, long_ru if a.lang == "ru" else long_en])
	await until(func(): return s.chats.get(PEER, []).size() > 0 or s.unread.get(PEER, 0) > 0, 10.0)
	await a.settle(0.5)
	await a.shot("chat_message_came", "A friend's message came")
	s.open_chat(PEER, true)
	s.send_message(PEER, "Давай! Только сначала доиграю арену, у меня уже семь побед подряд, а это рекорд." if a.lang == "ru" else "Sure! Let me finish my Arena run first, I have seven wins in a row, my best ever.")
	await a.settle(0.8)
	await a.shot("chat", "A chat window with long messages")
	# watching the friend's game
	s.watch(PEER)
	if await until(func(): return m.watch_view != null, 15.0):
		await a.settle(2.5)
		await a.shot("watch", "Watching a friend's game")
		m.close_watch()
		await a.settle(0.6)
	else:
		a.error("pass %d: no spectator table" % n)
	# a friendly invite from the friend
	for k in s.open_chats.duplicate():
		s.close_chat(k)
	peer("idle")
	await until(func(): return s.status.get(PEER, "") in ["online", "searching"], 30.0)
	peer("invite " + user)
	if await until(func(): return s.find_child("InviteDialog", true, false) != null or s.invite_from != "", 15.0):
		await a.settle(0.8)
		await a.shot("invite", "A friend invites to a friendly game")
		s.answer_invite(false)
		await a.settle(0.3)
	else:
		a.error("pass %d: no invite came" % n)
	peer("play")
	s.show_panel(false)


# --- the game: menu, lobby, a ranked game -------------------------------------------------------

func _lobby() -> void:
	var loot: Pack = a.main_pack
	m.enter_game(loot)
	await a.settle(1.2)
	await a.shot("game_menu_server", "The game's menu through a server (Play, Tournaments)")
	# the decks: the server's (none yet), then this device's copied there
	DeckStore.write(DeckStore.file(), Decks.templates().map(func(x): return x.deck.to_dict().merged({"name": x.name}, true)))
	m.show_collection()
	await a.settle(1.0)
	var dl: DeckListView = m.screen
	await a.shot("server_decks_empty", "The Collection through a server: no decks on the server yet")
	dl.show_copy_local()
	await a.settle(0.5)
	await a.shot("server_copy_local", "Copy local decks to the server")
	dl._close()
	dl.copy_local(dl.local_decks().map(func(x): return x.deck))
	await until(func(): return dl._pending.is_empty(), 20.0)
	await a.settle(0.8)
	await a.shot("server_decks", "The Collection through a server: the decks copied")
	m.show_game_menu()
	var v: ServerView = m.show_server()
	await a.settle(1.0)
	v.set_mode("casual")
	await a.settle(0.6)
	await a.shot("lobby_casual", "The lobby: Casual, the deck box, Play")
	v.set_mode("ranked")
	await a.settle(0.6)
	await a.shot("lobby_ranked", "The lobby: Ranked with the rank")
	v.queue("ranked")
	await a.wait(3.2)
	await a.shot("lobby_searching", "The lobby: searching for an opponent (ranked)")
	if not await until(func(): return m.screen is MatchView, 40.0):
		a.error("pass %d: no ranked game started" % n)
		return
	await _play_a_bit("server_game", "A ranked game through the server")
	m.screen.lobby_back.emit()
	await a.settle(1.5)
	await a.shot("lobby_after_game", "The lobby after a lost ranked game (the result and the rank)")


## The game on the screen now: the mulligan, a turn, then conceded and its result.
func _play_a_bit(name: String, note: String) -> void:
	var v: MatchView = m.screen
	await a.settle(2.0)
	await a.shot(name + "_mulligan", note + ": the mulligan")
	var c: Match = v.controller
	c.submit({"type": "mulligan", "player": c.viewer(), "replace": []})
	await until(func(): return c.game.players[c.viewer()].mulliganed and c.game.players[1 - c.viewer()].mulliganed, 20.0)
	await until(func(): return c.game.current == c.viewer() and not c.waiting(), 30.0)
	await a.settle(2.0)
	await a.shot(name, note + ": the player's turn")
	c.submit({"type": "concede", "player": c.viewer()})
	await until(func(): return c.game.game_over, 15.0)
	await a.wait(4.0)
	await a.shot(name + "_result", note + ": the result after a concede")


# --- the Arena -------------------------------------------------------------------------------

func _arena() -> void:
	var v: ServerView = m.screen if m.screen is ServerView else m.show_server()
	v.tab = "Arena"
	v._go("lobby")
	await a.settle(0.8)
	await a.shot("arena_ticket", "The Arena on the server: the ticket")
	link.send(link.with_pack({"t": "arena_start"}))
	if not await until(func(): return not v.arena.get("heroes", []).is_empty(), 10.0):
		a.error("pass %d: no Arena heroes" % n)
		return
	await a.settle(0.8)
	await a.shot("arena_heroes", "The Arena: choose a hero")
	link.send({"t": "arena_hero", "i": 1})
	await until(func(): return not v.arena.get("offer", []).is_empty(), 10.0)
	await a.settle(0.8)
	await a.shot("arena_draft", "The Arena draft: the first pick")
	for i in 30:
		var had: int = v.arena.get("cards", []).size()
		link.send({"t": "arena_pick", "i": i % 3})
		await until(func(): return v.arena.get("cards", []).size() > had or v.arena.get("done", false), 5.0)
		if i == 17:
			await a.settle(0.6)
			await a.shot("arena_draft_mid", "The Arena draft at pick 19: the deck list and the curve")
	await a.settle(0.8)
	await a.shot("arena_run", "The Arena run: the record, Play, Retire")
	(v.find_child("ArenaRetire", true, false) as Button).pressed.emit()
	await a.wait(0.3)
	await a.shot("arena_retire_armed", "The Arena: Retire pressed once")
	v._go("lobby")
	(v.find_child("ArenaQueue", true, false) as Button).pressed.emit()
	await a.wait(2.5)
	await a.shot("arena_searching", "The Arena: searching for an opponent")
	if not await until(func(): return m.screen is MatchView, 40.0):
		a.error("pass %d: no Arena game started" % n)
		return
	await _play_a_bit("arena_game", "An Arena game on the server")
	m.screen.lobby_back.emit()
	await a.settle(1.5)
	if m.screen is ServerView and m.screen.tab != "Arena":
		m.screen.tab = "Arena"
		m.screen._go("lobby")
		await a.settle(0.6)
	await a.shot("arena_after_game", "The Arena after a lost game: the record")


# --- tournaments -------------------------------------------------------------------------------

func _tournaments() -> void:
	m.show_game_menu()
	var tv: TournamentsView = m.show_tournaments()
	await a.settle(1.2)
	await a.shot("tournaments_empty", "Tournaments: none yet")
	tv.show_tab("create")
	await a.settle(0.6)
	await a.shot("tournament_form", "Create a tournament: the form (defaults)")
	var fs := tv.find_child("FormScroll", true, false) as ScrollContainer
	if fs:
		fs.scroll_vertical = 100000
		await a.wait(0.4)
		await a.shot("tournament_form_bottom", "Create a tournament: the form scrolled down")
	for spec in [["swiss", {"format": "swiss", "drop_after": 2, "swiss_rounds": 0, "series": "lhs", "best_of": 5, "bans": 1, "deck_reveal": true}],
			["round_robin", {"format": "round_robin", "rr_rounds": 2, "best_of": 7, "max_players": 32, "spectators": false}],
			["teams", {"format": "scheveningen", "max_players": 64, "min_players": 64, "best_of": 3}]]:
		tv.form.merge(spec[1], true)
		tv.form.name = "Кубок пятничного вечера в Каражане" if a.lang == "ru" else "Friday night Karazhan cup"
		tv._build_form()
		await a.settle(0.4)
		await a.shot("tournament_form_" + spec[0], "Create a tournament: the form, " + spec[0])
		var s2 := tv.find_child("FormScroll", true, false) as ScrollContainer
		s2.scroll_vertical = 100000
		await a.wait(0.3)
		await a.shot("tournament_form_%s_bottom" % spec[0], "Create a tournament: the form, %s, scrolled down" % spec[0])
	tv.form = TournamentsView.default_form()
	tv.form.merge({"name": ("Кубок кобольдов — отборочный тур" if a.lang == "ru" else "Kobolds and Catacombs Cup — qualifier"),
		"format": "elimination", "best_of": 1, "bans": 1, "max_players": 8, "deck_reveal": true}, true)
	tv._build_form()
	await a.settle(0.3)
	tv.submit_form()
	if not await until(func(): return tv.tab == "page" and not tv.page.is_empty(), 10.0):
		a.error("pass %d: the tournament was not created: %s" % [n, tv._status.text])
		return
	await a.settle(0.8)
	await a.shot("tournament_page", "A new tournament's page (the creator)")
	tv.show_add_bots()
	await a.settle(0.4)
	await a.shot("tournament_add_bots", "Add bots")
	tv.close_overlay()
	for lv in ["easy", "medium", "hard", "superhard"]:
		var cnt := 1 if lv == "superhard" else 2
		var before: int = tv.page.get("entrants", []).size()
		link.send({"t": "t_add_bots", "id": TournamentsView.wire_id(tv.page_id), "level": lv, "count": cnt})
		await until(func(): return tv.page.get("entrants", []).size() >= before + cnt, 6.0)
	tv.pick_decks(false)
	await a.settle(0.5)
	await a.shot("tournament_pick_decks", "Taking part: choose the decks (2 of different classes)")
	var all := tv.decks_for(tv.page)
	var seen := {}
	for d: Deck in all:
		if not seen.has(d.card_class()) and seen.size() < TournamentsView.decks_needed(tv.page):
			seen[d.card_class()] = true
			tv.chosen.append(d)
	tv._build_picker(false, TournamentsView.decks_needed(tv.page), all)
	await a.settle(0.3)
	await a.shot("tournament_pick_decks_chosen", "Taking part: the decks chosen")
	tv.send_decks(false)
	await until(func(): return not tv._my_entrant().is_empty(), 6.0)
	await a.settle(0.6)
	await a.shot("tournament_page_full", "The tournament's page: 8 players, the creator's tools, my decks")
	tv.page_tab = "bracket"
	tv._build_page()
	await a.settle(0.4)
	await a.shot("tournament_bracket_none", "The bracket tab before the draw")
	# the start now: the server moves it on within 2 s (its scheduler reads the database)
	var id := int(TournamentsView.wire_id(tv.page_id))
	var out := []
	OS.execute("sqlite3", ["-cmd", ".timeout 5000", db, "update tournaments set start_at = %d where id = %d" % [TournamentsView.now_ms() - 2000, id]], out, true)
	var panel: TournamentPanel = m.tournament_panel
	if not await until(func(): return panel.visible and panel.phase() == "accept", 30.0):
		a.error("pass %d: no tournament match panel: %s" % [n, out])
	else:
		await a.settle(0.6)
		await a.shot("tournament_t_match_accept", "The tournament match panel: accept")
		link.send({"t": "t_accept", "match": panel.cur.get("match")})
		if await until(func(): return panel.phase() == "ban", 15.0):
			await a.settle(0.5)
			await a.shot("tournament_t_match_ban", "The tournament match panel: ban a deck")
			link.send({"t": "t_ban", "match": panel.cur.get("match"), "deck": 0})
		if await until(func(): return panel.phase() == "pick", 15.0):
			await a.settle(0.5)
			await a.shot("tournament_t_match_pick", "The tournament match panel: choose the deck")
			link.send({"t": "t_pick", "match": panel.cur.get("match"), "deck": 0})
		await until(func(): return panel.phase() == "wait" or m.screen is MatchView, 15.0)
		if panel.visible and panel.phase() == "wait":
			await a.shot("tournament_t_match_wait", "The tournament match panel: waiting")
		if await until(func(): return m.screen is MatchView, 40.0):
			await _play_a_bit("tournament_game", "A tournament game")
			m.screen.lobby_back.emit()
			await a.settle(1.5)
	if not m.screen is TournamentsView:
		tv = m.show_tournaments(id)
		await a.settle(1.2)
	else:
		tv = m.screen
	await until(func(): return not tv.page.is_empty(), 8.0)
	tv.page_tab = "bracket"
	tv._build_page()
	await a.settle(0.8)
	await a.shot("tournament_bracket", "The tournament's bracket, running (8 players)")
	var ms := TournamentBracket.matches_of(tv.page)
	if not ms.is_empty():
		tv.show_match(ms[0])
		await a.settle(0.4)
		await a.shot("tournament_match_dialog", "A bracket match's window")
		tv.close_overlay()
	tv.page_tab = "overview"
	tv._build_page()
	await a.settle(0.6)
	await a.shot("tournament_page_running", "The tournament's page, running: standings")
	tv.show_tab("upcoming")
	await until(func(): return tv.lists.has("upcoming"), 6.0)
	await a.settle(0.6)
	await a.shot("tournaments_list", "Tournaments: the list")
	link.send({"t": "t_cancel", "id": id})  # (its bots are free for the next pass)
	await a.wait(0.5)


# --- a lost connection, another device ------------------------------------------------------

func _lost() -> void:
	m.show_game_menu()
	var v: ServerView = m.show_server()
	await a.settle(0.8)
	link.socket.close()  # the connection drops (as a server restart or a lost network does)
	await until(func(): return v.stage == "login", 10.0)
	await a.settle(0.6)
	await a.shot("lobby_connection_lost", "The lobby when the connection is lost")
	var c: ConnectionsView = m.show_connections()
	await until(func(): return link.logged_in(), 15.0)
	await a.settle(0.6)
	await a.shot("connections_logged_in", "Game servers after logging in again by itself")
	peer("kick %s %s" % [user, PASSWORD])
	await until(func(): return link.kicked, 15.0)
	await a.settle(1.0)
	await a.shot("connections_kicked", "Game servers after a login from another device (a toast)")
	m.open_connection(link.id)
	await a.settle(1.5)
	await a.shot("login_kicked", "The login after another device took the session: Play here")
