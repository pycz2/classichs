extends TestCase
## ClassicHS Studio's Cards tab (studio/studio_cards.gd): a minion made and changed through the tab's own
## functions lands in the project (card, texts, keywords, effect, picture, framing, sounds) and the preview
## draws it from the project's preview pack.

const ROOT := "user://test_studio_cards"


static func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_wipe(dir + "/" + d)
	DirAccess.remove_absolute(dir)


func _tab() -> StudioCards:
	StudioProject.root = ROOT
	_wipe(ROOT)
	var c := StudioCards.new()
	c.project = StudioProject.create("cards-test", "Cards Test")
	_root().add_child(c)
	return c


func test_a_minion_made_in_the_tab() -> void:
	var t := _tab()
	var p := t.project
	var times := [0]
	t.changed.connect(func(): times[0] += 1)
	var id := t.new_card("MINION")
	eq(t.cid, id, "the new card is chosen")
	check(t._list.item_count >= 4, "it is in the list with the template's cards")
	t.set_field("cost", 3)
	t.set_field("attack", 2)
	t.set_field("health", 5)
	t.set_field("race", "BEAST")
	var taunt := p.mechanic_name("GUARD")
	t.set_keyword(taunt, true)
	t.set_texts("Bear Guard", "<b>Taunt</b>")
	t.set_lang("ru")
	t.set_texts("Медведь-страж", "<b>Провокация</b>")
	var c := p.card(id)
	eq([c.cost, c.attack, c.health, c.race], [3, 2, 5, "BEAST"], "the numbers and the tribe")
	eq(c.keywords, [taunt], "Taunt")
	eq(p.text(id, "en"), {"name": "Bear Guard", "text": "<b>Taunt</b>"}, "the English texts")
	eq(p.text(id, "ru").name, "Медведь-страж", "the Russian name")
	check(times[0] >= 8, "each change says so")
	t.refresh_preview()
	check(t.card_view != null and t.card_view.pack == t.preview and t.card_view.card_id == id, "the preview draws the card from the preview pack")
	eq(t.card_view.locale, "ru", "in the chosen language")
	CardDb.begin(t.preview)
	eq(int(CardDb.card(id).get("cost", -1)), 3, "the preview pack has its cost")
	eq(CardText.name(id, CardText.hs_locale("ru")), "Медведь-страж", "and its name")
	CardDb.end()
	check(t.minion_view != null and t.minion_view.s.has("TAUNT"), "the minion on the board, with its Taunt")
	eq(t.minion_view.s.atk(), 2, "and its Attack")
	t.set_type("WEAPON")
	check(not c.has("health") and not c.has("race") and c.durability == 2, "a weapon: Durability, no Health or tribe")
	t.set_type("CHAMPION")
	eq([c.health, c.power, c.has("attack")], [30, p.rules.default_power, false], "a hero: its Health and Hero Power")
	t.refresh_preview()
	check(t.minion_view == null and t.card_view != null, "a hero shows only its card")
	t.set_type("MINION")
	eq(t.rename("bear_guard"), "", "renamed")
	eq(t.cid, "bear_guard", "the tab follows")
	check(t.rename("coin") != "", "a taken id is refused")
	p.add_set("wild")
	t.refresh()
	eq(t.cid, "bear_guard", "shown again after another tab's change: the same card")
	check(range(t._control("set").item_count).any(func(i): return t._control("set").get_item_metadata(i) == "wild"), "with the new set to choose")
	t.free()


func test_effect_blocks_and_raw_lua() -> void:
	var t := _tab()
	var p := t.project
	var id := t.new_card("MINION")
	t.add_block()
	t.set_block(0, "target", "chosen_enemy_minion")
	t.set_block(0, "n", 2, false)
	eq(p.effects[id].blocks, [{"when": "play", "target": "chosen_enemy_minion", "do": "damage", "n": 2}], "the block")
	check(p.card(id).keywords.has(p.mechanic_name("ON_PLAY")), "Battlecry comes with it")
	eq(t._problems.text, "", "no problems")
	t.set_block(0, "do", "summon")
	check(p.effects[id].blocks[0].has("card") and not p.effects[id].blocks[0].has("m"), "summon needs a card")
	check(t._problems.text != "", "a chosen target can't take a summon: shown")
	t.set_block(0, "target", "my_hero")
	eq(t._problems.text, "", "fine again")
	t.set_block(0, "do", "damage")
	t.set_block(0, "target", "enemy_hero")
	t.english_from_effect()
	eq(p.text(id, "en").text, "<b>Battlecry:</b> Deal 2 damage to the enemy hero.", "the English text from the blocks")
	var taunt := p.mechanic_name("GUARD")
	t.set_keyword(taunt, true)
	t.select(id)  # (the form is filled again: the keyword boxes are new)
	t.set_raw_lua(true)
	check(p.card(id).keywords.has(taunt) and not p.card(id).keywords.has(p.mechanic_name("ON_PLAY")), "raw Lua: Battlecry goes, Taunt stays")
	check(p.effects[id].lua.begins_with("battlecry = function(g, me, t)"), "raw Lua starts from the blocks' Lua")
	t.set_lua("battlecry = function(g, me) g.draw(g.ctrl(me), 1) end,")
	check(StudioEffects.card_lua(id, "MINION", p.effects[id]).contains("g.draw"), "the hand-written Lua is the effect")
	t.set_raw_lua(false)
	eq(p.effects[id].lua, "", "off: the blocks again")
	eq(p.effects[id].blocks.size(), 1, "kept")
	t.remove_block(0)
	check(not p.effects.has(id), "no blocks: no effect")
	t.free()


