extends TestCase
## Tournaments in the client (ui/tournaments_view.gd, ui/tournament_bracket.gd,
## ui/tournament_panel.gd) against a FakeLink: the list tabs, the create form, joining with decks,
## the page on the server's pushes, the match panel's steps, every bracket kind, the top three.

const ME := {"user": "anna", "tag": null, "arena": null, "season": "2026-11", "rank": {}}


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _link() -> FakeLink:
	var l := FakeLink.new()
	l.url = "ws://localhost:7441"
	l.dispatch({"t": "auth", "ok": true, "token": "x", "me": ME})
	l.sent.clear()
	return l


func _view(page_id: Variant = null) -> TournamentsView:
	TournamentsView.cache = {}
	var v := TournamentsView.new()
	v.link = _link()
	v.page_id = page_id
	root().add_child(v)
	return v


func _free(v: Control) -> void:
	var l: ServerLink = v.link
	v.free()
	l.free()


func _press(parent: Node, button_name: String) -> void:
	var b := parent.find_child(button_name, true, false) as BaseButton
	check(b != null and b.is_visible_in_tree() and not b.disabled, button_name + " shown and enabled")
	if b and not b.disabled:
		b.pressed.emit()


func _sent(v: TournamentsView, t: String) -> Array:
	return (v.link as FakeLink).of(t)


static func summary(id: int, name: String, status := "open") -> Dictionary:
	return {"id": float(id), "name": name, "creator": "bob", "pack": "h", "pack_name": "Classic", "format": "swiss",
		"series": "conquest", "best_of": 3.0, "start_at": float(TournamentsView.now_ms() + 3600000), "status": status,
		"entrants": 5.0, "max_players": 16.0, "joined": id == 1}


## Full data: n entrants p1..pn (anna is p1 when me_in), the matches of the format.
static func full(format: String, n: int, opts := {}, me_in := true) -> Dictionary:
	var ents: Array = []
	for i in n:
		var who := "anna" if i == 0 and me_in else "p%d" % (i + 1)
		# as the server sends them: seeds from 0, team -1 outside Scheveningen
		ents.append({"name": who, "seed": float(i), "team": float(i % 2) if format == "scheveningen" else -1.0,
			"eliminated": false, "place": null, "points": float(n - i), "wins": float(n - i), "losses": float(i)})
	var t := {"id": 7.0, "name": "Friday cup", "creator": "bob", "pack": Packs.active().rules_hash(), "pack_name": "Classic",
		"format": format, "series": "conquest", "best_of": 3.0, "bans": 0.0, "start_at": float(TournamentsView.now_ms() + 3600000),
		"status": "open", "entrants": ents, "max_players": 16.0, "min_players": 2.0, "deck_reveal": false, "spectators": true,
		"options": {}, "matches": [], "can": {"join": not me_in, "leave": me_in, "decks": me_in, "edit": false, "cancel": false, "reschedule": false, "spectate": false}}
	t.merge(opts, true)
	t.matches = matches_for(t)
	return t


static func _m(id: int, rnd: int, br: String, slot: int, a: Variant, b: Variant, status := "done", sc := [2, 1]) -> Dictionary:
	var done := status == "done"
	return {"id": float(id), "round": float(rnd), "bracket": br, "slot": float(slot), "p": [a, b], "status": status,
		"score": sc if done else [0, 0], "winner": a if done else null, "games": ["g%d_1" % id, "g%d_2" % id] if done else []}


static func matches_for(t: Dictionary) -> Array:
	var names: Array = t.entrants.map(func(e): return e.name)
	var n := names.size()
	var out: Array = []
	var id := 1
	match str(t.format):
		"elimination":
			var r := 1
			var cur := names.duplicate()
			while cur.size() > 1:
				var nxt := []
				for i in cur.size() / 2:
					out.append(_m(id, r, "w", i, cur[2 * i], cur[2 * i + 1], "running" if r == 3 else "done"))
					id += 1
					nxt.append(cur[2 * i])
				cur = nxt
				r += 1
			if int(TournamentsView.opt(t, "losses", 1)) == 2:
				for spec in [[1, 2], [2, 2], [3, 1], [4, 1]]:
					for i in spec[1]:
						out.append(_m(id, spec[0], "l", i, names[n - 1 - i], names[n - 2 - i], "pending"))
						id += 1
				out.append(_m(id, 1, "gf", 0, null, null, "pending"))
		"round_robin":
			for i in n:
				for j in range(i + 1, n):
					out.append(_m(id, 1, "", id, names[i], names[j]))
					id += 1
		"swiss":
			for r in 3:
				for i in n / 2:
					out.append(_m(id, r + 1, "", i, names[(i * 2 + r) % n], names[(i * 2 + 1 + r * 3) % n], "done" if r < 2 else "running"))
					id += 1
		"scheveningen":
			for a in range(0, n, 2):
				for b in range(1, n, 2):
					out.append(_m(id, 1, "", id, names[a], names[b]))
					id += 1
	return out


