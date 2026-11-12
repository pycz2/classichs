extends SceneTree
## Screenshots of one game pack for the owner's local expansions report (tools/expansions_report.py writes
## the job and runs this in a window, one run at a time): the game's menu, its collection filtered by its set,
## big views of its signature cards, and scripted table scenes (data/card_tests' scene and steps format) with
## the hovered card and the history. Needs a window. Every user file goes to its own user dir
## (REPORT_USER_DIR, as tests/run.gd's TEST_USER_DIR), never the player's.
## Usage: REPORT_USER_DIR=classichs-report/x godot --path . --script res://tools/expansions_shots.gd -- <job.json>
## Job: {pack, art?, sound?, set_key, langs, out, tab?, signature: [ids], scenes: [{name, scene | game, steps,
## wait?, hover?, history?, choose?}], only?: [shot names]}; a shot is <out>/<lang>_<name>.jpg.

const MOUSE_AWAY := Vector2(640, 330)  # the empty middle of the table, over no card
var job: Dictionary
var m: Node
var pack: Pack
var failed := 0


func _init() -> void:
	var own := OS.get_environment("REPORT_USER_DIR")
	if own != "":
		ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
		ProjectSettings.set_setting("application/config/custom_user_dir_name", own)
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_factor = 1.0
	# the player's own mouse never hovers anything in the shots: the window lets it through, the GUI takes no input
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MOUSE_PASSTHROUGH, true)
	root.gui_disable_input = true
	if OS.get_environment("REPORT_USER_DIR") == "":
		print("ERROR: set REPORT_USER_DIR (the run's own user dir)")
		quit(2)
		return
	job = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]))
	_run()


func _run() -> void:
	var r := Packs.install_file(str(job.pack))
	if not r.has("pack"):
		print("ERROR: the pack does not install: ", r)
		quit(1)
		return
	pack = r.pack
	if job.get("check", false):  # headless: play every scene's steps and print the table they end at
		_check()
		return
	DirAccess.make_dir_recursive_absolute(str(job.out))
	for lang in job.langs:
		await _open(lang)
		await _shot("menu")
		await _collection()
		for id in job.get("signature", []):
			await _big(str(id))
		for sc in job.get("scenes", []):
			await _scene(sc)
	if m:
		m.free()
	print("SHOTS DONE: %d failed" % failed)
	quit(1 if failed else 0)


## Plays each scene without a window and prints where it ends (hands, boards, a pending choice, the glowing cards).
func _check() -> void:
	Packs._active = pack
	Packs._changed()
	for id in job.get("signature", []):
		if CardDb.card(str(id)).is_empty() or not CardDb.collectible().has(str(id)):
			print("ERROR: signature %s is no collectible card of the pack" % id)
			failed += 1
	for sc in job.get("scenes", []):
		var r := CardTests.run(sc) if not sc.has("game") else _run_game(sc)
		if r.error != "":
			print("ERROR: scene %s, step %d: %s" % [sc.name, r.step + 1, r.error])
			failed += 1
		if r.match == null:
			continue
		var g: GameView = r.match.game
		print("scene %s: turn %d, current %d%s" % [sc.name, g.turn, g.current,
			", pending " + str(g.pending) if not g.pending.is_empty() else ""])
		for p in g.players:
			var hand: Array = p.hand.map(func(e): return e.card_id + ("*" if e.glow else ""))
			var board: Array = p.board.map(func(e): return "%s %d/%d" % [e.card_id, e.atk(), e.health()])
			print("  p%d hero %s %d hp +%d armor, mana %d/%d; hand %s; board %s" % [p.index, p.hero.card_id,
				p.hero.health(), int(p.hero.tags.get("ARMOR", 0)), p.mana, p.max_mana, hand, board])
		r.match.free()
	print("CHECK DONE: %d failed" % failed)
	quit(1 if failed else 0)


