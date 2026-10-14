class_name ServerView
extends Control
## Playing through a game server: log in or register, then the lobby — Play
## (casual and ranked with a deck), the Arena (12 wins or 3 losses), friends
## (by tag, requests, messages, invites, blocking) and the profile. The games
## themselves run as a NetSession over the server (main shows the match).
## Protocol: docs/superpowers/specs/2026-10-15-server-design.md.

signal back
signal play(session: NetSession, m: Match, mode: String)

## The 2014 ranks are named after cards: their art is the rank's emblem.
const RANK_CARDS := ["VAN_EX1_002", "VAN_EX1_620", "VAN_EX1_105", "VAN_EX1_586", "VAN_EX1_178", "VAN_EX1_032",
	"VAN_CS2_226", "VAN_CS2_151", "VAN_CS2_197", "VAN_EX1_005", "VAN_EX1_084", "VAN_NEW1_022", "VAN_CS2_122",
	"VAN_EX1_023", "VAN_EX1_044", "VAN_EX1_390", "VAN_EX1_608", "VAN_EX1_015", "VAN_EX1_405", "VAN_CS2_146",
	"VAN_CS2_168", "VAN_EX1_008", "VAN_EX1_029", "VAN_EX1_009"]  # ranks 2 … 25; rank 1 is the Innkeeper
const TABS := ["Play", "Arena", "Friends", "Profile"]

var link: ServerLink
var stage := ""  # "connecting", "login", "lobby"
var tab := "Play"
var deck: Deck  # the deck chosen for casual, ranked and friendly games
var friends := {"list": [], "requests_in": [], "requests_out": [], "blocked": []}
var arena := {}  # the Arena run from the server
var chat_with := ""
var chats := {}  # user -> [{from, text, at}]
var queued := ""  # the mode being searched ("" = none)
var waited := 0.0
var invite_from := ""
var _title: Label
var _subtitle: Label
var _status: Label
var _body := Control.new()
var _chooser: DeckChooser


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self)
	_title = Palette.label(tr("Game server"), 40, Palette.ATTACK)
	_title.position = Vector2(40, 18)
	add_child(_title)
	_subtitle = Palette.label("", 20)
	_subtitle.position = Vector2(42, 72)
	add_child(_subtitle)
	_status = Palette.label("", 18, Palette.SELECTED)
	_status.name = "Status"
	_status.position = Vector2(42, 682)
	_status.custom_minimum_size.x = 1180
	add_child(_status)
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	deck = _first_playable()
	link.message.connect(_on_message)
	link.closed.connect(func(why):
		queued = ""
		_go("login")
		say(tr("Connection lost") + (": " + why if why != "" else "")))
	if link.is_open() and link.token != "":
		_go("lobby")
		link.send({"t": "friends"})
		var last: Dictionary = link.get_meta("game_over", {})
		if not last.is_empty():
			say(_result_text(last))
			link.remove_meta("game_over")
	elif link.is_open():
		_go("login")
	else:
		_go("connecting")
		if link.open(Settings.data.server) != OK:
			_go("login")
			say(tr("Could not connect to %s") % Settings.data.server)
		else:
			link.opened.connect(func(): _go("login"), CONNECT_ONE_SHOT)


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


func _first_playable() -> Deck:
	for d in TrainingSetup.available_decks():
		if d.validate() == "":
			return d
	return null


## Rebuilds the screen for a stage.
func _go(s: String) -> void:
	stage = s
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_subtitle.text = Settings.data.server
	match s:
		"connecting":
			_subtitle.text = tr("Connecting to %s…") % Settings.data.server
			_back_button(Vector2(40, 620))
		"login":
			_build_login()
		"lobby":
			_build_lobby()


func _back_button(at: Vector2) -> void:
	var b := Palette.button(tr("Back"), "Back")
	b.position = at
	b.custom_minimum_size = Vector2(200, 48)
	b.pressed.connect(func():
		link.close()
		back.emit())
	_body.add_child(b)


# --- log in -------------------------------------------------------------------

