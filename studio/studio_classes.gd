class_name StudioClasses
extends Control
## The Studio's Classes tab: each class with its name in a chosen language, its colour (manifest colors.classes),
## its hero (name, health) and Hero Power (name); add and remove a class (its hero and Hero Power come and go
## with it). The neutral class is shown, not removable. A hero's picture and the power's effect are edited on
## the Cards tab ("Edit on the Cards tab").

signal changed

var project: StudioProject
var studio: Studio
var lang := "en"


func _ready() -> void:
	refresh()


func refresh() -> void:
	Studio.clear(self)
	var v := Studio.page(self)
	v.add_child(Studio.row([Studio.heading(tr("Classes")), Studio.languages(lang, func(l):
		lang = l
		refresh())], 24))
	for c: Dictionary in project.rules.classes:
		v.add_child(_class(c))
	var why := Palette.label("", 15, Palette.DANGER)
	why.name = "AddProblem"
	var nid := Studio.field("", "NewClass", func(_t): why.text = "", 200)
	nid.placeholder_text = "MAGE"
	var add := Studio.button(tr("Add a class"), "AddClass", 180)
	add.pressed.connect(func():
		why.text = tr(add_class(nid.text.strip_edges())))
	v.add_child(Studio.row([tr("Id"), nid, add, why]))


## Adds a class; "" or why not (English).
func add_class(cls: String) -> String:
	var why := project.add_class(cls)
	if why == "":
		changed.emit()
		refresh()
	return why


func remove_class(cls: String) -> void:
	project.remove_class(cls)
	changed.emit()
	refresh()


func _class(c: Dictionary) -> Control:
	var cls := str(c.id)
	var box := VBoxContainer.new()
	box.name = "Class_" + cls
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Palette.frame())
	panel.add_child(box)
	var colors: Dictionary = project.manifest.get_or_add("colors", {}).get_or_add("classes", {})
	var top := Studio.row([Palette.label(cls, 18, Palette.ATTACK),
		Studio.field(project.term("classes", cls, lang), "Name", func(t):
			project.set_term("classes", cls, lang, t.strip_edges())
			changed.emit(), 220),
		Studio.color_button(str(colors.get(cls, "868e96")), "Color", func(hex):
			colors[cls] = hex
			changed.emit())], 12)
	box.add_child(top)
	if c.get("neutral", false):
		top.add_child(Palette.label(tr("Neutral cards: every class may use them"), 15, Palette.MUTED))
		return panel
	var del := Studio.button(tr("Remove"), "Remove", 120)
	del.pressed.connect(func(): studio.confirm(tr("Remove the class %s, its hero and its Hero Power?") % cls, remove_class.bind(cls)))
	top.add_child(del)
	var hero := project.card(str(c.get("champion", "")))
	if not hero.is_empty():
		box.add_child(Studio.row([tr("Hero"), _name_field(hero.id, "HeroName"),
			tr("Health"), Studio.number(int(hero.get("health", 30)), 1, 1000, "Health", func(x):
				hero.health = x
				changed.emit()),
			_edit_button(hero.id, "EditHero")]))
		var power := project.card(str(hero.get("power", "")))
		if not power.is_empty():
			box.add_child(Studio.row([tr("Hero Power"), _name_field(power.id, "PowerName"),
				tr("Cost"), Studio.number(int(power.get("cost", 2)), 0, 10, "PowerCost", func(x):
					power.cost = x
					changed.emit()),
				_edit_button(power.id, "EditPower")]))
	return panel


## A card's name in the chosen language (its text stays).
func _name_field(cid: String, id: String) -> LineEdit:
	return Studio.field(str(project.text(cid, lang).get("name", "")), id, func(t):
		project.set_text(cid, lang, t.strip_edges(), str(project.text(cid, lang).get("text", "")))
		changed.emit(), 220)


func _edit_button(cid: String, id: String) -> Button:
	var b := Studio.button(tr("Edit on the Cards tab"), id, 220)
	b.pressed.connect(func(): studio.edit_card(cid))
	return b
