class_name IconView
extends Control
## Draws one of Icons' symbols to fill its rect.

var kind := "NEUTRAL":
	set(v):
		kind = v
		queue_redraw()


func _draw() -> void:
	Icons.paint(self, kind, Rect2(Vector2.ZERO, size))
