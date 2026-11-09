class_name TournamentsView
extends Control
## Tournaments on a game server (docs/superpowers/plans/2026-11-09-server-features.md, "D"):
## the tabs Upcoming, Finished and Closed (`t_list`), Create (a form with presets, every option
## explained in a line under it, the start picked in local time), and a tournament's page (`t_get`,
## then the server's `tournament` pushes): its status, the start with a countdown, the rules in
## words and when they lock, the players (places with gold, silver and bronze), joining with decks
## of different classes, leaving, changing decks, the creator's edit, reschedule and cancel, and
## the bracket (TournamentBracket) whose matches open their details: Watch (`t_spectate`) and the
## Replays of their games (`replay`). The match steps themselves (accept, ban, pick) are the
## TournamentPanel's, over any screen.

signal back
## A finished game's replay arrived (`replay` data): main opens it (part B's ReplayView).
signal replay_ready(data: Dictionary)

const TABS := ["upcoming", "finished", "closed"]
const TAB_NAMES := {"upcoming": "Upcoming", "finished": "Finished", "closed": "Closed", "create": "Create"}
const STATUS := {"open": ["Joining open", Color("5fd35a")], "locked": ["Locked in", Color("f2c94c")],
	"seeded": ["Seeded", Color("f2a64c")], "running": ["Running", Color("5ab4ff")],
	"finished": ["Ended", Color("ffd34d")], "closed": ["Not held", Color("9a8f80")],
	"cancelled": ["Cancelled", Color("ff7a6a")]}
const FORMATS := {"elimination": "Elimination", "round_robin": "Round robin", "swiss": "Swiss", "scheveningen": "Scheveningen"}
const SERIES := {"conquest": "Conquest", "lhs": "Last Hero Standing"}
const MIN_LEAD_MS := 11 * 60 * 1000  # the earliest start: now + 11 min
const MAX_LEAD_MS := 14 * 24 * 3600 * 1000  # the latest: now + 14 days
const LOCK_MS := 10 * 60 * 1000
const SEED_MS := 60 * 1000
## The create form's presets: a name and the options they set.
const PRESETS := [
	["Quick 8 · Bo3 Conquest", {"format": "elimination", "losses": 1, "max_players": 8, "series": "conquest", "best_of": 3, "bans": 0}],
	["Double elimination 16 · Bo3", {"format": "elimination", "losses": 2, "max_players": 16, "series": "conquest", "best_of": 3, "bans": 1}],
	["Swiss 16 · Bo3", {"format": "swiss", "swiss_rounds": 0, "drop_after": 0, "max_players": 16, "series": "conquest", "best_of": 3, "bans": 0}],
	["Round robin 6 · Bo1", {"format": "round_robin", "rr_rounds": 1, "max_players": 6, "series": "conquest", "best_of": 1, "bans": 0}],
	["Team battle 8 · Bo5 LHS", {"format": "scheveningen", "max_players": 8, "series": "lhs", "best_of": 5, "bans": 1}]]
## The most players a format takes (the server's tournament::players_cap): everyone-plays-everyone
## formats grow by the square.
const PLAYERS_CAP := {"round_robin": 32, "scheveningen": 64}

## Words translated through a variable (the translation tool reads this list and the tables above).
const WORDS := ["No tournaments yet — create one", "No finished tournaments yet", "No closed or cancelled tournaments",
	"In 15 minutes", "In 1 hour", "At 20:00", "Tomorrow at 20:00", "Locked in", "Seeded", "Start",
	"Rules, decks and the start are frozen", "The bracket is drawn; joining and leaving close", "The first matches begin",
	"Banned", "Won", "Lost", "not enough players"]

## Full data of tournaments seen (id -> the `tournament` data): the match panel finds the
## player's decks there.
static var cache := {}

var link: ServerLink
## "upcoming", "finished", "closed", "create", or "page" (a tournament's page).
var tab := "upcoming"
var lists := {}  # tab -> the server's list
var page_id: Variant = null  # the tournament shown
var page := {}  # its full data
var page_tab := "overview"  # "overview" or "bracket"
## The create (or edit, or reschedule) form's values.
var form := {}
var form_mode := "create"
var _creating := false
var _from_tab := "upcoming"  # the list a page was opened from
var _want_replay := ""
var _cancel_armed := false
var _body := Control.new()
var _overlay: Control
var _status: Label
var _clocks: Array = []  # [Label, start ms, prefix]: counting down
var _tick := 0.0
var _scroll_keep := {}  # a rebuilt scroll's place: name -> Vector2


func _ready() -> void:
	name = "TournamentsView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	Palette.backdrop(self)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	_status = Palette.label("", 18, Palette.SELECTED)
	_status.name = "Status"
	_status.position = Vector2(150, 676)
	_status.size = Vector2(700, 30)
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)
	link.message.connect(_on_message)
	if page_id != null:
		open_page(page_id)
	else:
		show_tab(tab)


func _exit_tree() -> void:
	if page_id != null and is_instance_valid(link):
		link.send({"t": "t_unwatch", "id": wire_id(page_id)})


func say(text: String) -> void:
	_status.text = text


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.25:
		return
	_tick = 0.0
	for c in _clocks:
		if is_instance_valid(c[0]):
			c[0].text = clock_text(int(c[1]))


# --- small helpers -------------------------------------------------------------------------

## An id as the server wants it back (JSON numbers arrive as floats).
static func wire_id(v: Variant) -> Variant:
	return int(v) if v is float else v


static func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## The device's time zone offset in seconds (local = UTC + this).
static func tz_s() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


## A moment in the player's local time: "2026-11-10 18:30".
static func local_text(ms: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(ms / 1000) + tz_s())
	return "%04d-%02d-%02d %02d:%02d" % [d.year, d.month, d.day, d.hour, d.minute]


## Local date and time -> unix ms (ponytail: the offset of now, a DST change in between is off by an hour).
static func local_to_ms(year: int, month: int, day: int, hour: int, minute: int) -> int:
	var s := Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": 0})
	return (s - tz_s()) * 1000


## Time left as "2 d 5 h", "1:02:03" or "4:05".
static func left_text(ms: int) -> String:
	var s := maxi(0, ms / 1000)
	if s >= 86400:
		return _tr("%d d %d h") % [s / 86400, (s % 86400) / 3600]
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


## "Starts in 1:02:03", or "Started" once the moment passed.
static func clock_text(start: int) -> String:
	var left := start - now_ms()
	return _tr("Starts in %s") % left_text(left) if left > 0 else _tr("Started")


static func _tr(s: String) -> String:
	return str(TranslationServer.translate(s))


## An option of a tournament: at the top, else in `options` (the format's), else def.
static func opt(t: Dictionary, k: String, def: Variant) -> Variant:
	if t.get(k) != null:
		return t[k]
	var o = t.get("options")
	return o[k] if o is Dictionary and o.get(k) != null else def


## Decks each entrant brings: the wins needed plus the bans.
static func decks_needed(t: Dictionary) -> int:
	return (int(opt(t, "best_of", 1)) + 1) / 2 + int(opt(t, "bans", 0))


## The `tournament` message's data (the message itself when it carries the fields).
static func payload(msg: Dictionary) -> Dictionary:
	for k in ["tournament", "data"]:
		if msg.get(k) is Dictionary:
			return msg[k]
	return msg if msg.has("id") and msg.has("status") else {}


static func status_name(st: String) -> String:
	return _tr(STATUS[st][0]) if STATUS.has(st) else st


static func status_color(st: String) -> Color:
	return STATUS[st][1] if STATUS.has(st) else Palette.MUTED


static func format_name(t: Dictionary) -> String:
	var f := str(t.get("format", ""))
	if f == "elimination":
		return _tr("Double elimination") if int(opt(t, "losses", 1)) == 2 else _tr("Single elimination")
	return _tr(FORMATS.get(f, f))


static func series_name(t: Dictionary) -> String:
	return _tr("%s · best of %d") % [_tr(SERIES.get(str(opt(t, "series", "conquest")), "Conquest")), int(opt(t, "best_of", 1))]


## A class's name in the active pack's words (its champion's name when the pack has none).
static func class_name_of(hero: String) -> String:
	var cls := Decks.card_class(hero)
	var n := CardText.term("classes", cls) if cls != "" else ""
	return n if n != "" else (CardText.name(hero) if hero != "" else "?")


