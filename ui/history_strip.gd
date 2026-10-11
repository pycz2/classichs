class_name HistoryStrip
extends Control
## The history bar on the left, like the original: a tile with the picture of
## every card played, attack or hero power, newest on top; blue edge for your
## moves, red for the opponent's. Hovering a tile shows the card; a click opens
## the full text history.

signal open_history
signal show_card(card_id: String, on: bool)

const TILE := 46.0
const MAX := 11

var _items: Array = []  # [card_id, mine]


func _ready() -> void:
	name = "HistoryStrip"
	position = Vector2(8, 60)
	size = Vector2(TILE + 8, (TILE + 6) * MAX)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Rebuilds the tiles from the game history, seen by viewer.
func update_from(g: GameState, viewer: int) -> void:
	var items := []
	for entry in g.history:
		var a: Dictionary = entry.action
		var id: int = {"play": a.get("entity", -1), "attack": a.get("attacker", -1), "hero_power": a.get("entity", -1)}.get(a.get("type", ""), -1)
		if a.get("type") == "hero_power" and id < 0:
			id = g.players[int(a.get("player", 0))].hero_power.id
		var e := g.ent(id)
		if e:
			var secret: bool = a.get("type") == "play" and e.card().get("mechanics", []).has("SECRET") and int(a.get("player", -1)) != viewer and e.zone == "SECRET"
			items.append(["" if secret else e.card_id, int(a.get("player", -1)) == viewer])
	items.reverse()
	items = items.slice(0, MAX)
	if items != _items:
		_items = items
		queue_redraw()


func card_at(y: float) -> String:
	var i := int(y / (TILE + 6))
	return _items[i][0] if i >= 0 and i < _items.size() else ""


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var c := card_at(ev.position.y)
		show_card.emit(c, c != "")
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		open_history.emit()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		show_card.emit("", false)


func _draw() -> void:
	for i in _items.size():
		var r := Rect2(Vector2(4, i * (TILE + 6)), Vector2(TILE, TILE))
		var edge := Color("4dabf7") if _items[i][1] else Color("ff6b6b")
		draw_style_box(Palette.box(Color("1b140f"), 8, edge, 3), r.grow(2))
		if _items[i][0] == "":
			draw_style_box(Palette.box(Color("7048e8"), 6), r)
		else:
			Art.paint_in(self, r, _items[i][0], "rect")
