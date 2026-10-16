class_name Social
extends CanvasLayer
## Friends and messages over every screen while logged in to a game server (main
## owns it, like the connections): a friends button in a corner (friends online,
## unread messages), a panel sliding out on the left (presence, requests, add by
## tag, a chat in one click), chat windows that stay over the screen (Enter
## sends), toasts, and friendly-game invites that can be accepted from anywhere.
## Each server has its own friends, chats and invites (D14): with several logged in
## the panel has a tab per server. Works with an older server too: no presence
## pushes, no `chats` or `read`.

## Presence: the dot's colour and the words.
const STATUS := {"online": [Color("5fd35a"), "Online"], "searching": [Color("f2c94c"), "Looking for a game"],
	"in_game": [Color("ff9d3a"), "In a game"], "offline": [Color("7d7468"), "Offline"]}
const ORDER := ["online", "searching", "in_game", "offline"]
const MAX_CHATS := 3
const PANEL_W := 360.0
const CHAT_SIZE := Vector2(300, 380)
const TOAST_TIME := 5.0

## Every server's connection (main's server_links).
var links: Array = []:
	set(v):
		links = v
		_sync()
## The server shown in the panel.
var link: ServerLink:
	get:
		return _cur.link if _cur else null
	set(v):
		_select(v)
## The screen is a game: the button sits beside the gear, chats don't open by themselves.
var in_match := false
## The screen is the server's lobby: errors show in its status line, not as toasts.
var on_lobby := false
## Where the small button goes on a screen whose bottom left is taken (a game, the
## direct Arena); else it is the wide one in the bottom left corner.
var corner := Vector2(-1, -1)
## The panel's server's friends, presence, chats and unread counts (each server keeps its own).
var friends: Dictionary:
	get:
		return _cur.friends if _cur else Server.NO_FRIENDS
var status: Dictionary:  # user -> one of ORDER
	get:
		return _cur.status if _cur else {}
var chats: Dictionary:  # user -> [{from, text, at}]
	get:
		return _cur.chats if _cur else {}
var unread: Dictionary:  # user -> count
	get:
		return _cur.unread if _cur else {}
var open_chats: Array[String] = []  # chat keys: the user (on another server user@url)
var minimized := {}  # chat key -> true
var panel_open := false
var button: FriendsButton
var _servers: Array[Server] = []
var _cur: Server
var _invite: Server  # the server whose invite is shown
var _windows := {}  # chat key -> ChatWindow
var _root := Control.new()
var _catcher := Control.new()
var _panel := Panel.new()
var _tabs := HBoxContainer.new()
var _scroll := ScrollContainer.new()
var _list := VBoxContainer.new()
var _head: Label
var _toast: Button
var _toast_left := 0.0
var _toast_action := Callable()
var _toast_keep := false  # the toast stays after the login is gone (kicked)
var _dialog: Control
var _edit_tag := false


## One server's side of the overlay.
class Server:
	extends RefCounted
	const NO_FRIENDS := {"list": [], "requests_in": [], "requests_out": [], "blocked": []}
	var link: ServerLink
	var friends := NO_FRIENDS.duplicate(true)
	var status := {}
	var chats := {}
	var unread := {}
	var asked := {}  # user -> true: the history was asked for
	var user := ""  # who is logged in: another account starts clean
	var invite_from := ""


## The invite shown (or waiting for the screen to allow it).
var invite_from: String:
	get:
		return _invite.invite_from if _invite else ""


func _sync() -> void:
	for srv in _servers.duplicate():
		if not links.has(srv.link) or not is_instance_valid(srv.link):
			_reset(srv)
			_servers.erase(srv)
	for l in links:
		if not _servers.any(func(x): return x.link == l):
			var srv := Server.new()
			srv.link = l
			l.message.connect(_on_message.bind(srv))
			_servers.append(srv)
	if not _servers.has(_cur):
		_cur = _servers[0] if not _servers.is_empty() else null


func _select(l: ServerLink) -> void:
	if l and not links.has(l):
		links = links + [l]
	for srv in _servers:
		if srv.link == l:
			_cur = srv
	if panel_open:
		rebuild_panel()


