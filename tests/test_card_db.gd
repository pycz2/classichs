extends TestCase


func test_fireball_fields() -> void:
	var c := CardDb.card("VAN_CS2_029")
	eq(c.name.enUS, "Fireball", "name")
	eq(c.name.ruRU, "Огненный шар", "ru name")
	eq(c.cost, 4, "cost is int")
	eq(c.type, "SPELL", "type")
	eq(c.cardClass, "MAGE", "class")


func test_minion_stats_are_ints() -> void:
	var c := CardDb.card("VAN_CS1_042")  # Goldshire Footman
	eq(c.attack, 1, "attack")
	eq(c.health, 2, "health")
	check(c.mechanics.has("TAUNT"), "taunt")


func test_collectible_count() -> void:
	eq(CardDb.collectible().size(), 382, "collectible VANILLA cards")


func test_dbf_lookup() -> void:
	var c := CardDb.card("VAN_CS1_042")
	eq(CardDb.by_dbf(c.dbfId), "VAN_CS1_042", "dbf lookup")
	eq(CardDb.by_dbf(-5), "", "unknown dbf")


func test_extra_ids_present() -> void:
	for id in ["HERO_01", "HERO_09", "GAME_005", "EX1_323h", "hexfrog", "Mekka4t", "TU4a_001"]:
		check(CardDb.has(id), "missing " + id)


func test_junk_excluded() -> void:
	check(not CardDb.has("VAN_DFX_001"), "FX dummy must be excluded")
	check(not CardDb.has("Story_09_Shadowbolt"), "puzzle card must be excluded")
