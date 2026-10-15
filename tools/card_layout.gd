extends SceneTree
## Lists the card faces whose layout has a problem (CardLayout.problems).
## Usage: godot --headless --path . --script res://tools/card_layout.gd


func _process(_d: float) -> bool:
	var n := 0
	for id in CardDb.all_ids():
		for lang in CardLayout.LANGS:
			var pr := CardLayout.problems(id, lang)
			if not pr.is_empty():
				n += 1
				print("%s %s %s" % [id, lang, pr])
	print("%d card faces with problems" % n)
	quit()
	return true
