extends TestCase
## Problem reports (docs/superpowers/specs/2026-11-26-roles-subservers-design.md §3): the window with the
## screenshot taken before it opened, the context sent with a report, the voice message's WAV and the
## reports waiting in user:// for a login.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


static func _png() -> PackedByteArray:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color.RED)
	return img.save_png_to_buffer()


static func _clear_queue() -> void:
	for p in ServerLink.queued_reports():
		DirAccess.remove_absolute(p)


static func _link(logged_in := false) -> FakeLink:
	var l := FakeLink.new()
	l.url = "ws://localhost:7377"
	if logged_in:
		l.dispatch({"t": "auth", "ok": true, "token": "x", "me": {"user": "anna"}})
	return l


const REPORT := {"text": "The rope burned too early", "written_at": 1764000000, "context": {"game": ""}, "screen": "", "voice": ""}


func test_the_window_opens_with_the_screenshot_attached_and_removes_it() -> void:
	var v := ReportView.new(_png())
	root().add_child(v)
	var pic := v.find_child("Screenshot", true, false) as TextureRect
	check(pic != null and pic.is_visible_in_tree() and pic.texture != null, "the screenshot's preview")
	eq(v.report().screen, Marshalls.raw_to_base64(_png()), "the screenshot goes with the report")
	(v.find_child("RemoveScreenshot", true, false) as Button).pressed.emit()
	eq(v.report().screen, "", "removed")
	check(not pic.is_visible_in_tree(), "the preview is gone")
	v.free()


func test_the_text_is_cut_at_4000_characters_and_an_empty_one_cannot_go() -> void:
	var v := ReportView.new()
	root().add_child(v)
	var t := v.find_child("Text", true, false) as TextEdit
	var send := v.find_child("Send", true, false) as Button
	check(send.disabled, "nothing written: nothing to send")
	t.text = "x".repeat(4100)
	t.text_changed.emit()
	eq(t.text.length(), 4000, "cut")
	check(not send.disabled, "written: it can go")
	v.free()


func test_the_menus_open_the_window() -> void:
	var m := MainMenu.new()
	root().add_child(m)
	(m.find_child("ReportButton", true, false) as Button).pressed.emit()
	check(m.find_child("ReportView", true, false) != null, "the main menu opens it")
	m.free()
	var v := MatchView.new()
	root().add_child(v)
	v.bind(H.scene({"hero": "HERO_08"}))
	(v.find_child("ReportButton", true, false) as Button).pressed.emit()
	var r := v.find_child("ReportView", true, false) as ReportView
	check(r != null and not (v.find_child("GameMenu", true, false) as Control).visible, "the match menu opens it (and closes)")
	eq(r.game if r else "x", "", "not a server's match")
	v.free()


func test_the_context() -> void:
	var c := ReportView.context("g42")
	var p := Packs.active()
	eq(c.version, str(ProjectSettings.get_setting("application/config/version")), "the game's version")
	check(str(c.platform).begins_with(OS.get_name()), "the platform: " + str(c.platform))
	check(RegEx.create_from_string("^\\d+x\\d+$").search(str(c.screen)) != null, "the window's size: " + str(c.screen))
	eq(c.language, "en", "the language")
	eq(c.pack, {"id": p.id(), "version": p.version(), "rules_hash": p.rules_hash()}, "the game played")
	eq(c.game, "g42", "the match")
	eq(ReportView.context().game, "", "not from a match")


func test_the_voice_goes_as_a_16_khz_mono_16_bit_wav() -> void:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = 44100
	s.stereo = true
	var data := PackedByteArray()
	data.resize(44100 * 4)  # 1 s: left 1000, right 3000
	for i in 44100:
		data.encode_s16(i * 4, 1000)
		data.encode_s16(i * 4 + 2, 3000)
	s.data = data
	var w := ReportView.wav16k(s)
	eq(w.slice(0, 4).get_string_from_ascii(), "RIFF", "RIFF")
	eq(w.decode_u32(4), 36 + 32000, "the RIFF size")
	eq(w.slice(8, 16).get_string_from_ascii(), "WAVEfmt ", "WAVE fmt")
	eq([w.decode_u32(16), w.decode_u16(20), w.decode_u16(22), w.decode_u32(24), w.decode_u32(28), w.decode_u16(32), w.decode_u16(34)],
		[16, 1, 1, 16000, 32000, 2, 16], "PCM, mono, 16 kHz, 16-bit")
	eq(w.slice(36, 40).get_string_from_ascii(), "data", "data")
	eq(w.decode_u32(40), 32000, "one second of samples")
	eq(w.size(), 44 + 32000, "the file's size")
	eq(w.decode_s16(44 + 2 * 100), 2000, "both channels mixed")
	s.stereo = false
	s.mix_rate = 16000
	data = PackedByteArray()
	data.resize(70 * 16000 * 2)
	s.data = data
	eq(ReportView.wav16k(s).decode_u32(40), 60 * 32000, "cut at 60 s")


