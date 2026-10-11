class_name TableLayout
extends RefCounted
## Where things stand on the 1280x720 table: the hand fan, board slots (with a
## gap where a dragged minion would go), heroes, powers and deck piles.

const ENEMY_HERO := Vector2(575, 40)
const OWN_HERO := Vector2(575, 466)
const ENEMY_BOARD_Y := 188.0
const OWN_BOARD_Y := 336.0
const SLOT := 104.0
const MINION := Vector2(96, 116)
const CARD := Vector2(120, 170)
const OWN_DECK := Vector2(1168, 410)
const ENEMY_DECK := Vector2(1168, 150)
const HAND_Y := 600.0
const HOVER_LIFT := 150.0
const HOVER_SCALE := 1.45


## x of board slot i of n minions; gap >= 0 opens a space at that index.
static func board_x(i: int, n: int, gap := -1) -> float:
	var count := n + (1 if gap >= 0 else 0)
	var slot := i + (1 if gap >= 0 and i >= gap else 0)
	return 640.0 - count * SLOT / 2.0 + slot * SLOT + (SLOT - MINION.x) / 2.0


## The insertion index for a minion dropped at x on a board of n minions.
static func board_index(x: float, n: int) -> int:
	for i in n:
		if x < board_x(i, n) + MINION.x / 2.0:
			return i
	return n


## Hand cards as a fan: [{pos, rot, scale, z}] for n cards; hover lifts one.
static func hand(n: int, own: bool, hover := -1) -> Array:
	var out := []
	var k := 0.9 if own else 0.5
	var step := minf(96.0 * k / 0.9, (560.0 if own else 380.0) / maxf(1, n))
	var spread := minf(4.0, 24.0 / maxf(1, n))
	for i in n:
		var c := i - (n - 1) / 2.0
		var x := 640.0 + c * step - CARD.x * k / 2.0
		if hover >= 0 and i != hover:
			x += signf(i - hover) * 40.0  # neighbours make room
		var y := (HAND_Y + c * c * 2.5) if own else (-60.0 - c * c * 1.5)
		var rot := deg_to_rad(c * spread) * (1 if own else -1)
		var s := k
		if own and i == hover:
			y = HAND_Y - HOVER_LIFT
			rot = 0.0
			s = HOVER_SCALE * k
			x = clampf(640.0 + c * step - CARD.x * s / 2.0, 0.0, 1280.0 - CARD.x * s)
		out.append({"pos": Vector2(x, y), "rot": rot, "scale": s, "z": 20 if i == hover else i})
	return out