## The rules in words: [title, the line that explains it].
static func rules_lines(t: Dictionary) -> Array:
	var out: Array = []
	match str(t.get("format", "")):
		"elimination":
			if int(opt(t, "losses", 1)) == 2:
				out.append([_tr("Double elimination"), _tr("Two losses and you are out: a losers bracket, then the grand final")])
			else:
				out.append([_tr("Single elimination"), _tr("Lose a match and you are out")])
		"round_robin":
			out.append([_tr("Round robin"), _tr("Everyone plays everyone twice") if int(opt(t, "rounds", 1)) == 2 else _tr("Everyone plays everyone once")])
		"swiss":
			var r := int(opt(t, "rounds", 0))
			var d := int(opt(t, "drop_after", 0))
			var line := _tr("Players with equal points meet, never twice")
			if d > 0:
				line += " · " + _tr("out after %d losses") % d
			out.append([_tr("Swiss, %d rounds") % r if r > 0 else _tr("Swiss"), line])
		"scheveningen":
			out.append([_tr("Scheveningen"), _tr("Two teams: everyone plays everyone of the other team")])
	if str(opt(t, "series", "conquest")) == "lhs":
		out.append([series_name(t), _tr("A losing deck is out; the winner plays on with the same deck")])
	else:
		out.append([series_name(t), _tr("Win once with each deck: a deck that won can't play again in the match")])
	var bans := int(opt(t, "bans", 0))
	out.append([_tr("%d decks of different classes") % decks_needed(t),
		_tr("Each player bans one of the opponent's decks") if bans > 0 else _tr("No bans")])
	out.append([_tr("%d–%d players") % [int(opt(t, "min_players", 2)), int(opt(t, "max_players", 8))],
		_tr("Fewer than %d ten minutes before the start: the tournament is closed") % int(opt(t, "min_players", 2))])
	out.append([_tr("Open decklists"), _tr("Everyone sees every deck from 10 minutes before the start")] if opt(t, "deck_reveal", false) == true
		else [_tr("Hidden decklists"), _tr("Only you see your decks")])
	out.append([_tr("Spectators allowed"), _tr("The creator and eliminated players may watch running matches")] if opt(t, "spectators", false) == true
		else [_tr("No spectators"), _tr("Running matches are not shown")])
	return out


## The player's decks of the tournament's game (valid ones; the server checks them again).
func decks_for(t: Dictionary) -> Array:
	var p := Packs.find_rules(str(t.get("pack", "")))
	if p == null:
		return []
	var all: Array = link.decks_of(p) if link.has_decks else DeckStore.load_local(p.id())
	if p == Packs.active():
		all = all.filter(func(d: Deck): return d.validate() == "")
	return all


func me() -> String:
	return str(link.me.get("user", ""))


func _clear() -> void:
	_clocks.clear()
	_cancel_armed = false
	for c in _body.get_children():
		if c is ScrollContainer:
			_scroll_keep[c.name] = Vector2(c.scroll_horizontal, c.scroll_vertical)
		_body.remove_child(c)
		c.queue_free()
	close_overlay()


func _keep_scroll(s: ScrollContainer) -> void:
	if _scroll_keep.has(s.name):
		var v: Vector2 = _scroll_keep[s.name]
		(func():
			if is_instance_valid(s):
				s.scroll_horizontal = int(v.x)
				s.scroll_vertical = int(v.y)).call_deferred()


func _btn(text: String, id: String, fn: Callable, w := 200.0, h := 52.0, parent: Control = null) -> Button:
	var b := Palette.button(text, id)
	b.custom_minimum_size = Vector2(w, h)
	if fn.is_valid():
		b.pressed.connect(fn)
	if parent:
		parent.add_child(b)
	return b


func _lbl(text: String, size := 18, color := Palette.TEXT, parent: Control = null) -> Label:
	var l := Palette.label(text, size, color)
	if parent:
		parent.add_child(l)
	return l


func _wrap(l: Label, w: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l


## A framed card (dark wood, gold rim) holding a VBox.
func _card(at: Vector2, sz: Vector2, parent: Control = _body) -> VBoxContainer:
	var p := PanelContainer.new()
	p.position = at
	p.size = sz
	p.add_theme_stylebox_override("panel", Palette.frame(Color(0.09, 0.065, 0.04, 0.94), 12))
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	return v


func _scroll(at: Vector2, sz: Vector2, id: String, both := false) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.name = id
	s.position = at
	s.size = sz
	if not both:
		s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(s)
	_keep_scroll(s)
	return s


## The bar on top: Back, the title, the tabs (or the page's own), Create.
func _top_bar(title: String) -> void:
	var bar := Panel.new()
	bar.name = "TopBar"
	bar.size = Vector2(1280, 72)
	var st := Palette.box(Color(0.07, 0.045, 0.025, 0.94), 0)
	st.border_color = Color("a8863a")
	st.border_width_bottom = 3
	st.shadow_color = Color(0, 0, 0, 0.5)
	st.shadow_size = 8
	bar.add_theme_stylebox_override("panel", st)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(bar)
	var b := _btn(tr("Back"), "Back", _go_back, 130, 52, _body)
	b.position = Vector2(14, 10)
	var t := _lbl(title, 30, Palette.ATTACK, _body)
	t.name = "Title"
	t.position = Vector2(162, 12)
	t.size = Vector2(430 if tab != "page" else 560, 48)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _tab_buttons(items: Array, current: String, x: float, fn: Callable) -> float:
	for it in items:
		var id: String = it[0]
		var b := _btn(it[1], "Tab_" + id, fn.bind(id), it[2], 52, _body)
		b.position = Vector2(x, 10)
		mark(b, id == current)
		b.add_theme_font_size_override("font_size", 20)
		x += it[2] + 8
	return x


## A choice that is on: a gold rim and gold text (the others a little dimmer).
static func mark(b: Button, on: bool) -> void:
	if not on:
		b.modulate = Color(0.8, 0.76, 0.72)
		return
	var st := Palette.box(Color("4a3110"), 8, Palette.SELECTED, 3)
	st.set_content_margin_all(8)
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, st)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		b.add_theme_color_override(k, Palette.SELECTED)


func _go_back() -> void:
	if tab == "create" and form_mode != "create" and page_id != null:
		tab = "page"
		_build_page()
	elif tab == "page" or tab == "create":
		_leave_page()
		show_tab(_from_tab)
	else:
		back.emit()


func _leave_page() -> void:
	if page_id != null:
		link.send({"t": "t_unwatch", "id": wire_id(page_id)})
	page_id = null
	page = {}


# --- the lists -------------------------------------------------------------------------------

func show_tab(id: String) -> void:
	if tab == "page" or page_id != null:
		_leave_page()
	tab = id
	if id == "create":
		start_form("create")
		return
	_from_tab = id
	link.send({"t": "t_list", "tab": id})
	_build_list()


func _build_list() -> void:
	_clear()
	_top_bar(tr("Tournaments"))
	var x := _tab_buttons(TABS.map(func(t): return [t, tr(TAB_NAMES[t]), 150.0]), tab, 470, show_tab)
	var c := _btn("+ " + tr("Create"), "Tab_create", show_tab.bind("create"), 1266 - x, 52, _body)
	c.position = Vector2(x, 10)
	c.add_theme_font_size_override("font_size", 20)
	var list = lists.get(tab)
	if not list is Array:
		var wait := _lbl(tr("Loading…"), 22, Palette.MUTED, _body)
		wait.name = "Loading"
		wait.position = Vector2(0, 330)
		wait.size = Vector2(1280, 40)
		wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	if list.is_empty():
		_empty_state()
		return
	var s := _scroll(Vector2(24, 88), Vector2(1232, 572), "ListScroll")
	var v := VBoxContainer.new()
	v.name = "List"
	v.custom_minimum_size.x = 1220
	v.add_theme_constant_override("separation", 10)
	s.add_child(v)
	for e in list:
		if e is Dictionary:
			var row := ListRow.new()
			row.e = e
			row.name = "T_" + TournamentBracket.key(e.get("id"))
			row.pressed.connect(open_page.bind(e.get("id")))
			v.add_child(row)


func _empty_state() -> void:
	var v := _card(Vector2(340, 200), Vector2(600, 280))
	v.name = "Empty"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var cup := Trophy.new()
	cup.custom_minimum_size = Vector2(560, 90)
	v.add_child(cup)
	var text: String = {"upcoming": "No tournaments yet — create one", "finished": "No finished tournaments yet",
		"closed": "No closed or cancelled tournaments"}.get(tab, "")
	var l := _lbl(tr(text), 24, Palette.ATTACK, v)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if tab == "upcoming":
		var b := _btn(tr("Create a tournament"), "EmptyCreate", show_tab.bind("create"), 320, 56)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(b)


# --- a tournament's page ------------------------------------------------------------------

func open_page(id: Variant) -> void:
	if page_id != null and TournamentBracket.key(page_id) != TournamentBracket.key(id):
		_leave_page()
	if page_id == null or TournamentBracket.key(page_id) != TournamentBracket.key(id):
		_scroll_keep.clear()
	page_id = wire_id(id)
	tab = "page"
	page = cache.get(TournamentBracket.key(id), {})
	link.send({"t": "t_get", "id": page_id})
	_build_page()