func test_a_report_without_a_login_waits_and_goes_at_the_next_login() -> void:
	_clear_queue()
	var v := ReportView.new()
	root().add_child(v)
	var t := v.find_child("Text", true, false) as TextEdit
	t.text = "Hello"
	t.text_changed.emit()
	(v.find_child("Send", true, false) as Button).pressed.emit()
	eq(ServerLink.queued_reports().size(), 1, "kept")
	check((v.find_child("Status", true, false) as Label).text != "", "the player is told")
	v.free()
	var l := _link(true)
	eq(l.http.size(), 1, "sent at the login")
	eq(l.http[0].path, "/reports", "to /reports")
	eq(l.http[0].content_type, "application/json", "as JSON")
	eq(JSON.parse_string(l.http[0].body.get_string_from_utf8()).text, "Hello", "the report")
	l.http[0].done.call(201, '{"report": {"id": 5}}'.to_utf8_buffer())
	eq(ServerLink.queued_reports(), [], "sent: no longer kept")
	l.free()


func test_a_waiting_report_stays_on_no_answer_401_and_429_and_goes_on_a_bad_report() -> void:
	_clear_queue()
	ServerLink.queue_report(REPORT)
	for code in [0, 401, 429, 500]:
		var l := _link(true)
		eq(l.http.size(), 1, "sent at the login (%d)" % code)
		l.http[0].done.call(code, '{"error": "x", "code": "x"}'.to_utf8_buffer() if code > 0 else PackedByteArray())
		eq(ServerLink.queued_reports().size(), 1, "kept on %d" % code)
		l.free()
	var l := _link(true)
	l.http[0].done.call(400, '{"error": "empty", "code": "bad_text"}'.to_utf8_buffer())
	eq(ServerLink.queued_reports(), [], "a bad report never goes through: dropped")
	l.free()


func test_a_report_sent_while_logged_in_tells_the_answer() -> void:
	_clear_queue()
	var l := _link(true)
	var v := ReportView.new(PackedByteArray(), "g7", l)
	root().add_child(v)
	var t := v.find_child("Text", true, false) as TextEdit
	t.text = "Hello"
	t.text_changed.emit()
	(v.find_child("Send", true, false) as Button).pressed.emit()
	eq(l.http.size(), 1, "sent")
	eq(JSON.parse_string(l.http[0].body.get_string_from_utf8()).context.game, "g7", "from the match")
	l.http[0].done.call(429, '{"error": "slow down", "code": "too_many"}'.to_utf8_buffer())
	var status := (v.find_child("Status", true, false) as Label).text
	check(status.contains(tr(ServerLink.REPORT_ERRORS.too_many)), "the server's answer in the player's words: " + status)
	eq(ServerLink.queued_reports().size(), 1, "kept for later")
	(v.find_child("Send", true, false) as Button).disabled = false
	_clear_queue()
	(v.find_child("Send", true, false) as Button).pressed.emit()
	l.http[1].done.call(201, '{"report": {"id": 9}}'.to_utf8_buffer())
	eq((v.find_child("Status", true, false) as Label).text, tr("The report is sent. Thank you!"), "sent")
	eq(ServerLink.queued_reports(), [], "nothing kept")
	v.free()
	l.free()


# --- the player's reports as threads, with the admins' answers --------------------------------

const LIST := {"unread": 1, "list": [
	{"id": 5, "text": "The rope burned too early", "state": "open", "received_at": 1764000000, "last_at": 1764003600, "unread": true, "messages": 2},
	{"id": 3, "text": "A card shows the wrong art", "state": "closed", "received_at": 1763000000, "last_at": 1763000000, "unread": false, "messages": 1}]}
