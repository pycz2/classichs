extends TestCase
## Pack UI themes (ui/theme.json, docs/packs/format.md "UI theme"): Classic keeps its look,
## Neonfall restyles the interface, and a switch of the active pack restyles in place.


static func _pack(id: String) -> Pack:
	for p: Pack in Packs.all():
		if p.id() == id:
			return p
	return null


func test_classic_has_its_wooden_look() -> void:
	var t := Fonts.theme()
	check(Palette.CLASSIC, "Classic has no theme.json")
	eq(Palette.TEXT, Color("f4ead5"), "cream text")
	eq(Palette.ui(Color("c9a74a")), Color("c9a74a"), "gold stays gold")
	check(t.get_stylebox("normal", "Button") is StyleBoxTexture, "wooden planks")
	eq(Fonts.end_turn(false) is StyleBoxTexture, true, "a wooden End Turn")


func test_neonfall_restyles_and_switching_back_restores() -> void:
	var t := Fonts.theme()
	var frame := Palette.frame()
	var heading := Palette.label("Games", 34, Palette.ATTACK)
	var bare := Palette.label("Games", 34, Palette.ATTACK)  # on a layer outside the root's theme
	(Engine.get_main_loop() as SceneTree).root.add_child(bare)
	var owner := Control.new()
	owner.theme = t
	owner.add_child(heading)
	(Engine.get_main_loop() as SceneTree).root.add_child(owner)
	Packs.set_active(_pack("neon"))
	check(not Palette.CLASSIC, "Neonfall has a theme")
	eq(Palette.ATTACK, Color("3ee8ff"), "the accent is neon cyan")
	var b := t.get_stylebox("normal", "Button")
	check(b is StyleBoxFlat and (b as StyleBoxFlat).shadow_size > 0, "flat glowing buttons")
	eq(frame.border_color, Color("22d3eecc"), "an open frame restyled in place")
	eq(heading.get_theme_color("font_color"), Color("3ee8ff"), "a heading follows the theme")
	eq(bare.get_theme_color("font_color"), Color("3ee8ff"), "also outside the root's theme")
	var f := Fonts.ui()
	for ch in "AżłЖё":
		check(f.has_char(ch.unicode_at(0)), "the body font has " + ch)
	check(Fonts.title().has_char("Я".unicode_at(0)), "the title font has Cyrillic")
	Packs.set_active(_pack(Packs.CLASSIC))
	check(Palette.CLASSIC and t.get_stylebox("normal", "Button") is StyleBoxTexture, "Classic again")
	eq(frame.border_color, Color("a8863a"), "the frame is gold again")
	eq(heading.get_theme_color("font_color"), Color("f2c200"), "the heading is gold again")
	owner.free()
	bare.free()