func test_list_tabs() -> void:
	var v := _view()
	eq(_sent(v, "t_list"), [{"t": "t_list", "tab": "upcoming"}], "the Upcoming list is asked for")
	check(v.find_child("Loading", true, false) != null, "loading until it comes")
	v.link.dispatch({"t": "t_list", "tab": "upcoming", "list": [summary(1, "Friday cup"), summary(2, "Saturday swiss", "locked")]})
	check(v.find_child("T_1", true, false) != null and v.find_child("T_2", true, false) != null, "a row per tournament")
	check(v.find_child("ListScroll", true, false) is ScrollContainer, "the list scrolls by finger")
	_press(v, "Tab_finished")
	eq(_sent(v, "t_list").back(), {"t": "t_list", "tab": "finished"})
	v.link.dispatch({"t": "t_list", "tab": "finished", "list": []})
	check(v.find_child("Empty", true, false) != null, "an empty tab says so")
	v.link.dispatch({"t": "t_list", "tab": "upcoming", "list": []})
	check(v.find_child("T_1", true, false) == null, "another tab's list does not show here")
	_press(v, "Tab_closed")
	eq(_sent(v, "t_list").back(), {"t": "t_list", "tab": "closed"})
	_press(v, "Tab_upcoming")
	check(v.find_child("EmptyCreate", true, false) != null, "the empty Upcoming tab offers Create")
	_press(v, "EmptyCreate")
	eq(v.tab, "create")
	_free(v)


func test_create_form_validation_and_message() -> void:
	var v := _view()
	_press(v, "Tab_create")
	check(v.find_child("Form", true, false) != null, "the form")
	_press(v, "FormOk")
	eq(_sent(v, "t_create"), [], "no name: nothing sent")
	eq(v._status.text, "The name needs 3 to 40 letters")
	_press(v, "Preset2")  # Swiss 16 · Bo3
	eq([v.form.format, int(v.form.max_players), int(v.form.best_of)], ["swiss", 16, 3], "the preset's options")
	check(str(v.form.name) != "", "a preset names an unnamed tournament")
	_press(v, "best_of_5")
	_press(v, "bans_1")
	eq((v.find_child("DecksNeeded", true, false) as Label).text, "Each player brings 4 decks of different classes")
	_press(v, "max_players_minus10")
	eq(int(v.form.max_players), 6)
	v.form.min_players = 6
	_press(v, "max_players_minus1")
	eq(int(v.form.min_players), 5, "the minimum follows the maximum down")
	v.form.start_at = TournamentsView.now_ms() + 5 * 60000
	_press(v, "FormOk")
	eq(v._status.text, "The start must be at least 11 minutes from now")
	v.form.start_at = TournamentsView.now_ms() + 15 * 24 * 3600000
	eq(TournamentsView.check_form(v.form), "The start can be at most 14 days ahead")
	_press(v, "Quick_In1hour")
	var start := int(v.form.start_at)
	check(start > TournamentsView.now_ms() + 3500000, "In 1 hour")
	_press(v, "Start_hour_plus")
	eq(int(v.form.start_at), start + 3600000, "an hour later")
	(v.find_child("NameEdit", true, false) as LineEdit).text_changed.emit("  Night swiss  ")
	_press(v, "FormOk")
	var sent := _sent(v, "t_create")
	eq(sent.size(), 1, "sent")
	var m: Dictionary = sent[0]
	eq([m.name, m.pack, m.format, m.options, m.series, m.best_of, m.bans, m.max_players, m.min_players, m.start_at, m.deck_reveal, m.spectators],
		["Night swiss", Packs.active().rules_hash(), "swiss", {"drop_after": 0}, "conquest", 5, 1, 5, 5, start + 3600000, false, true],
		"the message (swiss rounds left to the server)")
	v.link.dispatch({"t": "tournament", "tournament": full("swiss", 0, {"id": 9.0, "name": "Night swiss"})})
	eq([v.tab, v.page_id], ["page", 9], "the new tournament's page opens")
	_free(v)


