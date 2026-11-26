extends TestCase
## The tournament chats (ui/chat_panel.gd) against a FakeLink: the history, new messages, deleted
## lines, the admin and creator marks, the read-only state, the moderator's delete, and the
## tournaments screen subscribing to its channels ("tournaments", "t:<id>") and leaving them.

const ME := {"user": "anna", "tag": null, "arena": null, "season": "2026-11", "rank": {}}


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _link() -> FakeLink:
	var l := FakeLink.new()
	l.url = "ws://localhost:7441"
	l.dispatch({"t": "auth", "ok": true, "token": "x", "me": ME})
	l.sent.clear()
	return l


static func msg(id: int, from: String, text: String, mark := "", deleted_by := "") -> Dictionary:
	return {"id": float(id), "from": from, "text": text, "at": 1764150000.0 + id, "mark": mark, "deleted_by": deleted_by}


func _panel(channel := "tournaments") -> ChatPanel:
	var p := ChatPanel.new()
	p.size = Vector2(400, 500)
	root().add_child(p)
	p.open(_link(), channel)
	return p


func _free(p: ChatPanel) -> void:
	var l := p.link
	p.free()
	l.free()


func _line(p: ChatPanel, id: int) -> String:
	var row := p.find_child("Msg_%d" % id, true, false)
	if row == null:
		return ""
	return (row.find_child("Text", true, false) as RichTextLabel).get_parsed_text()


func _history(p: ChatPanel, list: Array, open := true, moderator := false, closes := 0) -> void:
	p.link.dispatch({"t": "chat_history", "channel": p.channel, "list": list, "open": open, "closes": float(closes), "moderator": moderator})


func test_subscribes_shows_the_history_and_new_messages() -> void:
	var p := _panel()
	eq((p.link as FakeLink).of("chat_sub"), [{"t": "chat_sub", "channel": "tournaments"}], "subscribed")
	_history(p, [msg(1, "bob", "hi all"), msg(2, "cat", "gl hf [b]x[/b]")])
	check(_line(p, 1).contains("bob") and _line(p, 1).contains("hi all"), "the first line: " + _line(p, 1))
	check(_line(p, 2).contains("gl hf [b]x[/b]"), "a message's brackets are its text: " + _line(p, 2))
	p.link.dispatch({"t": "chat_msg", "channel": "t:9", "msg": msg(3, "dan", "other channel")})
	eq(_line(p, 3), "", "another channel's message is not here")
	p.link.dispatch({"t": "chat_msg", "channel": "tournaments", "msg": msg(3, "dan", "new one")})
	check(_line(p, 3).contains("new one"), "a pushed message is added")
	eq(p.find_child("Lines", true, false).get_child_count(), 3, "three lines")
	_free(p)


func test_send_waits_for_the_push() -> void:
	var p := _panel()
	_history(p, [])
	var input := p.find_child("ChatInput", true, false) as LineEdit
	input.text = "  hello  "
	input.text_submitted.emit(input.text)
	eq((p.link as FakeLink).of("chat_send"), [{"t": "chat_send", "channel": "tournaments", "text": "hello"}], "sent trimmed")
	eq(input.text, "", "the line is emptied")
	eq(p.find_child("Lines", true, false).get_child_count(), 0, "nothing added before the push")
	input.text = "   "
	input.text_submitted.emit(input.text)
	eq((p.link as FakeLink).of("chat_send").size(), 1, "an empty line is not sent")
	_free(p)


func test_deleted_lines_and_marks() -> void:
	var p := _panel("t:7")
	_history(p, [msg(1, "root", "rules: be nice", "admin"), msg(2, "bob", "welcome", "creator"), msg(3, "eve", "", "", "root")])
	check(_line(p, 1).contains(tr("admin")), "the admin mark: " + _line(p, 1))
	check(_line(p, 2).contains(tr("creator")), "the creator mark: " + _line(p, 2))
	check(_line(p, 3).contains(tr("Deleted by %s") % "root"), "a deleted message from the history: " + _line(p, 3))
	p.link.dispatch({"t": "chat_deleted", "channel": "t:7", "id": 2.0, "by": "root"})
	check(_line(p, 2).contains(tr("Deleted by %s") % "root") and not _line(p, 2).contains("welcome"), "deleted live: " + _line(p, 2))
	_free(p)


