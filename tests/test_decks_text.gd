extends TestCase

const CLASSES := ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"]


func test_basic_decks_are_legal() -> void:
	for cls in CLASSES:
		var d := Decks.basic(cls)
		eq(d.size(), 30, cls + " size")
		for id in d:
			var c := CardDb.card(id)
			check(c.cardClass == cls or c.cardClass == "NEUTRAL", "%s: %s class" % [cls, id])
			check(c.get("collectible", false), "%s: %s collectible" % [cls, id])
			check(d.count(id) <= 2, "%s: %s copies" % [cls, id])


func test_hero_for_class() -> void:
	eq(Decks.hero("MAGE"), "HERO_08", "mage hero")
	eq(Decks.card_class("HERO_01"), "WARRIOR", "warrior class")


func test_card_name_localized() -> void:
	eq(CardText.name("VAN_CS2_029", "ru"), "Огненный шар", "ru")
	eq(CardText.name("VAN_CS2_029", "en"), "Fireball", "en")
	eq(CardText.name("VAN_CS2_029", "xx"), "Fireball", "fallback to English")


func test_card_text_clean() -> void:
	eq(CardText.text("VAN_CS2_029", "en"), "Deal 6 damage.", "dollar removed")
	eq(CardText.text("VAN_CS1_042", "en"), "Taunt", "tags removed")
	eq(CardText.text("VAN_EX1_011", "en"), "Battlecry: Restore 2" + String.chr(0xA0) + "Health.", "hash removed, nbsp kept")
	eq(CardText.text("VAN_CS2_029", "en", 1), "Deal *7* damage.", "spell damage shown")
	check(not CardText.text("VAN_HERO_04bp", "en").contains("{0}"), "placeholders removed")


func test_hs_locale_mapping() -> void:
	eq(CardText.hs_locale("ru_RU"), "ruRU", "ru")
	eq(CardText.hs_locale("zh_TW"), "zhTW", "zh_TW")
	eq(CardText.hs_locale("pt"), "ptBR", "pt")
	eq(CardText.hs_locale("en_US"), "enUS", "en")


func test_plural_forms_follow_their_number() -> void:
	eq(CardText.text("VAN_CS2_012", "frFR"), "Inflige 4 points de dégâts à un adversaire et 1 point de dégâts à tous les autres adversaires.", "Swipe: 1 point")
	check(CardText.rich("VAN_CS2_061", "frFR").contains("Rend 2 points de vie"), CardText.rich("VAN_CS2_061", "frFR"))
	check(CardText.text("VAN_CS2_061", "frFR", 1).contains("*3* points"), "with spell damage: " + CardText.text("VAN_CS2_061", "frFR", 1))