func _ready() -> void:
	layer = 20
	_root.name = "SocialRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = Fonts.theme()
	add_child(_root)
	_catcher.name = "Catcher"  # a click beside the open panel closes it
	_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_catcher.visible = false
	_catcher.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			show_panel(false))
	_root.add_child(_catcher)
	_build_panel()
	button = FriendsButton.new()
	button.name = "FriendsButton"
	button.pressed.connect(func(): show_panel(not panel_open))
	_root.add_child(button)
	_toast = Button.new()
	_toast.name = "Toast"
	_toast.visible = false
	_toast.focus_mode = Control.FOCUS_NONE
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toast.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toast.add_theme_stylebox_override("normal", Palette.frame(Color(0.1, 0.07, 0.04, 0.97), 10))
	_toast.add_theme_stylebox_override("hover", Palette.frame(Color(0.16, 0.11, 0.06, 0.97), 10))
	_toast.add_theme_stylebox_override("pressed", Palette.frame(Color(0.16, 0.11, 0.06, 0.97), 10))
	_toast.pressed.connect(func():
		_toast.visible = false
		if _toast_action.is_valid():
			_toast_action.call())
	_root.add_child(_toast)
	visible = false
	_place()


## The servers logged in now.
func logged_in() -> Array[Server]:
	var out: Array[Server] = []
	out.assign(_servers.filter(func(srv): return is_instance_valid(srv.link) and srv.link.logged_in()))
	return out


func _process(delta: float) -> void:
	var on_list := logged_in()
	var on := not on_list.is_empty()
	if on and not on_list.has(_cur):
		_cur = on_list[0]
		rebuild_panel()
	if on != button.visible:
		button.visible = on
		for w in _windows.values():
			w.visible = on
		if not on:
			show_panel(false)
	if not on and not _toast_keep:
		_toast.visible = false
	visible = on or _toast.visible
	if _toast.visible and _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.visible = false


## main tells which screen is shown.
func screen_changed(s: Node) -> void:
	in_match = s is MatchView
	on_lobby = s is ServerView
	corner = Vector2(1188, 4) if in_match else (Vector2(912, 14) if s is ArenaView else Vector2(-1, -1))
	if in_match:  # a game starts: the chats fold to their headers, out of its way
		for k in open_chats:
			minimized[k] = true
	show_panel(false)
	_place()
	if invite_from != "" and not in_match:
		_show_invite()


## The button: bottom left (the screens keep that corner free), or beside the gear in a game.
func _place() -> void:
	var small := corner.x >= 0
	button.position = corner if small else Vector2(12, 668)
	button.size = Vector2(42, 40) if small else Vector2(120, 42)
	_toast.size = Vector2(380, 46)
	_toast.position = Vector2(minf(corner.x, 1280 - 392), corner.y + 48) if small else Vector2(12, 614)
	_layout_chats()
	_update_button()


## Friends online: on one server (srv), else on every server logged in.
func online_count(srv: Server = null) -> int:
	var n := 0
	for x in ([srv] if srv else logged_in()):
		n += x.friends.get("list", []).filter(func(f): return x.status.get(str(f.get("user", "")), "offline") != "offline").size()
	return n


## Unread messages: on one server (srv), else on every server logged in.
func unread_total(srv: Server = null) -> int:
	var n := 0
	for x in ([srv] if srv else logged_in()):
		for k in x.unread:
			n += int(x.unread[k])
	return n


func _update_button() -> void:
	if button == null:
		return
	var requests := 0
	for x in logged_in():
		requests += x.friends.get("requests_in", []).size()
	button.text = "" if corner.x >= 0 else str(online_count())
	button.unread = unread_total() + requests
	button.queue_redraw()


## "online", "searching", "in_game" or "offline" (an older server says "game" and "queue").
static func presence(s: Variant, online: Variant = null) -> String:
	match str(s):
		"online", "searching", "in_game", "offline":
			return str(s)
		"game":
			return "in_game"
		"queue":
			return "searching"
	return "online" if online == true else "offline"


func status_text(user: String) -> String:
	return tr(STATUS[status.get(user, "offline")][1])


## A text about a server: with several logged in it says which one.
func _about(srv: Server, text: String) -> String:
	return "%s: %s" % [srv.link.display_name(), text] if logged_in().size() > 1 else text


## A chat's key: the user, on a server other than the first one user@url.
func _key(srv: Server, user: String) -> String:
	return user if _servers.is_empty() or srv == _servers[0] else "%s@%s" % [user, srv.link.url]


func _reset(srv: Server) -> void:
	srv.friends = Server.NO_FRIENDS.duplicate(true)
	srv.status = {}
	srv.chats = {}
	srv.unread = {}
	srv.asked = {}
	srv.invite_from = ""
	for k in open_chats.duplicate():
		if _windows[k].srv == srv:
			close_chat(k)
	if _dialog and _invite == srv:
		_dialog.queue_free()
		_dialog = null
	if srv == _cur:
		show_panel(false)
	_update_button()