func test_picture_framing_and_sounds() -> void:
	var t := _tab()
	var p := t.project
	var id := t.new_card("MINION")
	var img := Image.create(64, 48, false, Image.FORMAT_RGB8)
	img.fill(Color.ORANGE)
	eq(t.load_art(img), "", "a picture")
	check(p.art_path(id) != "", "saved into the pack")
	t.set_frame(0.25, -0.1, 1.5)
	eq(p.framing(id), Vector3(0.25, -0.1, 1.5), "framed")
	eq(t._sliders.zoom.value, 1.5, "the sliders follow")
	t._framer.size = Vector2(400, 300)
	t._framer.moved.emit(Vector3(0.3, -0.1, 1.5))
	check(is_equal_approx(p.framing(id).x, 0.3), "dragging moves it")
	t.refresh_preview()
	CardDb.begin(t.preview)
	check(Art.texture(id) != null, "the preview pack has the picture")
	eq(Art._framing.get(id), Vector3(0.3, -0.1, 1.5), "with its framing, as the game reads it")
	CardDb.end()
	eq(t.load_sound("play", PackedByteArray([1, 2, 3]), "ogg"), "", "a sound")
	check(p.sound_path(id, "play").ends_with("_play.ogg"), "saved")
	check(t.load_sound("play", PackedByteArray([1]), "txt") != "", "not a sound file")
	var copy := t.duplicate_card()
	check(p.art_path(copy) != "" and p.sound_path(copy, "play") != "", "a copy has the picture and the sound")
	eq(p.framing(copy), p.framing(id), "and the framing")
	t.select(id)
	t.remove_sound("play")
	eq(p.sound_path(id, "play"), "", "removed")
	eq(p.sound_path(copy, "play").get_extension(), "ogg", "the copy keeps its own")
	t.delete_card()
	check(p.card(id).is_empty() and p.art_path(id) == "", "deleted with its picture")
	t.free()


func test_a_card_of_several_classes() -> void:
	var t := _tab()
	var p := t.project
	p.add_class("MAGE")
	p.add_class("ROGUE")
	var id := t.new_card("MINION")
	t.select(id)
	eq(t._control("classes").get_child_count(), 3, "a box per playable class")
	t.set_class_of_several("KNIGHT", true)
	t.set_class_of_several("MAGE", true)
	eq(p.card(id).get("classes"), ["KNIGHT", "MAGE"], "of two classes")
	eq(p.card(id).get("class"), "NEUTRAL", "its class a neutral one")
	check(p.deck_pool("knight_hero").has(id) and p.deck_pool("mage_hero").has(id), "in both classes' decks")
	check(not p.deck_pool("rogue_hero").has(id), "not in another's")
	eq(p.build().errors(), 0, "the pack checks: " + str(p.build().items.filter(func(it): return it.level == "error")))
	t.set_class_of_several("MAGE", false)
	eq(p.card(id).get("classes"), null, "one class left")
	eq(p.card(id).get("class"), "KNIGHT", "is the card's class")
	t.free()


func test_a_new_secret() -> void:
	var t := _tab()
	var p := t.project
	var id := t.new_secret()
	eq(p.card(id).type, "SPELL", "a spell")
	check(p.card(id).get("keywords", []).has(p.mechanic_name("TRAP")), "with the pack's Secret mechanic")
	eq(t._shown().has(id), true, "listed")
	eq(StudioProject.blocking(p.build(true)), 0, "it compiles: " + str(p.build().items.filter(func(it): return it.level == "error")))
	t.free()


func test_the_english_text_from_blocks_names_the_cards() -> void:
	var t := _tab()
	var p := t.project
	var cub := t.new_card("MINION")
	t.set_texts("Wolf Cub", "")
	var id := t.new_card("MINION")
	p.set_effect(id, {"blocks": [{"when": "deathrattle", "target": "my_hero", "do": "summon", "card": cub, "n": 1}], "lua": ""})
	t.english_from_effect()
	var text := str(p.text(id, "en").get("text", ""))
	check("Wolf Cub" in text and not cub in text, "the summoned card by its name: " + text)
	t.free()