func _build_page() -> void:
	_clear()
	var t := page
	_top_bar(str(t.get("name", "")) if not t.is_empty() else tr("Tournament"))
	if t.is_empty():
		var wait := _lbl(tr("Loading…"), 22, Palette.MUTED, _body)
		wait.name = "Loading"
		wait.position = Vector2(0, 330)
		wait.size = Vector2(1280, 40)
		wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	_tab_buttons([["overview", tr("Overview"), 160.0], ["bracket", tr("Bracket"), 160.0]], page_tab, 932, func(id):
		page_tab = id
		_build_page())
	var head := PageHead.new()
	head.name = "PageHead"
	head.t = t
	head.position = Vector2(24, 84)
	head.size = Vector2(1232, 74)
	_body.add_child(head)
	var clock := _lbl("", 24, Palette.SELECTED, _body)
	clock.name = "Countdown"
	clock.position = Vector2(820, 90)
	clock.size = Vector2(420, 32)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var start := int(opt(t, "start_at", 0))
	if str(t.get("status", "")) in ["open", "locked", "seeded"]:
		clock.text = clock_text(start)
		_clocks.append([clock, start])
	var when := _lbl(tr("Start: %s (your time)") % local_text(start), 17, Palette.MUTED, _body)
	when.name = "StartTime"
	when.position = Vector2(820, 124)
	when.size = Vector2(420, 26)
	when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if page_tab == "bracket":
		_build_bracket_tab()
	else:
		_build_overview()


func _build_overview() -> void:
	var t := page
	var s := _scroll(Vector2(24, 170), Vector2(640, 494), "InfoScroll")
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 626
	v.add_theme_constant_override("separation", 12)
	s.add_child(v)
	if str(t.get("status", "")) == "finished":
		var res := _section(v, tr("Results"))
		res.get_parent().name = "Results"
		var pod := Podium.new()
		pod.list = TournamentBracket.standings(t).filter(func(e): return TournamentBracket.place_of(e) in [1, 2, 3])
		pod.me = me()
		pod.custom_minimum_size = Vector2(590, 230)
		res.add_child(pod)
	_entry_card(v)
	_creator_card(v)
	var rules := _section(v, tr("Rules"))
	for r in rules_lines(t):
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		_lbl(r[0], 20, Palette.TEXT, row)
		_wrap(_lbl(r[1], 16, Palette.MUTED, row), 590)
		rules.add_child(row)
	var steps := _section(v, tr("When things lock"))
	var tl := Timeline.new()
	tl.name = "Timeline"
	tl.start = int(opt(t, "start_at", 0))
	tl.custom_minimum_size = Vector2(590, 176)
	steps.add_child(tl)
	_players(Vector2(680, 170), Vector2(576, 494))


## A titled card inside the overview's column.
func _section(parent: Control, title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Palette.frame(Color(0.09, 0.065, 0.04, 0.94), 12))
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	_lbl(title, 22, Palette.ATTACK, v)
	return v


## The player's part: Join, or their decks with Change decks and Leave.
func _entry_card(parent: Control) -> void:
	var t := page
	var can: Dictionary = t.get("can", {}) if t.get("can") is Dictionary else {}
	var mine := _my_entrant()
	if mine.is_empty() and not can.get("join", false):
		return
	var over: bool = str(t.get("status", "")) in ["finished", "cancelled", "closed"]
	var v := _section(parent, (tr("Your decks") if over else tr("You are in")) if not mine.is_empty() else tr("Join this tournament"))
	v.get_parent().name = "EntryCard"
	if mine.is_empty():
		_wrap(_lbl(tr("Bring %d decks of different classes from your decks of this game.") % decks_needed(t), 17, Palette.TEXT, v), 590)
		var j := _btn(tr("Join"), "Join", pick_decks.bind(false), 590, 60, v)
		j.add_theme_font_size_override("font_size", 24)
		return
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	v.add_child(row)
	var decks = mine.get("decks")
	for d in decks if decks is Array else []:
		if d is Dictionary:
			var tile := DeckChip.new()
			tile.hero = str(d.get("hero", ""))
			tile.title = str(d.get("name", ""))
			tile.custom_minimum_size = Vector2(190, 64)
			tile.pressed.connect(show_deck.bind(d))
			row.add_child(tile)
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 10)
	v.add_child(acts)
	if can.get("decks", false):
		_btn(tr("Change decks"), "ChangeDecks", pick_decks.bind(true), 290, 52, acts)
	if can.get("leave", false):
		_btn(tr("Withdraw"), "Leave", func(): link.send({"t": "t_leave", "id": wire_id(page_id)}), 290, 52, acts)
	if not can.get("decks", false) and not over:
		_wrap(_lbl(tr("Decks are locked: they can't be changed any more."), 16, Palette.MUTED, v), 590)


## The creator's tools: Edit, Reschedule (later only), Cancel (pressed twice), with when they lock.
func _creator_card(parent: Control) -> void:
	var can: Dictionary = page.get("can", {}) if page.get("can") is Dictionary else {}
	if not (can.get("edit", false) or can.get("reschedule", false) or can.get("cancel", false)):
		return
	var v := _section(parent, tr("Your tournament"))
	v.get_parent().name = "CreatorCard"
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 10)
	v.add_child(acts)
	if can.get("edit", false):
		_btn(tr("Edit"), "Edit", start_form.bind("edit"), 190, 52, acts)
	if can.get("reschedule", false):
		_btn(tr("Reschedule"), "Reschedule", start_form.bind("reschedule"), 190, 52, acts)
	if can.get("cancel", false):
		var c := _btn(tr("Cancel it"), "CancelT", Callable(), 190, 52, acts)
		c.pressed.connect(func():
			if not _cancel_armed:
				_cancel_armed = true
				c.text = tr("Sure? Press again")
				c.add_theme_color_override("font_color", Palette.DANGER)
				return
			link.send({"t": "t_cancel", "id": wire_id(page_id)}))
	if can.get("edit", false) or can.get("reschedule", false):
		_wrap(_lbl(tr("Rules and the start can be changed until %s; the start only to later.") % local_text(int(opt(page, "start_at", 0)) - LOCK_MS), 16, Palette.MUTED, v), 590)


func _my_entrant() -> Dictionary:
	for e in page.get("entrants", []) if page.get("entrants") is Array else []:
		if e is Dictionary and str(e.get("name", "")) == me():
			return e
	return {}


## The players: place (medals for the top three), name, seed or team, points, and their deck
## classes when the decks are open.
func _players(at: Vector2, sz: Vector2) -> void:
	var t := page
	var list := TournamentBracket.standings(t)
	var head := _lbl(tr("Players %d / %d") % [list.size(), int(opt(t, "max_players", 0))], 22, Palette.ATTACK, _body)
	head.name = "PlayersHead"
	head.position = at
	var s := _scroll(at + Vector2(0, 40), sz - Vector2(0, 40), "Players")
	var v := VBoxContainer.new()
	v.name = "PlayerList"
	v.custom_minimum_size.x = sz.x - 14
	v.add_theme_constant_override("separation", 6)
	s.add_child(v)
	if list.is_empty():
		_wrap(_lbl(tr("Nobody has joined yet."), 18, Palette.MUTED, v), sz.x - 20)
	for e in list:
		var row := PlayerRow.new()
		row.e = e
		row.me = me()
		row.scored = not TournamentBracket.matches_of(t).is_empty()
		row.name = "Player_" + str(e.get("name", "")).validate_node_name()
		row.custom_minimum_size = Vector2(sz.x - 14, 64)
		var decks = e.get("decks")
		if decks is Array and not decks.is_empty() and str(e.get("name", "")) != me():
			row.pressed.connect(show_decks_of.bind(e))
		v.add_child(row)
		var place := TournamentBracket.place_of(e)
		var m := TournamentBracket.medal(place)
		m.position = Vector2(8, 12)
		row.add_child(m)


func _build_bracket_tab() -> void:
	var t := page
	if TournamentBracket.matches_of(t).is_empty():
		var v := _card(Vector2(290, 220), Vector2(700, 200))
		v.name = "NoBracket"
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var l := _wrap(_lbl(tr("The bracket is drawn one minute before the start."), 22, Palette.ATTACK, v), 660)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	var s := _scroll(Vector2(16, 166), Vector2(1248, 500), "BracketScroll", true)
	var b := TournamentBracket.make(t, me())
	b.match_pressed.connect(show_match)
	var mid := CenterContainer.new()  # a small bracket in the middle, not in a corner
	mid.custom_minimum_size = s.size - Vector2(14, 14)
	mid.add_child(b)
	s.add_child(mid)


