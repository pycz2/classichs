class_name ServerView
extends Control
## Playing through a game server, in the look of the 2014 game: log in (once —
## the session is saved), then Play (a deck box, Casual or Ranked with the rank
## medal, one big Play button) or the Arena (a ticket, three heroes, the draft,
## the record of wins and losses). Friends and messages are the Social overlay's
## (on every screen); a game the server starts is shown by main. The last deck,
## mode and tab are remembered per server. With several servers a picker at the top
## switches (D14); "Games" lists the server's game packs (download, use, upload).
## The ranks' names and emblems come from the active pack. Protocol: server/README.md.

signal back
## Another server was picked (main shows the lobby again for it).
signal server_chosen(link: ServerLink)

const TABS := ["Play", "Arena"]
const MODES := ["casual", "ranked"]
const ARENA_WINS := 12
const ARENA_LOSSES := 3
const LIST_X := 968.0  # the Arena deck list on the right

var link: ServerLink
## Every server's connection (for the picker; main's server_links).
var links: Array = []
var stage := ""  # "connecting", "login", "lobby"
var tab := "Play"
var mode := "casual"  # Play: casual or ranked
var deck: Deck  # the deck for casual, ranked and friendly games
var arena := {}  # the Arena run from the server
var queued := ""  # the mode being searched ("" = none)
var waited := 0.0
var _status: Label
var _body := Control.new()
var _retire_armed := false
var _games: Control  # the "Games on this server" panel while open
var _delete_armed := ""  # the content hash whose Delete was pressed once


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self)
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	_status = Palette.label("", 18, Palette.SELECTED)
	_status.name = "Status"
	_status.position = Vector2(372, 668)
	_status.custom_minimum_size = Vector2(460, 0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var s := link.saved()
	tab = s.get("tab") if s.get("tab") in TABS else "Play"
	mode = s.get("mode") if s.get("mode") in MODES else "casual"
	deck = remembered_deck(link)
	link.message.connect(_on_message)
	link.packs_changed.connect(_packs_changed)
	link.pack_progress.connect(_pack_progress)
	link.pack_downloaded.connect(_pack_downloaded)
	link.pack_uploaded.connect(_pack_uploaded)
	link.closed.connect(func(_why):
		queued = ""
		_go("login")
		if link.kicked:
			say(tr("You logged in on another device"))
		else:
			say(tr("Connection lost") if link.was_open() else tr("Could not connect to %s") % link.url))
	if link.logged_in():  # back from a game, or still logged in
		if link.get_meta("mode", "") == "arena":
			tab = "Arena"
		_set_arena(link.me.get("arena"))
		_go("lobby")
		var last: Dictionary = link.get_meta("game_over", {})
		link.remove_meta("game_over")
		if last.is_empty():
			link.request_me()
		else:
			_on_message(last)  # the result, the Arena score; asks for a fresh profile
	elif link.is_open():
		_go("connecting" if link.resuming else "login")
	else:
		_go("connecting")
		if link.open_and_resume(link.url) != OK:
			_go("login")
			say(tr("Could not connect to %s") % link.url)
		else:
			link.opened.connect(func():
				if not link.resuming and stage == "connecting":
					_go("login"), CONNECT_ONE_SHOT)


func say(text: String) -> void:
	_status.text = text


func _process(delta: float) -> void:
	if queued != "":
		waited += delta
		var t := find_child("QueueTime", true, false) as Label
		if t:
			t.text = tr("Searching for an opponent… %s") % _mmss(waited)


static func _mmss(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


## The deck chosen last time on a server (by name and hero), else the first finished one.
static func remembered_deck(l: ServerLink = null) -> Deck:
	var want = l.saved().get("deck") if l else null
	var first: Deck = null
	for d in TrainingSetup.available_decks():
		if d.validate() != "":
			continue
		if want is Dictionary and d.name == want.get("name") and d.hero == want.get("hero"):
			return d
		if first == null:
			first = d
	return first


## Rebuilds the screen for a stage.
func _go(s: String) -> void:
	stage = s
	_retire_armed = false
	for c in _body.get_children():  # freed later: a pressed button may still be in its signal
		_body.remove_child(c)
		c.queue_free()
	match s:
		"connecting":
			_build_connecting()
		"login":
			_build_login()
		"lobby":
			_build_lobby()
	if links.size() > 1:
		_server_picker(Vector2(360, 8) if s == "lobby" else Vector2(490, 40))


## The server picker (several servers): another one shows the lobby for it.
func _server_picker(at: Vector2) -> void:
	var pick := OptionButton.new()
	pick.name = "ServerPick"
	pick.position = at
	pick.custom_minimum_size = Vector2(180 if stage == "lobby" else 300, 46)
	pick.clip_text = true
	pick.focus_mode = Control.FOCUS_NONE
	pick.add_theme_font_size_override("font_size", 18)
	for l in links:
		pick.add_item(l.display_name() + (" · " + str(l.me.get("user", "")) if l.logged_in() else ""))
	pick.select(maxi(0, links.find(link)))
	pick.item_selected.connect(func(i):
		if links[i] != link:
			if queued != "":
				unqueue()
			server_chosen.emit(links[i]))
	_body.add_child(pick)


func _panel(at: Vector2, sz: Vector2, parent: Control = _body) -> Panel:
	var p := Panel.new()
	p.position = at
	p.size = sz
	p.add_theme_stylebox_override("panel", Palette.frame())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _centered(text: String, font_size: int, at: Vector2, width: float, color := Palette.TEXT, parent: Control = _body) -> Label:
	var l := Palette.label(text, font_size, color)
	l.position = at
	l.custom_minimum_size.x = width
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _back_button(close_link: bool) -> void:
	var b := Palette.button(tr("Back"), "Back")
	b.position = Vector2(156, 664)
	b.custom_minimum_size = Vector2(190, 46)
	b.pressed.connect(func():
		if close_link:
			link.close()
		elif queued != "":
			unqueue()
		back.emit())
	_body.add_child(b)


# --- connecting and log in -------------------------------------------------------

func _build_connecting() -> void:
	_panel(Vector2(390, 200), Vector2(500, 260))
	var spin := Spinner.new()
	spin.position = Vector2(640, 300)
	_body.add_child(spin)
	_centered(tr("Connecting to %s…") % _address(), 22, Vector2(410, 380), 460)
	_back_button(true)


func _address() -> String:
	return link.url


func _build_login() -> void:
	_panel(Vector2(370, 110), Vector2(540, 470))
	_centered(tr("Game server"), 40, Vector2(390, 132), 500, Palette.ATTACK)
	var host := Settings.server_label(link.url)
	_centered(_address() if link.display_name() == host else "%s · %s" % [link.display_name(), _address()], 18, Vector2(390, 186), 500, Color("c9b48a"))
	var box := VBoxContainer.new()
	box.position = Vector2(430, 232)
	box.custom_minimum_size.x = 420
	box.add_theme_constant_override("separation", 14)
	_body.add_child(box)
	var user := LineEdit.new()
	user.name = "User"
	user.placeholder_text = tr("Account name")
	user.max_length = 20
	var known := Profile.load_name()
	user.text = known.replace(" ", "_") if known != Profile.DEFAULT_NAME else ""
	var pw := LineEdit.new()
	pw.name = "Password"
	pw.placeholder_text = tr("Password (8 characters or more)")
	pw.secret = true
	pw.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD  # a phone's keyboard offers the saved password
	pw.max_length = 128
	for e in [user, pw]:
		e.custom_minimum_size = Vector2(420, 52)
		e.add_theme_font_size_override("font_size", 22)
		box.add_child(e)
	user.text_submitted.connect(func(_t): pw.grab_focus())
	pw.text_submitted.connect(func(_t): log_in("login", user.text.strip_edges(), pw.text))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	for spec in [[tr("Log in"), "Login", "login"], [tr("Register"), "Register", "register"]]:
		var b := Palette.button(spec[0], spec[1])
		b.custom_minimum_size = Vector2(202, 56)
		b.add_theme_font_size_override("font_size", 24)
		var op: String = spec[2]
		b.pressed.connect(func(): log_in(op, user.text.strip_edges(), pw.text))
		row.add_child(b)
	var stay := Palette.label(tr("You stay logged in on this device until you log out."), 16, Color("c9b48a"))
	stay.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stay.custom_minimum_size.x = 420
	box.add_child(stay)
	var note := Palette.label(tr("The password goes only to this server. Use a server you trust; a public server needs wss:// (TLS)."), 15, Color("a8967a"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 420
	box.add_child(note)
	_back_button(true)
	if link.saved().get("kicked", false) and str(link.saved().get("token", "")) != "":
		var here := Palette.button(tr("Play here"), "PlayHere")
		here.position = Vector2(520, 596)
		here.custom_minimum_size = Vector2(240, 50)
		here.tooltip_text = tr("You logged in on another device")
		here.pressed.connect(play_here)
		_body.add_child(here)
	var field := user if user.text == "" else pw
	if field.is_inside_tree():
		field.grab_focus()


## Kicked out by another login: the saved session again (the other device gets kicked).
func play_here() -> void:
	if link.is_open():
		link.resume_saved()
	else:
		link.open_and_resume(link.url, true)
	_go("connecting")


func log_in(op: String, user: String, password: String) -> void:
	if user.length() < 3 or password.length() < 8:
		say(tr("An account name of 3 or more letters and a password of 8 or more characters"))
		return
	link.send({"t": op, "user": user, "password": password})
	say(tr("Connecting…"))


# --- lobby --------------------------------------------------------------------

func _build_lobby() -> void:
	var bar := Panel.new()
	bar.name = "TopBar"
	bar.size = Vector2(1280, 62)
	var st := Palette.box(Color(0.07, 0.045, 0.025, 0.94), 0)
	st.border_color = Color("a8863a")
	st.border_width_bottom = 3
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 8
	bar.add_theme_stylebox_override("panel", st)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(bar)
	var several := links.size() > 1  # room for the server picker: narrower tabs
	var tw := 152.0 if several else 184.0
	for i in TABS.size():
		var t: String = TABS[i]
		var b := Palette.button(tr(t), "Tab" + t)
		b.position = Vector2(20 + i * (tw + 12), 8)
		b.custom_minimum_size = Vector2(tw, 46)
		b.add_theme_font_size_override("font_size", 24)
		b.toggle_mode = true
		b.button_pressed = t == tab
		b.modulate = Color.WHITE if t == tab else Color(0.68, 0.64, 0.6)
		b.pressed.connect(func():
			tab = t
			link.remember({"tab": t})
			_go("lobby"))
		_body.add_child(b)
	var gx := 552.0 if several else 412.0
	var games := Palette.button(_game_line(), "GamesButton")
	games.position = Vector2(gx, 8)
	games.custom_minimum_size = Vector2(180 if several else 196, 46)
	games.size = games.custom_minimum_size
	games.clip_text = true
	games.add_theme_font_size_override("font_size", 18)
	games.tooltip_text = tr("Games on this server")
	if not link.has_game(Packs.active()):
		games.add_theme_color_override("font_color", Palette.OPPONENT)
		games.tooltip_text = link.game_problem(Packs.active())
	games.pressed.connect(show_games)
	_body.add_child(games)
	var me := link.me
	var nx := gx + games.custom_minimum_size.x + 12
	for spec in [["PlayerName", player_label(me), 22, Palette.ATTACK, 4], ["RankLine", rank_text(me.get("rank", {})), 15, Color("c9b48a"), 32]]:
		var l := Palette.label(spec[1], spec[2], spec[3])
		l.name = spec[0]
		l.position = Vector2(nx, spec[4])
		l.size = Vector2(1120 - nx, 28)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_body.add_child(l)
	var out := Palette.button(tr("Log out"), "Logout")
	out.position = Vector2(1136, 10)
	out.custom_minimum_size = Vector2(128, 42)
	out.add_theme_font_size_override("font_size", 17)
	out.pressed.connect(log_out)
	_body.add_child(out)
	if tab == "Arena":
		_build_arena()
	else:
		_build_play()
	_back_button(false)


func log_out() -> void:
	if queued != "":
		link.send({"t": "unqueue"})
	queued = ""
	link.log_out()
	_go("login")


## "Rank 18 · Sorcerer's Apprentice · stars 2 of 3" or "Legend 42" (server: {rank, stars, legend}).
func rank_text(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	if int(r.get("rank", 25)) == 0:  # Legend; "legend" is the place, null outside the top
		var n := int(r.get("legend")) if r.get("legend") is float else 0
		return tr("Legend") + (" %d" % n if n > 0 else "")
	var rank := int(r.get("rank", 25))
	var n := rank_name(rank)
	return tr("Rank %d") % rank + (" · " + n if n != "" else "") + " · " + tr("stars %d of %d") % [int(r.get("stars", 0)), stars_needed(rank)]


## The active pack's rule for a rank (rules.json ranked.ranks[]: {rank, stars, emblem…}; {} when none).
static func rank_rule(rank: int) -> Dictionary:
	var p := Packs.active()
	var ranked = p.rules().get("ranked") if p else null
	for r in ranked.get("ranks", []) if ranked is Dictionary else []:
		if r is Dictionary and int(r.get("rank", -1)) == rank:
			return r
	return {}


## Stars to the next rank: the pack's, else as in 2014 (2 at ranks 25–21, 3 at 20–16, 4 at 15–11, 5 above).
static func stars_needed(rank: int) -> int:
	var r := rank_rule(rank)
	if r.get("stars") is float or r.get("stars") is int:
		return int(r.stars)
	return 2 if rank > 20 else (3 if rank > 15 else (4 if rank > 10 else 5))


## A rank's name: the active pack's (locales: ranks "25" … "1", "0" = Legend), else its emblem
## card's name, else "" (the number alone).
static func rank_name(rank: int) -> String:
	var p := Packs.active()
	if p:
		var names = p.locale(p.lang_for(Settings.language())).get("ranks")
		if names is Dictionary and names.has(str(rank)):
			return str(names[str(rank)])
		names = p.locale(p.default_locale()).get("ranks")  # the client knows the words of the default
		if names is Dictionary and names.has(str(rank)):
			return TranslationServer.translate(str(names[str(rank)]))
	var e = rank_rule(rank).get("emblem")
	return CardText.name(str(e.card)) if e is Dictionary and e.get("card") is String else ""


# --- play: the deck boxes, casual or ranked, the Play button ----------------------

func _build_play() -> void:
	var book := _panel(Vector2(24, 76), Vector2(800, 576))
	book.name = "DeckBook"
	var head := Palette.label(tr("Choose a deck"), 24, Palette.ATTACK)
	head.position = Vector2(46, 86)
	_body.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 124)
	scroll.size = Vector2(772, 516)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "Decks"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var decks := TrainingSetup.available_decks().filter(func(d: Deck): return d.validate() == "")
	if decks.is_empty():
		var none := _centered(tr("No finished deck yet: build one in the Collection"), 22, Vector2(60, 300), 720)
		none.name = "NoDecks"
	for i in decks.size():
		var d: Deck = decks[i]
		var b := DeckBox.new(d)
		b.name = "Deck%d" % i
		b.selected = deck != null and d.name == deck.name and d.hero == deck.hero
		b.pressed.connect(func(): choose_deck(d))
		b.gui_input.connect(func(ev):  # a double click searches at once
			if ev is InputEventMouseButton and ev.double_click and queued == "":
				choose_deck(d)
				queue(mode))
		grid.add_child(b)
	# the right column: casual or ranked, the hero, the rank, Play
	for i in MODES.size():
		var m: String = MODES[i]
		var b := Palette.button(tr("Casual") if m == "casual" else tr("Ranked"), "Mode_" + m)
		b.position = Vector2(848 + i * 208, 76)
		b.custom_minimum_size = Vector2(200, 50)
		b.add_theme_font_size_override("font_size", 22)
		b.toggle_mode = true
		b.button_pressed = m == mode
		b.modulate = Color.WHITE if m == mode else Color(0.62, 0.58, 0.55)
		b.disabled = queued != ""
		b.pressed.connect(func(): set_mode(m))
		_body.add_child(b)
	var plate := HeroPlate.new()
	plate.name = "HeroPlate"
	plate.deck = deck
	plate.searching = queued != ""
	plate.position = Vector2(848, 136)
	plate.size = Vector2(408, 330)
	_body.add_child(plate)
	var info := Control.new()
	info.position = Vector2(848, 476)
	info.size = Vector2(408, 88)
	_body.add_child(info)
	if queued != "":
		var t := _centered("", 22, Vector2(0, 26), 408, Palette.SELECTED, info)
		t.name = "QueueTime"
		t.text = tr("Searching for an opponent… %s") % _mmss(waited)
	elif mode == "ranked":
		var r := RankInfo.new()
		r.name = "RankInfo"
		r.rank = link.me.get("rank", {})
		r.text = rank_text(r.rank)
		r.size = info.size
		info.add_child(r)
	else:
		_centered(tr("No rank, a hidden rating finds an equal opponent"), 18, Vector2(10, 18), 388, Color("e0d2b4"), info)
	var go := PlayButton.new()
	go.position = Vector2(848, 572)
	go.size = Vector2(408, 124)
	if queued != "":
		go.name = "Unqueue"
		go.text = tr("Cancel")
		go.calm = true
		go.pressed.connect(unqueue)
	else:
		go.name = "Queue_" + mode
		go.text = tr("Play")
		go.disabled = deck == null
		go.pressed.connect(func(): queue(mode))
	_body.add_child(go)


func choose_deck(d: Deck) -> void:
	if queued != "":
		return
	deck = d
	link.remember({"deck": {"name": d.name, "hero": d.hero}})
	_go("lobby")


func set_mode(m: String) -> void:
	mode = m
	link.remember({"mode": m})
	_go("lobby")


func queue(m: String) -> void:
	if deck == null or deck.validate() != "":
		say(tr("Choose your deck"))
		return
	if not _game_here():
		return
	link.game_deck = deck
	link.send(link.with_pack({"t": "queue", "mode": m, "deck": deck.to_dict()}))
	queued = m
	waited = 0.0
	say("")
	_go("lobby")


func unqueue() -> void:
	link.send({"t": "unqueue"})
	queued = ""
	_go("lobby")


# --- arena --------------------------------------------------------------------

func _build_arena() -> void:
	var st: String = arena.get("status", "")  # only "over" (set here after the last game); the server's run has none
	if arena.is_empty() or st == "over":
		_build_ticket(st == "over")
	elif Packs.active() and str(arena.get("pack", Packs.active().rules_hash())) != Packs.active().rules_hash():
		_build_other_arena()
	elif str(arena.get("hero", "")) == "":
		_build_heroes()
	elif not arena.get("done", false):
		_build_draft()
	else:
		_build_run()


## The run is in another game (pack): use that game (download it first if needed) or retire.
func _build_other_arena() -> void:
	var h := str(arena.get("pack", ""))
	var entry := {}
	for e in link.packs.server + link.packs.mine:
		if str(e.get("rules_hash", "")) == h:
			entry = e
	var have := ServerLink.local_pack(entry) if not entry.is_empty() else null
	var name := have.title(Settings.language()) if have else (entry_title(entry) if not entry.is_empty() else "?")
	var l := _centered(tr("Your Arena run is in another game: %s") % name, 26, Vector2(290, 200), 700, Palette.ATTACK)
	l.name = "OtherArena"
	var go := Palette.button(tr("Use") if have else tr("Download"), "ArenaGame")
	go.position = Vector2(440, 320)
	go.custom_minimum_size = Vector2(400, 60)
	go.disabled = have == null and (entry.is_empty() or link.downloading.has(str(entry.get("content_hash", ""))))
	go.pressed.connect(func():
		if have:
			Packs.set_active(have)
			link.request_me()
			deck = remembered_deck(link)
			_go("lobby")
		else:
			link.download_pack(entry)
			go.disabled = true
			say(tr("Downloading…")))
	_body.add_child(go)
	var quit := Palette.button(tr("Retire"), "ArenaRetire")
	quit.position = Vector2(540, 400)
	quit.custom_minimum_size = Vector2(200, 46)
	quit.pressed.connect(func():
		if _retire_armed:
			link.send({"t": "arena_retire"})
			return
		_retire_armed = true
		quit.text = tr("Retire? Press again"))
	_body.add_child(quit)


## No run: the ticket, and the last run's result.
func _build_ticket(after: bool) -> void:
	if after:
		var res := _centered(tr("Your last Arena: %d wins, %d losses") % [int(arena.get("wins", 0)), int(arena.get("losses", 0))], 24, Vector2(340, 80), 600, Palette.ATTACK)
		res.name = "LastArena"
	var t := Ticket.new()
	t.name = "Ticket"
	t.position = Vector2(400, 124)
	t.size = Vector2(480, 300)
	_body.add_child(t)
	var go := PlayButton.new()
	go.name = "ArenaStart"
	go.text = tr("Enter the Arena")
	go.position = Vector2(440, 444)
	go.size = Vector2(400, 104)
	go.pressed.connect(func():
		if _game_here():
			link.send(link.with_pack({"t": "arena_start"})))
	_body.add_child(go)
	_centered(tr("Draft a deck from three cards at a time, then play until 12 wins or 3 losses"), 18, Vector2(390, 560), 500, Color("e0d2b4"))


func _build_heroes() -> void:
	_centered(tr("Choose your hero"), 30, Vector2(240, 76), 800, Palette.ATTACK)
	var heroes: Array = arena.get("heroes", [])
	var x0 := (1280 - heroes.size() * 300 - (heroes.size() - 1) * 40) / 2.0
	for i in heroes.size():
		var h := HeroChoice.new(str(heroes[i]))
		h.name = "Hero_%d" % i
		h.position = Vector2(x0 + i * 340, 128)
		h.size = Vector2(300, 440)
		var k := i
		h.pressed.connect(func(): link.send({"t": "arena_hero", "i": k}))
		_body.add_child(h)


func _build_draft() -> void:
	var cards: Array = arena.get("cards", [])
	_centered(tr("Choose a card: pick %d of 30") % (cards.size() + 1), 26, Vector2(40, 72), LIST_X - 80, Palette.ATTACK)
	var offer: Array = arena.get("offer", [])
	var k := ArenaView.OFFER_SCALE
	var w := CardView.SIZE.x * k
	var x0 := (LIST_X - (offer.size() * w + (offer.size() - 1) * 44)) / 2.0
	for i in offer.size():
		var cv := CardView.make(offer[i], k)
		cv.name = "Offer%d" % i
		cv.position = Vector2(x0 + i * (w + 44), 116)
		var n := i
		cv.clicked.connect(func(_v): link.send({"t": "arena_pick", "i": n}))
		_body.add_child(cv)
	if not offer.is_empty():
		var tier := ArenaDraft.tier(offer[0])
		_centered({"common": tr("Common"), "rare": tr("Rare"), "epic": tr("Epic"), "legendary": tr("Legendary")}.get(tier, ""),
			18, Vector2(40, 422), LIST_X - 80, Palette.of_rarity(tier.to_upper()))
	var curve := ManaCurve.new()
	curve.name = "Curve"
	var d := arena_deck()
	var counts := [0, 0, 0, 0, 0, 0, 0, 0]
	for id in d.cards:
		counts[mini(int(CardDb.card(id).get("cost", 0)), 7)] += 1
	curve.counts = counts
	curve.position = Vector2(400, 500)
	curve.size = Vector2(380, 150)
	_body.add_child(curve)
	_deck_list(d)


## The drafted deck: the record, Play (or the search), Retire, the deck list.
func _build_run() -> void:
	var plate := HeroPlate.new()
	plate.name = "HeroPlate"
	plate.deck = arena_deck()
	plate.searching = queued == "arena"
	plate.position = Vector2(40, 80)
	plate.size = Vector2(380, 330)
	_body.add_child(plate)
	var rec := Record.new()
	rec.name = "Record"
	rec.wins = int(arena.get("wins", 0))
	rec.losses = int(arena.get("losses", 0))
	rec.position = Vector2(450, 80)
	rec.size = Vector2(490, 330)
	_body.add_child(rec)
	var go := PlayButton.new()
	go.position = Vector2(450, 470)
	go.size = Vector2(490, 116)
	if queued == "arena":
		var t := _centered(tr("Searching for an opponent… %s") % _mmss(waited), 22, Vector2(450, 426), 490, Palette.SELECTED)
		t.name = "QueueTime"
		go.name = "Unqueue"
		go.text = tr("Cancel")
		go.calm = true
		go.pressed.connect(unqueue)
	else:
		go.name = "ArenaQueue"
		go.text = tr("Play")
		go.pressed.connect(func():
			link.game_deck = arena_deck()
			link.send({"t": "arena_queue"})
			queued = "arena"
			waited = 0.0
			say("")
			_go("lobby"))
	_body.add_child(go)
	var quit := Palette.button(tr("Retire"), "ArenaRetire")
	quit.position = Vector2(595, 600)
	quit.custom_minimum_size = Vector2(200, 46)
	quit.disabled = queued != ""
	quit.pressed.connect(func():
		if _retire_armed:
			link.send({"t": "arena_retire"})
			return
		_retire_armed = true
		quit.text = tr("Retire? Press again"))
	_body.add_child(quit)
	_deck_list(arena_deck())


func _deck_list(d: Deck) -> void:
	_panel(Vector2(LIST_X, 76), Vector2(292, 632))
	var head := HeroStrip.new()
	head.hero = d.hero
	head.text = "%s · %d / 30" % [CardText.name(d.hero), d.cards.size()]
	head.position = Vector2(LIST_X + 8, 84)
	head.size = Vector2(276, 48)
	_body.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(LIST_X + 8, 138)
	scroll.size = Vector2(280, 562)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "ArenaDeck"
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	for it in d.sorted_counts():
		var t := DeckTiles.DeckTile.new(it[0], it[1])
		t.custom_minimum_size.x = 268
		list.add_child(t)


## The Arena deck of the run (for its games).
func arena_deck() -> Deck:
	var d := Deck.new()
	d.name = tr("Arena")
	d.hero = str(arena.get("hero", ""))
	d.arena = true
	for id in arena.get("cards", []):
		d.cards.append(str(id))
	return d


# --- games (packs) on this server ------------------------------------------------

## The top bar's game: the active pack's name (a warning mark when this server lacks it).
func _game_line() -> String:
	var p := Packs.active()
	return ("" if link.has_game(p) else "! ") + (p.title(Settings.language()) if p else "")


## Whether the active game can be played here; if not, says so and shows the server's games.
func _game_here() -> bool:
	if link.has_game(Packs.active()):
		return true
	say(link.game_problem(Packs.active()))
	show_games()
	return false


## A server pack's name in the interface language ({lang: text}), else its id.
static func entry_title(e: Dictionary) -> String:
	var n = e.get("name")
	if n is Dictionary and not n.is_empty():
		var lang := Settings.language()
		for k in [lang, lang.get_slice("_", 0), "en"]:
			if n.has(k):
				return str(n[k])
		return str(n.values()[0])
	return str(e.get("id", "?"))


## The "Games on this server" panel: the server's packs and the player's uploads, each
## with Download (and its progress), Use or In use; Upload my game; Delete (own, twice).
func show_games() -> void:
	close_games()
	_delete_armed = ""
	var dim := ColorRect.new()
	dim.name = "GamesPanel"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_games = dim
	_build_games()
	link.request_packs()


func close_games() -> void:
	if _games:
		remove_child(_games)
		_games.queue_free()
		_games = null


func _build_games() -> void:
	for c in _games.get_children():
		_games.remove_child(c)
		c.queue_free()
	var p := _panel(Vector2(240, 60), Vector2(800, 600), _games)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	_centered(tr("Games on this server"), 32, Vector2(20, 14), 760, Palette.ATTACK, p)
	var act := Packs.active()
	var here := link.has_game(act)
	var line := _centered((tr("Your game: %s") % act.title(Settings.language())) + ("" if here else "  ·  " + link.game_problem(act)),
		18, Vector2(20, 62), 760, Palette.TEXT if here else Palette.OPPONENT, p)
	line.name = "GameLine"
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(24, 100)
	scroll.size = Vector2(752, 410)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "GamesList"
	list.custom_minimum_size.x = 740
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var all: Array = link.packs.server + link.packs.mine
	if all.is_empty():
		var none := Palette.label(tr("No games on this server yet") if link.has_packs or not link.logged_in() else tr("This server does not share games"), 18, Color("c9b48a"))
		none.name = "NoGames"
		list.add_child(none)
	for e in all:
		list.add_child(_game_row(e))
	var up := Palette.button(tr("Upload my game"), "UploadPack")
	up.position = Vector2(24, 530)
	up.custom_minimum_size = Vector2(260, 50)
	up.tooltip_text = act.title(Settings.language())
	up.disabled = not link.has_packs
	up.pressed.connect(func():
		up.disabled = true
		_games_say(tr("Uploading %s…") % act.title(Settings.language()))
		link.upload_pack(act))
	p.add_child(up)
	var note := _centered("", 16, Vector2(296, 534), 300, Color("c9b48a"), p)
	note.name = "GamesNote"
	var close := Palette.button(tr("Close"), "CloseGames")
	close.position = Vector2(616, 530)
	close.custom_minimum_size = Vector2(160, 50)
	close.pressed.connect(close_games)
	p.add_child(close)


func _games_say(text: String) -> void:
	var n := _games.find_child("GamesNote", true, false) as Label if _games else null
	if n:
		n.text = text


## One server pack: its name, version and size; on the right what can be done with it.
func _game_row(e: Dictionary) -> Control:
	var h := str(e.get("content_hash", ""))
	var row := PanelContainer.new()
	row.name = "Game_" + h.left(12)
	var st := Palette.box(Color(0, 0, 0, 0.28), 10, Color("6b5320", 0.7), 1)
	st.content_margin_left = 12
	st.content_margin_right = 8
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", st)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	row.add_child(hb)
	var mine := link.is_mine(e)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	hb.add_child(words)
	words.add_child(Palette.label(entry_title(e), 20, Palette.ATTACK))
	var sub := "%s · %s" % [str(e.get("version", "")), Packs.size_text(int(e.get("size", 0)))]
	if mine:
		sub += " · " + (tr("uploaded by you") if e.get("enabled", true) else tr("uploaded by you, turned off"))
	words.add_child(Palette.label(sub, 15, Color("c9b48a")))
	var have := ServerLink.local_pack(e)
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	hb.add_child(right)
	if have and have == Packs.active():
		right.add_child(Palette.label(tr("In use"), 18, Color("8fd97a")))
	elif have:
		_row_button(right, tr("Use"), "Use", func():
			Packs.set_active(have)
			link.request_me()
			deck = remembered_deck(link)
			_go(stage)
			_build_games())
	elif link.downloading.has(h):
		var prog := Palette.label(tr("Downloading…"), 17, Palette.SELECTED)
		prog.name = "Progress"
		right.add_child(prog)
	else:
		_row_button(right, tr("Download"), "Download", func():
			link.download_pack(e)
			_build_games())
	if mine:
		var del := _row_button(right, tr("Delete"), "Delete", func(): pass)
		del.pressed.connect(func():
			if _delete_armed == h:
				link.delete_pack(h)
				_delete_armed = ""
				_games_say(tr("Deleting…"))
				return
			_delete_armed = h
			del.text = tr("Delete? Press again"))
	return row


func _row_button(parent: Control, text: String, id: String, fn: Callable) -> Button:
	var b := Palette.button(text, id)
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


func _packs_changed() -> void:
	if _games:
		_build_games()
	if link.logged_in() and Packs.active() and str(link.me.get("pack", "")) != Packs.active().rules_hash() and not link.server_pack_for(Packs.active(), false).is_empty():
		link.request_me()  # the rank in the active game
	if stage == "lobby":
		_go("lobby")


func _pack_progress(h: String, done: int, total: int) -> void:
	var row := _games.find_child("Game_" + h.left(12), true, false) if _games else null
	var l := row.find_child("Progress", true, false) as Label if row else null
	if l:
		l.text = tr("Downloading… %d%%") % (100 * done / total) if total > 0 else tr("Downloading…")


func _pack_downloaded(_h: String, res: Dictionary) -> void:
	if stage == "lobby" and not _games:
		_go("lobby")
		say(tr("Downloaded: %s") % res.pack.title(Settings.language()) if res.has("pack") else str(res.get("error", "")))
	if _games:
		_build_games()
		_games_say(tr("Downloaded: %s") % res.pack.title(Settings.language()) if res.has("pack") else str(res.get("error", "")))


func _pack_uploaded(res: Dictionary) -> void:
	if _games:
		_build_games()
		_games_say(tr("Uploaded: %s") % entry_title(res.pack) if res.has("pack") else str(res.get("error", "")))


# --- messages from the server -------------------------------------------------

func _on_message(msg: Dictionary) -> void:
	match msg.t:
		"auth":
			if msg.get("ok", false):
				_set_arena(link.me.get("arena"))
				say("")
				_go("lobby")
			else:
				say(str(msg.get("text", tr("Wrong account name or password"))))
		"error":
			if stage == "connecting":  # a refused saved session: log in by hand
				_go("login")
			say(str(msg.get("text", msg.get("code", "error"))))
			if msg.get("code", "") in ["queue", "deck"]:
				queued = ""
				_go("lobby")
		"me":
			link.me = msg.get("me", msg)
			_set_arena(link.me.get("arena"))
			if stage == "lobby":
				_go("lobby")
		"queued":
			queued = str(msg.get("mode", queued))
		"queue_status":
			waited = float(msg.get("waited", waited))
		"arena":
			_set_arena(msg.get("state"))
			if stage == "lobby" and tab == "Arena":
				_go("lobby")
		"match":
			queued = ""  # main starts the game
			say(tr("Opponent found!"))
		"game_over":
			say(_result_text(msg))
			var a = msg.get("arena")
			if a is Dictionary:
				if a.get("over", false):
					arena = {"status": "over", "wins": a.get("wins", 0), "losses": a.get("losses", 0)}
				else:
					arena.merge(a, true)
			link.request_me()
		"invite_declined":
			say(tr("%s declined the invitation") % str(msg.get("by", "")))
		"logged_out":
			_go("login")
		"kicked":
			queued = ""
			_go("login")
			say(tr("You logged in on another device"))


func _set_arena(v: Variant) -> void:
	if not v is Dictionary and arena.get("status", "") == "over":
		return  # keep the result of the run that just ended
	arena = v if v is Dictionary else {}
	if stage == "lobby" and tab == "Arena":
		_go("lobby")


## "name#tag", or the name alone before the player sets a tag.
static func player_label(p: Dictionary) -> String:
	var t := _str(p.get("tag"))
	return str(p.get("user", "")) + ("#" + t if t != "" else "")


static func _str(v: Variant) -> String:
	return "" if v == null else str(v)


func _result_text(msg: Dictionary) -> String:
	var res: String = {"win": tr("Victory!"), "loss": tr("Defeat"), "draw": tr("Draw")}.get(str(msg.get("result", "")), "")
	var r: Dictionary = msg.get("rank", {})
	return res + ("  ·  " + rank_text(r) if not r.is_empty() else "")


# --- drawing --------------------------------------------------------------------

## Text centred on x (cut with … to width).
static func ctext(ci: Control, x: float, baseline: float, s: String, font_size: int, col := Palette.TEXT, width := 10000.0) -> void:
	var f := ci.get_theme_font("font", "Label")
	var w := minf(f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, width)
	DeckTiles.text(ci, Vector2(x - w / 2.0, baseline), s, font_size, col, width)


## A band of a card's picture filling rect (focus: where the band sits, 0 top … 1 bottom).
static func band(ci: CanvasItem, rect: Rect2, card_id: String, focus := 0.3) -> void:
	var tex := Art.texture(card_id)
	if tex == null:
		Art.paint(ci, rect, card_id)
		return
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var src := Rect2(0, 0, tw, tw * rect.size.y / rect.size.x)
	if src.size.y > th:
		src = Rect2(0, 0, th * rect.size.x / rect.size.y, th)
		src.position.x = (tw - src.size.x) / 2.0
	src.position.y = clampf(th * focus - src.size.y / 2.0, 0.0, th - src.size.y)
	ci.draw_texture_rect_region(tex, rect, src)


## A big arched hero portrait in a gold frame (the crest on top).
static func portrait(ci: CanvasItem, r: Rect2, hero: String) -> void:
	var cls := Decks.card_class(hero) if hero != "" else "NEUTRAL"
	ci.draw_colored_polygon(Art.outline("arch", r.grow(9)), Color("2a1a0b"))
	ci.draw_colored_polygon(Art.outline("arch", r.grow(6)), Frames.GOLD.darkened(0.25))
	ci.draw_colored_polygon(Art.outline("arch", r.grow(2)), Palette.of_class(cls).darkened(0.35))
	if hero != "":
		Art.paint_in(ci, r, hero, "arch")
	Frames.ring(ci, Art.outline("arch", r), Frames.GOLD, 3)
	Frames.crest(ci, Vector2(r.get_center().x, r.position.y + 6), r.size.x * 0.62)


## A star of the rank (filled or empty).
static func star(ci: CanvasItem, c: Vector2, r: float, filled: bool) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + PI * i / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(pts, Color("ffd75e") if filled else Color(0.1, 0.07, 0.04, 0.9))
	Frames.ring(ci, pts, Color("8a6d2a") if filled else Color("6b5320"), 1.5)


## A deck box: the hero's portrait, the class crest and the deck's name on a plate.
class DeckBox:
	extends Button
	var deck: Deck
	var selected := false

	func _init(d: Deck) -> void:
		deck = d
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(244, 160)
		tooltip_text = d.name
		pressed.connect(Sound.play.bind("click"))
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		var cls := deck.card_class()
		if selected:
			for i in 3:
				draw_style_box(Palette.box(Color(0, 0, 0, 0), 16 + i * 2, Color(1, 0.82, 0.3, 0.45 - i * 0.13), 3), r.grow(1 + i * 2))
		draw_style_box(Palette.box(Palette.of_class(cls).darkened(0.6), 12, Frames.GOLD.darkened(0.45 if not selected else 0.0), 3), r)
		var art := Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 46))
		ServerView.band(self, art, deck.hero, 0.3)
		if not selected and not is_hovered():
			draw_rect(art, Color(0, 0, 0, 0.22))
		var plate := Rect2(Vector2(r.position.x + 3, r.end.y - 42), Vector2(r.size.x - 6, 39))
		draw_style_box(Palette.box(Color("21150b"), 8), plate)
		draw_line(plate.position, plate.position + Vector2(plate.size.x, 0), Frames.GOLD.darkened(0.2), 2)
		ServerView.ctext(self, size.x / 2.0, plate.position.y + 27, deck.name, 19, Palette.SELECTED if selected else Palette.TEXT, plate.size.x - 16)
		Icons.paint(self, cls, Rect2(r.position + Vector2(8, 8), Vector2(36, 36)))
		if is_hovered() and not selected:
			draw_style_box(Palette.box(Color(0, 0, 0, 0), 12, Color("e8cc78", 0.8), 3), r)


## The chosen deck's hero, big: a frame, the arched portrait and a ribbon with
## the deck's name. While searching, gold arcs turn around it.
class HeroPlate:
	extends Control
	var deck: Deck
	var searching := false
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(searching and not Anim.instant)

	func _process(d: float) -> void:
		_t += d
		queue_redraw()

	func _draw() -> void:
		draw_style_box(Palette.frame(), Rect2(Vector2.ZERO, size))
		var pr := Rect2(Vector2(size.x / 2.0 - 105, 44), Vector2(210, 226))
		ServerView.portrait(self, pr, deck.hero if deck else "")
		if deck == null:
			ServerView.ctext(self, size.x / 2.0, pr.get_center().y, "?", 64, Palette.ATTACK)
		if searching:
			var c := pr.get_center()
			for i in 3:
				var a := _t * 2.4 + TAU * i / 3.0
				draw_arc(c, 150, a, a + 1.2, 24, Color(1, 0.84, 0.35, 0.85), 6, true)
				draw_arc(c, 162, -a * 0.7, -a * 0.7 + 0.8, 16, Color(1, 0.6, 0.2, 0.5), 3, true)
		var rib := Rect2(Vector2(24, size.y - 54), Vector2(size.x - 48, 40))
		var col := Palette.of_class(deck.card_class() if deck else "NEUTRAL").darkened(0.35)
		var k := 14.0
		draw_colored_polygon(PackedVector2Array([rib.position - Vector2(k, -4), rib.position, Vector2(rib.end.x, rib.position.y), Vector2(rib.end.x + k, rib.position.y + 4),
			Vector2(rib.end.x + 4, rib.get_center().y + 4), Vector2(rib.end.x + k, rib.end.y + 4), rib.end, Vector2(rib.position.x, rib.end.y),
			Vector2(rib.position.x - k, rib.end.y + 4), Vector2(rib.position.x - 4, rib.get_center().y + 4)]), col)
		draw_line(rib.position, Vector2(rib.end.x, rib.position.y), Frames.GOLD, 2)
		draw_line(Vector2(rib.position.x, rib.end.y), rib.end, Frames.GOLD, 2)
		ServerView.ctext(self, size.x / 2.0, rib.position.y + 28, deck.name if deck else tr("Choose your deck"), 22, Palette.TEXT, rib.size.x - 12)


## The rank medal with the stars and the rank's name (Legend: the place).
class RankInfo:
	extends Control
	var rank := {}
	var text := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var e := RankEmblem.new()
		e.rank = rank
		e.position = Vector2(4, 0)
		e.size = Vector2(88, 88)
		add_child(e)

	func _draw() -> void:
		draw_style_box(Palette.box(Color(0.07, 0.045, 0.025, 0.85), 12, Color("6b5320"), 2), Rect2(Vector2(44, 6), size - Vector2(44, 12)))
		var n := int(rank.get("rank", 25))
		var name := tr("Legend") if n == 0 else ServerView.rank_name(n)
		if name == "":
			name = tr("Rank %d") % n
		DeckTiles.text(self, Vector2(104, 38), name, 20, Palette.ATTACK, size.x - 112)
		if n == 0:
			var place := int(rank.get("legend")) if rank.get("legend") is float else 0
			if place > 0:
				DeckTiles.text(self, Vector2(104, 68), "#%d" % place, 20, Palette.TEXT)
			return
		var need := ServerView.stars_needed(n)
		for i in need:
			ServerView.star(self, Vector2(118 + i * 30, 62), 12, i < int(rank.get("stars", 0)))


## The rank's emblem in a gold ring, from the active pack: a card's art, a picture, or the
## crest when it has none (Legend: a gold crest).
class RankEmblem:
	extends Control
	var rank := {}
	var _tex: Texture2D
	var _tex_of := ""

	## The active pack's picture for an {image} emblem (loaded once).
	func _image(file: String) -> Texture2D:
		if _tex_of != file:
			_tex_of = file
			_tex = Packs.active().texture(file)
		return _tex

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 6
		draw_circle(c, r + 6, Color("c9a74a"))
		draw_circle(c, r + 2, Color("2a1d10"))
		var n := int(rank.get("rank", 25))
		if n == 0:
			draw_circle(c, r, Color("ff9f1a"))
			Sprites.draw(self, "class_NEUTRAL", c, r * 1.4)
			return
		var e = ServerView.rank_rule(n).get("emblem")
		var box := Rect2(c - Vector2(r, r), Vector2(r, r) * 2)
		if e is Dictionary and e.get("card") is String:
			Art.paint_in(self, box, str(e.card), "circle")
		elif e is Dictionary and e.get("image") is String and _image(str(e.image)):
			var pts := Art.outline("circle", box)
			var uvs := PackedVector2Array()
			for pt in pts:
				uvs.append((pt - box.position) / box.size)
			draw_colored_polygon(pts, Color.WHITE, uvs, _tex)
		else:  # no emblem: the crest
			draw_circle(c, r, Color("7a4a1c"))
			Sprites.draw(self, "class_NEUTRAL", c, r * 1.4)
		var f := get_theme_default_font()
		var fs := int(size.y * 0.34)
		draw_string_outline(f, Vector2(0, size.y - 4), str(n), HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, 6, Color.BLACK)
		draw_string(f, Vector2(0, size.y - 4), str(n), HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color("ffd75e"))


## The big Play button: a glowing gold plaque (calm: a plain one, for Cancel).
class PlayButton:
	extends Button
	var calm := false
	var _t := 0.0

	func _ready() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		add_theme_font_override("font", Fonts.ui(800))
		pressed.connect(Sound.play.bind("click"))
		set_process(not Anim.instant)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _process(d: float) -> void:
		_t += d
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
		var pulse := 0.5 + 0.5 * sin(_t * 2.6)
		if not disabled and not calm:
			for i in 4:
				draw_style_box(Palette.box(Color(0, 0, 0, 0), 26 + i * 3, Color(1, 0.75, 0.25, (0.28 - i * 0.06) * (0.6 + 0.4 * pulse)), 4), r.grow(2 + i * 3))
		var fill := Color("6b4a14") if not calm else Color("4a2c18")
		if disabled:
			fill = Color("3a3530")
		elif is_hovered():
			fill = fill.lightened(0.15)
		draw_style_box(Palette.box(Color("1b0f06"), 26), r.grow(3))
		draw_style_box(Palette.box(fill, 24, Frames.GOLD if not disabled else Color("6b6b6b"), 4), r)
		var inner := r.grow(-10)
		draw_style_box(Palette.box(Color(1, 0.85, 0.45, 0.10 if not calm else 0.04), 16), Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.45)))
		var f := get_theme_font("font")
		var fs := int(minf(size.y * 0.42, 52))
		var col := Color("fff1c1") if not disabled else Color("9a9a9a")
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2((size.x - w) / 2.0, size.y / 2.0 + fs * 0.34)
		draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color("2a1606"))
		draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## The Arena's admission ticket (no run yet).
