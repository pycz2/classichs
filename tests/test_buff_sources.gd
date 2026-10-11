extends TestCase


func test_buffs_and_auras_remember_their_source() -> void:
	var g := H.game()
	var yeti := H.board(g, 0, "VAN_CS2_182")
	H.play(g, H.hand(g, 0, "VAN_CS2_092"), yeti)  # Blessing of Kings: +4/+4
	eq(yeti.enchantments.back().get("src"), "VAN_CS2_092", "the spell is the source")
	H.board(g, 0, "VAN_CS2_122")  # Raid Leader: other friendly minions +1 Attack
	g.update_auras()
	eq(yeti.aura.get("src", {}).get("VAN_CS2_122"), [1, 0], "the aura's source and size")
	eq(g.source_card, "", "no source left over after the effects")
