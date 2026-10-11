extends TestCase


func test_speed_setting_scales_durations() -> void:
	var was := Anim.instant
	Anim.instant = false
	Settings.data.anim_speed = 2
	eq(Anim.d(1.0), 0.5, "2x faster")
	Settings.data.anim_speed = 4
	eq(Anim.d(1.0), 0.25, "4x faster")
	Anim.instant = true
	eq(Anim.d(1.0), 0.0, "instant in tests")
	Anim.instant = was
	Settings.data.anim_speed = 1


func test_speed_setting_is_clamped_and_saved() -> void:
	Settings.path = "user://test_anim_settings.json"
	var f := FileAccess.open(Settings.path, FileAccess.WRITE)
	f.store_string('{"anim_speed": 9}')
	f.close()
	Settings.load_settings()
	eq(Settings.data.anim_speed, 4, "clamped to 4x")
	Settings.data.anim_speed = 3
	Settings.save()
	Settings.load_settings()
	eq(Settings.data.anim_speed, 3, "saved")
	DirAccess.remove_absolute(Settings.path)


func test_settings_screen_has_speed_slider() -> void:
	var s := SettingsView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(s)
	var sl := s.find_child("AnimSpeed", true, false) as HSlider
	check(sl != null and sl.min_value == 1 and sl.max_value == 4, "slider 1x..4x")
	s.free()
