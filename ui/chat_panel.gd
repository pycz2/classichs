class_name ChatPanel
extends PanelContainer
## A tournament chat on a game server: the common channel "tournaments" beside the list, and a
## tournament's own "t:<id>" on its page (TournamentsView). open() subscribes (`chat_sub`, answered
## by `chat_history`), then the server pushes `chat_msg`, `chat_deleted` and `chat_closed`; a sent
## message shows when its push comes back. Each line: the time, the sender, an admin or creator
## mark, the text (or "Deleted by …"), and for a moderator a delete button. A closed channel (the
## server's `open`, its closing time `closes`, or ten minutes after the tournament ended) is read only.

## A message arrived (the screen counts the ones not seen).
signal arrived

const MARKS := {"admin": ["admin", Color("ff7a6a")], "creator": ["creator", Color("5ab4ff")]}
const CLOSE_AFTER_S := 600  # a tournament's chat stays open ten minutes after its end
const KEPT := 200  # lines kept on the screen

var link: ServerLink
var channel := ""
var messages: Array = []  # the server's MSG dictionaries, oldest first
var moderator := false
var is_open := true
var closes := 0  # unix seconds when the channel becomes read only, 0 = not known
var _lines := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _input := LineEdit.new()
var _send: Button
var _row := HBoxContainer.new()
var _note: Label
var _closed_note: Label
var _second := 0
var sending := false  # a message sent, its push not back yet (the server's errors to it are told here)


func _init() -> void:
	name = "Chat"
	add_theme_stylebox_override("panel", Palette.frame(Color(0.09, 0.065, 0.04, 0.94), 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var title := Palette.label(TranslationServer.translate("Chat"), 22, Palette.ATTACK)
	v.add_child(title)
	_scroll.name = "ChatScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	_lines.name = "Lines"
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.add_theme_constant_override("separation", 4)
	_scroll.add_child(_lines)
	_note = Palette.label("", 15, Palette.MUTED)
	_note.name = "ChatNote"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.visible = false
	v.add_child(_note)
	_closed_note = Palette.label(TranslationServer.translate("The chat is closed: messages can only be read"), 16, Palette.MUTED)
	_closed_note.name = "ClosedNote"
	_closed_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_closed_note.visible = false
	v.add_child(_closed_note)
	_row.add_theme_constant_override("separation", 6)
	v.add_child(_row)
	_input.name = "ChatInput"
	_input.placeholder_text = TranslationServer.translate("Write a message, Enter sends")
	_input.max_length = 500
	_input.custom_minimum_size.y = 44
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t): send_text())
	_row.add_child(_input)
	_send = Palette.button(TranslationServer.translate("Send"), "ChatSend")
	_send.custom_minimum_size = Vector2(90, 44)
	_send.pressed.connect(send_text)
	_row.add_child(_send)


## Subscribes to ch (leaving the channel before).
func open(l: ServerLink, ch: String) -> void:
	close()
	link = l
	channel = ch
	messages = []
	moderator = false
	is_open = true
	closes = 0
	_note.visible = false
	if not link.message.is_connected(_on_message):
		link.message.connect(_on_message)
	link.send({"t": "chat_sub", "channel": channel})
	_render()


## Leaves the channel.
func close() -> void:
	if channel != "" and is_instance_valid(link):
		link.send({"t": "chat_unsub", "channel": channel})
	channel = ""


func _exit_tree() -> void:
	close()
	if is_instance_valid(link) and link.message.is_connected(_on_message):
		link.message.disconnect(_on_message)


## The tournament's end (unix ms, 0 = not ended) from its `tournament` push: the chat closes ten minutes later.
func set_ended(ended_ms: int) -> void:
	if ended_ms > 0:
		closes = ended_ms / 1000 + CLOSE_AFTER_S
		_update_state()


func read_only() -> bool:
	return not is_open or (closes > 0 and int(Time.get_unix_time_from_system()) >= closes)


func send_text() -> void:
	var text := _input.text.strip_edges()
	if text == "" or read_only() or channel == "":
		return
	_input.text = ""
	_note.visible = false
	sending = true
	link.send({"t": "chat_send", "channel": channel, "text": text})


func _process(_d: float) -> void:
	var s := int(Time.get_unix_time_from_system())
	if s != _second and closes > 0:  # (the closing time passing: once a second)
		_second = s
		_update_state()


