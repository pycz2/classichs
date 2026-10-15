class_name Missions
extends RefCounted
## The six tutorial missions as the screens show them (boss, intro, lines, reward,
## hints). Their decks and rules live in the engine (rust/engine/src/missions.rs):
## a mission's game is the engine's `new` with `mission`.

const JAINA := "HERO_08"
const FIREBLAST := "VAN_HERO_08bp"

const LIST := [
	{
		"boss": "TU4a_001",
		"intro": "Play minions and use them to attack Hogger. Deal enough damage and you win!",
		"lines": {"start": "Grrr! Hogger smash puny mage!", "hurt": "Rrraaagh! Hogger angry!", "defeat": "Nooo... Hogger... tired..."},
		"reward": "VAN_CS2_023", "reward_line": "Oh yeah!",
		"hints": ["play", "attack", "end_turn"],
	},
	{
		"boss": "TU4b_001",
		"intro": "Expend your Mana each turn to crush this annoying gnome!",
		"lines": {"start": "Millhouse Manastorm is here! Prepare to be amazed!", "hurt": "Hey, that hurt! Wait till you see my big spell!",
			"defeat": "No fair! I was just getting to the good part!"},
		"reward": "VAN_EX1_015", "reward_line": "This is quite impressive.",
		"hints": ["mana", "play", "attack", "raid_leader"],
	},
	{
		"boss": "TU4f_001",
		"intro": "When minions fight each other, they both take damage.",
		"lines": {"start": "Greetings, traveler. Let us learn together.", "hurt": "A wise move. But balance must be kept.",
			"defeat": "Your skill honors the path. Go well."},
		"reward": "VAN_CS2_124", "reward_line": "Hot hot hot!",
		"hints": ["trade", "heal", "battlecry", "attack"],
	},
	{
		"boss": "TU4c_001",
		"intro": "Don't understand a card? Mouse-over it!",
		"lines": {"start": "Mukla want bananas! You no take!", "hurt": "Ooh ooh! Mukla call big brother!", "defeat": "Mukla... share bananas..."},
		"reward": "VAN_CS2_022", "reward_line": "You are on a roll!",
		"hints": ["tooltip", "taunt", "charge", "buff"],
	},
	{
		"boss": "TU4d_001",
		"intro": "Kill his minions or he'll overwhelm you!",
		"lines": {"start": "Fresh game! Let the hunt begin!", "hurt": "You're a tough one to bag!", "defeat": "Well, I'll be... the hunter becomes the hunted."},
		"reward": "VAN_CS2_213", "reward_line": "That was incredible.",
		"hints": ["hero_power", "attack"],
	},
	{
		"boss": "TU4e_001",
		"intro": "This fight is totally not fair. Blame the terrible game designers.",
		"lines": {"start": "You are not prepared!", "hurt": "I will not be stopped!", "defeat": "Impossible... beaten by a novice?"},
		"reward": "VAN_EX1_277", "reward_line": "Magnificent!",
		"hints": ["weapon", "hero_power"],
	},
]


static func count() -> int:
	return LIST.size()


static func get_mission(n: int) -> Dictionary:
	return LIST[n - 1]
