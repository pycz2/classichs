extends SceneTree
# TEMP (step 10 client check): the loot pack's cards and table in a window; screenshots to /tmp/lootui/shots.

const OUT := "/tmp/lootui/shots/"


func _initialize() -> void:
	Settings.path = "user://uitest_loot_settings.json"
	Profile.path = "user://uitest_loot_profile.json"
	DeckStore.path = "user://uitest_loot_decks.json"
	Progress.path = "user://uitest_loot_progress.json"
	Packs.user_dir = "user://uitest_loot_packs"
	DirAccess.make_dir_recursive_absolute(OUT)
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("shot ", name)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	var p := Pack.open("/tmp/loot-ui.cardpack", "imported")
	Packs._active = p
	CardDb.reset()
	KeywordTips.reset()
	print("pack ", p.id(), " engine: ", Rules.load_pack(p))
	var bg := ColorRect.new()
	bg.color = Color("30261c")
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	var cards := ["LOOT_051", "LOOT_503", "LOOT_526d", "LOOT_193", "LOOT_542", "LOOT_370"]
	for lang in ["de"]:
		TranslationServer.set_locale(lang)
		var box := Control.new()
		root.add_child(box)
		for i in cards.size():
			var cv := CardView.make(cards[i], 1.5)
			cv.position = Vector2(10 + 210 * i, 10)
			box.add_child(cv)
			print(lang, " ", cards[i], ": ", CardText.text(cards[i], CardText.hs_locale(lang)))
		for i in 2:
			var t := KeywordTips.make(["LOOT_370", "LOOT_193"][i])
			t.position = Vector2(10 + 250 * i, 300)
			box.add_child(t)
		await _shot("cards_" + lang)
		box.queue_free()
	TranslationServer.set_locale("en")
	var m := Match.new()
	m.bot_delay = 0.0
	var why := m.setup({"scenario": {"current": 0, "players": [
		{"hero": "HERO_01", "mana": 10, "max_mana": 10, "hand": ["LOOT_370", "LOOT_051"],
			"deck": ["VAN_CS2_182", "VAN_CS2_182", "VAN_CS2_182", "LOOT_278"], "weapon": "LOOT_542", "board": ["LOOT_193"]},
		{"hero": "HERO_08", "mana": 10, "max_mana": 10, "hero_state": {"tags": ["ELUSIVE"]},
			"deck": ["VAN_CS2_182", "LOOT_526t"], "board": ["LOOT_193"]}]}}, [false, true])
	print("setup: ", why)
	var v := MatchView.new()
	root.add_child(v)
	v.bind(m)
	await _wait(1.0)
	await _shot("table")
	var g := m.game
	var party: GameView.Ent = g.players[0].hand.filter(func(e): return e.card_id == "LOOT_370")[0]
	print(m.submit({"type": "play", "player": 0, "entity": party.id, "target": -1, "pos": -1, "choice": -1}).get("ok"))
	for i in 6:
		await _wait(0.1)
		await _shot("recruit_%d" % i)
	await _wait(2.0)
	await _shot("recruit_after")
	print(m.submit({"type": "end_turn", "player": 0}).get("ok"))
	for i in 12:
		await _wait(0.25)
		await _shot("turn2_%d" % i)
	for i in 12:
		await _wait(0.25)
		await _shot("turn3_%d" % i)
	for e in g.history:
		for line in HistoryText.lines(e, g, 0, "en"):
			print("  history: ", line)
	quit(0)
