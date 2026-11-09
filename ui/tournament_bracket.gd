class_name TournamentBracket
extends Control
## A tournament's bracket from its full data (the `tournament` message, server/README.md
## "Tournaments"), drawn to be read on a phone: elimination as a tree (the winners bracket, the
## losers bracket under it, the grand final to the right); round robin as a cross table; swiss as
## the standings beside the rounds' pairings; Scheveningen as the two teams and their result grid.
## Every match is a finger-sized button (match_pressed: its details, Watch, Replays). It lives in a
## ScrollContainer: its minimum size is the whole drawing.

signal match_pressed(m: Dictionary)

const BOX := Vector2(236, 70)
const GAP := Vector2(64, 18)
const HEAD := 40.0  # a column's title above it
## The top three: gold, silver, bronze.
const MEDALS := [Color("ffd34d"), Color("dfe6ee"), Color("e0925a")]
## A match's status while it is played (its steps, then the game), and when it is over.
const LIVE := ["running", "ready", "accept", "ban", "pick", "playing", "game"]
const DONE := ["done", "finished", "bye", "forfeit"]
const WIN := Color("6fdc6a")
const LOSS := Color("ff7a6a")

var t := {}
## The player's name (their matches stand out).
var me := ""
## Match id -> the node that shows it (tests count them).
var drawn := {}
var _last := {}  # a bracket ("w", "l") -> the boxes of its last round
var _lines: Array = []  # the tree's connectors: [from, to, the match it comes from]


static func make(data: Dictionary, me_name: String) -> TournamentBracket:
	var b := TournamentBracket.new()
	b.name = "Bracket"
	b.t = data
	b.me = me_name
	b._build()
	return b


# --- data -------------------------------------------------------------------------------

static func key(v: Variant) -> String:
	return str(int(v)) if v is float else str(v)


static func matches_of(data: Dictionary) -> Array:
	var m = data.get("matches", data.get("rounds", []))
	return m.filter(func(x): return x is Dictionary) if m is Array else []


static func players(m: Dictionary) -> Array:
	var p = m.get("p", [])
	var a = p[0] if p is Array and p.size() > 0 else null
	var b = p[1] if p is Array and p.size() > 1 else null
	return [a if a is String else "", b if b is String else ""]


static func score(m: Dictionary) -> Array:
	var s = m.get("score", [])
	return [int(s[0]) if s is Array and s.size() > 0 and s[0] != null else 0,
		int(s[1]) if s is Array and s.size() > 1 and s[1] != null else 0]


static func winner(m: Dictionary) -> String:
	var w = m.get("winner")
	if w is String:
		return w
	if w is float or w is int:  # a seat
		return players(m)[clampi(int(w), 0, 1)]
	return ""


static func is_live(m: Dictionary) -> bool:
	return str(m.get("status", "")) in LIVE


static func is_done(m: Dictionary) -> bool:
	return str(m.get("status", "")) in DONE or winner(m) != ""


## The entrants in standing order: by place, else points, wins − losses, seed.
static func standings(data: Dictionary) -> Array:
	var list: Array = data.get("entrants", []).filter(func(e): return e is Dictionary) if data.get("entrants") is Array else []
	list.sort_custom(func(a, b):
		var pa := int(a.get("place", 0)) if a.get("place") != null else 0
		var pb := int(b.get("place", 0)) if b.get("place") != null else 0
		if (pa > 0) != (pb > 0):
			return pa > 0
		if pa != pb:
			return pa < pb
		var qa := float(a.get("points", 0) if a.get("points") != null else 0)
		var qb := float(b.get("points", 0) if b.get("points") != null else 0)
		if qa != qb:
			return qa > qb
		var da := TournamentBracket.n(a.get("wins")) - TournamentBracket.n(a.get("losses"))
		var db := TournamentBracket.n(b.get("wins")) - TournamentBracket.n(b.get("losses"))
		if da != db:
			return da > db
		return TournamentBracket.n(a.get("seed")) < TournamentBracket.n(b.get("seed")))
	return list


