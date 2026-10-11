class_name Missions
extends RefCounted
## The six tutorial missions (order, boss health and rules from the original
## tutorial; decks rebuilt from the TU4 cards and Basic Mage cards).
## Decks are listed top card first.

const JAINA := "HERO_08"
const FIREBLAST := "VAN_HERO_08bp"

const LIST := [
	{
		"boss": "TU4a_001", "boss_power": FIREBLAST, "locked": true, "unlosable": true,
		"block_mana": true, "block_attack": true,
		"player_hand": ["VAN_CS2_168"],
		"player_deck": ["VAN_CS2_172", "VAN_CS2_120", "VAN_CS2_118", "VAN_CS2_182", "VAN_CS2_124", "VAN_CS2_200",
			"VAN_CS2_172", "VAN_CS2_168", "VAN_CS2_120", "VAN_CS2_182", "VAN_CS2_124", "VAN_CS2_200", "VAN_CS2_201"],
		"boss_deck": ["TU4a_002", "TU4a_003", "TU4a_002", "TU4a_004", "TU4a_005", "TU4a_003", "TU4a_002",
			"TU4a_005", "TU4a_004", "TU4a_003", "TU4a_002", "TU4a_005"],
		"intro": "Play minions and use them to attack Hogger. Deal enough damage and you win!",
		"lines": {"start": "Grrr! Hogger smash puny mage!", "hurt": "Rrraaagh! Hogger angry!", "defeat": "Nooo... Hogger... tired..."},
		"reward": "VAN_CS2_023", "reward_line": "Oh yeah!",
		"hints": ["play", "attack", "end_turn"],
	},
	{
		"boss": "TU4b_001", "boss_power": FIREBLAST, "locked": true, "unlosable": true,
		"block_mana": true, "block_attack": true,
		"player_hand": ["VAN_CS2_172", "VAN_CS2_168"],
		"player_deck": ["VAN_CS2_120", "VAN_CS2_122", "VAN_CS2_118", "VAN_CS2_182", "VAN_CS2_124", "VAN_CS2_122",
			"VAN_CS2_200", "VAN_CS2_119", "VAN_CS2_201", "VAN_CS2_222", "VAN_CS2_120", "VAN_CS2_182", "VAN_CS2_200"],
		"boss_deck": ["VAN_EX1_277", "VAN_CS2_024", "VAN_CS2_025", "VAN_CS2_024", "VAN_CS2_029", "VAN_EX1_277",
			"VAN_CS2_026", "VAN_CS2_025", "VAN_CS2_029", "VAN_CS2_032", "VAN_EX1_279", "VAN_EX1_279"],
		"intro": "Expend your Mana each turn to crush this annoying gnome!",
		"lines": {"start": "Millhouse Manastorm is here! Prepare to be amazed!", "hurt": "Hey, that hurt! Wait till you see my big spell!",
			"defeat": "No fair! I was just getting to the good part!"},
		"reward": "VAN_EX1_015", "reward_line": "This is quite impressive.",
		"hints": ["mana", "play", "attack", "raid_leader"],
	},
	{
		"boss": "TU4f_001", "boss_power": FIREBLAST, "locked": true, "unlosable": false,
		"block_mana": false, "block_attack": true,
		"player_hand": ["VAN_EX1_011", "VAN_CS2_189"],
		"player_deck": ["VAN_EX1_015", "VAN_CS2_117", "VAN_CS2_172", "VAN_EX1_019", "VAN_DS1_055", "VAN_CS2_120", "VAN_CS2_141",
			"VAN_CS2_182", "VAN_CS2_147", "VAN_CS2_200", "VAN_CS2_150", "VAN_CS2_179", "VAN_CS2_182", "VAN_CS2_201", "VAN_CS2_222"],
		"boss_deck": ["TU4f_002", "TU4f_003", "TU4f_006", "TU4f_002", "TU4f_004", "TU4f_005", "TU4f_003", "TU4f_005",
			"TU4f_004", "TU4f_002", "TU4f_005", "TU4f_003"],
		"intro": "When minions fight each other, they both take damage.",
		"lines": {"start": "Greetings, traveler. Let us learn together.", "hurt": "A wise move. But balance must be kept.",
			"defeat": "Your skill honors the path. Go well."},
		"reward": "VAN_CS2_124", "reward_line": "Hot hot hot!",
		"hints": ["trade", "heal", "battlecry", "attack"],
	},
	{
		"boss": "TU4c_001", "boss_power": FIREBLAST, "locked": true, "unlosable": false,
		"block_mana": false, "block_attack": false,
		"player_hand": ["VAN_CS1_042", "VAN_CS2_171", "VAN_EX1_019"],
		"player_deck": ["VAN_CS2_124", "VAN_CS2_121", "VAN_CS2_022", "VAN_CS2_179", "VAN_CS2_213", "VAN_CS2_182",
			"VAN_CS2_022", "VAN_CS2_200", "VAN_CS2_162", "VAN_CS2_222", "VAN_CS2_179", "VAN_CS2_201", "VAN_CS2_213"],
		"boss_deck": ["TU4c_003", "TU4c_002", "TU4f_007", "TU4c_004", "TU4c_005", "TU4c_006", "TU4c_007", "TU4c_008",
			"TU4c_003", "TU4c_002", "TU4f_007", "TU4c_007"],
		"intro": "Don't understand a card? Mouse-over it!",
		"lines": {"start": "Mukla want bananas! You no take!", "hurt": "Ooh ooh! Mukla call big brother!", "defeat": "Mukla... share bananas..."},
		"reward": "VAN_CS2_022", "reward_line": "You are on a roll!",
		"hints": ["tooltip", "taunt", "charge", "buff"],
	},
	{
		"boss": "TU4d_001", "boss_power": "TU4d_003", "locked": false, "unlosable": false,
		"block_mana": false, "block_attack": false,
		"player_hand": ["VAN_EX1_277", "VAN_CS2_172", "VAN_CS2_027"],
		"player_deck": ["VAN_CS2_024", "VAN_CS2_033", "VAN_CS2_029", "VAN_CS2_120", "VAN_CS2_022", "VAN_CS2_182",
			"VAN_CS2_023", "VAN_CS2_024", "VAN_CS2_029", "VAN_CS2_200", "VAN_CS2_032", "VAN_CS2_033", "VAN_CS2_201"],
		"boss_deck": ["TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002",
			"TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002", "TU4d_002"],
		"intro": "Kill his minions or he'll overwhelm you!",
		"lines": {"start": "Fresh game! Let the hunt begin!", "hurt": "You're a tough one to bag!", "defeat": "Well, I'll be... the hunter becomes the hunted."},
		"reward": "VAN_CS2_213", "reward_line": "That was incredible.",
		"hints": ["hero_power", "attack"],
	},
	{
		"boss": "TU4e_001", "boss_power": "TU4e_002", "locked": false, "unlosable": false,
		"block_mana": false, "block_attack": false,
		"player_hand": ["VAN_CS2_027", "VAN_CS2_024", "VAN_CS2_172"],
		"player_deck": ["VAN_CS2_025", "VAN_CS2_120", "VAN_EX1_277", "VAN_CS2_033", "VAN_CS2_023", "VAN_CS2_182",
			"VAN_CS2_032", "VAN_CS2_029", "VAN_CS2_033", "VAN_CS2_200", "VAN_CS2_022", "VAN_CS2_029", "VAN_CS2_201",
			"VAN_CS2_222", "VAN_CS2_026"],
		"boss_deck": ["TU4e_003", "TU4e_004", "TU4e_003", "TU4e_005", "TU4e_003", "TU4e_007", "TU4e_003", "TU4e_003",
			"TU4e_003", "TU4e_003", "TU4e_003", "TU4e_003"],
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


## The match for mission n via Scenario: scripted hands and deck order, Jaina first, no mulligan.
static func build(n: int) -> Dictionary:
	var m := get_mission(n)
	var pd: Array = m.player_deck.duplicate()
	pd.reverse()  # Scenario: the last card is the top
	var bd: Array = m.boss_deck.duplicate()
	bd.reverse()
	return Scenario.build({"current": 0, "players": [
		{"hero": JAINA, "mana": 1, "max_mana": 1, "hand": m.player_hand, "deck": pd, "hero_power_locked": m.locked},
		{"hero": m.boss, "hero_power": m.boss_power, "hand": m.get("boss_hand", []), "deck": bd, "hero_power_locked": m.locked},
	]})
