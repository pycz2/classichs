extends TestCase
## Multi-class cards (cards.md `classes`: Mean Streets of Gadgetzan's tri-class cards) in the collection and on the card
## face, and the card text's "{0}", "{1}" filled with a game's `text_args` (a Jade card's next Golem, a potion's effects).
## The active pack is Classic: the cards here are put into CardDb for the test and taken out after it.

const JADE := "TEST_JADE"
const POTION := "TEST_POTION"
const DAMAGE := "TEST_DAMAGE"


func _add_cards() -> void:
	CardDb.has(JADE)  # loaded
	CardDb._cards[JADE] = {"id": JADE, "type": "MINION", "cardClass": "NEUTRAL", "classes": ["DRUID", "ROGUE", "SHAMAN"],
		"set": "VANILLA", "collectible": true, "cost": 4, "attack": 2, "health": 3, "name": {"enUS": "Jade Thing"},
		"text": {"enUS": "<b>Battlecry:</b> Summon a{1} {0} <b>Jade Golem</b>.",
			"deDE": "<b>Kampfschrei:</b> Ruft einen <b>Jadegolem</b> ({0}) herbei.",
			"ruRU": "<b>Боевой клич:</b> призывает <b>нефритового голема</b> {0}."}}
	CardDb._cards[POTION] = {"id": POTION, "type": "SPELL", "cardClass": "NEUTRAL", "set": "VANILLA", "cost": 1,
		"name": {"enUS": "Potion"}, "text": {"enUS": "{0}\n{1}"}}
	CardDb._cards[DAMAGE] = {"id": DAMAGE, "type": "SPELL", "cardClass": "NEUTRAL", "set": "VANILLA", "cost": 1,
		"name": {"enUS": "Fire"}, "text": {"enUS": "Deal $3 damage."}}


func _remove_cards() -> void:
	for id in [JADE, POTION, DAMAGE]:
		CardDb._cards.erase(id)


func test_placeholders_filled_or_left_out() -> void:
	_add_cards()
	eq(CardText.text(JADE, "en"), "Battlecry: Summon a Jade Golem.", "no game: left out")
	eq(CardText.text(JADE, "en", 0, ["4/4", ""]), "Battlecry: Summon a 4/4 Jade Golem.", "the next Golem")
	eq(CardText.text(JADE, "en", 0, ["8/8", "n"]), "Battlecry: Summon an 8/8 Jade Golem.", "an 8/8")
	eq(CardText.text(JADE, "de"), "Kampfschrei: Ruft einen Jadegolem herbei.", "German: no empty brackets")
	eq(CardText.text(JADE, "de", 0, ["3/3", ""]), "Kampfschrei: Ruft einen Jadegolem (3/3) herbei.", "German")
	eq(CardText.text(JADE, "ru"), "Боевой клич: призывает нефритового голема.", "Russian: no space before the stop")
	eq(CardText.text(POTION, "en", 0, [DAMAGE, ""]), "Deal 3 damage.", "a card id stands for its text")
	check(CardText.rich(POTION, "en", 0, [DAMAGE, JADE]).contains("[b]Jade Golem[/b]"), "both effects")
	_remove_cards()


func test_collection_shows_a_multi_class_card_under_each_class() -> void:
	_add_cards()
	var c := CollectionView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(c)
	for cls in ["DRUID", "ROGUE", "SHAMAN"]:
		c.set_tab(cls)
		check(c.filtered().has(JADE), "under " + cls)
	for cls in ["NEUTRAL", "MAGE"]:
		c.set_tab(cls)
		check(not c.filtered().has(JADE), "not under " + cls)
	c.free()
	_remove_cards()


func test_card_face_and_tips_of_a_multi_class_card() -> void:
	_add_cards()
	var cv := CardView.make(JADE, 1.5)
	cv.text_args = ["5/5", ""]
	(Engine.get_main_loop() as SceneTree).root.add_child(cv)
	cv.queue_redraw()
	await (Engine.get_main_loop() as SceneTree).process_frame
	var tips := KeywordTips.make(JADE)
	var box := tips.get_node_or_null("Classes")
	check(box != null, "the classes under the big card")
	if box:
		eq(box.get_child(0).get_child_count(), 3, "three classes")
	tips.free()
	cv.free()
	_remove_cards()
