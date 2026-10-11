class_name ChangelogView
extends Control
## The game's whole change history (CHANGELOG.md) in a scrollable window.

const PATH := "res://CHANGELOG.md"
const HEADING_SIZES := [30, 24, 20]


func _ready() -> void:
	name = "ChangelogView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	var style := Palette.box(Palette.TABLE, 12)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 140
	panel.offset_right = -140
	panel.offset_top = 40
	panel.offset_bottom = -40
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var text := RichTextLabel.new()
	text.name = "Text"
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 17)
	text.text = to_bbcode(FileAccess.get_file_as_string(PATH))
	box.add_child(text)
	var close := Palette.button(tr("Close"), "Close")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	box.add_child(close)


## The Markdown subset the changelog uses: headings, "- " lists, **bold**, `code`, links.
static func to_bbcode(md: String) -> String:
	var link := RegEx.create_from_string("\\[([^\\]]*)\\]\\([^)]*\\)")
	var bold := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	var code := RegEx.create_from_string("`(.+?)`")
	var out := PackedStringArray()
	for line in md.split("\n"):
		line = link.sub(line, "$1", true).replace("[", "[lb]")
		line = code.sub(bold.sub(line, "[b]$1[/b]", true), "[code]$1[/code]", true)
		var level := 0
		while level < line.length() and line[level] == "#":
			level += 1
		if level > 0:
			line = "[font_size=%d][b]%s[/b][/font_size]" % [HEADING_SIZES[mini(level, 3) - 1], line.substr(level).strip_edges()]
		elif line.begins_with("- "):
			line = "• " + line.substr(2)
		out.append(line)
	return "\n".join(out)