# --- the friends panel ------------------------------------------------------------

func _build_panel() -> void:
	_panel.name = "FriendsPanel"
	_panel.size = Vector2(PANEL_W, 720)
	_panel.position = Vector2(-PANEL_W - 20, 0)
	var st := Palette.frame(Color(0.1, 0.067, 0.04, 0.98), 0)
	st.border_width_left = 0
	st.border_width_top = 0
	st.border_width_bottom = 0
	_panel.add_theme_stylebox_override("panel", st)
	_panel.visible = false
	_root.add_child(_panel)
	_head = Palette.label(tr("Friends"), 28, Palette.ATTACK)
	_head.position = Vector2(18, 10)
	_panel.add_child(_head)
	var x := Button.new()
	x.name = "ClosePanel"
	x.text = "×"
	x.flat = true
	x.focus_mode = Control.FOCUS_NONE
	x.add_theme_font_size_override("font_size", 30)
	x.position = Vector2(PANEL_W - 52, 6)
	x.size = Vector2(40, 40)
	x.pressed.connect(show_panel.bind(false))
	_panel.add_child(x)
	_tabs.name = "ServerTabs"
	_tabs.position = Vector2(10, 54)
	_tabs.size = Vector2(PANEL_W - 20, 36)
	_tabs.add_theme_constant_override("separation", 4)
	_panel.add_child(_tabs)
	_scroll.position = Vector2(10, 56)
	_scroll.size = Vector2(PANEL_W - 20, 656)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	_list.name = "FriendList"
	_list.custom_minimum_size.x = PANEL_W - 32
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)