func test_read_only_when_closed() -> void:
	var p := _panel("t:7")
	_history(p, [msg(1, "bob", "gg")], false)
	var input := p.find_child("ChatInput", true, false) as LineEdit
	check(not input.is_visible_in_tree(), "a closed chat has no input")
	check(p.find_child("ClosedNote", true, false).is_visible_in_tree(), "it says it is closed")
	_history(p, [msg(1, "bob", "gg")], true)
	check(input.is_visible_in_tree(), "an open chat has the input")
	check(not p.find_child("ClosedNote", true, false).is_visible_in_tree(), "no note while no closing time is known")
	_history(p, [], true, false, int(Time.get_unix_time_from_system()) + 3600)
	check(input.is_visible_in_tree(), "open until its closing time")
	var note := p.find_child("ClosedNote", true, false) as Label
	check(note.is_visible_in_tree() and note.text == tr("The chat closes at %s") % note.text.right(5), "the closing time said: " + note.text)
	check(p.find_child("NoMessages", true, false).is_visible_in_tree(), "an empty chat says so")
	p.link.dispatch({"t": "chat_closed", "channel": "t:7"})
	check(not input.is_visible_in_tree(), "closed by the push")
	_history(p, [], true, false, int(Time.get_unix_time_from_system()) - 5)
	check(not input.is_visible_in_tree(), "closed: its closing time passed")
	_history(p, [], true)
	p.link.dispatch({"t": "error", "code": "chat_closed", "text": "closed"})
	check(not input.is_visible_in_tree(), "closed by the error to a send")
	_history(p, [], true)
	p.set_ended(TournamentsView.now_ms() - 11 * 60 * 1000)
	check(not input.is_visible_in_tree(), "closed ten minutes after the tournament's end")
	_free(p)


func test_moderator_deletes() -> void:
	var p := _panel()
	_history(p, [msg(1, "bob", "spam"), msg(2, "eve", "", "", "root")])
	check(p.find_child("Delete_1", true, false) == null, "no delete for a player")
	_history(p, [msg(1, "bob", "spam"), msg(2, "eve", "", "", "root")], true, true)
	var del := p.find_child("Delete_1", true, false) as Button
	check(del != null and del.is_visible_in_tree(), "a moderator's delete")
	check(p.find_child("Delete_2", true, false) == null, "none on a deleted line")
	if del:
		del.pressed.emit()
	eq((p.link as FakeLink).of("chat_delete"), [{"t": "chat_delete", "id": 1}], "the delete sent")
	_free(p)


func test_resubscribes_after_a_new_login() -> void:
	var p := _panel()
	p.link.dispatch({"t": "auth", "ok": true, "token": "y", "me": ME})
	eq((p.link as FakeLink).of("chat_sub").size(), 2, "subscribed again after the reconnection")
	_free(p)


func test_tournaments_screen_subscribes_and_leaves() -> void:
	TournamentsView.cache = {}
	var v := TournamentsView.new()
	v.link = _link()
	v.page_ms = 0
	root().add_child(v)
	var l := v.link as FakeLink
	eq(l.of("chat_sub"), [{"t": "chat_sub", "channel": "tournaments"}], "the list subscribes to the common channel")
	var chat := v.find_child("Chat", true, false) as ChatPanel
	check(chat != null and chat.is_visible_in_tree(), "the chat beside the list")
	v.show_tab("finished")
	eq(l.of("chat_sub").size(), 1, "the other tabs keep the channel")
	v.open_page(7)
	eq(l.of("chat_unsub"), [{"t": "chat_unsub", "channel": "tournaments"}], "a page leaves the common channel")
	eq(l.of("chat_sub").back(), {"t": "chat_sub", "channel": "t:7"}, "and joins its own")
	var t: Dictionary = load("res://tests/test_tournaments.gd").full("swiss", 4)
	l.dispatch({"t": "tournament", "tournament": t})
	var tab := v.find_child("Tab_chat", true, false) as Button
	check(tab != null, "the page's Chat tab")
	check(not chat.is_visible_in_tree(), "the overview hides the chat")
	l.dispatch({"t": "chat_msg", "channel": "t:7", "msg": msg(1, "bob", "hi")})
	eq(tab.text, tr("Chat") + " (1)", "a message not seen counted on the tab")
	if tab:
		tab.pressed.emit()
	check(v.find_child("Chat", true, false).is_visible_in_tree(), "the chat tab shows the chat")
	t["ended"] = float(TournamentsView.now_ms() - 20 * 60 * 1000)
	l.dispatch({"t": "tournament", "tournament": t})
	check(not chat.find_child("ChatInput", true, false).is_visible_in_tree(), "the push's end closes the chat")
	v._go_back()
	eq(l.of("chat_unsub").back(), {"t": "chat_unsub", "channel": "t:7"}, "back to the list leaves the page's channel")
	eq(l.of("chat_sub").back(), {"t": "chat_sub", "channel": "tournaments"}, "and joins the common one")
	v.free()
	eq(l.of("chat_unsub").back(), {"t": "chat_unsub", "channel": "tournaments"}, "closing the screen leaves it")
	l.free()