func test_form_messages() -> void:
	var f := TournamentsView.default_form()
	f.name = "Cup"
	f.format = "elimination"
	f.losses = 2
	eq(TournamentsView.form_message(f, "create", "h").options, {"losses": 2})
	f.format = "round_robin"
	f.rr_rounds = 2
	var e := TournamentsView.form_message(f, "edit", "", 7.0)
	eq([e.t, e.id, e.options, e.has("series"), e.has("best_of"), e.has("start_at")], ["t_edit", 7, {"rounds": 2}, false, false, false],
		"an edit sends only what may change")
	f.start_at = 1000
	eq(TournamentsView.form_message(f, "reschedule", "", 7.0), {"t": "t_reschedule", "id": 7, "start_at": 1000})
	f.start_at = TournamentsView.now_ms() + 3600000
	eq(TournamentsView.check_form(f, "reschedule", int(f.start_at) + 60000), "A tournament can only be moved to later")
	eq(TournamentsView.check_form(f, "reschedule", int(f.start_at) - 60000), "")
	var back := TournamentsView.form_of(full("swiss", 2, {"options": {"rounds": 4.0, "drop_after": 2.0}}))
	eq([back.format, back.swiss_rounds, back.drop_after, back.best_of], ["swiss", 4, 2, 3], "a tournament back into the form")


func test_join_with_decks_of_different_classes() -> void:
	var v := _view(7)
	eq(_sent(v, "t_get"), [{"t": "t_get", "id": 7}], "the page asks for the tournament")
	v.link.dispatch({"t": "tournament", "tournament": full("elimination", 4, {"bans": 1.0}, false)})
	_press(v, "Join")
	var picker := v.find_child("DeckPicker", true, false)
	check(picker != null, "the deck picker")
	eq(TournamentsView.decks_needed(v.page), 3, "best of 3 + a ban: 3 decks")
	eq((picker.find_child("DialogTitle", true, false) as Label).text, "Choose 3 decks of different classes")
	_press(v, "Deck0")
	_press(v, "Deck1")
	check((v.find_child("PickOk", true, false) as Button).disabled, "2 of 3: not yet")
	eq((v.find_child("PickOk", true, false) as Button).text, "Take part", "not \"Join\" (Russian: \"Войти\", log in)")
	_press(v, "Deck1")
	eq(v.chosen.size(), 1, "a second press takes a deck out")
	_press(v, "Deck1")
	_press(v, "Deck2")
	_press(v, "PickOk")
	var j := _sent(v, "t_join")
	eq(j.size(), 1, "t_join sent")
	eq(j[0].id, 7)
	eq(j[0].decks.size(), 3)
	var heroes := {}
	for d in j[0].decks:
		heroes[d.hero] = true
		eq(d.cards.size(), 30, "a whole deck")
	eq(heroes.size(), 3, "three classes")
	# the same class again replaces the first
	var all := v.decks_for(v.page)
	var same := Deck.from_dict(all[0].to_dict())
	same.name = "Other " + all[0].name
	v.chosen = [all[0]]
	v._build_picker(false, 3, all + [same])
	_press(v, "Deck%d" % all.size())
	eq(v.chosen, [same], "one deck per class")
	_free(v)


