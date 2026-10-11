extends TestCase


func test_basic_totems_have_their_stats() -> void:
	for id in ["VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009"]:
		var g := H.game()
		var t := H.board(g, 0, id)
		var c := CardDb.card(id)
		eq([t.atk(), t.health()], [int(c.attack), int(c.health)], id)
	eq([int(CardDb.card("VAN_CS2_050").health), int(CardDb.card("VAN_CS2_051").health)], [1, 2], "Searing 1/1, Stoneclaw 0/2")
