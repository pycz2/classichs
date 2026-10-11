extends TestCase
## The effects lab (Debug Table): any card on the table with any buffs, debuffs
## and states switched on and off, in any language.


func _lab() -> EffectsLab:
	var lab := EffectsLab.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(lab)
	lab.show_card("VAN_CS2_182")  # Chillwind Yeti 4/5
	return lab


func test_effects_switch_on_and_off_on_the_minion() -> void:
	var lab := _lab()
	lab.set_effect("DIVINE_SHIELD", true)
	lab.set_effect("buff", true)
	lab.set_effect("damaged", true)
	var s := (lab.find_child("Minion", true, false) as MinionView).s
	check(s.has("DIVINE_SHIELD"), "shield on")
	eq([s.atk(), s.max_health(), s.health()], [5, 6, 4], "+1/+1 buff, 2 damage")
	lab.set_effect("silenced", true)
	s = (lab.find_child("Minion", true, false) as MinionView).s
	check(s.silenced and not s.has("DIVINE_SHIELD"), "silence takes the shield and the buff")
	eq(s.atk(), 4, "buff gone")
	lab.set_effect("silenced", false)
	s = (lab.find_child("Minion", true, false) as MinionView).s
	check(not s.silenced and s.has("DIVINE_SHIELD") and s.atk() == 5, "silence off: all back")
	lab.free()


func test_every_effect_can_be_shown() -> void:
	var lab := _lab()
	for key in EffectsLab.EFFECTS.map(func(x): return x[0]):
		lab.set_effect(key, true)
	var tips := lab.find_child("KeywordTips", true, false)
	check(tips != null and tips.find_child("Changes", true, false) != null, "the changes box lists them")
	for key in EffectsLab.EFFECTS.map(func(x): return x[0]):
		lab.set_effect(key, false)
	lab.free()


func test_language_is_the_labs_and_comes_back() -> void:
	var lab := _lab()
	lab.set_effect("TAUNT", true)
	lab.set_language("ru")
	var text := ""
	for l in lab.find_child("KeywordTips", true, false).find_children("*", "Label", true, false):
		text += l.text
	check(text.contains("Провокация"), "tips in Russian: " + text)
	lab.back.emit()
	eq(TranslationServer.get_locale(), "en", "the game's language again")
	lab.free()
