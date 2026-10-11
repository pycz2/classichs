extends TestCase
## Card names and texts fit inside the card in every language.

const LOCALES := ["enUS", "ruRU", "deDE", "frFR", "esES", "ptBR", "itIT", "plPL"]


func test_every_text_fits_its_box_in_every_language() -> void:
	var body := Fonts.ui(800)  # measured in bold: the widest
	var bad := []
	for id in CardDb.all_ids():
		for loc in LOCALES:
			var plain := CardText.plain_rich(CardText.rich(id, loc))
			if plain != "":
				var fs := CardView.fit_text(body, plain, CardView.TEXT_BOX.size, CardView.TEXT_MAX)
				if fs < 0:
					bad.append("%s %s" % [id, loc])
			var name := CardText.name(id, loc)
			if CardView.fit_name(body, name, CardView.NAME_BOX.size.x, CardView.NAME_MAX) < 0:
				bad.append("name %s %s" % [id, loc])
	eq(bad.slice(0, 10), [], "%d texts that do not fit" % bad.size())


func test_keywords_become_bold() -> void:
	var r := CardText.rich("VAN_CS2_150", "ruRU")  # Stormpike Commando
	check(r.begins_with("[b]Боевой клич:[/b]"), r)
	check(not r.contains("  "), "spaces collapsed: " + r)
	eq(CardText.plain_rich("[b]A[/b] [lb]b"), "A [b", "plain text for measuring")
