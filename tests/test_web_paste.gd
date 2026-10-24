extends TestCase
## The browser's paste: the text of its paste event goes into the focused field; the key (Ctrl+V,
## Cmd+V) is not left to Godot there, which would paste its stale copy of the clipboard first.


static func root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _field(text: String) -> LineEdit:
	var le := LineEdit.new()
	le.text = text
	root().add_child(le)
	return le


func test_inserts_at_the_caret_and_replaces_the_selection() -> void:
	var le := _field("abcd")
	le.caret_column = 2
	check(WebPaste.insert(le, "XY"), "inserted")
	eq([le.text, le.caret_column], ["abXYcd", 4], "at the caret")
	le.select(0, 2)
	WebPaste.insert(le, "-")
	eq(le.text, "-XYcd", "the selection replaced")
	le.max_length = 6
	WebPaste.insert(le, "123456")
	eq(le.text.length(), 6, "no longer than the field allows")
	le.editable = false
	check(not WebPaste.insert(le, "z"), "a read-only field takes nothing")
	le.free()


func test_text_changed_and_the_password_manager_line_end() -> void:
	var le := _field("")
	var got := []
	le.text_changed.connect(func(t): got.append(t))
	WebPaste.insert(le, "s3cret\r\n")
	eq([le.text, got], ["s3cret", ["s3cret"]], "one line, the change signalled")
	le.free()


func test_takes_the_paste_key_only_in_a_text_field() -> void:
	var le := _field("")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_V
	key.ctrl_pressed = true
	check(WebPaste.is_paste_key(key, le), "Ctrl+V in a field")
	key.ctrl_pressed = false
	key.meta_pressed = true
	check(WebPaste.is_paste_key(key, le), "Cmd+V in a field")
	check(not WebPaste.is_paste_key(key, Button.new()), "not on a button")
	key.keycode = KEY_C
	check(not WebPaste.is_paste_key(key, le), "not Cmd+C")
	le.free()