func show_panel(on: bool) -> void:
	if on == panel_open and _panel.visible == on:
		return
	panel_open = on
	_catcher.visible = on
	if on:
		rebuild_panel()
		if link and link.is_open():
			link.send({"t": "friends"})  # fresh presence even from an older server
		_panel.visible = true
		if Anim.instant:
			_panel.position.x = 0
		else:
			_panel.create_tween().tween_property(_panel, "position:x", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_panel.position.x = -PANEL_W - 20
		_panel.visible = false
	_layout_chats()


## A tab per server logged in (none with one server: the panel looks as it always did).
func _build_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	var on := logged_in()
	_tabs.visible = on.size() > 1
	_scroll.position.y = 96.0 if _tabs.visible else 56.0
	_scroll.size.y = 720.0 - _scroll.position.y - 8.0
	if not _tabs.visible:
		return
	for i in on.size():
		var srv: Server = on[i]
		var n: int = unread_total(srv) + srv.friends.get("requests_in", []).size()
		var b := Palette.button(srv.link.display_name() + (" (%d)" % n if n > 0 else ""), "ServerTab%d" % i)
		b.custom_minimum_size = Vector2(0, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 15)
		b.toggle_mode = true
		b.button_pressed = srv == _cur
		b.modulate = Color.WHITE if srv == _cur else Color(0.68, 0.64, 0.6)
		b.pressed.connect(func():
			_cur = srv
			if srv.link.is_open():
				srv.link.send({"t": "friends"})
			rebuild_panel())
		_tabs.add_child(b)


func rebuild_panel() -> void:
	if not panel_open:
		return
	_build_tabs()
	_head.text = tr("Friends") + "  (%d / %d)" % [online_count(_cur) if _cur else 0, friends.get("list", []).size()]
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var me: Dictionary = link.me if link else {}
	var mine := Palette.label(ServerView.player_label(me), 22, Palette.TEXT)
	mine.name = "Me"
	_list.add_child(mine)
	var tag := ServerView._str(me.get("tag"))
	if tag == "" or _edit_tag:
		_list.add_child(_note(tr("A tag: 3–16 letters and digits; friends add you by it")))
		var row := _entry_row("TagEdit", tr("Your tag"), tr("Save"), "TagSave", func(t: String):
			_edit_tag = false
			link.send({"t": "set_tag", "tag": t}))
		(row.get_child(0) as LineEdit).text = tag
	else:
		var r := HBoxContainer.new()
		r.add_child(_note(tr("Your tag: %s — share it so friends can add you") % tag))
		_small(r, tr("Change"), "TagChange", func():
			_edit_tag = true
			rebuild_panel())
		_list.add_child(r)
	_entry_row("FriendTag", tr("A friend's tag"), tr("Add"), "FriendAdd", func(t: String):
		link.send({"t": "friend_add", "tag": t.substr(t.rfind("#") + 1)})
		toast(tr("Request sent to %s") % t))
	var ins: Array = friends.get("requests_in", [])
	if not ins.is_empty():
		_section(tr("Friend requests"))
		for f in ins:
			var who := str(f.get("user", ""))
			var row := FriendRow.new(self, f, "request")
			_list.add_child(row)
			row.add_action("check", tr("Accept"), "Accept", func(): link.send({"t": "friend_accept", "user": who}))
			row.add_action("cross", tr("Decline"), "Decline", func(): link.send({"t": "friend_decline", "user": who}))
	var list: Array = friends.get("list", []).duplicate()
	list.sort_custom(func(a, b):
		var sa := ORDER.find(status.get(str(a.get("user")), "offline"))
		var sb := ORDER.find(status.get(str(b.get("user")), "offline"))
		return sa < sb if sa != sb else str(a.get("user")).nocasecmp_to(str(b.get("user"))) < 0)
	_section(tr("Friends"))
	if list.is_empty():
		_list.add_child(_note(tr("No friends yet: add one by tag")))
	for f in list:
		var who := str(f.get("user", ""))
		var row := FriendRow.new(self, f, "friend")
		row.pressed.connect(open_chat.bind(who, true))
		_list.add_child(row)
		row.add_action("chat", tr("Message"), "Chat", open_chat.bind(who, true))
		var inv := row.add_action("swords", tr("Invite to a friendly game"), "Invite", invite.bind(who))
		inv.disabled = status.get(who, "offline") not in ["online", "searching"]
		row.add_action("more", tr("More"), "More", _more.bind(who, row))
	var outs: Array = friends.get("requests_out", [])
	var blocked: Array = friends.get("blocked", [])
	if not outs.is_empty():
		_section(tr("Requests sent"))
		for f in outs:
			_list.add_child(FriendRow.new(self, f, "sent"))
	if not blocked.is_empty():
		_section(tr("Blocked"))
		for f in blocked:
			var who := str(f.get("user", ""))
			var row := FriendRow.new(self, f, "blocked")
			_list.add_child(row)
			row.add_action("cross", tr("Unblock"), "Unblock", func(): link.send({"t": "unblock", "user": who}))


func _note(text: String) -> Label:
	var l := Palette.label(text, 15, Color("c9b48a"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = PANEL_W - 130
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _section(text: String) -> void:
	var l := Palette.label(text, 18, Palette.ATTACK)
	l.custom_minimum_size.y = 30
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_list.add_child(l)


## A text field and a button beside it (Enter works too); fn gets the trimmed text.
func _entry_row(id: String, hint: String, label: String, button_id: String, fn: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var e := LineEdit.new()
	e.name = id
	e.placeholder_text = hint
	e.max_length = 40
	e.custom_minimum_size = Vector2(0, 40)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(e)
	var go := func(_t = ""):
		var t := e.text.strip_edges()
		if t != "":
			e.text = ""
			fn.call(t)
	e.text_submitted.connect(go)
	_small(row, label, button_id, go)
	_list.add_child(row)
	return row


func _small(row: Container, text: String, id: String, fn: Callable) -> Button:
	var b := Palette.button(text, id)
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(fn)
	row.add_child(b)
	return b


func _more(who: String, row: Control) -> void:
	var m := PopupMenu.new()
	m.name = "FriendMenu"
	m.add_item(tr("Remove"), 0)
	m.add_item(tr("Block"), 1)
	var l := link
	m.id_pressed.connect(func(id):
		l.send({"t": "friend_remove" if id == 0 else "block", "user": who})
		m.queue_free())
	m.popup_hide.connect(m.queue_free)
	_root.add_child(m)
	m.popup(Rect2i(Vector2i(row.global_position + Vector2(row.size.x - 120, row.size.y)), Vector2i(140, 0)))


## A friendly game with a friend on the panel's server (the active game must be one it plays).
func invite(user: String) -> void:
	var d := ServerView.remembered_deck(link)
	if d == null:
		toast(tr("Choose your deck"))
		return
	if not link.has_game(Packs.active()):
		toast(link.game_problem(Packs.active()))
		return
	link.game_deck = d
	link.send(link.with_pack({"t": "invite", "to": user, "deck": d.to_dict()}))
	toast(tr("Invitation sent to %s") % user)


# --- chats --------------------------------------------------------------------

## Opens (or shows again) the chat with a friend (on the panel's server, or srv);
## focus puts the cursor in it.
func open_chat(user: String, focus := false, srv: Server = null) -> ChatWindow:
	if srv == null:
		srv = _cur
	var k := _key(srv, user)
	if not open_chats.has(k):
		open_chats.append(k)
		if open_chats.size() > MAX_CHATS:
			close_chat(open_chats[0])
		var w := ChatWindow.new(self, srv, user)
		w.name = "Chat_" + k.validate_node_name()
		_windows[k] = w
		_root.add_child(w)
		_root.move_child(w, _panel.get_index())  # under the panel and the button
		if not srv.asked.has(user):
			srv.asked[user] = true
			srv.link.send({"t": "history", "with": user})
	minimized.erase(k)
	var win: ChatWindow = _windows[k]
	win.refresh()
	if focus:
		mark_read(user, srv)
		show_panel(false)
	_layout_chats()
	if focus and win.input.is_visible_in_tree():
		win.input.grab_focus()
	return win


func close_chat(key: String) -> void:
	open_chats.erase(key)
	minimized.erase(key)
	if _windows.has(key):
		_windows[key].queue_free()
		_root.remove_child(_windows[key])
		_windows.erase(key)
	_layout_chats()


func minimize_chat(key: String) -> void:
	if minimized.has(key):
		minimized.erase(key)
	else:
		minimized[key] = true
	_layout_chats()


## The friend's messages were seen (on the panel's server, or srv).
func mark_read(user: String, srv: Server = null) -> void:
	if srv == null:
		srv = _cur
	if srv == null:
		return
	if int(srv.unread.get(user, 0)) > 0 and srv.link.has_chats:
		srv.link.send({"t": "read", "with": user})
	srv.unread.erase(user)
	var k := _key(srv, user)
	if _windows.has(k):
		_windows[k].queue_redraw()
	_update_button()
	if panel_open:
		rebuild_panel()


func send_message(user: String, text: String, srv: Server = null) -> void:
	if srv == null:
		srv = _cur
	text = text.strip_edges().left(500)
	if text == "":
		return
	srv.link.send({"t": "msg", "to": user, "text": text})
	srv.chats[user] = srv.chats.get(user, []) + [{"from": str(srv.link.me.get("user", "")), "text": text, "at": Time.get_unix_time_from_system()}]
	mark_read(user, srv)
	var k := _key(srv, user)
	if _windows.has(k):
		_windows[k].refresh()


## Chat windows side by side along the bottom, right of the button (or of the panel).
func _layout_chats() -> void:
	var x := (PANEL_W + 12.0) if panel_open else 144.0
	for k in open_chats:
		var w: ChatWindow = _windows[k]
		var h := 40.0 if minimized.has(k) else CHAT_SIZE.y
		w.size = Vector2(CHAT_SIZE.x, h)
		w.position = Vector2(x, 712 - h)
		w.set_collapsed(minimized.has(k))
		x += CHAT_SIZE.x + 10


# --- toasts and invites ------------------------------------------------------------

## A short note over the screen; a click runs action (if any); keep: it stays after a logout.
func toast(text: String, action := Callable(), keep := false) -> void:
	_toast.text = "  " + text
	_toast.tooltip_text = text
	_toast_action = action
	_toast_keep = keep
	_toast_left = TOAST_TIME
	_toast.visible = true
	visible = true
	_root.move_child(_toast, -1)


func _show_invite() -> void:
	if _dialog:
		_dialog.queue_free()
	var dim := ColorRect.new()
	dim.name = "InviteDialog"
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_dialog = dim
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", Palette.frame())
	p.position = Vector2(380, 200)
	p.size = Vector2(520, 300)
	dim.add_child(p)
	var q := Palette.label(_about(_invite, tr("%s invites you to a friendly game") % invite_from), 26, Palette.ATTACK)
	q.position = Vector2(20, 18)
	q.custom_minimum_size.x = 480
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(q)
	var d := ServerView.remembered_deck(_invite.link)
	var deck_line := Palette.label(tr("Your deck:"), 18)
	deck_line.position = Vector2(40, 100)
	p.add_child(deck_line)
	if d:
		var row := DeckTiles.DeckRow.new(d)
		row.name = "InviteDeck"
		row.position = Vector2(40, 128)
		row.size = Vector2(440, 68)
		row.tooltip_text = tr("Choose a deck")
		row.pressed.connect(_choose_invite_deck)
		p.add_child(row)
	for i in 2:
		var b := Palette.button(tr("Accept") if i == 0 else tr("Decline"), "InviteAccept" if i == 0 else "InviteDecline")
		b.position = Vector2(40 + i * 230, 222)
		b.custom_minimum_size = Vector2(210, 54)
		b.pressed.connect(answer_invite.bind(i == 0))
		p.add_child(b)


func _choose_invite_deck() -> void:
	var dim := ColorRect.new()
	dim.name = "DeckDialog"
	dim.color = Color(0.05, 0.03, 0.02, 0.95)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var c := DeckChooser.new()
	c.position = Vector2(140, 90)
	c.size = Vector2(1000, 580)
	c.chosen.connect(func(dk: Deck):
		_invite.link.remember({"deck": {"name": dk.name, "hero": dk.hero}})
		dim.queue_free()
		_show_invite())
	c.back.connect(dim.queue_free)
	c.edit_decks.connect(dim.queue_free)
	dim.add_child(c)


func answer_invite(accept: bool) -> void:
	var srv := _invite
	if srv == null:
		return
	var l := srv.link
	var d := ServerView.remembered_deck(l)
	if accept and d and not l.has_game(Packs.active()):
		toast(l.game_problem(Packs.active()))
		accept = false
	if accept and d:
		l.game_deck = d
		l.send(l.with_pack({"t": "invite_accept", "from": srv.invite_from, "deck": d.to_dict()}))
	else:
		l.send({"t": "invite_decline", "from": srv.invite_from})
	srv.invite_from = ""
	_invite = null
	for x in _servers:  # another server's invite waits behind this one
		if x.invite_from != "":
			_invite = x
	if _dialog:
		_dialog.queue_free()
		_dialog = null
	if _invite and not in_match:
		_show_invite()


# --- messages from the server -------------------------------------------------

func _on_message(msg: Dictionary, srv: Server) -> void:
	var l := srv.link
	match msg.t:
		"auth":
			if msg.get("ok", false):
				var who := str(l.me.get("user", ""))
				if who != srv.user:
					_reset(srv)
					srv.user = who
				l.send({"t": "friends"})
		"logged_out":
			_reset(srv)
			srv.user = ""
		"kicked":
			if not (on_lobby and srv == _cur):
				toast(_about(srv, tr("You logged in on another device")), Callable(), true)
		"me":
			if panel_open and srv == _cur:
				rebuild_panel()
		"friends":
			var known: Array = srv.friends.get("requests_in", []).map(func(f): return f.get("user"))
			for f in msg.get("requests_in", []):
				if not f.get("user") in known and srv.user != "":
					toast(_about(srv, ServerView.player_label(f) + " — " + tr("wants to be friends")), func():
						_cur = srv
						show_panel(true))
			srv.friends = msg
			for f in msg.get("list", []):
				srv.status[str(f.get("user", ""))] = presence(f.get("status"), f.get("online"))
			_changed()
		"presence":
			srv.status[str(msg.get("user", ""))] = presence(msg.get("status"), msg.get("online"))
			_changed()
		"chats":
			for c in msg.get("list", []):
				var who := str(c.get("with", ""))
				if c.has("status") or c.has("online"):
					srv.status[who] = presence(c.get("status"), c.get("online"))
				if int(c.get("unread", 0)) > 0:
					srv.unread[who] = int(c.unread)
			_changed()
		"msg":
			_on_chat_message(msg, srv)
		"history":
			var who := str(msg.get("with", ""))
			srv.chats[who] = msg.get("list", [])
			var k := _key(srv, who)
			if _windows.has(k):
				_windows[k].refresh()
		"invite":
			srv.invite_from = str(msg.get("from", ""))
			_invite = srv
			if in_match:
				toast(_about(srv, tr("%s invites you to a friendly game") % srv.invite_from))
			else:
				_show_invite()
		"invite_declined":
			toast(_about(srv, tr("%s declined the invitation") % str(msg.get("by", ""))))
		"error":
			if not (on_lobby and srv == _cur) and not msg.get("resume", false):
				toast(_about(srv, str(msg.get("text", msg.get("code", "error")))))


func _changed() -> void:
	_update_button()
	rebuild_panel()
	for w in _windows.values():
		w.queue_redraw()


## A friend wrote: the open window shows it; otherwise a badge, and outside a game
## the chat opens by itself (inside one: a toast to click).
func _on_chat_message(msg: Dictionary, srv: Server) -> void:
	var who := str(msg.get("from", ""))
	var k := _key(srv, who)
	srv.chats[who] = srv.chats.get(who, []) + [msg]
	var shown := _windows.has(k) and not minimized.has(k)
	srv.unread[who] = int(srv.unread.get(who, 0)) + 1
	if shown and _windows[k].input.has_focus():
		mark_read(who, srv)
	elif not shown and not in_match and not open_chats.has(k):
		open_chat(who, false, srv)
	elif not shown:
		toast(_about(srv, "%s: %s" % [who, str(msg.get("text", ""))]), open_chat.bind(who, true, srv))
	if _windows.has(k):
		_windows[k].refresh()
	_update_button()
	if panel_open:
		rebuild_panel()
	Sound.play("click")


## The corner button: the friends icon, how many are online, a red badge of unread messages.
class FriendsButton:
	extends Button
	var unread := 0

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		add_theme_font_size_override("font_size", 22)
		tooltip_text = TranslationServer.translate("Friends")
		pressed.connect(Sound.play.bind("click"))
		Icons.attach(self, "friends", 30)

	func _draw() -> void:
		if unread > 0:
			var c := Vector2(size.x - 4, 4)
			draw_circle(c, 13, Color("2a0805"))
			draw_circle(c, 11, Color("d8261c"))
			var f := get_theme_font("font")
			var s := str(unread) if unread < 100 else "99+"
			draw_string(f, c + Vector2(-12, 6), s, HORIZONTAL_ALIGNMENT_CENTER, 24, 15, Color.WHITE)


## A friend (or a request) in the panel: presence dot, name#tag, status line,
## unread badge and small buttons on the right.
class FriendRow:
	extends Button
	var social: Social
	var info := {}
	var kind := ""  # "friend", "request", "sent" or "blocked"
	var user := ""
	var actions := HBoxContainer.new()

	func _init(s: Social, f: Dictionary, k: String) -> void:
		social = s
		info = f
		kind = k
		user = str(f.get("user", ""))
		name = "Friend_" + user
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(Social.PANEL_W - 32, 58)
		actions.add_theme_constant_override("separation", 4)
		actions.position = Vector2(0, 13)
		add_child(actions)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		resized.connect(func(): actions.position.x = size.x - actions.size.x - 8)

	func add_action(icon: String, tip: String, id: String, fn: Callable) -> Button:
		var b := Button.new()
		b.name = id
		b.tooltip_text = tip
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(34, 32)
		b.pressed.connect(Sound.play.bind("click"))
		b.pressed.connect(fn)
		Icons.attach(b, icon, 22)
		actions.add_child(b)
		actions.reset_size()
		actions.position.x = size.x - actions.size.x - 8
		return b

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var st: String = social.status.get(user, "offline") if kind == "friend" else "offline"
		draw_style_box(Palette.box(Color(1, 0.9, 0.6, 0.10) if is_hovered() else Color(0, 0, 0, 0.28), 10, Color("6b5320", 0.7), 1), r)
		var dot: Color = Social.STATUS[st][0] if kind == "friend" else Color("c9a74a")
		draw_circle(Vector2(18, size.y / 2.0), 8, Color(0, 0, 0, 0.7))
		draw_circle(Vector2(18, size.y / 2.0), 6, dot)
		var room := size.x - 36 - actions.size.x - 16
		var name_col := Palette.TEXT if st != "offline" or kind != "friend" else Color("a89c88")
		DeckTiles.text(self, Vector2(34, 25), ServerView.player_label(info), 19, name_col, room)
		var line := ""
		match kind:
			"friend":
				line = social.status_text(user)
			"request":
				line = tr("wants to be friends")
			"sent":
				line = tr("request sent")
			"blocked":
				line = tr("Blocked")
		DeckTiles.text(self, Vector2(34, 46), line, 14, dot.lightened(0.2) if kind == "friend" else Color("c9b48a"), room)
		var n := int(social.unread.get(user, 0))
		if n > 0:
			var c := Vector2(size.x - actions.size.x - 22, size.y / 2.0)
			draw_circle(c, 11, Color("d8261c"))
			draw_string(get_theme_font("font", "Label"), c + Vector2(-11, 5), str(n), HORIZONTAL_ALIGNMENT_CENTER, 22, 14, Color.WHITE)


## A chat with one friend, over the screen: the header (presence, name, minimize,
## close), the messages, and a line where Enter sends.
class ChatWindow:
	extends Panel
	var social: Social
	var srv: Social.Server
	var user := ""
	var input := LineEdit.new()
	var _scroll := ScrollContainer.new()
	var _lines := VBoxContainer.new()
	var _header := Button.new()

	func _init(s: Social, sv: Social.Server, u: String) -> void:
		social = s
		srv = sv
		user = u
		add_theme_stylebox_override("panel", Palette.frame(Color(0.1, 0.067, 0.04, 0.97), 12))
		_header.name = "Header"
		_header.flat = true
		_header.focus_mode = Control.FOCUS_NONE
		_header.position = Vector2(0, 0)
		_header.size = Vector2(Social.CHAT_SIZE.x - 76, 40)
		_header.pressed.connect(func(): social.minimize_chat(social._key(srv, user)))
		add_child(_header)
		for spec in [["–", "Minimize", func(): social.minimize_chat(social._key(srv, user)), 76], ["×", "CloseChat", func(): social.close_chat(social._key(srv, user)), 40]]:
			var b := Button.new()
			b.name = spec[1]
			b.text = spec[0]
			b.flat = true
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 24)
			b.position = Vector2(Social.CHAT_SIZE.x - spec[3], 2)
			b.size = Vector2(36, 36)
			b.pressed.connect(spec[2])
			add_child(b)
		_scroll.position = Vector2(10, 44)
		_scroll.size = Vector2(Social.CHAT_SIZE.x - 20, Social.CHAT_SIZE.y - 100)
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(_scroll)
		_lines.name = "ChatLines"
		_lines.custom_minimum_size.x = Social.CHAT_SIZE.x - 34
		_lines.add_theme_constant_override("separation", 6)
		_scroll.add_child(_lines)
		input.name = "ChatText"
		input.placeholder_text = TranslationServer.translate("Write a message, Enter sends")
		input.max_length = 500
		input.position = Vector2(10, Social.CHAT_SIZE.y - 50)
		input.size = Vector2(Social.CHAT_SIZE.x - 20, 40)
		input.text_submitted.connect(func(t):
			input.text = ""
			social.send_message(user, t, srv))
		input.focus_entered.connect(func(): social.mark_read(user, srv))
		add_child(input)
		gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed:
				social.mark_read(user, srv))

	func set_collapsed(on: bool) -> void:
		_scroll.visible = not on
		input.visible = not on
		queue_redraw()

	func refresh() -> void:
		for c in _lines.get_children():
			_lines.remove_child(c)
			c.queue_free()
		var me := str(srv.link.me.get("user", ""))
		var font := get_theme_font("font", "Label")
		var most := Social.CHAT_SIZE.x - 70
		for m in srv.chats.get(user, []):
			var mine: bool = str(m.get("from", "")) == me
			var text := str(m.get("text", ""))
			var l := Palette.label(text, 17, Color("fff1c8") if mine else Palette.TEXT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 6, most)
			var bubble := PanelContainer.new()  # a speech bubble: mine on the right, gold
			var st := Palette.box(Color("5a3c12") if mine else Color("2c2119"), 10, Color("a8863a") if mine else Color("5a4a36"), 1)
			st.content_margin_left = 10
			st.content_margin_right = 10
			st.content_margin_top = 4
			st.content_margin_bottom = 5
			bubble.add_theme_stylebox_override("panel", st)
			bubble.add_child(l)
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_END if mine else BoxContainer.ALIGNMENT_BEGIN
			row.add_child(bubble)
			_lines.add_child(row)
		if srv.chats.get(user, []).is_empty():
			var l := Palette.label(TranslationServer.translate("No messages yet"), 15, Color("a89c88"))
			_lines.add_child(l)
		_scroll.call_deferred("set_v_scroll", 1 << 20)
		queue_redraw()

	func _draw() -> void:
		var st: String = srv.status.get(user, "offline")
		var fresh := int(srv.unread.get(user, 0)) > 0
		var bar := Rect2(Vector2(3, 3), Vector2(size.x - 6, 36))
		draw_style_box(Palette.box(Color("6b3f12") if fresh else Color("24170c"), 9), bar)
		draw_circle(Vector2(18, 21), 6, Social.STATUS[st][0])
		var title := user if social.logged_in().size() < 2 else "%s · %s" % [user, srv.link.display_name()]
		DeckTiles.text(self, Vector2(32, 28), title, 19, Palette.ATTACK, size.x - 120)
