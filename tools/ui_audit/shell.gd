extends RefCounted
## The client's own screens: the language picker, the main menu (Play, parallax at its edges), the
## changelog, the settings (outside and inside a game), the game library with every pack (its details, the
## delete question, the adding box, an adding error), the pack tools, the game's menu, a toast.
## Run it with every pack: tools/ui_audit.py shell --packs <build/packs/*.cardpack but loot>,<loot custom>.


func run(a) -> void:
	var m: Node = await a.open()
	m.show_language_picker()
	await a.settle()
	await a.shot("language_picker", "The first run: the language picker")
	m.show_menu()
	await a.settle(1.2)
	await a.shot("main_menu", "The main menu")
	var menu: MainMenu = m.screen
	menu.set_process(false)
	for corner in [Vector2(1, 1), Vector2(-1, -1)]:  # the parallax at its far corners
		menu.place(corner)
		await a.wait(0.2)
		await a.shot("main_menu_parallax_%s" % ("dr" if corner.x > 0 else "ul"), "The main menu, the parallax at its far corner")
	menu.set_process(true)
	menu.show_play()
	await a.settle(1.0)
	await a.shot("main_menu_play", "The main menu's Play submenu: Direct / Server")
	(menu.find_child("Version", true, false) as Button).pressed.emit()
	await a.settle(0.8)
	await a.shot("changelog", "The changelog (the version button)")
	var text := menu.find_child("Text", true, false) as RichTextLabel
	if text:
		text.scroll_to_line(text.get_line_count() / 2)
		await a.wait(0.3)
		await a.shot("changelog_middle", "The changelog scrolled to its middle")
	m.show_settings()
	await a.settle()
	await a.shot("settings", "The settings (outside a game)")
	var lang_pick := m.screen.find_child("Language", true, false) as OptionButton
	if lang_pick:
		lang_pick.show_popup()
		await a.wait(0.4)
		await a.shot("settings_language_list", "The settings: the language list open")
		lang_pick.get_popup().hide()
	var back_pick := m.screen.find_child("CardBack", true, false) as OptionButton
	if back_pick:
		back_pick.show_popup()
		await a.wait(0.4)
		await a.shot("settings_card_backs", "The settings: the card back list open")
		back_pick.get_popup().hide()

	# the library: every pack
	var g: GamesView = m.show_library()
	await a.settle()
	await a.shot("library", "The game library with every pack (the active one selected)")
	var scroll := _scroll(g)
	if scroll:
		scroll.scroll_vertical = 100000
		await a.wait(0.4)
		await a.shot("library_bottom", "The game library scrolled to its end")
	for id in ["classic-2014", "naxx-2014", "neon", "og-2016", "msg-2016", "icc-2017"]:
		for p: Pack in Packs.all():
			if p.id() == id:
				g.select(p)
				await a.settle(0.4)
				await a.shot("library_" + id.replace("-", "_"), "The game library, the pack selected: " + p.title())
				break
	var exp: Pack = null
	for p: Pack in Packs.all():
		if p.id() == "og-2016":
			exp = p
	if exp:
		g.select(exp)
		DeckStore.write(DeckStore.file(exp.id()), [{"name": "Old Gods test deck", "hero": "HERO_01", "cards": []}])
		g._confirm_delete(exp)
		await a.settle(0.4)
		await a.shot("library_delete", "The question before a pack is deleted")
		g._close()
	var bar := g._progress(tr_("Adding a game"), "loot-custom-art-with-a-rather-long-file-name.cardpack")
	g._progress_set(bar, TranslationServer.translate("Reading the file… %s of %s") % ["88.1 MB", "168.1 MB"], 0.3)
	await a.wait(0.4)
	await a.shot("library_adding", "The box while a pack file is added")
	g._close()
	await g.import_bytes(PackedByteArray([1, 2, 3, 4]), "broken-game-file.cardpack")
	await a.settle(0.4)
	await a.shot("library_add_error", "The library after a broken file was added: its error line")

	var t: PackTools = m.show_pack_tools()
	await a.settle()
	await a.shot("pack_tools", "The pack tools, nothing chosen")
	var src := ProjectSettings.globalize_path("res://build/packs/loe.cardpack")
	if FileAccess.file_exists(src):
		t.games = 0
		t.open_bytes(FileAccess.get_file_as_bytes(src), src.get_file(), src)
		await a.settle(0.6)
		await a.shot("pack_tools_checked", "The pack tools after a pack file was checked")
	t.open_bytes(PackedByteArray([80, 75, 3, 4, 0, 0]), "broken.zip", "")
	await a.settle(0.4)
	await a.shot("pack_tools_errors", "The pack tools with a broken file: its errors")

	m.enter_game(a.main_pack)
	await a.settle(1.2)
	await a.shot("game_menu", "The game's menu (Direct), Kobolds & Catacombs")
	for p: Pack in Packs.all():
		if p.id() in ["classic-2014", "neon", "naxx-2014"]:
			m.enter_game(p)
			await a.settle(1.0)
			await a.shot("game_menu_" + p.id().replace("-", "_"), "The game's menu: " + p.title())
	m.enter_game(a.main_pack)
	await a.settle(0.6)
	m.show_settings()
	await a.settle()
	await a.shot("game_settings", "The settings inside a game (with the debug tools button)")
	m.show_game_menu()
	await a.settle(0.5)
	m.social.toast(TranslationServer.translate("The server has no replay of this game") + " — " +
		TranslationServer.translate("Could not read the file") + " (a-very-long-file-name-of-a-replay-2017-12-07.json)", Callable(), true)
	await a.wait(0.5)
	await a.shot("toast", "A toast over the game's menu (a long one)")


func tr_(s: String) -> String:
	return TranslationServer.translate(s)


func _scroll(n: Node) -> ScrollContainer:
	return n.find_children("*", "ScrollContainer", true, false).front() if not n.find_children("*", "ScrollContainer", true, false).is_empty() else null