# --- dialogs ------------------------------------------------------------------------------

func close_overlay() -> void:
	if _overlay:
		remove_child(_overlay)  # (gone at once: a new dialog's buttons are the only ones)
		_overlay.queue_free()
		_overlay = null


## A dimmed screen with a framed box in the middle (a tap beside it closes it); its VBox.
func _dialog(title: String, sz: Vector2, id: String) -> VBoxContainer:
	close_overlay()
	var dim := ColorRect.new()
	dim.name = id
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			close_overlay())
	add_child(dim)
	_overlay = dim
	var p := PanelContainer.new()
	p.position = (Vector2(1280, 720) - sz) / 2.0
	p.size = sz
	p.add_theme_stylebox_override("panel", Palette.frame())
	dim.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var l := _lbl(title, 26, Palette.ATTACK, v)
	l.name = "DialogTitle"
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return v


## A match of the bracket: both players, the score, its games' Replays, Watch while it runs.
func show_match(m: Dictionary) -> void:
	var p := TournamentBracket.players(m)
	var v := _dialog(tr("Match"), Vector2(720, 480), "MatchDialog")
	var vs := Versus.new()
	vs.m = m
	vs.me = me()
	vs.custom_minimum_size = Vector2(690, 120)
	v.add_child(vs)
	var st := str(m.get("status", ""))
	var line := tr("Being played") if TournamentBracket.is_live(m) else (tr("%s won the match") % TournamentBracket.winner(m) if TournamentBracket.is_done(m) else tr("Not started"))
	if TournamentBracket.is_done(m) and p[1] == "":
		line = tr("A bye: %s goes on") % p[0]
	var sl := _lbl(line, 18, Palette.MUTED, v)
	sl.name = "MatchState"
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var can: Dictionary = page.get("can", {}) if page.get("can") is Dictionary else {}
	if TournamentBracket.is_live(m) and can.get("spectate", false):
		var w := _btn(tr("Watch"), "Watch", func():
			link.send({"t": "t_spectate", "match": wire_id(m.get("id"))})
			say(tr("Opening the game…"))
			close_overlay(), 690, 56, v)
		w.add_theme_font_size_override("font_size", 22)
	var games = m.get("games")
	if games is Array and not games.is_empty():
		var s := ScrollContainer.new()
		s.name = "Games"
		s.custom_minimum_size = Vector2(690, 150)
		s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(s)
		var flow := HFlowContainer.new()
		flow.custom_minimum_size.x = 680
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		s.add_child(flow)
		for i in games.size():
			var g := str(games[i])
			var done: bool = i < games.size() - 1 or not TournamentBracket.is_live(m)
			var b := _btn(tr("Replay of game %d") % (i + 1), "Replay_%d" % i, request_replay.bind(g), 334, 52, flow)
			b.disabled = not done
	elif st != "":
		var l := _lbl(tr("No games played yet."), 17, Palette.MUTED, v)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var c := _btn(tr("Close"), "Close", close_overlay, 200, 52, v)
	c.size_flags_horizontal = Control.SIZE_SHRINK_END


## Asks the server for a game's replay (part B's `replay {game}`); replay_ready brings it.
func request_replay(game: String) -> void:
	_want_replay = game
	link.send({"t": "replay", "game": game})
	say(tr("Loading the replay…"))


## A deck's cards (own, or revealed).
func show_deck(d: Dictionary) -> void:
	var v := _dialog(str(d.get("name", "")) + "  ·  " + class_name_of(str(d.get("hero", ""))), Vector2(560, 600), "DeckDialog")
	var s := ScrollContainer.new()
	s.custom_minimum_size = Vector2(530, 440)
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(s)
	var list := VBoxContainer.new()
	s.add_child(list)
	var deck := Deck.from_dict(d)
	for pair in deck.sorted_counts() if deck else []:
		var tile := DeckTiles.DeckTile.new(pair[0], pair[1])
		tile.custom_minimum_size = Vector2(510, 36)
		list.add_child(tile)
	_btn(tr("Close"), "Close", close_overlay, 200, 52, v).size_flags_horizontal = Control.SIZE_SHRINK_END


## Another player's revealed decks.
func show_decks_of(e: Dictionary) -> void:
	var v := _dialog(tr("Decks of %s") % str(e.get("name", "")), Vector2(640, 360), "DecksOf")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	v.add_child(flow)
	for d in e.get("decks", []):
		if d is Dictionary:
			var tile := DeckChip.new()
			tile.hero = str(d.get("hero", ""))
			tile.title = str(d.get("name", ""))
			tile.custom_minimum_size = Vector2(190, 64)
			tile.pressed.connect(show_deck.bind(d))
			flow.add_child(tile)
	_btn(tr("Close"), "Close", close_overlay, 200, 52, v).size_flags_horizontal = Control.SIZE_SHRINK_END


## Choosing the decks to join with (or to change to): exactly decks_needed, each of another
## class; a deck of a class already chosen takes that class's place.
var chosen: Array = []


func pick_decks(change: bool) -> void:
	var n := decks_needed(page)
	var all := decks_for(page)
	chosen = []
	if change:  # the decks given before, found again by name and class
		var had = _my_entrant().get("decks")
		for d: Deck in all:
			if had is Array and had.any(func(x): return x is Dictionary and x.get("name") == d.name and x.get("hero") == d.hero):
				chosen.append(d)
	_build_picker(change, n, all)


func _build_picker(change: bool, n: int, all: Array) -> void:
	var v := _dialog(tr("Choose %d decks of different classes") % n, Vector2(1100, 620), "DeckPicker")
	if Packs.find_rules(str(page.get("pack", ""))) == null:
		_wrap(_lbl(tr("You don't have this game: get it in the server's home first."), 20, Palette.DANGER, v), 1060)
	elif all.is_empty():
		_wrap(_lbl(tr("You have no finished decks of this game: build them in the Collection."), 20, Palette.DANGER, v), 1060)
	var s := ScrollContainer.new()
	s.custom_minimum_size = Vector2(1070, 420)
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(s)
	var grid := GridContainer.new()
	grid.name = "Decks"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	s.add_child(grid)
	for i in all.size():
		var d: Deck = all[i]
		var tile := DeckChip.new()
		tile.name = "Deck%d" % i
		tile.hero = d.hero
		tile.title = d.name
		tile.selected = chosen.has(d)
		tile.custom_minimum_size = Vector2(258, 84)
		tile.pressed.connect(func():
			if chosen.has(d):
				chosen.erase(d)
			else:
				chosen = chosen.filter(func(x: Deck): return x.card_class() != d.card_class())
				chosen.append(d)
				if chosen.size() > n:
					chosen.pop_front()
			_build_picker(change, n, all))
		grid.add_child(tile)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var pips := Pips.new()
	pips.total = n
	pips.filled = chosen.size()
	pips.custom_minimum_size = Vector2(maxf(40.0 * n, 80), 52)
	row.add_child(pips)
	var cnt := _lbl(tr("%d of %d chosen") % [chosen.size(), n], 20, Palette.TEXT, row)
	cnt.name = "Chosen"
	cnt.custom_minimum_size = Vector2(300, 52)
	cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_btn(tr("Cancel"), "PickCancel", close_overlay, 200, 56, row)
	var ok := _btn(tr("Save decks") if change else tr("Join"), "PickOk", send_decks.bind(change), 240, 56, row)
	ok.disabled = chosen.size() != n


## Sends the chosen decks: t_join, or t_decks to change them.
func send_decks(change: bool) -> void:
	var decks: Array = chosen.map(func(d: Deck): return {"name": d.name, "hero": d.hero, "cards": Array(d.cards)})
	link.send({"t": "t_decks" if change else "t_join", "id": wire_id(page_id), "decks": decks})
	close_overlay()
	say(tr("Sent…"))


# --- the create / edit / reschedule form -------------------------------------------------------

## The form's starting values: now + 1 h on a whole quarter (local), 8 players, single elimination,
## Conquest best of 3, no bans, decks hidden, spectators on.
static func default_form() -> Dictionary:
	var start := now_ms() + 3600 * 1000
	start = (start / (15 * 60000) + 1) * (15 * 60000)
	return {"name": "", "format": "elimination", "losses": 1, "rr_rounds": 1, "swiss_rounds": 0, "drop_after": 0,
		"series": "conquest", "best_of": 3, "bans": 0, "max_players": 8, "min_players": 2, "start_at": start,
		"deck_reveal": false, "spectators": true}


