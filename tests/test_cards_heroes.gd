extends TestCase


func test_heroes_have_30_health_jaraxxus_15() -> void:
	for i in range(1, 10):
		eq(CardDb.card("HERO_0%d" % i).health, 30, "hero %d" % i)
	eq(CardDb.card("EX1_323h").health, 15, "Jaraxxus")


func test_coin_gives_one_mana_capped() -> void:
	var g := H.game()
	g.players[0].mana = 0
	check(H.play(g, H.hand(g, 0, "GAME_005")).ok, "coin")
	eq(g.players[0].mana, 1, "+1")
	H.play(g, H.hand(g, 0, "GAME_005"))
	g.players[0].mana = 10
	H.play(g, H.hand(g, 0, "GAME_005"))
	eq(g.players[0].mana, 10, "capped at 10")


func test_coin_enables_combo() -> void:
	var g := H.game()
	H.play(g, H.hand(g, 0, "GAME_005"))
	eq(g.players[0].cards_played_this_turn, 1, "coin counts as a played card")


func test_armor_up() -> void:
	var g := H.scene({"hero": "HERO_01"})
	check(H.power(g).ok, "used")
	eq(int(g.players[0].hero.tags.ARMOR), 2, "2 armor")
	eq(g.players[0].mana, 8, "costs 2")


func test_totemic_call_summons_missing_basic_totem() -> void:
	var g := H.scene({"hero": "HERO_02", "board": ["VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052"]})
	check(H.power(g).ok, "used")
	eq(g.players[0].board.back().card_id, "VAN_NEW1_009", "only Healing Totem was missing")


func test_totemic_call_blocked_when_all_totems_present() -> void:
	var g := H.scene({"hero": "HERO_02", "board": ["VAN_CS2_050", "VAN_CS2_051", "VAN_CS2_052", "VAN_NEW1_009"]})
	check(not H.power(g).ok, "nothing to summon")


func test_dagger_mastery() -> void:
	var g := H.scene({"hero": "HERO_03"})
	H.power(g)
	var w := g.players[0].weapon
	eq([w.card_id, w.atk(), int(w.tags.DURABILITY)], ["VAN_CS2_082", 1, 2], "1/2 dagger")


func test_reinforce_and_full_board() -> void:
	var g := H.scene({"hero": "HERO_04"})
	H.power(g)
	eq(g.players[0].board.back().card_id, "VAN_CS2_101t", "recruit")
	var full := H.scene({"hero": "HERO_04", "board": ["VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231",
		"VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231", "VAN_CS2_231"]})
	check(not H.power(full).ok, "board full")


func test_steady_shot_hits_enemy_hero_without_target() -> void:
	var g := H.scene({"hero": "HERO_05"})
	check(H.power(g).ok, "no target needed")
	eq(g.players[1].hero.health(), 28, "2 damage")


func test_shapeshift() -> void:
	var g := H.scene({"hero": "HERO_06"})
	H.power(g)
	var hero := g.players[0].hero
	eq([g.hero_atk(hero), int(hero.tags.ARMOR)], [1, 1], "+1 atk, +1 armor")
	check(H.attack(g, hero, g.players[1].hero).ok, "hero attacks")
	H.end_turn(g)
	eq(hero.atk(), 0, "attack gone after turn")
	eq(int(hero.tags.ARMOR), 1, "armor stays")


func test_life_tap() -> void:
	var g := H.scene({"hero": "HERO_07", "deck": ["VAN_CS2_231"]})
	H.power(g)
	eq(g.players[0].hero.health(), 28, "2 damage")
	eq(g.players[0].hand.size(), 1, "drew a card")


func test_fireblast_any_target() -> void:
	var g := H.game()
	var w := H.board(g, 1, H.WISP)
	check(H.power(g, w).ok, "minion target")
	eq(w.zone, "GRAVEYARD", "1 damage")


func test_fireblast_ignores_spell_damage() -> void:
	var g := H.scene({"hero": "HERO_08", "board": ["VAN_CS2_142"]})  # Kobold Geomancer
	H.power(g, g.players[1].hero)
	eq(g.players[1].hero.health(), 29, "still 1 damage")


func test_lesser_heal() -> void:
	var g := H.scene({"hero": "HERO_09", "damage": 5})
	check(H.power(g, g.players[0].hero).ok, "heal own hero")
	eq(g.players[0].hero.health(), 27, "+2")


func test_inferno() -> void:
	var g := H.scene({"hero": "HERO_07", "hero_power": "VAN_EX1_tk33"})
	H.power(g)
	eq(g.players[0].board.back().card_id, "VAN_EX1_tk34", "6/6 Infernal")


func test_mind_spike_and_shatter() -> void:
	var g := H.scene({"hero": "HERO_09", "hero_power": "EX1_625t"})
	H.power(g, g.players[1].hero)
	eq(g.players[1].hero.health(), 28, "2 damage")
	var g2 := H.scene({"hero": "HERO_09", "hero_power": "EX1_625t2"})
	H.power(g2, g2.players[1].hero)
	eq(g2.players[1].hero.health(), 27, "3 damage")


func test_healing_totem() -> void:
	var g := H.scene({"hero": "HERO_02", "damage": 5,
		"board": ["VAN_NEW1_009", {"card": "VAN_CS2_182", "damage": 3}]}, {"hero": "HERO_01", "board": [{"card": "VAN_CS2_182", "damage": 3}]})
	H.end_turn(g)
	eq(g.players[0].board[1].health(), 3, "friendly minion +1")
	eq(g.hero(0).health(), 25, "hero not healed")
	eq(g.players[1].board[0].health(), 2, "enemy not healed")