class Ticket:
	extends Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(10, 30), size - Vector2(20, 40))
		var pts := PackedVector2Array()
		var notch := 22.0
		var cy := r.get_center().y
		pts.append_array([r.position, Vector2(r.end.x, r.position.y)])
		for i in 9:  # a punched half circle on the right
			var a := -PI / 2 - PI * i / 8.0
			pts.append(Vector2(r.end.x, cy) + Vector2(cos(a), sin(a)) * notch)
		pts.append_array([r.end, Vector2(r.position.x, r.end.y)])
		for i in 9:  # and on the left
			var a := PI / 2 - PI * i / 8.0
			pts.append(Vector2(r.position.x, cy) + Vector2(cos(a), sin(a)) * notch)
		draw_colored_polygon(pts, Color("e7d3a2"))
		Frames.ring(self, pts, Color("8a6d2a"), 4)
		var inner := r.grow(-16)
		draw_style_box(Palette.box(Color(0, 0, 0, 0), 8, Color("a8863a", 0.8), 2), inner)
		Frames.crest(self, Vector2(size.x / 2.0, r.position.y + 14), 230)
		var f := get_theme_font("font", "Label")
		var title := tr("Arena")
		var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
		draw_string(f, Vector2((size.x - tw) / 2.0, r.position.y + 132), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color("5a3510"))
		var sub := tr("Admit one")
		var sw := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(f, Vector2((size.x - sw) / 2.0, r.position.y + 176), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color("7a5320"))


