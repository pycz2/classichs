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


## Firefox answers navigator.clipboard.readText (Godot's clipboard_get on the web) with its own "Paste"
## menu at the pointer: the game never reads the clipboard by itself, the paste event brings the text.
func test_the_game_never_reads_the_clipboard() -> void:
	for dir in ["res://ui", "res://game", "res://net"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				var src := FileAccess.get_file_as_string(dir + "/" + f)
				check(not src.contains("clipboard_get"), "%s/%s reads no clipboard" % [dir, f])


## Godot cancels the keys it gets, and a cancelled Ctrl+V/Cmd+V makes no paste event (Firefox):
## the paste key stops on window, before Godot's canvas handler.
func test_the_paste_key_never_reaches_godot_in_the_browser() -> void:
	var src := FileAccess.get_file_as_string("res://ui/web_paste.gd")
	check(src.contains("addEventListener('keydown'") and src.contains("e.code === 'KeyV'") and src.contains("stopImmediatePropagation"),
		"a capture keydown listener on window stops Ctrl/Cmd+V")
