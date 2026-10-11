extends TestCase
## Every card's name and text sit well on the card in every language: each card
## face has its lines written out (data/card_layout/<lang>.json), they say what
## the card says, and nothing sticks out of its box or runs into the gems.


func test_every_card_face_is_laid_out_without_problems() -> void:
	var bad := []
	for id in CardDb.all_ids():
		for lang in CardLayout.LANGS:
			var pr := CardLayout.problems(id, lang)
			if not pr.is_empty():
				bad.append("%s %s %s" % [id, lang, pr])
	eq(bad.slice(0, 10), [], "%d card faces with problems" % bad.size())


func test_problems_are_found() -> void:
	var was := CardLayout.of("VAN_CS2_029", "en").duplicate(true)  # Fireball
	CardLayout.store("VAN_CS2_029", "en", {"text": 11, "name": 12, "lines": ["Deal 6 damage. Deal 6 damage. Deal 6 damage."]})
	eq(CardLayout.problems("VAN_CS2_029", "en"), ["text differs", "line too wide"], "a wrong text in one long line")
	CardLayout.store("VAN_CS2_029", "en", {"text": 11, "name": 60, "lines": ["De", "al", "[b]6[/b]", "dam", "age."]})
	eq(CardLayout.problems("VAN_CS2_029", "en"), ["name too long", "text too tall"], "a big name, too many lines")
	CardLayout.store("VAN_CS2_029", "en", was)


func test_keywords_become_bold() -> void:
	var r := CardText.rich("VAN_CS2_150", "ruRU")  # Stormpike Commando
	check(r.begins_with("[b]Боевой клич:[/b]"), r)
	check(not r.contains("  "), "spaces collapsed: " + r)
	var spans := CardLayout.spans("VAN_CS2_150", "ru")
	eq(spans[0], ["Боевой клич:", true], "the keyword span is bold")


func test_card_lab_shows_every_language_and_changes_a_layout() -> void:
	var lab := CardLab.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(lab)
	lab.find("VAN_CS2_029")  # Fireball
	eq(lab.ids[lab.index], "VAN_CS2_029", "found by id")
	for lang in CardLayout.LANGS:
		check(lab.find_child("Lang_" + lang, true, false) != null, "a panel for " + lang)
	var was := CardLayout.of("VAN_CS2_029", "ru").duplicate(true)
	lab.change("VAN_CS2_029", "ru", "text", -1)
	eq(int(CardLayout.of("VAN_CS2_029", "ru").text), int(was.text) - 1, "smaller text")
	lab.set_lines("VAN_CS2_029", "ru", "Наносит 6 ед.\nурона.")
	eq(CardLayout.of("VAN_CS2_029", "ru").lines, ["Наносит 6 ед.", "урона."], "lines as typed")
	CardLayout.store("VAN_CS2_029", "ru", was)
	lab.free()