## The form from a tournament (editing it).
static func form_of(t: Dictionary) -> Dictionary:
	var f := default_form()
	f.name = str(t.get("name", ""))
	f.format = str(t.get("format", "elimination"))
	f.losses = int(opt(t, "losses", 1))
	f.rr_rounds = int(opt(t, "rounds", 1)) if f.format == "round_robin" else 1
	f.swiss_rounds = int(opt(t, "rounds", 0)) if f.format == "swiss" else 0
	f.drop_after = int(opt(t, "drop_after", 0))
	for k in ["series", "best_of", "bans", "max_players", "min_players", "start_at", "deck_reveal", "spectators"]:
		var v = opt(t, k, f[k])
		f[k] = int(v) if v is float else v
	return f


## Why the form can't be sent ("" = it can). mode: "create", "edit" or "reschedule" (later only).
static func check_form(f: Dictionary, mode := "create", old_start := 0) -> String:
	var now := now_ms()
	if mode != "reschedule":
		var n := str(f.get("name", "")).strip_edges().length()
		if n < 3 or n > 40:
			return _tr("The name needs 3 to 40 letters")
		if int(f.max_players) < 2 or int(f.max_players) > 128:
			return _tr("Players: 2 to 128")
		if int(f.min_players) < 2 or int(f.min_players) > int(f.max_players):
			return _tr("The minimum is 2 to the maximum")
		if f.format == "scheveningen" and int(f.max_players) < 2:
			return _tr("Players: 2 to 128")
	if mode != "edit":
		var s := int(f.start_at)
		if s < now + MIN_LEAD_MS:
			return _tr("The start must be at least 11 minutes from now")
		if s > now + MAX_LEAD_MS:
			return _tr("The start can be at most 14 days ahead")
		if mode == "reschedule" and s <= old_start:
			return _tr("A tournament can only be moved to later")
	return ""


## The format's options as the server takes them.
static func format_options(f: Dictionary) -> Dictionary:
	match str(f.format):
		"elimination":
			return {"losses": int(f.losses)}
		"round_robin":
			return {"rounds": int(f.rr_rounds)}
		"swiss":
			var o := {"drop_after": int(f.drop_after)}
			if int(f.swiss_rounds) > 0:  # none: the server's default, ceil(log2 n)
				o["rounds"] = int(f.swiss_rounds)
			return o
	return {}


## The message for the form: t_create (with the pack), t_edit (the editable options) or
## t_reschedule.
static func form_message(f: Dictionary, mode: String, pack_hash := "", id: Variant = null) -> Dictionary:
	if mode == "reschedule":
		return {"t": "t_reschedule", "id": wire_id(id), "start_at": int(f.start_at)}
	var m := {"name": str(f.name).strip_edges(), "format": str(f.format), "options": format_options(f),
		"bans": int(f.bans), "max_players": int(f.max_players), "min_players": int(f.min_players),
		"deck_reveal": f.deck_reveal == true, "spectators": f.spectators == true}
	if mode == "edit":
		m["t"] = "t_edit"
		m["id"] = wire_id(id)
		return m
	m["t"] = "t_create"
	m["pack"] = pack_hash
	m["series"] = str(f.series)
	m["best_of"] = int(f.best_of)
	m["start_at"] = int(f.start_at)
	return m


func start_form(mode: String) -> void:
	form_mode = mode
	form = default_form() if mode == "create" else form_of(page)
	if mode != "create":
		tab = "create"
	_scroll_keep.erase("FormScroll")
	_build_form()


func _build_form() -> void:
	_clear()
	var title: String = {"create": tr("Tournaments"), "edit": tr("Edit the tournament"), "reschedule": tr("Reschedule")}[form_mode]
	_top_bar(title)
	if form_mode == "create":
		var x := _tab_buttons(TABS.map(func(t): return [t, tr(TAB_NAMES[t]), 150.0]), "", 470, show_tab)
		var c := _btn("+ " + tr("Create"), "Tab_create", Callable(), 1266 - x, 52, _body)
		c.position = Vector2(x, 10)
		mark(c, true)
	var s := _scroll(Vector2(24, 84), Vector2(1232, 500), "FormScroll")
	var v := VBoxContainer.new()
	v.name = "Form"
	v.custom_minimum_size.x = 1216
	v.add_theme_constant_override("separation", 12)
	s.add_child(v)
	var fixed := form_mode == "edit"
	if form_mode == "create":
		var pv := _section(v, tr("Start from a preset"))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		pv.add_child(flow)
		for i in PRESETS.size():
			var pr: Array = PRESETS[i]
			var b := _btn(tr(pr[0]), "Preset%d" % i, func():
				for k in pr[1]:
					form[k] = pr[1][k]
				form.min_players = mini(int(form.min_players), int(form.max_players))
				if str(form.name).strip_edges() == "":
					form.name = tr(pr[0])
				_build_form(), 0, 52, flow)
			b.add_theme_font_size_override("font_size", 18)
	if form_mode != "edit":
		_start_picker(v)
	if form_mode != "reschedule":
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 12)
		v.add_child(cols)
		var left := _section(cols, tr("The tournament"))
		left.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var right := _section(cols, tr("The matches"))
		right.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_field(left, tr("Name"), tr("3 to 40 letters; everyone sees it"), _name_edit())
		_field(left, tr("Format"), _format_line(), _segment("format", [["elimination", tr("Elimination")], ["swiss", tr("Swiss")], ["round_robin", tr("Round robin")], ["scheveningen", tr("Teams")]]))
		match str(form.format):
			"elimination":
				_field(left, tr("Lives"), tr("Double: a second chance in the losers bracket"), _segment("losses", [[1, tr("Single")], [2, tr("Double")]]))
			"round_robin":
				_field(left, tr("Rounds"), tr("Twice: everyone plays everyone again"), _segment("rr_rounds", [[1, tr("Once")], [2, tr("Twice")]]))
			"swiss":
				_field(left, tr("Rounds"), tr("Auto: enough rounds for one clear winner"), _stepper("swiss_rounds", 0, 10, tr("Auto")))
				_field(left, tr("Out after losses"), tr("A player with this many lost matches stops playing"), _segment("drop_after", [[0, tr("Never")], [1, "1"], [2, "2"], [3, "3"], [4, "4"], [5, "5"]]))
		var cap: int = PLAYERS_CAP.get(str(form.format), 128)
		form.max_players = mini(int(form.max_players), cap)
		form.min_players = mini(int(form.min_players), int(form.max_players))
		_field(left, tr("Players at most"), tr("2 to %d") % cap, _stepper("max_players", 2, cap))
		_field(left, tr("Players at least"), tr("Fewer by 10 minutes before the start: it is closed"), _stepper("min_players", 2, int(form.max_players)))
		var series := _segment("series", [["conquest", tr("Conquest")], ["lhs", tr("Last Hero Standing")]], fixed)
		_field(right, tr("Series"), tr("Conquest: win once with each deck. Last Hero Standing: a losing deck is out") if not fixed else tr("Fixed after creation"), series)
		_field(right, tr("Length"), tr("Wins needed: %d") % ((int(form.best_of) + 1) / 2) if not fixed else tr("Fixed after creation"),
			_segment("best_of", [[1, tr("Bo1")], [3, tr("Bo3")], [5, tr("Bo5")], [7, tr("Bo7")]], fixed))
		_field(right, tr("Bans"), tr("Each player bans one of the opponent's decks before the games"), _segment("bans", [[0, tr("No bans")], [1, tr("One ban")]]))
		var need := _lbl(tr("Each player brings %d decks of different classes") % decks_needed(form), 19, Palette.SELECTED, right)
		need.name = "DecksNeeded"
		_field(right, tr("Decklists"), tr("Open: everyone sees every deck from 10 minutes before the start"), _segment("deck_reveal", [[false, tr("Hidden")], [true, tr("Open")]]))
		_field(right, tr("Spectators"), tr("The creator and eliminated players may watch running matches"), _segment("spectators", [[true, tr("Allowed")], [false, tr("No")]]))
	var foot := Panel.new()  # the summary and the button on a footer, as the top bar
	foot.name = "FormFoot"
	foot.position = Vector2(0, 588)
	foot.size = Vector2(1280, 80)
	var fst := Palette.box(Color(0.07, 0.045, 0.025, 0.94), 0)
	fst.border_color = Color("a8863a")
	fst.border_width_top = 2
	foot.add_theme_stylebox_override("panel", fst)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(foot)
	var bar := HBoxContainer.new()
	bar.name = "FormBar"
	bar.position = Vector2(150, 596)
	bar.size = Vector2(1106, 64)
	bar.add_theme_constant_override("separation", 14)
	_body.add_child(bar)
	var sum := _lbl(_summary(), 18, Palette.TEXT, bar)
	sum.name = "Summary"
	sum.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sum.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sum.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var go_text: String = {"create": tr("Create the tournament"), "edit": tr("Save"), "reschedule": tr("Move the start")}[form_mode]
	var go := _btn(go_text, "FormOk", submit_form, 320, 60, bar)
	go.add_theme_font_size_override("font_size", 22)