func test_page_follows_pushes() -> void:
	var v := _view(7)
	var t := full("swiss", 3, {}, false)
	v.link.dispatch({"t": "tournament", "tournament": t})
	eq((v.find_child("PlayerList", true, false) as Node).get_child_count(), 3)
	check(v.find_child("Join", true, false) != null, "Join while it may")
	check((v.find_child("Countdown", true, false) as Label).text.begins_with("Starts in "), "the countdown")
	var t2 := full("swiss", 4, {"status": "locked"}, true)
	t2.can = {"join": false, "leave": false, "decks": false}
	t2.entrants[0].decks = [{"name": "Fire", "hero": "HERO_08", "cards": Decks.basic("MAGE")}]
	v.link.dispatch({"t": "tournament", "tournament": t2})
	eq((v.find_child("PlayerList", true, false) as Node).get_child_count(), 4, "a new player shows")
	check(v.find_child("Join", true, false) == null, "no Join after the lock")
	check(v.find_child("EntryCard", true, false) != null, "the player's decks")
	check(v.find_child("Leave", true, false) == null, "no Leave once leaving closed")
	var other := full("swiss", 2)
	other.id = 8.0
	v.link.dispatch({"t": "tournament", "tournament": other})
	eq((v.find_child("PlayerList", true, false) as Node).get_child_count(), 4, "another tournament's push changes nothing here")
	_press(v, "Tab_bracket")
	check(v.find_child("Bracket", true, false) != null, "the bracket tab")
	v.page_tab = "overview"
	t2.can = {"edit": true, "cancel": true, "reschedule": true}
	v.link.dispatch({"t": "tournament", "tournament": t2})
	_press(v, "CancelT")
	eq(_sent(v, "t_cancel"), [], "Cancel asks first")
	_press(v, "CancelT")
	eq(_sent(v, "t_cancel"), [{"t": "t_cancel", "id": 7}])
	_press(v, "Reschedule")
	eq(v.form_mode, "reschedule")
	check(v.find_child("NameEdit", true, false) == null, "reschedule: only the start")
	_press(v, "Back")
	eq(v.tab, "page", "back to the page")
	_press(v, "Back")
	eq(_sent(v, "t_unwatch"), [{"t": "t_unwatch", "id": 7}], "leaving the page stops its pushes")
	_free(v)


func test_match_dialog_watch_and_replay() -> void:
	var v := _view(7)
	var t := full("elimination", 8)
	t.can.spectate = true
	v.link.dispatch({"t": "tournament", "tournament": t})
	var live: Dictionary = t.matches.filter(func(m): return m.status == "running")[0]
	v.show_match(live)
	_press(v, "Watch")
	eq(_sent(v, "t_spectate"), [{"t": "t_spectate", "match": int(live.id)}])
	v.show_match(t.matches[0])
	check(v.find_child("Watch", true, false) == null, "no Watch for a finished match")
	_press(v, "Replay_1")
	eq(_sent(v, "replay"), [{"t": "replay", "game": "g1_2"}])
	var got := []
	v.replay_ready.connect(func(d): got.append(d))
	v.link.dispatch({"t": "replay", "game": "g1_2", "data": {"format": "classichs-replay"}})
	eq(got, [{"format": "classichs-replay"}], "the replay goes on to main")
	_free(v)


func test_match_panel_steps() -> void:
	var p := TournamentPanel.new()
	root().add_child(p)
	var l := _link()
	var base := {"t": "t_match", "tournament": 7.0, "name": "Friday cup", "match": 31.0, "opponent": "bob", "score": [0.0, 0.0],
		"mine": [{"hero": "HERO_08", "name": "Fire", "state": "ok"}, {"hero": "HERO_01", "name": "Axe", "state": "ok"}],
		"theirs": [{"hero": "HERO_02", "state": "ok"}, {"hero": "HERO_03", "state": "ok"}]}
	var m := base.duplicate(true)
	m.phase = "accept"
	m.deadline = float(TournamentsView.now_ms() + 42000)
	p.show_match(m, l)
	check(p.visible, "shown over the screen")
	check(abs(p.left_ms() - 42000) < 2000, "42 s left")
	p._process(0.0)
	check(abs(p._ring.left - 42000) < 2000, "the ring counts down")
	_press(p, "Accept")
	eq(l.of("t_accept"), [{"t": "t_accept", "match": 31}])
	check((p.find_child("Accept", true, false) as Button).disabled, "answered once")
	m = base.duplicate(true)
	m.phase = "ban"
	m.deadline = float(TournamentsView.now_ms() + 60000)
	m.theirs[0].state = "banned"
	p.show_match(m, l)
	check((p.find_child("Theirs0", true, false) as Button).disabled, "a banned deck can't be banned")
	_press(p, "Theirs1")
	eq(l.of("t_ban"), [{"t": "t_ban", "match": 31, "deck": 1}])
	_press(p, "Hide")
	check(p.find_child("PanelChip", true, false) != null, "Hide folds it into a chip")
	m = base.duplicate(true)
	m.phase = "pick"
	m.score = [1.0, 0.0]
	m.mine[0].state = "won"
	m.deadline = float(TournamentsView.now_ms() + 60000)
	p.show_match(m, l)
	check(p.find_child("Mine0", true, false) != null, "a new step opens it again")
	check((p.find_child("Mine0", true, false) as Button).disabled, "a deck that won can't play again (Conquest)")
	_press(p, "Mine1")
	eq(l.of("t_pick"), [{"t": "t_pick", "match": 31, "deck": 1}])
	m = base.duplicate(true)
	m.phase = "done"
	m.score = [2.0, 1.0]
	p.show_match(m, l)
	eq((p.find_child("Step", true, false) as Label).text, "You won the match!")
	m.status = "pick"  # the tournament stopped mid-match (cancelled): not a result
	m.score = [0.0, 0.0]
	p.show_match(m, l)
	eq((p.find_child("Step", true, false) as Label).text, "The tournament was cancelled")
	p._process(9.0)
	check(not p.visible, "the result goes away by itself")
	p.free()
	l.free()


