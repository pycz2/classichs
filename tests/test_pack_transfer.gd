extends TestCase
## P2P pack negotiation and transfer (D13). One process has one active pack, so the
## host plays a pack file that is not installed (a Classic variant with other rules):
## the guest lacks it.

const VARIANT := "user://test_runner_variant.cardpack"
const VARIANT2 := "user://test_runner_variant2.cardpack"


## Classic without its media, plus a README; other_rules gives a second more grace time in
## rules.json (another rules_hash; a valid pack the engine plays).
func _variant(path := VARIANT, readme := "A test variant", other_rules := true) -> Pack:
	var src := Pack.open("res://packs/classic.cardpack")
	var files := {}
	for f: String in src.files():
		if not f.get_slice("/", 0) in ["art", "sounds", "music", "voice"]:
			files[f] = src.read(f)
	src.close()
	if other_rules:
		var rules: Dictionary = JSON.parse_string(files["rules.json"].get_string_from_utf8())
		rules.timers.grace += 1
		files["rules.json"] = Pack.canonical(rules).to_utf8_buffer()
		var items := []
		for f: String in files:
			if Pack.is_rules_file(f):
				items.append([f, Pack.normalized(f, files[f])])
		var manifest: Dictionary = JSON.parse_string(files["manifest.json"].get_string_from_utf8())
		manifest.rules_hash = Pack.digest("cardpack-rules/1", items)
		files["manifest.json"] = Pack.canonical(manifest).to_utf8_buffer()
	var z := ZIPPacker.new()
	z.compression_level = ZIPPacker.COMPRESSION_NONE
	z.open(path)
	for f: String in files:
		z.start_file(f)
		z.write_file(files[f])
		z.close_file()
	z.start_file("README.md")
	z.write_file(readme.to_utf8_buffer())
	z.close_file()
	z.close()
	return Pack.open(path, "imported")


func _deck(cls: String) -> Deck:
	var d := Deck.new()
	d.hero = Decks.hero(cls)
	d.cards.assign(Decks.basic(cls))
	return d


## Host and guest on a loopback pair, hellos exchanged; the host plays host_pack.
func _pair(host_pack: Pack = null) -> Dictionary:
	var t := LoopbackTransport.pair()
	var p := {"t": t, "h": NetSession.new(), "g": NetSession.new(), "m": [null, null], "fail": [[], []],
		"offers": [], "sent": [], "got": []}
	p.h.setup(t[0], true, "Host", _deck("MAGE"))
	p.g.setup(t[1], false, "Guest", _deck("WARRIOR"))
	if host_pack:
		p.h.pack = host_pack
	for side in 2:
		var s: NetSession = [p.h, p.g][side]
		s.started.connect(func(m): p.m[side] = m)
		s.failed.connect(func(r): p.fail[side].append(r))
	p.g.pack_offer.connect(func(info): p.offers.append(info))
	p.h.pack_progress.connect(func(done, total): p.sent.append([done, total]))
	p.g.pack_progress.connect(func(done, total): p.got.append([done, total]))
	p.h.say_hello()
	p.g.say_hello()
	LoopbackTransport.pump(t)
	return p


func _free(p: Dictionary) -> void:
	for m in p.m:
		if m:
			m.free()
	for t in p.t:
		t.free()
	p.h.free()
	p.g.free()
	_clean()


## The variant files and every pack installed by a test go; Classic is active again.
func _clean() -> void:
	for path in [VARIANT, VARIANT2]:
		DirAccess.remove_absolute(path)
	for pk: Pack in Packs.all():
		if not pk.builtin():
			Packs.remove(pk)


func test_same_pack_starts_as_before() -> void:
	var p := _pair()
	check(p.m[0] != null and p.m[1] != null, "both started: %s" % str(p.fail))
	eq(p.offers, [], "nothing offered")
	eq(p.m[0].state_hash, p.m[1].state_hash, "same game")
	_free(p)


func test_same_rules_other_content_plays_without_an_offer() -> void:
	var v := _variant(VARIANT, "Other art, same game", false)
	check(Packs.content_hash(v) != Packs.content_hash(Packs.active()) and v.rules_hash() == Packs.active().rules_hash(), "only the content differs")
	var p := _pair(v)
	eq(p.offers, [], "nothing offered")
	check(p.m[0] != null and p.m[1] != null, "both started: %s" % str(p.fail))
	check(Packs.active().builtin(), "the guest keeps its pack")
	_free(p)


func test_missing_pack_is_offered_sent_installed_and_played() -> void:
	var v := _variant()
	eq(v.problems(), [], "a sound pack")
	var want := Packs.content_hash(v)
	check(v.rules_hash() != Packs.active().rules_hash(), "other rules")
	var p := _pair(v)
	eq(p.offers.size(), 1, "offered")
	eq(p.offers[0] if p.offers.size() else {}, {"name": v.title("en"), "version": v.version(), "size": v.size, "content_hash": want}, "what is offered")
	check(p.m[0] == null and p.m[1] == null, "no game yet")
	p.g.accept_pack()
	LoopbackTransport.pump(p.t)
	var chunks := ceili(v.size / float(NetSession.CHUNK))
	eq(p.sent.size(), chunks, "one chunk per ack")
	eq(p.got.back() if p.got.size() else [], [v.size, v.size], "all bytes came")
	check(FileAccess.file_exists(Packs.user_dir + "/" + want + ".cardpack"), "installed in the packs folder")
	var got := Packs.find(want)
	check(got != null and got.origin == "p2p", "known as received")
	eq(Packs.content_hash(Packs.active()), want, "the guest switched to it")
	check(p.m[0] != null and p.m[1] != null, "both started: %s" % str(p.fail))
	eq(p.g.pack.rules_hash(), p.h.pack.rules_hash(), "same rules")
	if p.m[0] and p.m[1]:
		eq(p.m[0].state_hash, p.m[1].state_hash, "same game")
	_free(p)