## A number of the server's data (null, a missing field: 0).
static func n(v: Variant) -> int:
	return int(v) if v is float or v is int else 0


static func place_of(e: Dictionary) -> int:
	return int(e.get("place")) if e.get("place") is float or e.get("place") is int else 0


## The place mark: a gold, silver or bronze disc with the number for the top three, else the
## number (or nothing before the places are known).
static func medal(place: int) -> Control:
	var m := Medal.new()
	m.place = place
	m.name = "Medal%d" % place if place in [1, 2, 3] else "Place"
	m.custom_minimum_size = Vector2(40, 40)
	m.tooltip_text = [_tr("1st place"), _tr("2nd place"), _tr("3rd place")][place - 1] if place in [1, 2, 3] else ""
	return m


## A player's round badge: the first letter on a disc of a colour of their own (by the name).
static func avatar(ci: CanvasItem, c: Vector2, r: float, who: String) -> void:
	var col := Color.from_hsv(float(who.hash() % 360) / 360.0, 0.45, 0.62) if who != "" else Color(0.3, 0.28, 0.25)
	ci.draw_circle(c, r + 2, Color(0, 0, 0, 0.6))
	ci.draw_circle(c, r, col)
	ci.draw_arc(c, r, 0, TAU, 28, col.lightened(0.35), 1.5, true)
	if who == "":
		return
	var f: Font = (ci as Control).get_theme_font("font", "Label") if ci is Control else ThemeDB.fallback_font
	var fs := int(r * 1.15)
	var ch := who.left(1).to_upper()
	var w := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(f, c + Vector2(-w / 2.0, fs * 0.36), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## A Control showing avatar() (for rows built of containers).
static func avatar_node(who: String, side := 36.0) -> Control:
	var a := Avatar.new()
	a.who = who
	a.custom_minimum_size = Vector2(side, side)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return a


static func _tr(s: String) -> String:
	return str(TranslationServer.translate(s))


# --- building ---------------------------------------------------------------------------

func _build() -> void:
	match str(t.get("format", "")):
		"elimination":
			_build_tree()
		"round_robin":
			_build_cross()
		"swiss":
			_build_swiss()
		"scheveningen":
			_build_teams()
		_:
			_build_tree()


func _label(text: String, at: Vector2, font_size := 18, color := Palette.ATTACK, parent: Control = self) -> Label:
	var l := Palette.label(text, font_size, color)
	l.position = at
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _box(m: Dictionary, at: Vector2) -> MatchBox:
	var b := MatchBox.new()
	b.m = m
	b.me = me
	b.name = "Match_" + key(m.get("id"))
	b.position = at
	b.size = BOX
	var p := players(m)
	b.tooltip_text = "%s — %s" % [p[0] if p[0] != "" else "?", p[1] if p[1] != "" else "?"]
	b.pressed.connect(func(): match_pressed.emit(m))
	add_child(b)
	drawn[key(m.get("id"))] = b
	return b


## Elimination: the winners bracket's rounds as columns (each round's matches centred between the
## two they come from), the losers bracket under it, the grand final at the right.
func _build_tree() -> void:
	var by := {"w": {}, "l": {}, "gf": {}}
	for m in matches_of(t):
		var br := str(m.get("bracket", "w"))
		br = br if by.has(br) else "w"
		var r := int(m.get("round", 1))
		if not by[br].has(r):
			by[br][r] = []
		by[br][r].append(m)
	var double: bool = not by.l.is_empty() or not by.gf.is_empty()
	var at := Vector2(8, 0)
	var w_end := _columns(by.w, at, "w", double)
	var bottom := w_end.end.y
	var l_end := Rect2(at, Vector2.ZERO)
	if not by.l.is_empty():
		var head := _label(tr("Losers bracket"), Vector2(8, bottom + 24), 22)
		head.name = "LosersHead"
		l_end = _columns(by.l, Vector2(8, bottom + 64), "l", true)
		bottom = l_end.end.y
	var right := maxf(w_end.end.x, l_end.end.x)
	if not by.gf.is_empty():
		var keys: Array = by.gf.keys()
		keys.sort()
		var x := right + GAP.x
		var mid := (w_end.get_center().y + (l_end.get_center().y if not by.l.is_empty() else w_end.get_center().y)) / 2.0
		_label(tr("Grand final"), Vector2(x, mid - BOX.y / 2.0 - HEAD))
		for i in keys.size():
			for m in by.gf[keys[i]]:
				var b := _box(m, Vector2(x, mid - BOX.y / 2.0))
				for from: Rect2 in [_last_box("w"), _last_box("l")]:
					if from.size != Vector2.ZERO:
						_lines.append([from.position + Vector2(BOX.x, BOX.y / 2.0), b.position + Vector2(0, BOX.y / 2.0), _at(from.position)])
				x += BOX.x + GAP.x
		right = x
	custom_minimum_size = Vector2(right + 16, bottom + 16)


## A bracket's rounds as columns from at; returns the area used.
func _columns(rounds: Dictionary, at: Vector2, br: String, double: bool) -> Rect2:
	var keys: Array = rounds.keys()
	keys.sort()
	var most := 1
	for r in keys:
		rounds[r].sort_custom(func(a, b): return int(a.get("slot", 0)) < int(b.get("slot", 0)))
		most = maxi(most, rounds[r].size())
	var unit := BOX.y + GAP.y
	var height := most * unit
	var prev: Array = []
	for c in keys.size():
		var list: Array = rounds[keys[c]]
		var x := at.x + c * (BOX.x + GAP.x)
		var title := tr("Round %d") % int(keys[c])
		if c == keys.size() - 1 and keys.size() > 1:
			title = tr("Losers final") if br == "l" else (tr("Winners final") if double else tr("Final"))
		elif br == "l":
			title = tr("Losers round %d") % int(keys[c])
		_label(title, Vector2(x, at.y))
		var share := height / list.size()
		var boxes: Array = []
		for i in list.size():
			var b := _box(list[i], Vector2(x, at.y + HEAD + share * (i + 0.5) - BOX.y / 2.0))
			b.set_meta("bracket", br)
			boxes.append(b)
		if not prev.is_empty():  # each match of the round before leads into one of this round
			for i in prev.size():
				var to: Control = boxes[mini(i * boxes.size() / prev.size(), boxes.size() - 1)]
				var from: Control = prev[i]
				_lines.append([from.position + Vector2(BOX.x, BOX.y / 2.0), to.position + Vector2(0, BOX.y / 2.0), (from as MatchBox).m])
		prev = boxes
	_last[br] = prev
	return Rect2(at, Vector2(keys.size() * (BOX.x + GAP.x) - GAP.x, HEAD + height))


func _last_box(br: String) -> Rect2:
	var last: Array = _last.get(br, [])
	if last.is_empty():
		return Rect2()
	var b: Control = last[0]
	return Rect2(b.position, b.size)


func _at(pos: Vector2) -> Dictionary:
	for c in get_children():
		if c is MatchBox and c.position == pos:
			return c.m
	return {}


## The connectors: dim where nobody went on yet, gold along the winners' paths, the player's
## own path in the bright highlight (drawn last, over the others).
func _draw() -> void:
	var order := _lines.duplicate()
	order.sort_custom(func(a, b): return _rank(a[2]) < _rank(b[2]))
	for l in order:
		var a: Vector2 = l[0]
		var b: Vector2 = l[1]
		var mx := (a.x + b.x) / 2.0
		var r := _rank(l[2])
		var col: Color = [Color(0.55, 0.47, 0.32, 0.55), Color(0.9, 0.74, 0.36, 0.95), Palette.SELECTED][r]
		draw_polyline(PackedVector2Array([a, Vector2(mx, a.y), Vector2(mx, b.y), b]), col, [2.0, 3.5, 5.0][r], true)


## 0 = no winner yet, 1 = a winner went on, 2 = the player went on.
func _rank(m: Dictionary) -> int:
	var w := winner(m)
	return 0 if w == "" else (2 if w == me and me != "" else 1)


## Round robin: a row per entrant, a column per opponent (by seed number), the result of each
## pairing from the row's side (both of a double round robin), then points and place.
func _build_cross() -> void:
	var list: Array = t.get("entrants", []).filter(func(e): return e is Dictionary) if t.get("entrants") is Array else []
	list.sort_custom(func(a, b): return TournamentBracket.n(a.get("seed")) < TournamentBracket.n(b.get("seed")))
	var n := list.size()
	var pair := {}  # "a|b" -> [match]
	for m in matches_of(t):
		var p := players(m)
		for k in [p[0] + "|" + p[1], p[1] + "|" + p[0]]:
			if not pair.has(k):
				pair[k] = []
			pair[k].append(m)
	var back := PanelContainer.new()
	back.add_theme_stylebox_override("panel", Palette.frame(Color(0.08, 0.055, 0.035, 0.9), 12))
	add_child(back)
	var grid := GridContainer.new()
	grid.name = "Cross"
	grid.columns = n + 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	back.add_child(grid)
	grid.add_child(_cell_label("", 230))
	for j in n:
		grid.add_child(_cell_label(str(j + 1), 76, true))
	grid.add_child(_cell_label(tr("Points"), 84, true))
	grid.add_child(_cell_label(tr("Place"), 64, true))
	for i in n:
		var e: Dictionary = list[i]
		var who := str(e.get("name", ""))
		var head := _cell_label("%d. %s" % [i + 1, who], 230)
		if who == me:
			head.add_theme_color_override("font_color", Palette.SELECTED)
		grid.add_child(head)
		for j in n:
			var other := str(list[j].get("name", ""))
			var cell := VBoxContainer.new()
			cell.custom_minimum_size = Vector2(76, 52)
			cell.add_theme_constant_override("separation", 2)
			if i == j:
				var dark := ColorRect.new()
				dark.color = Color(0, 0, 0, 0.45)
				dark.custom_minimum_size = Vector2(76, 52)
				cell.add_child(dark)
			for m in pair.get(who + "|" + other, []) if i != j else []:
				cell.add_child(_cell_button(m, who))
			grid.add_child(cell)
		grid.add_child(_cell_label(_num(e.get("points")), 84, true))
		var pl := CenterContainer.new()
		pl.add_child(medal(place_of(e)))
		grid.add_child(pl)
	custom_minimum_size = back.get_combined_minimum_size() + Vector2(8, 8)


func _cell_label(text: String, w: float, center := false) -> Label:
	var l := Palette.label(text, 18, Palette.TEXT)
	l.custom_minimum_size = Vector2(w, 44)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## One result in the cross table, from who's side: 2:1 (green won, red lost), "live" while played.
func _cell_button(m: Dictionary, who: String) -> Button:
	var b := Button.new()
	var s := score(m)
	var mine: bool = players(m)[0] == who
	var a: int = s[0] if mine else s[1]
	var c: int = s[1] if mine else s[0]
	b.text = tr("live") if is_live(m) else ("%d:%d" % [a, c] if is_done(m) else "–")
	b.custom_minimum_size = Vector2(76, 48)
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	if is_done(m):
		var w := winner(m)
		b.add_theme_color_override("font_color", WIN if w == who else (LOSS if w != "" else Palette.TEXT))
	elif is_live(m):
		b.add_theme_color_override("font_color", Palette.SELECTED)
	b.pressed.connect(func(): match_pressed.emit(m))
	var k := key(m.get("id"))
	if not drawn.has(k):
		b.name = "Match_" + k
		drawn[k] = b
	return b


static func _num(v: Variant) -> String:
	if v == null:
		return "0"
	var f := float(v)
	return str(int(f)) if f == floorf(f) else "%.1f" % f


## The standings: place, name, points, games won and lost.
func _standings_table(at: Vector2, width: float) -> float:
	_label(tr("Standings"), at, 22)
	var y := at.y + HEAD
	for e in standings(t):
		var row := _standing_row(e, width)
		row.position = Vector2(at.x, y)
		add_child(row)
		y += 50
	return y


func _standing_row(e: Dictionary, width: float) -> Control:
	var row := HBoxContainer.new()
	row.name = "Standing_" + str(e.get("name", "")).validate_node_name()
	row.size = Vector2(width, 46)
	row.add_theme_constant_override("separation", 8)
	row.add_child(medal(place_of(e)))
	var who := str(e.get("name", ""))
	row.add_child(avatar_node(who))
	var n := Palette.label(who, 19, Palette.SELECTED if who == me else (Palette.MUTED if e.get("eliminated", false) == true else Palette.TEXT))
	n.custom_minimum_size = Vector2(width - 244, 40)
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(n)
	var pts := Palette.label(_num(e.get("points")), 19, Palette.ATTACK)
	pts.custom_minimum_size = Vector2(50, 40)
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(pts)
	var wl := Palette.label("%d–%d" % [TournamentBracket.n(e.get("wins")), TournamentBracket.n(e.get("losses"))], 17, Palette.MUTED)
	wl.custom_minimum_size = Vector2(70, 40)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(wl)
	return row


## Swiss: the standings at the left, each round's pairings as a column (a bye has no opponent).
func _build_swiss() -> void:
	var bottom := _standings_table(Vector2(8, 0), 380)
	var by := {}
	for m in matches_of(t):
		var r := int(m.get("round", 1))
		if not by.has(r):
			by[r] = []
		by[r].append(m)
	var keys: Array = by.keys()
	keys.sort()
	var x := 420.0
	for r in keys:
		_label(tr("Round %d") % int(r), Vector2(x, 0))
		var list: Array = by[r]
		list.sort_custom(func(a, b): return int(a.get("slot", 0)) < int(b.get("slot", 0)))
		for i in list.size():
			_box(list[i], Vector2(x, HEAD + i * (BOX.y + GAP.y)))
		bottom = maxf(bottom, HEAD + list.size() * (BOX.y + GAP.y))
		x += BOX.x + 28
	custom_minimum_size = Vector2(x + 8, bottom + 16)


## Scheveningen: the two teams (their points) side by side, then the grid of results (a row per
## player of the first team, a column per player of the second).
func _build_teams() -> void:
	var teams := {}
	for e in standings(t):
		var k := str(e.get("team", "0"))
		if not teams.has(k):
			teams[k] = []
		teams[k].append(e)
	var keys: Array = teams.keys()
	keys.sort()
	while keys.size() < 2:
		keys.append("_%d" % keys.size())
		teams[keys[-1]] = []
	var total := [0.0, 0.0]
	for i in 2:
		for e in teams[keys[i]]:
			total[i] += float(e.get("points", 0) if e.get("points") != null else 0)
	var head := _label(tr("Team %d") % 1 + "   " + _num(total[0]) + " : " + _num(total[1]) + "   " + tr("Team %d") % 2, Vector2(8, 0), 26)
	head.name = "TeamScore"
	var y := 0.0
	for i in 2:
		var x := 8.0 + i * 430.0
		var tl := _label(tr("Team %d") % (i + 1), Vector2(x, HEAD + 4), 22, Palette.TEXT)
		tl.name = "Team%d" % (i + 1)
		var ty := HEAD * 2 + 4
		for e in teams[keys[i]]:
			var row := _standing_row(e, 400)
			row.position = Vector2(x, ty)
			add_child(row)
			ty += 50
		y = maxf(y, ty)
	var by_pair := {}
	for m in matches_of(t):
		var p := players(m)
		by_pair[p[0] + "|" + p[1]] = m
		by_pair[p[1] + "|" + p[0]] = m
	var back := PanelContainer.new()
	back.position = Vector2(8, y + 24)
	back.add_theme_stylebox_override("panel", Palette.frame(Color(0.08, 0.055, 0.035, 0.9), 12))
	add_child(back)
	var grid := GridContainer.new()
	grid.name = "TeamGrid"
	grid.columns = teams[keys[1]].size() + 1
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	back.add_child(grid)
	grid.add_child(_cell_label("", 230))
	for e in teams[keys[1]]:
		grid.add_child(_cell_label(str(e.get("name", "")), 120, true))
	for a in teams[keys[0]]:
		var who := str(a.get("name", ""))
		grid.add_child(_cell_label(who, 230))
		for b in teams[keys[1]]:
			var m = by_pair.get(who + "|" + str(b.get("name", "")))
			if m is Dictionary:
				var c := _cell_button(m, who)
				c.custom_minimum_size.x = 120
				grid.add_child(c)
			else:
				grid.add_child(_cell_label("", 120))
	custom_minimum_size = Vector2(maxf(880, back.get_combined_minimum_size().x + 16), y + 40 + back.get_combined_minimum_size().y)


## A match in the tree or the swiss rounds: both names with their scores (the winner bright, the
## loser dim), the player's own match framed in gold, a running one marked "live".
class MatchBox:
	extends Button
	var m := {}
	var me := ""

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = TournamentBracket.BOX

	func _draw() -> void:
		var p := TournamentBracket.players(m)
		var s := TournamentBracket.score(m)
		var w := TournamentBracket.winner(m)
		var live := TournamentBracket.is_live(m)
		var mine := me != "" and me in p
		var border := Palette.SELECTED if mine else (TournamentBracket.WIN if live else Color("6b5320"))
		draw_style_box(Palette.box(Color(0.08, 0.06, 0.04, 0.95) if not is_hovered() else Color(0.14, 0.1, 0.06, 0.95), 8, border, 3 if mine or live else 2), Rect2(Vector2.ZERO, size))
		draw_line(Vector2(8, size.y / 2.0), Vector2(size.x - 8, size.y / 2.0), Color(1, 1, 1, 0.12), 1.0)
		var bye: bool = p[0] != "" and p[1] == "" and TournamentBracket.is_done(m)
		for i in 2:
			var nm: String = p[i]
			var col := Palette.TEXT
			if nm == "":
				nm = TournamentBracket._tr("bye") if bye and i == 1 else "—"
				col = Palette.MUTED
			elif w != "":
				col = Palette.ATTACK if w == p[i] else Color(0.62, 0.58, 0.52)
			var base := 26.0 + i * 33.0
			if p[i] != "":
				TournamentBracket.avatar(self, Vector2(22, base - 6), 10, p[i])
			DeckTiles.text(self, Vector2(40, base), nm, 18, col, size.x - 86)
			if p[i] != "" and (TournamentBracket.is_done(m) or live):
				var sc := str(s[i])
				var f := get_theme_font("font", "Label")
				DeckTiles.text(self, Vector2(size.x - 14 - f.get_string_size(sc, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x, base), sc, 20, col)
		if live:  # a green tag on the top rim
			var tag := TournamentBracket._tr("live")
			var tw := get_theme_font("font", "Label").get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 22
			TournamentsView.pill(self, Vector2(size.x - tw - 12, -13), tag, TournamentBracket.WIN, 13, true)


## A place: the number on a gold, silver or bronze disc (top three), else plain.
class Medal:
	extends Control
	var place := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var c := size / 2.0
		var f := get_theme_font("font", "Label")
		var text := str(place) if place > 0 else ""
		if place in [1, 2, 3]:
			var col: Color = TournamentBracket.MEDALS[place - 1]
			draw_circle(c, 17, col.darkened(0.45))
			draw_circle(c, 14, col)
			draw_arc(c, 14, 0, TAU, 32, col.lightened(0.4), 2.0, true)
			var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			draw_string(f, c + Vector2(-w / 2.0, 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("2a1a08"))
		elif text != "":
			var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
			draw_string(f, c + Vector2(-w / 2.0, 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.MUTED)


class Avatar:
	extends Control
	var who := ""

	func _draw() -> void:
		TournamentBracket.avatar(self, size / 2.0, minf(size.x, size.y) / 2.0 - 3, who)
