class_name DebugTable
extends Control
## Build any position (JSON scenario + card search) and play it against the bot or hot-seat.

signal start(game: Game, bots: Array)
signal back

const ZONES := [["Hand", "hand"], ["Board", "board"], ["Deck", "deck"]]

var editor := TextEdit.new()
var search := LineEdit.new()
var results := ItemList.new()
var error := Label.new()
var mode := OptionButton.new()
var _ids: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Palette.TABLE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var title := Palette.label(tr("Debug Table"), 30, Palette.ATTACK)
	title.position = Vector2(20, 14)
	add_child(title)
	editor.position = Vector2(20, 64)
	editor.size = Vector2(700, 560)
	editor.name = "Editor"
	add_child(editor)
	error = Palette.label("", 16, Palette.TARGET)
	error.name = "Error"
	error.position = Vector2(20, 632)
	error.size = Vector2(700, 60)
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(error)
	search.position = Vector2(740, 64)
	search.size = Vector2(520, 36)
	search.placeholder_text = tr("Search a card by name")
	search.text_changed.connect(_on_search)
	add_child(search)
	results.position = Vector2(740, 106)
	results.size = Vector2(520, 330)
	add_child(results)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.position = Vector2(740, 446)
	for p in 2:
		for z in ZONES:
			var b := Button.new()
			b.text = tr("P%d %s") % [p + 1, tr(z[0])]
			b.custom_minimum_size = Vector2(170, 34)
			var player: int = p
			var zone: String = z[1]
			b.pressed.connect(func(): add_card(player, zone))
			grid.add_child(b)
	add_child(grid)
	mode.position = Vector2(740, 540)
	mode.size = Vector2(520, 36)
	mode.add_item(tr("Play against the bot (you are player 1)"))
	mode.add_item(tr("Hot-seat: control both players"))
	add_child(mode)
	var row := HBoxContainer.new()
	row.position = Vector2(740, 600)
	row.add_theme_constant_override("separation", 12)
	for spec in [[tr("Start"), "Start", start_game], [tr("Example"), "Example", load_example], [tr("Back"), "Back", func(): back.emit()]]:
		var b := Palette.button(spec[0], spec[1])
		b.custom_minimum_size = Vector2(160, 48)
		b.pressed.connect(spec[2])
		row.add_child(b)
	add_child(row)
	load_example()
	_on_search("")


func load_example() -> void:
	editor.text = FileAccess.get_file_as_string("res://data/debug_example.json")
	error.text = ""


func _parse() -> Variant:
	var j := JSON.new()
	if j.parse(editor.text) != OK or not j.data is Dictionary:
		error.text = tr("Invalid JSON")
		if j.get_error_line() > 0:
			error.text += " (%s %d: %s)" % [tr("line"), j.get_error_line(), j.get_error_message()]
		return null
	return j.data


func _on_search(text: String) -> void:
	results.clear()
	_ids.clear()
	var q := text.strip_edges().to_lower()
	var found: Array = []
	for id in CardDb.all_ids():
		var c := CardDb.card(id)
		if c.type in ["ENCHANTMENT", "HERO", "HERO_POWER"]:
			continue
		var n := CardText.name(id)
		if q == "" and not c.get("collectible", false):
			continue
		if q == "" or n.to_lower().contains(q) or id.to_lower().contains(q):
			found.append([int(c.get("cost", 0)), n, id])
	found.sort()
	for f in found.slice(0, 300):
		results.add_item("%d · %s  [%s]" % f)
		_ids.append(f[2])


## Adds the selected card to a player's zone in the JSON scenario.
func add_card(p: int, zone: String, id := "") -> void:
	if id == "":
		var sel := results.get_selected_items()
		if sel.is_empty():
			error.text = tr("Select a card first")
			return
		id = _ids[sel[0]]
	var sc = _parse()
	if sc == null:
		return
	if not sc.get("players") is Array or sc.players.size() != 2:
		sc["players"] = [{"hero": "HERO_08"}, {"hero": "HERO_01"}]
	var list: Array = sc.players[p].get(zone, [])
	list.append(id)
	sc.players[p][zone] = list
	editor.text = JSON.stringify(sc, "  ")
	error.text = ""


func start_game() -> void:
	var sc = _parse()
	if sc == null:
		return
	var r := Scenario.build(sc)
	if r.error != "":
		error.text = r.error
		return
	error.text = ""
	start.emit(r.game, [false, true] if mode.selected == 0 else [false, false])