## A hero to choose for the Arena: a big portrait, the name and the class crest.
class HeroChoice:
	extends Button
	var hero := ""

	func _init(h: String) -> void:
		hero = h
		flat = true
		focus_mode = Control.FOCUS_NONE
		tooltip_text = CardText.name(h)
		pressed.connect(Sound.play.bind("click"))
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _draw() -> void:
		var cls := Decks.card_class(hero)
		var box := Rect2(Vector2.ZERO, size)
		if is_hovered():
			for i in 3:
				draw_style_box(Palette.box(Color(0, 0, 0, 0), 18 + i * 2, Color(1, 0.82, 0.3, 0.5 - i * 0.14), 3), box.grow(1 + i * 2))
		draw_style_box(Palette.frame(Palette.of_class(cls).darkened(0.7)), box)
		ServerView.portrait(self, Rect2(Vector2(28, 58), Vector2(size.x - 56, 290)), hero)
		ServerView.ctext(self, size.x / 2.0, size.y - 44, CardText.name(hero), 28, Palette.ATTACK, size.x - 20)
		Icons.paint(self, cls, Rect2(Vector2(size.x / 2.0 - 18, size.y - 36), Vector2(36, 30)))


## The run's record, as in 2014: twelve win gems and three loss marks.
class Record:
	extends Control
	var wins := 0
	var losses := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_style_box(Palette.frame(), Rect2(Vector2.ZERO, size))
		ServerView.ctext(self, size.x / 2.0, 82, str(wins), 72, Palette.ATTACK)
		ServerView.ctext(self, size.x / 2.0, 116, tr("Wins"), 22, Palette.TEXT)
		for i in ServerView.ARENA_WINS:
			var c := Vector2(size.x / 2.0 + ((i % 6) - 2.5) * 66, 160 + (i / 6) * 50)
			var won := i < wins
			draw_circle(c, 21, Color("2a1a0b"))
			draw_circle(c, 18, Color("ffcc4d") if won else Color(0.16, 0.11, 0.07))
			if won:
				draw_circle(c + Vector2(-5, -6), 6, Color(1, 1, 1, 0.45))
			Frames.ring(self, Art.outline("circle", Rect2(c - Vector2(18, 18), Vector2(36, 36))), Frames.GOLD.darkened(0.2 if won else 0.5), 2)
			ServerView.ctext(self, c.x, c.y + 7, str(i + 1), 17, Color("3a2306") if won else Color("8a7a60"))
		ServerView.ctext(self, size.x / 2.0, 284, tr("Losses"), 20, Palette.TEXT)
		for i in ServerView.ARENA_LOSSES:
			var c := Vector2(size.x / 2.0 + (i - 1) * 60, 306)
			draw_circle(c, 16, Color("2a1a0b"))
			Frames.ring(self, Art.outline("circle", Rect2(c - Vector2(16, 16), Vector2(32, 32))), Color("6b5320"), 2)
			if i < losses:
				draw_line(c + Vector2(-10, -10), c + Vector2(10, 10), Color("e0352b"), 6, true)
				draw_line(c + Vector2(10, -10), c + Vector2(-10, 10), Color("e0352b"), 6, true)


## A hero's portrait band behind a line of text (the Arena deck's header).
class HeroStrip:
	extends Control
	var hero := ""
	var text := ""

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(Palette.box(Color("1b140f"), 8, Color("6b5320"), 2), r)
		if hero != "":
			DeckTiles.strip(self, r.grow(-3), hero, 0.3)
		DeckTiles.text(self, Vector2(12, size.y / 2.0 + 7), text, 19, Palette.ATTACK, size.x - 20)


## Gold arcs turning (waiting for the server).
class Spinner:
	extends Control
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		_t += d
		queue_redraw()

	func _draw() -> void:
		for i in 3:
			var a := _t * 3.0 + TAU * i / 3.0
			draw_arc(Vector2.ZERO, 40, a, a + 1.3, 20, Color(1, 0.84, 0.35, 0.9), 6, true)