func test_guest_with_the_pack_switches_without_a_transfer() -> void:
	var have: Pack = Packs.install(FileAccess.get_file_as_bytes(_variant().path), "imported").get("pack")
	check(have != null, "installed")
	var p := _pair(have)
	eq(p.offers, [], "nothing offered")
	eq(p.got, [], "nothing sent")
	check(Packs.active() == have, "switched")
	check(p.m[0] != null and p.m[1] != null, "both started: %s" % str(p.fail))
	_free(p)


func test_guest_with_the_same_rules_in_another_pack_switches_to_it() -> void:
	var have: Pack = Packs.install(FileAccess.get_file_as_bytes(_variant(VARIANT2, "Other art").path), "imported").get("pack")
	var p := _pair(_variant())
	eq(p.offers, [], "nothing offered")
	check(Packs.active() == have, "switched to its own pack with the host's rules")
	check(p.m[0] != null and p.m[1] != null, "both started: %s" % str(p.fail))
	_free(p)


func test_declined_pack_ends_the_session() -> void:
	var p := _pair(_variant())
	p.g.decline_pack()
	LoopbackTransport.pump(p.t)
	var said := str(TranslationServer.translate("The game pack was not accepted"))
	eq(p.fail, [[said], [said]], "both told")
	eq([p.h.failure_kind, p.g.failure_kind], ["pack", "pack"], "kind")
	check(Packs.active().builtin(), "the guest keeps its pack")
	_free(p)


func test_pack_not_redistributable_is_not_offered() -> void:
	var v := _variant()
	v.manifest.redistributable = false
	var p := _pair(v)
	eq(p.offers, [], "nothing offered")
	eq(p.fail[1], [str(TranslationServer.translate("The opponent plays a game you don't have"))], "the guest")
	eq(p.fail[0], [str(TranslationServer.translate(NetSession.BYE_TEXT.pack))], "the host")
	_free(p)


func test_cancel_mid_transfer() -> void:
	var p := _pair(_variant())
	p.g.pack_progress.connect(func(done, _total):
		if done >= 2 * NetSession.CHUNK:
			p.g.cancel_pack())
	p.g.accept_pack()
	LoopbackTransport.pump(p.t)
	var said := str(TranslationServer.translate(NetSession.CANCELLED))
	eq(p.fail, [[said], [said]], "both told")
	eq([p.h.failure_kind, p.g.failure_kind], ["cancel", "cancel"], "kind")
	eq(p.got.size(), 2, "stopped after two chunks")
	eq(Packs.all().filter(func(pk): return not pk.builtin()), [], "nothing installed")
	_free(p)


func test_damaged_pack_is_refused() -> void:
	var v := _variant()
	Packs.content_hash(v)  # what the host offers…
	v.path = _variant(VARIANT2, "Another text").path  # … is not what it sends
	var p := _pair(v)
	p.g.accept_pack()
	LoopbackTransport.pump(p.t)
	eq(p.fail[1], [str(TranslationServer.translate(NetSession.DAMAGED))], "the guest")
	eq(p.fail[0], [str(TranslationServer.translate(NetSession.BYE_TEXT.pack))], "the host is told")
	eq(Packs.all().filter(func(pk): return not pk.builtin()), [], "nothing installed")
	check(not FileAccess.file_exists(Packs.user_dir + "/incoming.tmp"), "no leftovers")
	_free(p)


func test_arena_needs_the_same_rules() -> void:
	var t := LoopbackTransport.pair()
	var a := ArenaSession.new()
	a.setup(t[0], true, "Host")
	var fails := []
	a.failed.connect(func(r): fails.append(r))
	var hello := {"t": "hello", "mode": "arena", "protocol": NetSession.PROTOCOL, "version": a.version,
		"data": Rules.data_hash(), "name": "Guest", "pack": {"rules_hash": "another"}}
	t[1].send(hello)
	LoopbackTransport.pump(t)
	eq(fails, [str(TranslationServer.translate(ArenaSession.SAME_GAME))], "refused")
	for x in t:
		x.free()
	a.free()


func test_online_view_asks_then_shows_the_transfer() -> void:
	var t := LoopbackTransport.pair()
	var v := OnlineView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	v.deck = _deck("WARRIOR")
	v.transport = t[1]
	v._begin_game(false)
	var h := NetSession.new()
	h.setup(t[0], true, "Host", _deck("MAGE"))
	h.pack = _variant()
	var seen := []
	v.session.pack_progress.connect(func(_d, _t): seen.append(v._pack_text.text))
	h.say_hello()
	v.session.say_hello()
	LoopbackTransport.pump(t)
	check(v.pack_dialog != null and v._pack_text.text.contains("Classic 2014"), "asked")
	var b := v.find_child("PackDownload", true, false) as Button
	check(b != null, "a Download button")
	if b:
		b.pressed.emit()
	LoopbackTransport.pump(t)
	check(seen.size() > 1 and seen[0].begins_with("Receiving the game: "), str(seen.slice(0, 2)))
	eq(v.state, "playing", "the game started")
	check(v.pack_dialog == null, "the dialog is gone")
	if h.match_:
		h.match_.free()
	if v.session.match_:
		v.session.match_.free()
	h.free()
	v.free()
	for x in t:
		x.free()
	_clean()