func _build_login() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(140, 150)
	box.custom_minimum_size.x = 420
	box.add_theme_constant_override("separation", 12)
	_body.add_child(box)
	var user := LineEdit.new()
	user.name = "User"
	user.placeholder_text = tr("Account name")
	user.max_length = 20
	user.text = Profile.load_name().replace(" ", "_")
	var pw := LineEdit.new()
	pw.name = "Password"
	pw.placeholder_text = tr("Password (8 characters or more)")
	pw.secret = true
	pw.max_length = 128
	for e in [user, pw]:
		e.custom_minimum_size = Vector2(420, 48)
		e.add_theme_font_size_override("font_size", 22)
		box.add_child(e)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	for spec in [[tr("Log in"), "Login", "login"], [tr("Register"), "Register", "register"]]:
		var b := Palette.button(spec[0], spec[1])
		b.custom_minimum_size = Vector2(202, 52)
		var op: String = spec[2]
		b.pressed.connect(func(): log_in(op, user.text.strip_edges(), pw.text))
		row.add_child(b)
	pw.text_submitted.connect(func(_t): log_in("login", user.text.strip_edges(), pw.text))
	var note := Palette.label(tr("The password goes only to this server. Use a server you trust; a public server needs wss:// (TLS)."), 16)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 420
	box.add_child(note)
	_back_button(Vector2(40, 620))


func log_in(op: String, user: String, password: String) -> void:
	if user.length() < 3 or password.length() < 8:
		say(tr("An account name of 3 or more letters and a password of 8 or more characters"))
		return
	link.send({"t": op, "user": user, "password": password})
	say(tr("Connecting…"))


# --- lobby --------------------------------------------------------------------

func _build_lobby() -> void:
	var me := link.me
	_subtitle.text = "%s#%s  ·  %s" % [me.get("user", ""), me.get("tag", ""), rank_text(me.get("rank", {}))]
	var tabs := VBoxContainer.new()
	tabs.position = Vector2(40, 130)
	tabs.add_theme_constant_override("separation", 10)
	_body.add_child(tabs)
	for t in TABS:
		var b := Palette.button(tr(t), "Tab" + t)
		b.custom_minimum_size = Vector2(220, 52)
		b.toggle_mode = true
		b.button_pressed = t == tab
		var name_t: String = t
		b.pressed.connect(func():
			tab = name_t
			_go("lobby"))
		tabs.add_child(b)
	var area := Control.new()
	area.name = "Area"
	area.position = Vector2(300, 130)
	area.size = Vector2(940, 540)
	_body.add_child(area)
	match tab:
		"Play":
			_build_play(area)
		"Arena":
			_build_arena(area)
		"Friends":
			_build_friends(area)
		"Profile":
			_build_profile(area)
	if invite_from != "":
		_build_invite()