func _bracket(t: Dictionary) -> TournamentBracket:
	var b := TournamentBracket.make(t, "anna")
	root().add_child(b)
	return b


func test_every_bracket_kind_draws_every_match() -> void:
	for spec in [["elimination", 8, {}], ["elimination", 8, {"options": {"losses": 2.0}}], ["round_robin", 5, {}],
			["swiss", 6, {}], ["scheveningen", 6, {}]]:
		var t := full(spec[0], spec[1], spec[2])
		var b := _bracket(t)
		eq(b.drawn.size(), t.matches.size(), "%s: every match drawn" % spec[0])
		check(b.custom_minimum_size.x > 200 and b.custom_minimum_size.y > 100, "%s: it has a size to scroll" % spec[0])
		match spec[0]:
			"elimination":
				eq(b.find_child("LosersHead", true, false) != null, spec[2].has("options"), "the losers bracket only in double")
				check(not b._lines.is_empty(), "connectors")
				check(b._lines.any(func(x): return b._rank(x[2]) == 2), "the player's own path stands out")
			"round_robin":
				eq((b.find_child("Cross", true, false) as GridContainer).columns, 5 + 3, "a column per opponent, points, place")
			"swiss":
				check(b.find_child("Standing_anna", true, false) != null, "the standings beside the rounds")
			"scheveningen":
				check(b.find_child("Team1", true, false) != null and b.find_child("Team2", true, false) != null, "two team columns")
				eq((b.find_child("TeamGrid", true, false) as GridContainer).columns, 4, "a column per player of the other team")
		b.free()


func test_top_three_marked() -> void:
	var v := _view(7)
	var t := full("swiss", 5, {"status": "finished"})
	for i in 5:
		t.entrants[i].place = float(5 - i)  # p5 first
	v.link.dispatch({"t": "tournament", "tournament": t})
	var list := v.find_child("PlayerList", true, false)
	for k in [1, 2, 3]:
		eq(list.find_children("Medal%d" % k, "", true, false).size(), 1, "one medal %d" % k)
	eq(str(list.get_child(0).name), "Player_p5", "the winner on top")
	eq(TournamentBracket.standings(t).map(func(e): return e.name), ["p5", "p4", "p3", "p2", "anna"])
	var b := _bracket(t)
	eq(b.find_children("Medal1", "", true, false).size(), 1, "the standings mark the winner too")
	b.free()
	_free(v)


func test_rules_in_words_and_time() -> void:
	var t := full("elimination", 2, {"options": {"losses": 2.0}, "bans": 1.0, "series": "lhs", "best_of": 5.0, "deck_reveal": true})
	var words: Array = TournamentsView.rules_lines(t).map(func(r): return r[0])
	eq(words, ["Double elimination", "Last Hero Standing · best of 5", "4 decks of different classes", "2–16 players", "Open decklists", "Spectators allowed"])
	eq(TournamentsView.left_text(65000), "1:05")
	eq(TournamentsView.left_text(3723000), "1:02:03")
	eq(TournamentsView.left_text(2 * 86400000 + 5 * 3600000), "2 d 5 h")
	var ms := TournamentsView.local_to_ms(2026, 11, 10, 18, 30)
	eq(TournamentsView.local_text(ms), "2026-11-10 18:30", "local time there and back")


