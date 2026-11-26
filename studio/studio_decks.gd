class_name StudioDecks
extends Control
## The Studio's Decks tab: the game's ready decks (decks/*.json, docs/packs/format.md §8). A list, a new deck
## (a name and a hero), the chosen deck's cards: those its hero may hold (StudioProject.deck_pool) with
## counts to add and take away; why the deck is not legal yet (deck_problem) and its size against the rules'.

signal changed

var project: StudioProject
var studio: Studio
## The chosen deck's file name ("" = none).
var chosen := ""


func _ready() -> void:
	refresh()


func refresh() -> void:
	Studio.clear(self)
	if not project.decks.has(chosen):
		chosen = "" if project.decks.is_empty() else project.decks.keys()[0]
	var cols := HBoxContainer.new()
	cols.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cols.add_theme_constant_override("separation", 20)
	add_child(cols)
	var left := Control.new()
	left.custom_minimum_size = Vector2(400, 0)
	cols.add_child(left)
	var l := Studio.page(left)
	l.add_child(Studio.heading(tr("Decks")))
	var names := project.decks.keys()
	names.sort()
	for d in names:
		var b := Studio.button(str(project.decks[d].get("name", d)), "Deck_" + d, 340)
		b.toggle_mode = true
		b.button_pressed = d == chosen
		b.pressed.connect(func():
			chosen = d
			refresh())
		l.add_child(b)
	l.add_child(Studio.heading(tr("New deck")))
	var name_f := Studio.field("", "NewDeckName", func(_t): pass, 340)
	name_f.placeholder_text = tr("Name")
	l.add_child(name_f)
	var hero := OptionButton.new()
	hero.name = "NewDeckHero"
	var heroes := _heroes()
	for h in heroes:
		hero.add_item("%s (%s)" % [project.text(h, "en").get("name", h), project.card(h).get("class", "")])
	l.add_child(hero)
	var make := Studio.button(tr("Create"), "CreateDeck")
	make.disabled = heroes.is_empty()
	make.pressed.connect(func():
		if hero.selected >= 0:
			new_deck(name_f.text.strip_edges(), heroes[hero.selected]))
	l.add_child(make)
	var right := Control.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	if chosen != "":
		_deck(Studio.page(right))


## The heroes of the classes (their CHAMPION cards).
func _heroes() -> Array:
	return project.rules.classes.filter(func(c): return c.has("champion") and not project.card(str(c.champion)).is_empty()) \
		.map(func(c): return str(c.champion))


## A new empty deck of a hero, chosen; its file name.
func new_deck(name: String, hero: String) -> String:
	if name == "":
		name = tr("New deck")
	var base := name.to_lower().replace(" ", "_")
	base = RegEx.create_from_string("[^a-z0-9_-]").sub(base, "", true)
	if base == "":
		base = "deck"
	var file := base
	var n := 1
	while project.decks.has(file):
		n += 1
		file = "%s_%d" % [base, n]
	project.decks[file] = {"name": name, "champion": hero, "cards": []}
	chosen = file
	changed.emit()
	refresh()
	return file


## Puts a card into the chosen deck (n = 1) or takes one out (n = -1).
func add(cid: String, n := 1) -> void:
	var cards: Array = project.decks[chosen].get_or_add("cards", [])
	if n > 0:
		cards.append(cid)
	else:
		cards.erase(cid)
	changed.emit()
	refresh()


func _deck(v: VBoxContainer) -> void:
	var d: Dictionary = project.decks[chosen]
	var cards: Array = d.get_or_add("cards", [])
	var size := int(project.rules.get("limits", {}).get("deck_size", 30))
	var del := Studio.button(tr("Delete the deck"), "DeleteDeck", 200)
	del.pressed.connect(func(): studio.confirm(tr("Delete the deck \"%s\"?") % d.get("name", chosen), func():
		project.decks.erase(chosen)
		changed.emit()
		refresh()))
	v.add_child(Studio.row([tr("Name"), Studio.field(str(d.get("name", "")), "DeckName", func(t):
		d.name = t
		changed.emit()), Palette.label(tr("Hero: %s") % project.text(str(d.get("champion", "")), "en").get("name", d.get("champion", "")), 16), del]))
	var count := Palette.label(tr("%d of %d cards") % [cards.size(), size], 18)
	count.name = "Count"
	v.add_child(count)
	var why := project.deck_problem(chosen)
	var problem := Palette.label(tr(why) if why != "" else tr("The deck is legal"), 16, Palette.DANGER if why != "" else Palette.OK)
	problem.name = "DeckProblem"
	problem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(problem)
	for cid: String in project.deck_pool(str(d.get("champion", ""))):
		var c := project.card(cid)
		var name_l := Palette.label("%d  %s" % [int(c.get("cost", 0)), project.text(cid, "en").get("name", cid)], 16)
		name_l.custom_minimum_size = Vector2(320, 0)
		name_l.clip_text = true
		var less := Studio.button("−", "Less", 44)
		less.disabled = not cards.has(cid)
		less.pressed.connect(add.bind(cid, -1))
		var more := Studio.button("+", "More", 44)
		more.pressed.connect(add.bind(cid, 1))
		var r := Studio.row([name_l, less, Palette.label(str(cards.count(cid)), 16), more])
		r.name = "Card_" + cid
		v.add_child(r)