func _summary() -> String:
	var parts: Array = []
	if form_mode != "reschedule":
		parts.append(tr("%d players") % int(form.max_players))
		parts.append(tr("%d decks each") % decks_needed(form))
	if form_mode != "edit":
		parts.append(tr("starts %s") % local_text(int(form.start_at)))
	return " · ".join(parts)


func _format_line() -> String:
	return {"elimination": tr("Lose and you are out; the bracket goes on to the final"),
		"swiss": tr("Rounds of players with equal points; nobody is out early"),
		"round_robin": tr("Everyone plays everyone"),
		"scheveningen": tr("Two random, balanced teams: everyone plays everyone of the other team")}.get(str(form.format), "")


## A form row: the label, the control, the line that explains it.
func _field(parent: Control, title: String, note: String, control: Control) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	_lbl(title, 19, Palette.TEXT, box)
	box.add_child(control)
	_wrap(_lbl(note, 15, Palette.MUTED, box), 560)


func _name_edit() -> LineEdit:
	var e := LineEdit.new()
	e.name = "NameEdit"
	e.text = str(form.name)
	e.max_length = 40
	e.placeholder_text = tr("Friday night cup")
	e.custom_minimum_size = Vector2(560, 52)
	e.add_theme_font_size_override("font_size", 20)
	e.text_changed.connect(func(s): form.name = s)
	return e


## A row of toggle buttons for one option (one is on); fixed: shown, not changeable.
func _segment(k: String, items: Array, fixed := false) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.name = "Opt_" + k
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	for it in items:
		var on: bool = str(form.get(k)) == str(it[0])
		var b := _btn(it[1], "%s_%s" % [k, str(it[0])], func():
			form[k] = it[0]
			if k == "max_players":
				form.min_players = mini(int(form.min_players), int(form.max_players))
			_build_form(), 0, 50, row)
		b.custom_minimum_size.x = 84
		mark(b, on)
		b.disabled = fixed and not on
		b.add_theme_font_size_override("font_size", 18)
	return row


