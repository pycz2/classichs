extends TestCase


func test_board_gap_moves_neighbours_apart() -> void:
	var before := [TableLayout.board_x(0, 2), TableLayout.board_x(1, 2)]
	var gap := [TableLayout.board_x(0, 2, 1), TableLayout.board_x(1, 2, 1)]
	check(gap[0] < before[0], "left minion moves left")
	check(gap[1] > before[1], "right minion moves right")
	eq(gap[1] - gap[0], 2 * TableLayout.SLOT, "one slot of space between them")
	eq(TableLayout.board_index(0.0, 2), 0, "far left")
	eq(TableLayout.board_index(1280.0, 2), 2, "far right")
	eq(TableLayout.board_index(640.0, 2), 1, "between")


func test_hand_fan_and_hover() -> void:
	var fan := TableLayout.hand(5, true)
	check(fan[0].rot < 0 and fan[4].rot > 0, "fanned")
	check(fan[0].pos.x < fan[4].pos.x, "left to right")
	var lifted := TableLayout.hand(5, true, 2)
	check(lifted[2].pos.y < fan[2].pos.y - 100, "hovered card rises")
	check(lifted[2].scale > fan[2].scale, "and grows")
	eq(lifted[2].rot, 0.0, "and straightens")
	check(lifted[1].pos.x < fan[1].pos.x and lifted[3].pos.x > fan[3].pos.x, "neighbours make room")
	for c in TableLayout.hand(10, true):
		check(c.pos.x >= -20 and c.pos.x <= 1280, "10 cards fit")
