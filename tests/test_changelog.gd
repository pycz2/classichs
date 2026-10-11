extends TestCase


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_markdown_to_bbcode() -> void:
	var b := ChangelogView.to_bbcode("# Title\n## [0.1.0] - 2026\n- **bold** and `code`, [link](http://x)\ntext [b]")
	check(b.contains("[font_size=30][b]Title[/b][/font_size]"), "h1: " + b)
	check(b.contains("[font_size=24][b][lb]0.1.0] - 2026[/b][/font_size]"), "h2 with escaped bracket: " + b)
	check(b.contains("• [b]bold[/b] and [code]code[/code], link"), "list, bold, code, link: " + b)
	check(b.contains("text [lb]b]"), "raw brackets escaped: " + b)


func test_menu_version_opens_changelog() -> void:
	var m := MainMenu.new()
	root().add_child(m)
	var v := m.find_child("Version", true, false) as Button
	eq(v.text, "v" + str(ProjectSettings.get_setting("application/config/version")), "version label")
	v.pressed.emit()
	var c := m.find_child("ChangelogView", true, false) as ChangelogView
	check(c != null, "changelog opened")
	var text := (c.find_child("Text", true, false) as RichTextLabel).text
	check(text.contains("0.5.0") and text.contains("0.1.0"), "whole history shown")
	(c.find_child("Close", true, false) as Button).pressed.emit()
	check(c.is_queued_for_deletion(), "closed")
	m.free()


func test_changelog_is_in_the_web_build() -> void:
	check(FileAccess.get_file_as_string("res://export_presets.cfg").contains("CHANGELOG.md"), "export include_filter")


func test_changelog_opens_in_the_game_language() -> void:
	for pair in [["ru", "res://CHANGELOG.md"], ["en", "res://data/changelog/en.md"], ["pl", "res://data/changelog/pl.md"]]:
		Locale.set_language(pair[0])
		eq(ChangelogView.path_for_language(), pair[1], pair[0])
	Locale.set_language("en")
	var re := RegEx.create_from_string("(?m)^## .*$")
	var versions := re.search_all(FileAccess.get_file_as_string("res://CHANGELOG.md")).map(func(m): return m.get_string())
	for code in Locale.LANGS:
		if code != "ru":
			var other := re.search_all(FileAccess.get_file_as_string("res://data/changelog/%s.md" % code)).map(func(m): return m.get_string())
			eq(other, versions, code + ": every version translated")
	check(FileAccess.get_file_as_string("res://export_presets.cfg").contains("data/changelog/*.md"), "translations in the web build")