## A scene's game: a built position (scene, which starts in the middle of a game), or a real game of two of the
## pack's ready decks (game: {decks: [key, key], seed?, first?}) whose start runs: Start of Game effects.
func _request(sc: Dictionary) -> Dictionary:
	if not sc.has("game"):
		return {"scenario": sc.scene}
	var decks := []
	for key in sc.game.decks:
		for t in Decks.templates():
			if t.key == key:
				decks.append({"hero": t.deck.hero, "cards": Array(t.deck.cards)})
	return {"decks": decks, "seed": int(sc.game.get("seed", 1)), "first": int(sc.game.get("first", 0))}


## A real game's mulligans: both players keep their hands.
func _keep_hands(mt: Match) -> void:
	for p in 2:
		if mt.game.phase == "MULLIGAN":
			mt.submit({"type": "mulligan", "player": p, "replace": []})


## CardTests.run for a real game (the scene's "game").
func _run_game(sc: Dictionary) -> Dictionary:
	var mt := Match.new()
	mt.bots = [false, false]
	var why := mt.setup(_request(sc), [false, false])
	if why != "":
		mt.free()
		return {"match": null, "error": "game: " + why, "step": -1}
	_keep_hands(mt)
	var steps: Array = sc.get("steps", [])
	for i in steps.size():
		var a := CardTests.action(mt, steps[i])
		var res: Dictionary = a if a.has("error") else mt.submit(a)
		if a.has("error") or not res.ok:
			return {"match": mt, "error": res.error, "step": i}
	return {"match": mt, "error": "", "step": steps.size()}


func _want(name: String) -> bool:
	return not job.has("only") or job.only.has(name)


## A shot of the window now: <out>/<lang>_<name>.jpg.
func _shot(name: String) -> void:
	if not _want(name):
		return
	var file := "%s/%s_%s.jpg" % [job.out, Settings.data.language, name]
	root.get_texture().get_image().save_jpg(file, 0.88)
	print("saved ", file.get_file())


## Lets the table's animations end, then a short pause.
func _settle(pause := 0.9) -> void:
	await create_timer(0.3).timeout
	var t0 := Time.get_ticks_msec()
	while m and m.screen is MatchView and (m.screen as MatchView)._busy and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	root.warp_mouse(MOUSE_AWAY)
	await create_timer(pause).timeout