func _update_state() -> void:
	var ro := read_only()
	_row.visible = not ro
	_closed_note.visible = ro


func _on_message(msg: Dictionary) -> void:
	var t := str(msg.get("t", ""))
	if t == "auth" and msg.get("ok", false) and channel != "":  # logged in again (a reconnection): subscribe again
		link.send({"t": "chat_sub", "channel": channel})
		return
	if t == "error":
		var was := sending
		sending = false
		match msg.get("code"):
			"chat_closed":
				is_open = false
				_update_state()
			"rate_limited" when was:
				_say(TranslationServer.translate("Too many messages: wait a little"))
			"bad_text" when was:
				_say(TranslationServer.translate("A message is 1 to 500 characters"))
		return
	if str(msg.get("channel", "")) != channel or channel == "":
		return
	match t:
		"chat_history":
			messages = (msg.get("list") as Array).filter(func(m): return m is Dictionary).slice(-KEPT) if msg.get("list") is Array else []
			is_open = msg.get("open", true) == true
			closes = maxi(closes, int(msg.get("closes", 0)))  # (a tournament's end may be known first)
			moderator = msg.get("moderator", false) == true
			_render()
		"chat_msg":
			if msg.get("msg") is Dictionary:
				if str(msg.msg.get("from", "")) == str(link.me.get("user", "")):
					sending = false
				messages.append(msg.msg)
				if messages.size() > KEPT:
					messages.pop_front()
					_lines.get_child(0).free()
				_lines.add_child(_line(msg.msg))
				_to_bottom()
				arrived.emit()
		"chat_deleted":
			for i in messages.size():
				if int(messages[i].get("id", -1)) == int(msg.get("id", -2)):
					messages[i] = messages[i].merged({"text": "", "deleted_by": str(msg.get("by", ""))}, true)
					_lines.get_child(i).free()  # (first: the new line takes its name)
					var line := _line(messages[i])
					_lines.add_child(line)
					_lines.move_child(line, i)
		"chat_closed":
			is_open = false
			_update_state()


func _say(text: String) -> void:
	_note.text = text
	_note.visible = true


func _render() -> void:
	for c in _lines.get_children():
		c.free()
	for m in messages:
		_lines.add_child(_line(m))
	_update_state()
	_to_bottom()


func _to_bottom() -> void:
	_scroll.call_deferred("set_v_scroll", 1 << 20)


## A message's line: "18:30 bob [admin] text", or "18:30 bob Deleted by root" dimmed.
func _line(m: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Msg_%d" % int(m.get("id", 0))
	var l := RichTextLabel.new()
	l.name = "Text"
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("normal_font_size", 17)
	l.add_theme_font_size_override("italics_font_size", 17)
	var d := Time.get_datetime_dict_from_unix_time(int(m.get("at", 0)) + TournamentsView.tz_s())
	var me := str(link.me.get("user", "")) if is_instance_valid(link) else ""
	var from := str(m.get("from", ""))
	var s := "[color=#%s]%02d:%02d[/color] [color=#%s]%s[/color]" % [Palette.MUTED.to_html(false), d.hour, d.minute,
		(Palette.SELECTED if from == me else Palette.ATTACK).to_html(false), _esc(from)]
	var mark = MARKS.get(str(m.get("mark", "")))
	if mark:
		s += " [bgcolor=#%s][color=#1a1208] %s [/color][/bgcolor]" % [mark[1].to_html(false), TranslationServer.translate(mark[0])]
	var by := str(m.get("deleted_by", ""))
	if by != "":
		s += " [i][color=#%s]%s[/color][/i]" % [Palette.MUTED.to_html(false), _esc(TranslationServer.translate("Deleted by %s") % by)]
	else:
		s += "  " + _esc(str(m.get("text", "")))
	l.text = s
	row.add_child(l)
	if moderator and by == "":
		var x := Button.new()
		x.name = "Delete_%d" % int(m.get("id", 0))
		x.text = "×"
		x.flat = true
		x.focus_mode = Control.FOCUS_NONE
		x.tooltip_text = TranslationServer.translate("Delete the message")
		x.add_theme_color_override("font_color", Palette.DANGER)
		x.custom_minimum_size = Vector2(36, 32)
		var id := int(m.get("id", 0))
		x.pressed.connect(func(): link.send({"t": "chat_delete", "id": id}))
		row.add_child(x)
	return row


## Text shown as it is (a "[" would start a BBCode tag).
static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")