## "Rank 18 · Sorcerer's Apprentice · stars 2 of 3" or "Legend 42".
func rank_text(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	if r.get("legend", false) or int(r.get("rank", 25)) == 0:
		var n := int(r.get("legend_rank", 0))
		return tr("Legend") + (" %d" % n if n > 0 else "")
	var rank := int(r.get("rank", 25))
	var need := 2 if rank > 20 else (3 if rank > 15 else (4 if rank > 10 else 5))
	var stars := int(r.get("stars", 0))
	return tr("Rank %d") % rank + " · " + rank_name(rank) + " · " + tr("stars %d of %d") % [stars, need]


static func rank_name(rank: int) -> String:
	if rank == 1:
		return TranslationServer.translate("Innkeeper")
	return CardText.name(RANK_CARDS[rank - 2]) if rank >= 2 and rank <= 25 else ""


func _build_play(area: Control) -> void:
	var emblem := RankEmblem.new()
	emblem.rank = link.me.get("rank", {})
	emblem.position = Vector2(0, 0)
	emblem.size = Vector2(120, 120)
	area.add_child(emblem)
	var r := Palette.label(rank_text(link.me.get("rank", {})), 22, Palette.ATTACK)
	r.position = Vector2(140, 20)
	area.add_child(r)
	var d := Palette.label(tr("Your deck: %s") % (deck.name if deck else "—"), 20)
	d.name = "DeckLine"
	d.position = Vector2(140, 60)
	area.add_child(d)
	var pick := Palette.button(tr("Choose a deck"), "ChooseDeck")
	pick.position = Vector2(140, 92)
	pick.custom_minimum_size = Vector2(220, 40)
	pick.pressed.connect(_choose_deck)
	area.add_child(pick)
	if queued != "":
		var t := Palette.label("", 26, Palette.SELECTED)
		t.name = "QueueTime"
		t.position = Vector2(0, 200)
		area.add_child(t)
		var stop := Palette.button(tr("Cancel"), "Unqueue")
		stop.position = Vector2(0, 260)
		stop.custom_minimum_size = Vector2(240, 52)
		stop.pressed.connect(func():
			link.send({"t": "unqueue"})
			queued = ""
			_go("lobby"))
		area.add_child(stop)
		return
	var row := HBoxContainer.new()
	row.position = Vector2(0, 200)
	row.add_theme_constant_override("separation", 30)
	area.add_child(row)
	for spec in [["casual", tr("Casual game"), tr("No rank, a hidden rating finds an equal opponent")],
			["ranked", tr("Ranked game"), tr("25 ranks and Legend, as in 2014: stars for wins, a new season every month")]]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		row.add_child(col)
		var b := Palette.button(spec[1], "Queue_" + spec[0])
		b.custom_minimum_size = Vector2(400, 140)
		b.add_theme_font_size_override("font_size", 28)
		var mode: String = spec[0]
		b.pressed.connect(func(): queue(mode))
		col.add_child(b)
		var why := Palette.label(spec[2], 17)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size.x = 400
		col.add_child(why)


func queue(mode: String) -> void:
	if deck == null or deck.validate() != "":
		say(tr("Choose your deck"))
		return
	link.send({"t": "queue", "mode": mode, "deck": deck.to_dict()})
	queued = mode
	waited = 0.0
	_go("lobby")


func _choose_deck() -> void:
	var dim := ColorRect.new()
	dim.name = "DeckDialog"
	dim.color = Color(0.05, 0.03, 0.02, 0.95)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_child(dim)
	var c := DeckChooser.new()
	c.position = Vector2(140, 90)
	c.size = Vector2(1000, 580)
	c.chosen.connect(func(dk: Deck):
		deck = dk
		dim.queue_free()
		_go("lobby"))
	c.back.connect(func(): dim.queue_free())
	c.edit_decks.connect(func(): dim.queue_free())
	dim.add_child(c)


# --- arena --------------------------------------------------------------------

func _build_arena(area: Control) -> void:
	var st: String = arena.get("status", "")
	if arena.is_empty() or st in ["", "none", "over"]:
		if st == "over":
			var res := Palette.label(tr("Your last Arena: %d wins, %d losses") % [int(arena.get("wins", 0)), int(arena.get("losses", 0))], 22)
			res.position = Vector2(0, 0)
			area.add_child(res)
		var b := Palette.button(tr("Start an Arena run"), "ArenaStart")
		b.position = Vector2(0, 60)
		b.custom_minimum_size = Vector2(400, 120)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(func(): link.send({"t": "arena_start"}))
		area.add_child(b)
		var why := Palette.label(tr("Draft a deck from three cards at a time, then play until 12 wins or 3 losses"), 17)
		why.position = Vector2(0, 196)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size.x = 600
		area.add_child(why)
		return
	var head := Palette.label(tr("Arena: %d wins, %d losses") % [int(arena.get("wins", 0)), int(arena.get("losses", 0))], 22, Palette.ATTACK)
	area.add_child(head)
	if str(arena.get("hero", "")) == "":
		var row := HBoxContainer.new()
		row.position = Vector2(0, 50)
		row.add_theme_constant_override("separation", 12)
		area.add_child(row)
		var heroes: Array = arena.get("heroes", [])
		for i in heroes.size():
			var t := TrainingSetup.HeroTile.new(Decks.card_class(heroes[i]))
			t.name = "Hero_%d" % i
			t.toggle_mode = false
			t.custom_minimum_size = Vector2(300, 150)
			var k := i
			t.pressed.connect(func(): link.send({"t": "arena_hero", "i": k}))
			row.add_child(t)
		return
	var cards: Array = arena.get("cards", [])
	if not arena.get("done", false):
		var picks := Palette.label(tr("Choose a card: pick %d of 30") % (cards.size() + 1), 20)
		picks.position = Vector2(0, 34)
		area.add_child(picks)
		var offer: Array = arena.get("offer", [])
		for i in offer.size():
			var cv := CardView.make(offer[i], 1.45)
			cv.name = "Offer%d" % i
			cv.position = Vector2(i * 200, 70)
			var k := i
			cv.clicked.connect(func(_v): link.send({"t": "arena_pick", "i": k}))
			area.add_child(cv)
	_arena_deck_list(area, cards)
	if arena.get("done", false):
		var row := HBoxContainer.new()
		row.position = Vector2(0, 60)
		row.add_theme_constant_override("separation", 16)
		area.add_child(row)
		if queued == "arena":
			var t := Palette.label("", 24, Palette.SELECTED)
			t.name = "QueueTime"
			row.add_child(t)
		else:
			var go := Palette.button(tr("Find an opponent"), "ArenaQueue")
			go.custom_minimum_size = Vector2(300, 60)
			go.pressed.connect(func():
				link.send({"t": "arena_queue"})
				queued = "arena"
				waited = 0.0
				_go("lobby"))
			row.add_child(go)
			var quit := Palette.button(tr("Retire"), "ArenaRetire")
			quit.custom_minimum_size = Vector2(200, 60)
			quit.pressed.connect(func(): link.send({"t": "arena_retire"}))
			row.add_child(quit)


func _arena_deck_list(area: Control, cards: Array) -> void:
	var d := Deck.new()
	d.hero = str(arena.get("hero", "HERO_08"))
	d.arena = true
	for id in cards:
		d.cards.append(str(id))
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(650, 0)
	scroll.size = Vector2(290, 540)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	area.add_child(scroll)
	var list := VBoxContainer.new()
	scroll.add_child(list)
	list.add_child(Palette.label("%s · %d / 30" % [CardText.name(d.hero), cards.size()], 18, Palette.ATTACK))
	for it in d.sorted_counts():
		var t := DeckTiles.DeckTile.new(it[0], it[1])
		t.custom_minimum_size.x = 276
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


# --- friends and messages -----------------------------------------------------

func _build_friends(area: Control) -> void:
	var mine := Palette.label(tr("Your tag: %s — share it so friends can add you") % link.me.get("tag", ""), 18)
	area.add_child(mine)
	var add := HBoxContainer.new()
	add.position = Vector2(0, 34)
	add.add_theme_constant_override("separation", 8)
	area.add_child(add)
	var tag := LineEdit.new()
	tag.name = "FriendTag"
	tag.placeholder_text = tr("A friend's tag")
	tag.max_length = 16
	tag.custom_minimum_size = Vector2(240, 40)
	add.add_child(tag)
	var b := Palette.button(tr("Add a friend"), "FriendAdd")
	b.custom_minimum_size = Vector2(180, 40)
	b.pressed.connect(func():
		if tag.text.strip_edges() != "":
			link.send({"t": "friend_add", "tag": tag.text.strip_edges()}))
	add.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 86)
	scroll.size = Vector2(500, 454)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	area.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "FriendList"
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for f in friends.get("requests_in", []):
		var row := _friend_row(list, str(f.get("user", "")), "%s#%s" % [f.get("user", ""), f.get("tag", "")] + "  — " + tr("wants to be friends"))
		_small(row, tr("Accept"), func(): link.send({"t": "friend_accept", "user": f.user}))
		_small(row, tr("Decline"), func(): link.send({"t": "friend_decline", "user": f.user}))
	for f in friends.get("list", []):
		var who := str(f.get("user", ""))
		var row := _friend_row(list, who, "%s#%s" % [who, f.get("tag", "")] + (" (" + tr("online") + ")" if f.get("online", false) else ""))
		_small(row, tr("Message"), func():
			chat_with = who
			link.send({"t": "history", "with": who})
			_go("lobby"))
		_small(row, tr("Invite"), func(): invite(who))
		_small(row, tr("Remove"), func(): link.send({"t": "friend_remove", "user": who}))
		_small(row, tr("Block"), func(): link.send({"t": "block", "user": who}))
	for f in friends.get("requests_out", []):
		_friend_row(list, str(f.get("user", "")), "%s#%s  — %s" % [f.get("user", ""), f.get("tag", ""), tr("request sent")])
	for f in friends.get("blocked", []):
		var row := _friend_row(list, str(f.get("user", "")), tr("Blocked: %s") % f.get("user", ""))
		_small(row, tr("Unblock"), func(): link.send({"t": "unblock", "user": f.user}))
	if chat_with != "":
		_build_chat(area)