## A fresh client in this language with the pack active (its art and sound sets as the job says), at its menu.
func _open(lang: String) -> void:
	if m:
		m.free()
	Settings.load_settings()
	Settings.data.language = lang
	Settings.data.tracker = false
	Settings.save()
	Packs.set_active(pack)
	for kind in ["art", "sound"]:
		if str(job.get(kind, "")) != "":
			Packs.set_choice(pack, kind, str(job[kind]))
	m = load("res://ui/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.5).timeout
	m.enter_game(pack)
	# the player's decks: the pack's ready ones (their names show beside the collection)
	DeckStore.write(DeckStore.file(), Decks.templates().map(func(t): return t.deck.to_dict().merged({"name": t.name}, true)))
	await _settle(1.5)


## The collection on a class tab, filtered by the pack's own set (its set mark on every card).
func _collection() -> CollectionView:
	m.show_collection()
	await process_frame
	var c: CollectionView = m.screen.browser
	var pick := c.find_child("SetFilter", true, false) as OptionButton
	var i := CollectionView.set_keys().find(str(job.set_key))
	if pick and i >= 0:
		pick.select(i + 1)
		pick.item_selected.emit(i + 1)
	else:
		print("ERROR: no set filter for ", job.set_key)
		failed += 1
	if str(job.get("tab", "")) != "":
		c.set_tab(str(job.tab))
	await _settle()
	await _shot("collection")
	return c


## A card shown big (the collection's hover view, with its keyword tips), found by its name on its class tab.
func _big(id: String) -> void:
	if not _want("card_" + id):
		return
	var c: CollectionView = m.screen.browser
	var card := CardDb.card(id)
	var classes: Array = card.get("classes", [])
	c.set_tab(str(classes[0]) if not classes.is_empty() else str(card.get("cardClass", "NEUTRAL")))
	var search := c.find_child("Search", true, false) as LineEdit
	search.text = CardText.name(id)
	search.text_changed.emit(search.text)
	var at := c.filtered().find(id)  # its name may match many cards (C'Thun): turn to the card's page
	if at >= 0:
		c.turn_page(at / CollectionView.PER_PAGE - c.page)
	await process_frame
	var hit: CardView = null
	for v in c._grid.get_children():
		if v.card_id == id:
			hit = v
	if hit == null:
		print("ERROR: %s is not in the collection" % id)
		failed += 1
	else:
		await _settle(0.4)
		c._on_hover(hit, true)
		await create_timer(0.6).timeout
		await _shot("card_" + id)
		c._on_hover(null, false)
	search.text = ""
	search.text_changed.emit("")


## A table scene: built, its steps played one by one (each must be legal), then shot; and the hovered entity
## (hover: a step ref) and the history's last card line (history: true) as their own shots.
func _scene(sc: Dictionary) -> void:
	var name := str(sc.name)
	if not (_want(name) or _want(name + "_card") or _want(name + "_history")):
		return
	var v: MatchView = m.start_match(_request(sc), [false, false], false)
	if v == null:
		print("ERROR: scene %s does not start" % name)
		failed += 1
		m.show_game_menu()
		return
	await _settle(0.6)
	if sc.has("game"):
		_keep_hands(v.controller)
		await _settle(0.6)
	var steps: Array = sc.get("steps", [])
	for i in steps.size():
		var a := CardTests.action(v.controller, steps[i])
		var res: Dictionary = a if a.has("error") else v.controller.submit(a)
		if a.has("error") or not res.get("ok", false):
			print("ERROR: scene %s, step %d: %s" % [name, i + 1, res.get("error", "?")])
			failed += 1
			break
		if i < steps.size() - 1 or not sc.has("wait"):
			await _settle(0.5)
	if sc.has("wait"):  # a shot in the middle of the last step's animation (a Joust's reveal)
		root.warp_mouse(MOUSE_AWAY)
		await create_timer(float(sc.wait)).timeout
	else:
		await _settle()
	await _shot(name)
	if sc.has("wait"):
		await _settle(0.3)  # the hover and history shots come after the animations
	if sc.has("hover"):
		var id := CardTests.entity(v.controller.game, sc.hover)
		var hand: Array = v.g.players[v.viewer()].hand
		var at := hand.find(v.g.ent(id))
		if at >= 0:  # an own hand card rises under the mouse (MatchView._track_hand_hover), not on _on_hover
			var f: Dictionary = TableLayout.hand(hand.size(), true)[at]
			root.warp_mouse(Vector2(f.pos.x + CardView.SIZE.x * f.scale / 2.0, 700))
			await create_timer(0.6).timeout
			await _shot(name + "_card")
			root.warp_mouse(MOUSE_AWAY)
			await create_timer(0.3).timeout
		elif v._views.has(id):
			v._on_hover(v._views[id], true)
			await create_timer(0.6).timeout
			await _shot(name + "_card")
			v._on_hover(v._views[id], false)
		else:
			print("ERROR: scene %s: nothing to hover at %s" % [name, sc.hover])
			failed += 1
	if sc.get("history", false):
		var strip: HistoryStrip = v._strip
		var tiles := []  # the card lines, top down (history: true is the top one, a number the n-th)
		for i in strip._items.size():
			if strip._items[i][0] is String and strip._items[i].size() > 2:
				tiles.append(i)
		var n := 0 if sc.history is bool else int(sc.history)
		if n < tiles.size():
			strip.hover(tiles[n])
			await create_timer(0.6).timeout
			await _shot(name + "_history")
			strip.hover(-1)
	m.show_game_menu()
	await process_frame
