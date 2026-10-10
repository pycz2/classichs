extends TestCase


func _e(card_id: String) -> Entity:
	return Entity.new(1, card_id, 0)


func test_base_stats_and_keywords() -> void:
	var e := _e("VAN_CS1_042")  # Goldshire Footman 1/2 Taunt
	eq(e.atk(), 1, "atk")
	eq(e.max_health(), 2, "max hp")
	check(e.has("TAUNT"), "taunt")
	check(not e.has("CHARGE"), "no charge")


func test_enchant_order_add_then_set() -> void:
	var e := _e("VAN_CS2_231")  # Wisp 1/1
	e.add_enchant({"atk": 2, "hp": 2})
	e.add_enchant({"set_atk": 1})  # Humility after +2/+2
	eq(e.atk(), 1, "set after add")
	e.add_enchant({"atk": 1})
	eq(e.atk(), 2, "add after set")
	eq(e.max_health(), 3, "hp")


func test_damage_eats_buff_first_on_silence() -> void:
	var e := _e("VAN_CS2_231")
	e.add_enchant({"hp": 2})  # 1/3
	e.damage = 2               # 1/1 left
	e.silence()
	eq(e.max_health(), 1, "max after silence")
	eq(e.health(), 1, "silence never kills")


func test_silence_removes_keywords_and_enchants() -> void:
	var e := _e("VAN_CS1_042")
	e.give_tag("WINDFURY")
	e.add_enchant({"atk": 3})
	e.tags["FROZEN"] = true
	e.silence()
	check(not e.has("TAUNT"), "taunt removed")
	check(not e.has("WINDFURY"), "windfury removed")
	check(not e.has("FROZEN"), "frozen removed")
	eq(e.atk(), 1, "enchant removed")
	check(e.silenced, "silenced flag")


func test_eot_removal() -> void:
	var e := _e("VAN_CS2_231")
	e.add_enchant({"atk": 3, "eot": true})
	e.give_tag("IMMUNE", true)
	e.remove_eot()
	eq(e.atk(), 1, "eot atk gone")
	check(not e.has("IMMUNE"), "eot tag gone")


func test_aura_drop_keeps_minion_alive() -> void:
	var e := _e("VAN_CS2_231")
	e.aura = {"atk": 0, "hp": 1, "tags": {}}  # 1/2
	e.damage = 1
	var old_max := e.max_health()
	var old_hp := e.health()
	e.aura = {"atk": 0, "hp": 0, "tags": {}}
	e.fix_health(old_max, old_hp)
	eq(e.health(), 1, "aura loss never kills")


func test_spellpower_from_card() -> void:
	var e := _e("VAN_CS2_142")  # Kobold Geomancer, Spell Damage +1
	eq(e.spellpower(), 1, "spellpower")
	e.silence()
	eq(e.spellpower(), 0, "silenced spellpower")