func _friend_row(list: Container, user: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Friend_" + user
	row.add_theme_constant_override("separation", 6)
	var l := Palette.label(text, 17)
	l.custom_minimum_size.x = 210
	l.clip_text = true
	row.add_child(l)
	list.add_child(row)
	return row


func _small(row: Container, text: String, fn: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(fn)
	row.add_child(b)


func _build_chat(area: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "Chat"
	panel.position = Vector2(520, 0)
	panel.size = Vector2(420, 540)
	panel.add_theme_stylebox_override("panel", Palette.box(Color(0.08, 0.06, 0.04, 0.9), 10, Color("6b5320"), 2))
	area.add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	col.add_child(Palette.label(tr("Messages with %s") % chat_with, 18, Palette.ATTACK))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var lines := VBoxContainer.new()
	lines.name = "ChatLines"
	scroll.add_child(lines)
	for m in chats.get(chat_with, []):
		var l := Palette.label("%s: %s" % [m.get("from", ""), m.get("text", "")], 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 380
		lines.add_child(l)
	scroll.call_deferred("set_v_scroll", 1 << 20)
	var row := HBoxContainer.new()
	col.add_child(row)
	var text := LineEdit.new()
	text.name = "ChatText"
	text.max_length = 500
	text.custom_minimum_size = Vector2(300, 38)
	row.add_child(text)
	var send := func():
		var t := text.text.strip_edges()
		if t != "":
			link.send({"t": "msg", "to": chat_with, "text": t})
			chats[chat_with] = chats.get(chat_with, []) + [{"from": link.me.get("user", ""), "text": t}]
			text.text = ""
			_go("lobby")
	text.text_submitted.connect(func(_t): send.call())
	_small(row, tr("Send"), send)


func invite(user: String) -> void:
	if deck == null or deck.validate() != "":
		say(tr("Choose your deck"))
		return
	link.send({"t": "invite", "to": user, "deck": deck.to_dict()})
	say(tr("Invitation sent to %s") % user)


func _build_invite() -> void:
	var dim := ColorRect.new()
	dim.name = "InviteDialog"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	dim.add_child(box)
	var q := Palette.label(tr("%s invites you to a friendly game (your deck: %s)") % [invite_from, deck.name if deck else "—"], 26, Palette.ATTACK)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(q)
	for spec in [[tr("Accept"), "InviteAccept"], [tr("Decline"), "InviteDecline"]]:
		var c := CenterContainer.new()
		var b := Palette.button(spec[0], spec[1])
		b.custom_minimum_size = Vector2(300, 48)
		var accept: bool = spec[1] == "InviteAccept"
		b.pressed.connect(func():
			if accept and deck:
				link.send({"t": "invite_accept", "from": invite_from, "deck": deck.to_dict()})
			else:
				link.send({"t": "invite_decline", "from": invite_from})
			invite_from = ""
			_go("lobby"))
		c.add_child(b)
		box.add_child(c)


# --- profile ------------------------------------------------------------------

func _build_profile(area: Control) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	area.add_child(box)
	box.add_child(Palette.label(tr("Account: %s") % link.me.get("user", ""), 22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var tag := LineEdit.new()
	tag.name = "TagEdit"
	tag.text = str(link.me.get("tag", ""))
	tag.max_length = 16
	tag.custom_minimum_size = Vector2(260, 40)
	row.add_child(tag)
	var save := Palette.button(tr("Save the tag"), "TagSave")
	save.custom_minimum_size = Vector2(200, 40)
	save.pressed.connect(func(): link.send({"t": "set_tag", "tag": tag.text.strip_edges()}))
	row.add_child(save)
	box.add_child(Palette.label(tr("A tag: 3–16 letters and digits; friends add you by it"), 16))
	var out := Palette.button(tr("Log out"), "Logout")
	out.custom_minimum_size = Vector2(200, 48)
	out.pressed.connect(func():
		link.send({"t": "logout"})
		link.token = ""
		link.me = {}
		_go("login"))
	box.add_child(out)
	var bk := Palette.button(tr("Back to Menu"), "BackToMenu")
	bk.custom_minimum_size = Vector2(200, 48)
	bk.pressed.connect(func():
		link.close()
		back.emit())
	box.add_child(bk)


# --- messages from the server -------------------------------------------------

func _on_message(msg: Dictionary) -> void:
	match msg.t:
		"auth":
			if msg.get("ok", false):
				link.token = str(msg.get("token", ""))
				link.me = msg.get("me", {})
				say("")
				link.send({"t": "friends"})
				_go("lobby")
			else:
				say(str(msg.get("text", tr("Wrong account name or password"))))
		"error":
			say(str(msg.get("text", msg.get("code", "error"))))
			if msg.get("code", "") in ["queue", "deck"]:
				queued = ""
				_go("lobby")
		"me":
			link.me = msg.get("me", msg)
			if stage == "lobby":
				_go("lobby")
		"friends":
			friends = msg
			if stage == "lobby" and tab == "Friends":
				_go("lobby")
		"msg":
			var who := str(msg.get("from", ""))
			chats[who] = chats.get(who, []) + [msg]
			if stage == "lobby" and tab == "Friends" and chat_with == who:
				_go("lobby")
			else:
				say(tr("A message from %s") % who)
		"history":
			chats[str(msg.get("with", ""))] = msg.get("list", [])
			if stage == "lobby":
				_go("lobby")
		"invite":
			invite_from = str(msg.get("from", ""))
			if stage == "lobby":
				_go("lobby")
		"queued":
			queued = str(msg.get("mode", queued))
		"queue_status":
			waited = float(msg.get("waited", waited))
		"arena":
			arena = msg.get("state", msg)
			if stage == "lobby" and tab == "Arena":
				_go("lobby")
		"match":
			_start_game(msg)
		"game_over":
			say(_result_text(msg))


func _result_text(msg: Dictionary) -> String:
	var res: String = {"win": tr("Victory!"), "loss": tr("Defeat"), "draw": tr("Draw")}.get(str(msg.get("result", "")), "")
	var r: Dictionary = msg.get("rank", {})
	return res + ("  ·  " + rank_text(r) if not r.is_empty() else "")


## The server matched us: the game runs as a NetSession over the server.
func _start_game(msg: Dictionary) -> void:
	var mode := str(msg.get("mode", "casual"))
	var d: Deck = arena_deck() if mode == "arena" else deck
	if d == null:
		return
	queued = ""
	var ch := link.channel(str(msg.get("game", "")))
	var s := NetSession.new()
	s.arena = mode == "arena"
	s.seed_override = int(msg.get("seed", -1))
	s.setup(ch, msg.get("host", false) == true, str(link.me.get("user", "")), d)
	link.add_child(ch)
	link.add_child(s)
	s.started.connect(func(m: Match): play.emit(s, m, mode))
	s.failed.connect(func(reason): say(reason))
	s.say_hello()


## The rank's emblem: the namesake card's art in a gold ring (Legend: a gold crest).
class RankEmblem:
	extends Control
	var rank := {}

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 6
		draw_circle(c, r + 6, Color("c9a74a"))
		draw_circle(c, r + 2, Color("2a1d10"))
		var n := int(rank.get("rank", 25))
		if rank.get("legend", false) or n == 0:
			draw_circle(c, r, Color("ff9f1a"))
			Sprites.draw(self, "class_NEUTRAL", c, r * 1.4)
			return
		if n == 1:
			draw_circle(c, r, Color("7a4a1c"))
			Sprites.draw(self, "class_NEUTRAL", c, r * 1.4)
		elif n <= 25:
			Art.paint_in(self, Rect2(c - Vector2(r, r), Vector2(r, r) * 2), ServerView.RANK_CARDS[n - 2], "circle")
		var f := get_theme_default_font()
		draw_string_outline(f, Vector2(0, size.y - 4), str(n), HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, 6, Color.BLACK)
		draw_string(f, Vector2(0, size.y - 4), str(n), HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color("ffd75e"))
