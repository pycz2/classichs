class_name WebPaste
extends Node
## Paste in the browser. Godot's web build keeps its own copy of the clipboard and refreshes it from
## the browser's paste event, which comes after the key: Ctrl+V pasted the previous text, or nothing
## (Firefox gives a page the clipboard only inside a paste event). So this node keeps the paste key
## from Godot and puts in the text of the paste event itself. Godot cancels every key it gets
## (preventDefault), and a cancelled Ctrl+V/Cmd+V makes no paste event: the key stops on window
## before Godot's handler. Nothing here reads the clipboard (navigator.clipboard.readText): Firefox
## answers that with its own "Paste" menu at the pointer. main adds this node on the web.

var _cb: JavaScriptObject  # the callback lives as long as this node


func _ready() -> void:
	_cb = JavaScriptBridge.create_callback(_on_paste)
	JavaScriptBridge.eval("""
		window.chsPaste = null;
		window.addEventListener('paste', function (e) {
			var t = e.target;  // the virtual keyboard's own field (phones) pastes by itself
			if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA')) return;
			if (window.chsPaste) window.chsPaste((e.clipboardData || window.clipboardData).getData('text'));
		}, true);
		window.addEventListener('keydown', function (e) {
			if ((e.ctrlKey || e.metaKey) && !e.altKey && e.code === 'KeyV') e.stopImmediatePropagation();
		}, true);""", true)
	JavaScriptBridge.get_interface("window").chsPaste = _cb


func _input(event: InputEvent) -> void:
	if is_paste_key(event, get_viewport().gui_get_focus_owner()):
		get_viewport().set_input_as_handled()  # the paste event brings the text


func _on_paste(args: Array) -> void:
	insert(get_viewport().gui_get_focus_owner(), str(args[0]))


## Ctrl+V or Cmd+V (held too) while a field that takes text has the focus.
static func is_paste_key(event: InputEvent, focus: Control) -> bool:
	var k := event as InputEventKey
	return k != null and k.pressed and k.keycode == KEY_V and (k.ctrl_pressed or k.meta_pressed) \
		and (focus is LineEdit or focus is TextEdit) and focus.editable


## Puts text in a field as its own paste would: over the selection, at the caret; a LineEdit gets one
## line (a password manager's copy often ends with a line break). false when the field takes nothing.
static func insert(c: Control, text: String) -> bool:
	if c is LineEdit and c.editable:
		var le := c as LineEdit
		if le.has_selection():
			var from := le.get_selection_from_column()
			le.delete_text(from, le.get_selection_to_column())
			le.deselect()
			le.caret_column = from
		le.insert_text_at_caret(text.strip_escapes())
		le.text_changed.emit(le.text)  # as Godot's own paste does (insert_text_at_caret does not)
		return true
	if c is TextEdit and c.editable:
		var te := c as TextEdit
		te.delete_selection()
		te.insert_text_at_caret(text)
		return true
	return false