## − value + for a number (lo..hi); zero_text: what 0 means.
func _stepper(k: String, lo: int, hi: int, zero_text := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Opt_" + k
	row.add_theme_constant_override("separation", 6)
	var val := int(form.get(k, lo))
	var steps := [[-10, "−10"], [-1, "−"]] if hi > 20 else [[-1, "−"]]
	for st in steps:
		var b := _btn(st[1], "%s_minus%d" % [k, absi(st[0])], _step.bind(k, st[0], lo, hi), 64, 50, row)
		b.disabled = val <= lo
	var l := _lbl(zero_text if val == 0 and zero_text != "" else str(val), 24, Palette.ATTACK, row)
	l.name = "Value"
	l.custom_minimum_size = Vector2(90, 50)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for st in [[1, "+"], [10, "+10"]] if hi > 20 else [[1, "+"]]:
		var b := _btn(st[1], "%s_plus%d" % [k, st[0]], _step.bind(k, st[0], lo, hi), 64, 50, row)
		b.disabled = val >= hi
	return row


func _step(k: String, d: int, lo: int, hi: int) -> void:
	form[k] = clampi(int(form.get(k, lo)) + d, lo, hi)
	form.min_players = clampi(int(form.min_players), 2, int(form.max_players))
	_build_form()


## The start in local time: quick choices, the day, the hour and minute.
func _start_picker(parent: Control) -> void:
	var v := _section(parent, tr("Start (your time)"))
	v.get_parent().name = "StartCard"
	var now := now_ms()
	var quick := HFlowContainer.new()
	quick.add_theme_constant_override("h_separation", 8)
	quick.add_theme_constant_override("v_separation", 8)
	v.add_child(quick)
	var today := Time.get_datetime_dict_from_unix_time(int(now / 1000) + tz_s())
	var evening := local_to_ms(today.year, today.month, today.day, 20, 0)
	if evening < now + MIN_LEAD_MS:
		evening += 86400 * 1000
	var round15 := func(ms: int) -> int: return (ms / (15 * 60000) + 1) * (15 * 60000)
	for q in [["In 15 minutes", round15.call(now + 11 * 60000)], ["In 1 hour", round15.call(now + 3600000)],
			["At 20:00", evening], ["Tomorrow at 20:00", evening + (86400 * 1000 if evening - now < 86400 * 1000 - MIN_LEAD_MS else 0)]]:
		var at: int = q[1]
		var b := _btn(tr(q[0]), "Quick_" + q[0].replace(" ", "").replace(":", ""), func():
			form.start_at = at
			_build_form(), 0, 50, quick)
		b.add_theme_font_size_override("font_size", 18)
		b.disabled = form_mode == "reschedule" and at <= int(opt(page, "start_at", 0))
	if form_mode == "reschedule":
		var was := _lbl(tr("Now set to %s; it can only move later") % local_text(int(opt(page, "start_at", 0))), 17, Palette.TEXT, v)
		was.name = "WasStart"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var cur := Time.get_datetime_dict_from_unix_time(int(int(form.start_at) / 1000) + tz_s())
	var day := OptionButton.new()
	day.name = "Day"
	day.custom_minimum_size = Vector2(300, 52)
	day.add_theme_font_size_override("font_size", 20)
	var sel := 0
	for i in 15:
		var d := Time.get_datetime_dict_from_unix_time(int(now / 1000) + tz_s() + i * 86400)
		var text := "%04d-%02d-%02d" % [d.year, d.month, d.day]
		if i == 0:
			text = tr("Today") + "  " + text
		elif i == 1:
			text = tr("Tomorrow") + "  " + text
		day.add_item(text, i)
		day.set_item_metadata(i, [d.year, d.month, d.day])
		if d.year == cur.year and d.month == cur.month and d.day == cur.day:
			sel = i
	day.select(sel)
	day.item_selected.connect(func(i):
		var d: Array = day.get_item_metadata(i)
		form.start_at = local_to_ms(d[0], d[1], d[2], cur.hour, cur.minute)
		_build_form())
	row.add_child(day)
	for unit in [["hour", 3600000, "%02d" % cur.hour], ["minute", 5 * 60000, "%02d" % cur.minute]]:
		var minus := _btn("−", "Start_%s_minus" % unit[0], _shift_start.bind(-int(unit[1])), 64, 52, row)
		minus.add_theme_font_size_override("font_size", 24)
		var l := _lbl(unit[2], 28, Palette.ATTACK, row)
		l.name = "Start_" + unit[0]
		l.custom_minimum_size = Vector2(56, 52)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var plus := _btn("+", "Start_%s_plus" % unit[0], _shift_start.bind(int(unit[1])), 64, 52, row)
		plus.add_theme_font_size_override("font_size", 24)
		if unit[0] == "hour":
			_lbl(":", 28, Palette.ATTACK, row).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var left := int(form.start_at) - now
	var note := tr("Starts in %s") % left_text(left) + "  ·  " + tr("from 11 minutes to 14 days from now")
	var nl := _lbl(note, 16, Palette.MUTED if left >= MIN_LEAD_MS and left <= MAX_LEAD_MS else Palette.DANGER, v)
	nl.name = "StartNote"


func _shift_start(d: int) -> void:
	var s := int(form.start_at) + d
	s = s - s % (5 * 60000)
	form.start_at = s
	_build_form()


func submit_form() -> void:
	var why := check_form(form, form_mode, int(opt(page, "start_at", 0)))
	if why != "":
		say(why)
		return
	var pack_hash := ""
	if form_mode == "create":
		var p := Packs.active()
		if p == null or not link.has_game(p):
			say(link.game_problem(p) if p else tr("This server does not have this game"))
			return
		pack_hash = str(link.server_pack_for(p).get("rules_hash", p.rules_hash()))
		_creating = true
	link.send(form_message(form, form_mode, pack_hash, page_id))
	say(tr("Sent…"))
	if form_mode != "create":
		tab = "page"
		_build_page()


# --- the server -------------------------------------------------------------------------------

func _on_message(msg: Dictionary) -> void:
	match msg.get("t"):
		"t_list":
			var t := str(msg.get("tab", ""))
			lists[t] = msg.get("list") if msg.get("list") is Array else []
			if tab == t:
				_build_list()
		"tournament":
			var t := payload(msg)
			if t.is_empty():
				return
			var k := TournamentBracket.key(t.get("id"))
			cache[k] = t
			if _creating:
				_creating = false
				say(tr("The tournament is created"))
				page_id = null
				open_page(t.get("id"))
			elif page_id != null and TournamentBracket.key(page_id) == k:
				page = t
				if _status.text == tr("Sent…"):
					say("")
				if tab == "page":
					var keep := _overlay != null and _overlay.name in ["DeckPicker", "DeckDialog", "DecksOf"]
					if not keep:
						_build_page()
		"error":
			if msg.get("code") == "tournament" or tab == "create" or tab == "page":
				_creating = false
				say(str(msg.get("text", msg.get("code", ""))))
		"replay":
			if str(msg.get("game", "")) == _want_replay and _want_replay != "":
				_want_replay = ""
				say("")
				replay_ready.emit(msg.get("data") if msg.get("data") is Dictionary else {})


# --- drawn pieces -------------------------------------------------------------------------------

## A rounded pill with text (a status badge, a chip): drawn at x, returns its right edge.
static func pill(ci: Control, at: Vector2, text: String, col: Color, font_size := 15, solid := false) -> float:
	var f := ci.get_theme_font("font", "Label")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 22
	var h := font_size + 13.0
	var r := Rect2(at, Vector2(w, h))
	var st := Palette.raw_box(col if solid else Color(col, 0.16), int(h / 2), col, 0 if solid else 2)
	ci.draw_style_box(st, r)
	ci.draw_string(f, at + Vector2(11, h / 2.0 + font_size * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("1a1208") if solid else col.lightened(0.25))
	return r.end.x


## A player's team (Scheveningen) or seed, as the server numbers them from 0 (-1: none yet).
static func seed_line(e: Dictionary) -> String:
	var team := TournamentBracket.n(e.get("team")) if e.get("team") != null else -1
	var seed := TournamentBracket.n(e.get("seed")) if e.get("seed") != null else -1
	if team >= 0:
		return _tr("Team %d") % (team + 1)
	return _tr("Seed %d") % (seed + 1) if seed >= 0 else ""


## A tournament in a list: a trophy, the name, who made it and the game, chips for the format,
## the series and the players, the status badge and the start (with the time left).
class ListRow:
	extends Button
	var e := {}

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(1220, 104)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var joined: bool = e.get("joined", false) == true
		draw_style_box(Palette.box(Color(0.1, 0.07, 0.045, 0.94) if not is_hovered() else Color(0.15, 0.1, 0.06, 0.96), 12,
			Palette.SELECTED if joined else Color("6b5320"), 3 if joined else 2), r)
		TournamentsView.Trophy.cup(self, Vector2(52, 52), 30, TournamentsView.status_color(str(e.get("status", ""))))
		DeckTiles.text(self, Vector2(100, 38), str(e.get("name", "")), 24, Palette.ATTACK, 620)
		var by := TournamentsView._tr("by %s") % str(e.get("creator", "")) + "  ·  " + str(e.get("pack_name", e.get("pack", "")))
		DeckTiles.text(self, Vector2(100, 64), by, 16, Palette.MUTED, 620)
		var x := 100.0
		x = TournamentsView.pill(self, Vector2(x, 72), TournamentsView.format_name(e), Color("c9a74a"), 14) + 8
		x = TournamentsView.pill(self, Vector2(x, 72), TournamentsView.series_name(e), Color("c9a74a"), 14) + 8
		x = TournamentsView.pill(self, Vector2(x, 72), TournamentsView._tr("%d / %d players") % [TournamentBracket.n(e.get("entrants")), TournamentBracket.n(e.get("max_players"))], Color("9fc4e8"), 14) + 8
		if joined:
			TournamentsView.pill(self, Vector2(x, 72), TournamentsView._tr("You are in"), Palette.SELECTED, 14, true)
		var st := str(e.get("status", ""))
		var f := get_theme_font("font", "Label")
		var badge := TournamentsView.status_name(st)
		var bw := f.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 22
		TournamentsView.pill(self, Vector2(size.x - 20 - bw, 14), badge, TournamentsView.status_color(st), 17, true)
		var start := int(e.get("start_at", 0))
		var when := TournamentsView.local_text(start)
		if st != "running":
			DeckTiles.text(self, Vector2(size.x - 20 - f.get_string_size(when, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x, 70), when, 18, Palette.TEXT)
		if st in ["open", "locked", "seeded"]:
			var left := TournamentsView.clock_text(start)
			DeckTiles.text(self, Vector2(size.x - 20 - f.get_string_size(left, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, 92), left, 15, Palette.SELECTED)
		elif st == "running":
			var live := TournamentsView._tr("live")
			TournamentsView.pill(self, Vector2(size.x - 34 - f.get_string_size(live, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, 72), live, TournamentBracket.WIN, 14, true)
		elif e.get("winner") is String:
			var w := TournamentsView._tr("Winner: %s") % e.winner
			DeckTiles.text(self, Vector2(size.x - 20 - f.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, 92), w, 15, TournamentBracket.MEDALS[0])

	func _process(_d: float) -> void:
		queue_redraw()  # the time left


## The page's head: the status badge, the creator, the game, the format and the series.
class PageHead:
	extends Control
	var t := {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_style_box(Palette.box(Color(0.08, 0.055, 0.035, 0.92), 12, Color("6b5320"), 2), Rect2(Vector2.ZERO, size))
		var st := str(t.get("status", ""))
		TournamentsView.Trophy.cup(self, Vector2(38, 37), 24, TournamentsView.status_color(st))
		var x := TournamentsView.pill(self, Vector2(74, 10), TournamentsView.status_name(st), TournamentsView.status_color(st), 17, true) + 10
		if st == "closed" and t.get("reason") is String:
			x = TournamentsView.pill(self, Vector2(x, 10), TournamentsView._tr(str(t.reason)), Palette.MUTED, 15) + 10
		var by := TournamentsView._tr("by %s") % str(t.get("creator", "")) + "  ·  " + str(t.get("pack_name", ""))
		DeckTiles.text(self, Vector2(x, 32), by, 17, Palette.MUTED, 700 - x)
		var y := 44.0
		x = TournamentsView.pill(self, Vector2(74, y), TournamentsView.format_name(t), Color("c9a74a"), 14) + 8
		x = TournamentsView.pill(self, Vector2(x, y), TournamentsView.series_name(t), Color("c9a74a"), 14) + 8
		TournamentsView.pill(self, Vector2(x, y), TournamentsView._tr("%d decks each") % TournamentsView.decks_needed(t), Color("9fc4e8"), 14)


## A player in the list: the place (a medal, added as a child), the avatar, the name (the
## player's own in the highlight; out: dim), the seed or team, points and W–L, their deck classes.
class PlayerRow:
	extends Button
	var e := {}
	var me := ""
	## Points and W–L shown (not before the bracket: nothing is played yet).
	var scored := true

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var who := str(e.get("name", ""))
		var mine := who == me
		var place := TournamentBracket.place_of(e)
		var edge: Color = TournamentBracket.MEDALS[place - 1] if place in [1, 2, 3] else (Palette.SELECTED if mine else Color(0, 0, 0, 0))
		draw_style_box(Palette.box(Color(0.1, 0.07, 0.045, 0.9), 10, edge, 2), Rect2(Vector2.ZERO, size))
		var dx := 0.0 if place > 0 else -44.0  # no places yet: no room kept for one
		TournamentBracket.avatar(self, Vector2(74 + dx, size.y / 2.0), 18, who)
		var out: bool = e.get("eliminated", false) == true
		var col := Palette.SELECTED if mine else (Color(0.6, 0.56, 0.5) if out else Palette.TEXT)
		DeckTiles.text(self, Vector2(102 + dx, 30), who, 20, col, 240)
		var sub := TournamentsView.seed_line(e)
		if out:
			sub += ("  ·  " if sub != "" else "") + TournamentsView._tr("out")
		DeckTiles.text(self, Vector2(102 + dx, 52), sub, 14, Palette.MUTED, 240)
		var x := 350.0
		var decks = e.get("decks")
		for d in decks if decks is Array else []:
			if d is Dictionary and x < size.x - 120:
				var cls := Decks.card_class(str(d.get("hero", "")))
				draw_circle(Vector2(x + 14, size.y / 2.0), 16, Palette.of_class(cls).darkened(0.3))
				Icons.paint(self, cls, Rect2(Vector2(x, size.y / 2.0 - 14), Vector2(28, 28)))
				x += 34
		if scored and (e.get("points") != null or e.get("wins") != null):
			var pts := TournamentBracket._num(e.get("points"))
			var f := get_theme_font("font", "Label")
			DeckTiles.text(self, Vector2(size.x - 16 - f.get_string_size(pts, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x, 30), pts, 22, Palette.ATTACK)
			var wl := "%d–%d" % [TournamentBracket.n(e.get("wins")), TournamentBracket.n(e.get("losses"))]
			DeckTiles.text(self, Vector2(size.x - 16 - f.get_string_size(wl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, 52), wl, 14, Palette.MUTED)


## A deck as a tile: its hero's picture in a band, the class colour and emblem, its name and
## class; selected: a gold rim and a tick; state: "banned", "won", "lost" over it.
class DeckChip:
	extends Button
	var hero := ""
	var title := ""
	var selected := false
	var state := "ok"

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE

	func _draw() -> void:
		var cls := Decks.card_class(hero)
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		var col := Palette.of_class(cls)
		draw_style_box(Palette.raw_box(col.darkened(0.55), 12), r)
		if hero != "":
			DeckTiles.strip(self, r.grow(-3), hero, 0.3)
		var side := minf(size.y - 24, 52.0)
		Icons.paint(self, cls, Rect2(Vector2(10, (size.y - side) / 2.0), Vector2(side, side)))
		var tx := 18.0 + side
		var fs := 18 if size.y >= 70 else 15  # a small tile: the deck's name still fits
		DeckTiles.text(self, Vector2(tx, size.y / 2.0 - 2), title, fs, Color("f4ead5"), size.x - tx - 12)
		DeckTiles.text(self, Vector2(tx, size.y / 2.0 + fs + 2), TournamentsView.class_name_of(hero), fs - 4, col.lightened(0.5), size.x - tx - 12)
		if state != "ok":
			draw_rect(r, Color(0, 0, 0, 0.6))
			var word: String = {"banned": "Banned", "won": "Won", "lost": "Lost"}.get(state, state)
			var tc: Color = {"banned": Color("ff6b5a"), "won": TournamentBracket.WIN, "lost": Color("b0a090")}.get(state, Palette.MUTED)
			if state == "banned":
				draw_line(r.position + Vector2(10, 10), r.end - Vector2(10, 10), Color(tc, 0.8), 4)
			var f := get_theme_font("font", "Label")
			var pw := f.get_string_size(TournamentsView._tr(word), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 22
			TournamentsView.pill(self, Vector2(size.x - pw - 10, size.y - 36), TournamentsView._tr(word), tc, 14, true)
		var edge := Palette.SELECTED if selected else (Color("c9a74a", 0.8) if is_hovered() and not disabled else Color(0, 0, 0, 0))
		draw_style_box(Palette.raw_box(Color(0, 0, 0, 0), 12, edge, 4 if selected else 2), r)
		if selected:
			var c := Vector2(size.x - 22, 22)
			draw_circle(c, 14, Palette.SELECTED)
			draw_polyline(PackedVector2Array([c + Vector2(-7, 0), c + Vector2(-2, 6), c + Vector2(7, -6)]), Color("1a1208"), 3.5, true)


## Two players face to face: avatars, names, the series score big in the middle.
class Versus:
	extends Control
	var m := {}
	var me := ""

	func _draw() -> void:
		var p := TournamentBracket.players(m)
		var s := TournamentBracket.score(m)
		var w := TournamentBracket.winner(m)
		var f := get_theme_font("font", "Label")
		for i in 2:
			var cx := size.x * (0.2 if i == 0 else 0.8)
			var who: String = p[i] if p[i] != "" else "—"
			TournamentBracket.avatar(self, Vector2(cx, 38), 30, p[i])
			var col := Palette.SELECTED if p[i] == me and me != "" else (Palette.ATTACK if w == p[i] else Palette.TEXT)
			var tw := minf(f.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x, 240)
			DeckTiles.text(self, Vector2(cx - tw / 2.0, 100), who, 22, col, 240)
		var sc := "%d : %d" % s
		var sw := f.get_string_size(sc, HORIZONTAL_ALIGNMENT_LEFT, -1, 44).x
		DeckTiles.text(self, Vector2(size.x / 2.0 - sw / 2.0, 60), sc, 44, Palette.ATTACK)


## Series pips: filled of total.
class Pips:
	extends Control
	var total := 1
	var filled := 0
	var color := Palette.SELECTED

	func _draw() -> void:
		var r := minf(14.0, size.y / 2.0 - 2)
		var step := r * 2 + 8
		var x0 := r + 2
		for i in total:
			var c := Vector2(x0 + i * step, size.y / 2.0)
			draw_circle(c, r + 2, Color(0, 0, 0, 0.6))
			draw_circle(c, r, color if i < filled else Color(0.25, 0.2, 0.15))
			draw_arc(c, r, 0, TAU, 24, color.darkened(0.2), 2.0, true)


## A trophy: a cup in a colour (the status's).
class Trophy:
	extends Control
	func _draw() -> void:
		TournamentsView.Trophy.cup(self, size / 2.0, minf(size.x, size.y) * 0.45, TournamentBracket.MEDALS[0])

	static func cup(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
		ci.draw_circle(c, r, Color(col, 0.16))
		ci.draw_arc(c, r, 0, TAU, 32, Color(col, 0.6), 2.0, true)
		var s := r / 24.0
		var bowl := PackedVector2Array([c + Vector2(-11, -12) * s, c + Vector2(11, -12) * s, c + Vector2(9, -1) * s,
			c + Vector2(4, 4) * s, c + Vector2(-4, 4) * s, c + Vector2(-9, -1) * s])
		ci.draw_colored_polygon(bowl, col)
		ci.draw_arc(c + Vector2(-11, -6) * s, 5 * s, PI * 0.5, PI * 1.5, 10, col, 2.5 * s)
		ci.draw_arc(c + Vector2(11, -6) * s, 5 * s, -PI * 0.5, PI * 0.5, 10, col, 2.5 * s)
		ci.draw_rect(Rect2(c + Vector2(-2, 4) * s, Vector2(4, 6) * s), col)
		ci.draw_rect(Rect2(c + Vector2(-8, 10) * s, Vector2(16, 4) * s), col)


## The lock steps on a line: now (open), T−10 min (locked), T−1 min (seeded), T (the start);
## the passed ones lit.
class Timeline:
	extends Control
	var start := 0

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var now := TournamentsView.now_ms()
		var steps := [[start - TournamentsView.LOCK_MS, "Locked in", "Rules, decks and the start are frozen"],
			[start - TournamentsView.SEED_MS, "Seeded", "The bracket is drawn; joining and leaving close"],
			[start, "Start", "The first matches begin"]]
		var x := 20.0
		var y0 := 22.0
		var gap := (size.y - 30) / steps.size()
		draw_line(Vector2(x, y0), Vector2(x, y0 + gap * (steps.size() - 1)), Color(0.5, 0.42, 0.3), 3)
		for i in steps.size():
			var st: Array = steps[i]
			var done: bool = now >= int(st[0])
			var y := y0 + gap * i
			draw_circle(Vector2(x, y), 10, Palette.SELECTED if done else Color(0.3, 0.25, 0.18))
			draw_arc(Vector2(x, y), 10, 0, TAU, 20, Palette.ATTACK, 2, true)
			var head := TournamentsView.local_text(int(st[0])).right(5) + "  " + TournamentsView._tr(st[1])
			DeckTiles.text(self, Vector2(x + 24, y + 2), head, 19, Palette.ATTACK if done else Palette.TEXT, size.x - 50)
			DeckTiles.text(self, Vector2(x + 24, y + 24), TournamentsView._tr(st[2]), 15, Palette.MUTED, size.x - 50)


## The top three on steps: the winner in the middle on the highest, gold, silver and bronze.
class Podium:
	extends Control
	var list: Array = []
	var me := ""

	func _draw() -> void:
		var f := get_theme_font("font", "Label")
		var w := size.x / 3.0
		for spot in [[2, 0, 70.0], [1, 1, 110.0], [3, 2, 46.0]]:
			var place: int = spot[0]
			# a shared place (elimination's two semi-final losers): side by side on its step
			var here: Array = list.filter(func(x): return TournamentBracket.place_of(x) == place).slice(0, 2)
			var col: Color = TournamentBracket.MEDALS[place - 1]
			var step := Rect2(Vector2(w * spot[1] + 8, size.y - spot[2]), Vector2(w - 16, spot[2]))
			draw_style_box(Palette.raw_box(col.darkened(0.55), 8, col, 2), step)
			var n := str(place)
			var nw := f.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			DeckTiles.text(self, Vector2(step.get_center().x - nw / 2.0, step.position.y + minf(38, spot[2] - 6)), n, 30, col)
			var share := step.size.x / maxf(here.size(), 1)
			for k in here.size():
				var who := str(here[k].get("name", ""))
				var c := Vector2(step.position.x + share * (k + 0.5), step.position.y - 66)
				var r := 28 if place == 1 else 24
				TournamentBracket.avatar(self, c, r, who)
				draw_arc(c, r + 3, 0, TAU, 36, col, 3, true)
				var tw := minf(f.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x, share - 8)
				DeckTiles.text(self, Vector2(c.x - tw / 2.0, step.position.y - 14), who, 19, Palette.SELECTED if who == me else Palette.TEXT, share - 8)