const THREAD := {"id": 5, "state": "open", "text": "The rope burned too early", "received_at": 1764000000, "last_at": 1764003600, "messages": [
	{"id": 1, "from": "you", "name": "anna", "text": "The rope burned too early", "at": 1764000000, "screen": true},
	{"id": 2, "from": "admin", "name": "Mod", "text": "Thanks, we will look", "at": 1764003600, "screen": false}]}


static func _gets(l: FakeLink, path: String) -> Array:
	return l.http.filter(func(h): return h.path == path and h.method == HTTPClient.METHOD_GET)


func test_the_badge_counts_the_reports_with_news() -> void:
	var l := _link()
	l.report_lists = true
	root().add_child(l)
	l.dispatch({"t": "auth", "ok": true, "token": "x", "me": {"user": "anna"}})
	var m := MainMenu.new()
	root().add_child(m)
	var badge := m.find_child("ReportBadge", true, false) as Label
	check(badge != null and not badge.visible, "nothing new: no badge")
	eq(_gets(l, "/reports").size(), 1, "the count is asked after the login")
	_gets(l, "/reports")[0].done.call(200, JSON.stringify({"list": [], "unread": 2}).to_utf8_buffer())
	check(badge.visible and badge.text == "2", "from GET /reports: " + badge.text)
	l.dispatch({"t": "reports_unread", "n": 3})
	check(badge.visible and badge.text == "3", "from the server's push: " + badge.text)
	l.dispatch({"t": "reports_unread", "n": 0})
	check(not badge.visible, "all seen")
	m.free()
	l.free()


func test_the_threads_list_and_one_thread() -> void:
	var l := _link(true)
	l.report_lists = true
	var v := ReportsView.new(l)
	root().add_child(v)
	_gets(l, "/reports")[0].done.call(200, JSON.stringify(LIST).to_utf8_buffer())
	var row := v.find_child("Report_5", true, false) as Button
	check(row != null and row.text.begins_with("• ") and row.text.contains(tr("Status: open")), "an unread open report: " + (row.text if row else ""))
	var old := v.find_child("Report_3", true, false) as Button
	check(old != null and not old.text.begins_with("•") and old.text.contains(tr("Status: closed")), "a closed one")
	row.pressed.emit()
	_gets(l, "/reports/5")[0].done.call(200, JSON.stringify(THREAD).to_utf8_buffer())
	check((v.find_child("State", true, false) as Label).text.contains(tr("Status: open")), "the state shown")
	eq((v.find_child("Message_1", true, false) as Label).text, "The rope burned too early", "the report first")
	eq((v.find_child("Message_2", true, false) as Label).text, "Thanks, we will look", "the admin's answer")
	eq(_gets(l, "/reports").size(), 2, "opened: the count is asked again")
	v.free()
	l.free()


func test_a_reply_goes_with_the_screenshot_unless_removed() -> void:
	var l := _link(true)
	var v := ReportsView.new(l, _png())
	root().add_child(v)
	v.show_thread(5)
	_gets(l, "/reports/5")[0].done.call(200, JSON.stringify(THREAD).to_utf8_buffer())
	(v.find_child("ReplyText", true, false) as TextEdit).text = "It happened again"
	(v.find_child("SendReply", true, false) as Button).pressed.emit()
	var posts := l.http.filter(func(h): return h.path == "/reports/5" and h.method == HTTPClient.METHOD_POST)
	eq(posts.size(), 1, "the reply is sent")
	var body = JSON.parse_string(posts[0].body.get_string_from_utf8())
	eq([body.text, body.screen, posts[0].content_type], ["It happened again", Marshalls.raw_to_base64(_png()), "application/json"], "text and screenshot")
	posts[0].done.call(400, JSON.stringify({"error": "x", "code": "bad_text"}).to_utf8_buffer())
	eq((v.find_child("Status", true, false) as Label).text, tr(ServerLink.REPORT_ERRORS.bad_text), "the server's answer")
	(v.find_child("RemoveScreenshot", true, false) as Button).pressed.emit()
	(v.find_child("SendReply", true, false) as Button).pressed.emit()
	posts = l.http.filter(func(h): return h.path == "/reports/5" and h.method == HTTPClient.METHOD_POST)
	eq(JSON.parse_string(posts[1].body.get_string_from_utf8()).screen, "", "removed: no screenshot")
	posts[1].done.call(201, JSON.stringify({"message": {"id": 3, "from": "you", "text": "It happened again"}}).to_utf8_buffer())
	eq(_gets(l, "/reports/5").size(), 2, "sent: the thread is shown again")
	v.free()
	l.free()
