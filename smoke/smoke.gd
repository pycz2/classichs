extends Node
## Plays one random game in the browser to prove the engine runs on the Web platform.


func _ready() -> void:
	var res := Sim.play_random(1, 200)
	var g: Game = res.game
	var label := Label.new()
	label.text = "engine ok: %d actions, hash %s" % [res.actions.size(), g.state_hash().left(12)]
	add_child(label)
	print(label.text)


func _exit_tree() -> void:
	Cards.unload()