## Through main: the server's game menu has Tournaments; a `t_match` shows the panel over any
## screen and the tournament's game hides it.
func test_main_menu_and_panel() -> void:
	if Settings.data.servers.is_empty():
		Settings.data.servers = [{"url": "ws://localhost:7441", "name": "localhost"}]
	Settings.save()
	var m: Node = load("res://ui/main.tscn").instantiate()
	m.server_link = FakeLink.new()
	root().add_child(m)
	m.show_connections()
	m.server_link.dispatch({"t": "auth", "ok": true, "token": "t", "me": ME})
	m.enter_game(Packs.active())
	_press(m.screen, "Tournaments")
	check(m.screen is TournamentsView, "the Tournaments screen")
	m.server_link.dispatch({"t": "t_match", "tournament": 7.0, "name": "Cup", "match": 3.0, "phase": "accept",
		"deadline": float(TournamentsView.now_ms() + 60000), "opponent": "bob", "score": [0.0, 0.0], "mine": [], "theirs": []})
	check(m.tournament_panel.visible, "the match panel pops up")
	m.show_game_menu()
	check(m.tournament_panel.visible, "and stays over another screen")
	m.server_link.dispatch({"t": "match", "game": "g9", "mode": "tournament", "tournament": 7.0, "match": 3.0, "you": 0, "opponent": {"user": "bob"}})
	check(not m.tournament_panel.visible, "the game hides it")
	eq(m.server_link.get_meta("tournament"), 7.0, "the game knows its tournament (back to its page)")
	FakeLink.engine_game("tour_eng")
	m.server_link.dispatch(JSON.parse_string(JSON.stringify(FakeLink.state("g9", "tour_eng", 0))))
	check(m.screen is MatchView and m.screen.lobby_label == "Back to the tournament", "its end leads back to the tournament, so it says")
	Rules.request({"op": "drop", "game": "tour_eng"})
	m.free()


## Found against the real server (0.50 check): seeds count from 0, no team is -1 (the rows said
## "Team 0" for everyone and "Seed -1" before seeding); points wait for the start.
func test_seed_and_team_lines_follow_the_server() -> void:
	eq(TournamentsView.seed_line({"seed": 0.0, "team": -1.0}), "Seed 1", "the first seed")
	eq(TournamentsView.seed_line({"seed": -1.0, "team": -1.0}), "", "not seeded yet: nothing")
	eq(TournamentsView.seed_line({"seed": 3.0, "team": 1.0}), "Team 2", "Scheveningen: the team")
	var v := _view(7.0)
	var t := full("elimination", 4)
	t.matches = []
	v.link.dispatch({"t": "tournament", "tournament": t})
	var row: TournamentsView.PlayerRow = v.find_child("Player_anna", true, false)
	check(row != null and not row.scored, "no points before the bracket")
	t = full("elimination", 4, {"status": "seeded"})
	v.link.dispatch({"t": "tournament", "tournament": t})
	row = v.find_child("Player_anna", true, false)
	check(not row.scored, "seeded: the bracket is drawn, nothing played yet")
	v.link.dispatch({"t": "tournament", "tournament": full("elimination", 4, {"status": "running"})})
	row = v.find_child("Player_anna", true, false)
	check(row.scored, "points once it runs")
	_free(v)


func test_single_elimination_names_its_rounds() -> void:
	var b := TournamentBracket.make(full("elimination", 8), "anna")
	var titles: Array = b.get_children().filter(func(c): return c is Label).map(func(c): return c.text)
	for want in ["Quarter-finals", "Semi-finals", "Final"]:
		check(titles.has(want), "%s in %s" % [want, titles])
	b.free()



## Bo1 without bans: one deck, said so (not "1 decks of different classes").
func test_one_deck_is_said_in_the_singular() -> void:
	var t := full("swiss", 4, {"best_of": 1.0, "bans": 0.0})
	check(TournamentsView.rules_lines(t).any(func(r): return r[0] == "One deck"), "the rules say one deck")
