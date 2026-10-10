extends TestCase

const KEYWORD_ONLY := ["VAN_CS1_042", "VAN_CS2_168", "VAN_CS2_171", "VAN_CS2_172", "VAN_CS2_173",
	"VAN_CS2_121", "VAN_CS2_142", "VAN_CS2_120", "VAN_EX1_582", "VAN_CS2_125", "VAN_CS2_118",
	"VAN_CS2_127", "VAN_CS2_124", "VAN_CS2_182", "VAN_CS2_119", "VAN_CS2_197", "VAN_CS2_179",
	"VAN_CS2_131", "VAN_CS2_187", "VAN_CS2_155", "VAN_CS2_200", "VAN_CS2_162", "VAN_CS2_213",
	"VAN_CS2_201", "VAN_CS2_186"]


func test_keyword_only_cards() -> void:
	for id in KEYWORD_ONLY:
		var g := H.game()
		var e := H.hand(g, 0, id)
		check(H.play(g, e).ok, id + " playable")
		eq(e.atk(), int(e.card().attack), id + " attack")
		eq(e.max_health(), int(e.card().health), id + " health")
		for m in ["TAUNT", "CHARGE"]:
			eq(e.has(m), e.card().get("mechanics", []).has(m), id + " " + m)


func test_elven_archer() -> void:
	var g := H.game()
	var enemy := H.board(g, 1, H.WISP)
	check(H.play(g, H.hand(g, 0, "VAN_CS2_189"), enemy).ok, "played")
	eq(enemy.zone, "GRAVEYARD", "1 damage kills wisp")


func test_grimscale_oracle_buffs_all_other_murlocs() -> void:
	var g := H.game()
	var mine := H.board(g, 0, "VAN_CS2_168")
	var theirs := H.board(g, 1, "VAN_CS2_168")
	var oracle := H.board(g, 0, "VAN_EX1_508")
	g.resolve()
	eq([mine.atk(), theirs.atk(), oracle.atk()], [3, 3, 1], "other murlocs +1, not itself")


func test_voodoo_doctor_heals() -> void:
	var g := H.scene({"hero": "HERO_08", "damage": 5})
	H.play(g, H.hand(g, 0, "VAN_EX1_011"), g.players[0].hero)
	eq(g.players[0].hero.health(), 27, "+2")


func test_acidic_swamp_ooze() -> void:
	var g := H.scene({"hero": "HERO_08"}, {"hero": "HERO_01", "weapon": "VAN_CS2_106"})
	H.play(g, H.hand(g, 0, "VAN_EX1_066"))
	eq(g.players[1].weapon, null, "weapon destroyed")


func test_murloc_tidehunter_summons_scout_to_the_right() -> void:
	var g := H.game()
	var right := H.board(g, 0, H.WISP)
	var t := H.hand(g, 0, "VAN_EX1_506")
	H.play(g, t, null, 0)
	var ids := g.players[0].board.map(func(m): return m.card_id)
	eq(ids, ["VAN_EX1_506", "VAN_EX1_506a", H.WISP], "scout right of tidehunter")
	eq(g.players[0].board[2], right, "old minion pushed right")


func test_novice_engineer_and_gnomish_inventor_draw() -> void:
	for id in ["VAN_EX1_015", "VAN_CS2_147"]:
		var g := H.scene({"hero": "HERO_08", "deck": [H.WISP]})
		H.play(g, H.hand(g, 0, id))
		eq(g.players[0].hand.size(), 1, id + " drew")


func test_ironforge_rifleman_and_stormpike_commando() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_141"), g.players[1].hero)
	H.play(g, H.hand(g, 0, "VAN_CS2_150"), g.players[1].hero)
	eq(g.players[1].hero.health(), 27, "1 + 2 damage")


func test_raid_leader() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	var enemy := H.board(g, 1, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_CS2_122"))
	eq([w.atk(), enemy.atk()], [2, 1], "only own other minions")


func test_razorfen_hunter() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_CS2_196"))
	eq(g.players[0].board.back().card_id, "VAN_CS2_boar", "boar")


func test_razorfen_hunter_full_board() -> void:
	var g := H.game()
	for i in 6:
		H.board(g, 0, H.WISP)
	check(H.play(g, H.hand(g, 0, "VAN_CS2_196")).ok, "playable as 7th")
	eq(g.players[0].board.size(), 7, "no boar")


func test_shattered_sun_cleric() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	H.play(g, H.hand(g, 0, "VAN_EX1_019"), w)
	eq([w.atk(), w.max_health()], [2, 2], "+1/+1")


func test_shattered_sun_cleric_cannot_target_enemy() -> void:
	var g := H.game()
	var enemy := H.board(g, 1, H.WISP)
	check(not H.play(g, H.hand(g, 0, "VAN_EX1_019"), enemy).ok, "friendly only")


func test_dragonling_mechanic() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_025"))
	eq(g.players[0].board.back().card_id, "EX1_025t", "dragonling")


func test_darkscale_healer() -> void:
	var g := H.scene({"hero": "HERO_08", "damage": 5, "board": [{"card": "VAN_CS2_120", "damage": 2}]},
		{"hero": "HERO_01", "damage": 5})
	H.play(g, H.hand(g, 0, "VAN_DS1_055"))
	eq(g.players[0].hero.health(), 27, "own hero +2")
	eq(g.players[0].board[0].health(), 3, "own minion +2 capped")
	eq(g.players[1].hero.health(), 25, "enemy untouched")


func test_frostwolf_warlord() -> void:
	var g := H.game()
	H.board(g, 0, H.WISP)
	H.board(g, 0, H.WISP)
	H.board(g, 1, H.WISP)
	var w := H.hand(g, 0, "VAN_CS2_226")
	H.play(g, w)
	eq([w.atk(), w.max_health()], [6, 6], "+2/+2 for two friendly minions")


func test_gurubashi_berserker() -> void:
	var g := H.game()
	var b := H.board(g, 0, "VAN_EX1_399")
	g.damage(g.players[1].hero, b, 1)
	g.resolve()
	eq(b.atk(), 5, "+3 attack")
	g.damage(g.players[1].hero, b, 1)
	g.resolve()
	eq(b.atk(), 8, "stacks")


func test_nightblade() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "VAN_EX1_593"))
	eq(g.players[1].hero.health(), 27, "3 to enemy hero")


func test_stormwind_champion() -> void:
	var g := H.game()
	var w := H.board(g, 0, H.WISP)
	var c := H.hand(g, 0, "VAN_CS2_222")
	H.play(g, c)
	eq([w.atk(), w.max_health(), c.atk()], [2, 2, 6], "others +1/+1")
